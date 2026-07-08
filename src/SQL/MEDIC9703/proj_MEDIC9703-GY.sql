/*                                             
# Description: this script extracts a cohort of midlife patients with multiple elevated biomarkers (BMI, A1C, BP, LDL)
#  - Inclusion criteria: 
        - Adults with at least 1 record of the 4 biomarkers 
        - Ages at the time of 4 biomarkers are between 40 – 60 years old
        - At least 2 of the 4 biomarkers were elevated
   - Exclusion criteria: 
        - With any prior elevated biomarkers
        - With high-risk conditions prior to elevated biomarkers (cancer, end-stage organ failure…)

#  - Exposure: 
        - Single-class medication use: Antihypertentives (AHD), Antidiabetics (ADD), LDL-lowering drug (LLD)
        - Multi-class medication use: at least two of the classes

#  - Outcome:
        - Pre-mature death (death before 75 years old)
*/

/*
identify eligible patient cohort
*/
-- collect all  collected together with age at labs
create or replace table all_bmi as 
with ht as (
    select v.patid, median(v.ht) as ht, 
    from PCORNET_CDM.CDM.deid_vital v
    join PCORNET_CDM.CDM.deid_demographic d 
    on v.patid = d.patid
    where datediff(year,d.birth_date,v.measure_date) > 18 and v.ht > 0
    group by v.patid
),  wt as (
    select patid, wt, measure_date
    from PCORNET_CDM.CDM.deid_vital
),  bmi as (
    select patid, original_bmi, measure_date
    from PCORNET_CDM.CDM.deid_vital
)
select distinct 
       ht.patid, 
       ht.ht,
       wt.wt,
       round(coalesce(bmi.original_bmi,wt.wt/(ht.ht*ht.ht)*703)) as bmi,
       coalesce(bmi.measure_date,bmi.measure_date) as measure_date
from ht
left join wt on ht.patid = wt.patid
left join bmi on ht.patid = bmi.patid
where round(coalesce(bmi.original_bmi,wt.wt/(ht.ht*ht.ht)*703)) is not null
;

select count(distinct patid), count(*) from all_bmi;
-- 672,724	373,212,203

create or replace table all_bmk_incld as 
select distinct
       a.patid, 
       coalesce(a.specimen_date,a.lab_order_date,a.result_date) as bmk_date,
       'A1C' as bmk_type,
       a.result_num, 
       a.result_unit,
       case when a.result_num >= 6.5 then 1 else 0 end as elevated_ind,
       datediff(year,d.birth_date,coalesce(a.specimen_date,a.lab_order_date,a.result_date)) as age_at_bmk
from PCORNET_CDM.CDM.DEID_LAB_RESULT_CM a 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d 
on a.patid = d.patid
where a.lab_loinc in (
          '4548-4'
         ,'4549-2'
         ,'17855-8'
         ,'17856-6'
         ,'41995-2'
         ,'59261-8'
         ,'62388-4'
         ,'71875-9'
         ,'54039-3'
) and a.result_num is not null
union 
select distinct
       a.patid, 
       coalesce(a.specimen_date,a.lab_order_date,a.result_date) as bmk_date,
       'LDL' as bmk_type,
       a.result_num, 
       a.result_unit,
       case when a.result_num >= 130 then 1 else 0 end as elevated_ind,
       datediff(year,d.birth_date,coalesce(a.specimen_date,a.lab_order_date,a.result_date)) as age_at_bmk
from PCORNET_CDM.CDM.DEID_LAB_RESULT_CM a 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d 
on a.patid = d.patid
where a.lab_loinc in (
        '2089-1',
        '2090-9',
        '22748-8',
        '35198-1',
        '18262-6',
        '49132-4',
        '55440-2',
        '96259-7'
) and a.result_num is not null
union 
select distinct
       a.patid, 
       a.measure_date as bmk_date,
       'SBP' as bmk_type,
       a.SYSTOLIC as result_num, 
       'mmHg' as result_unit,
       case when a.SYSTOLIC >= 130 then 1 else 0 end as elevated_ind,
       datediff(year,d.birth_date,a.measure_date) as age_at_bmk
from PCORNET_CDM.CDM.DEID_VITAL a 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d 
on a.patid = d.patid
where a.SYSTOLIC is not null
union 
select distinct
       a.patid, 
       a.measure_date as bmk_date,
       'BMI' as bmk_type,
       a.bmi as result_num, 
       'ratio' as result_unit,
       case when a.bmi >= 30 then 1 else 0 end as elevated_ind,
       datediff(year,d.birth_date,a.measure_date) as age_at_bmk
from all_bmi a 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d 
on a.patid = d.patid
where a.bmi is not null
;

select count(distinct patid), count(*) from all_bmk_incld
-- 1,006,305	126120067
;

/*
include only those with: 
-- at least a fullset of all the 4 biomarkers between 40 - 60 
-- at least 2 elevated 
-- use the initial full-biomarker year as the index year/age
*/

create or replace table bmk_index_age as 
with bmk_full as (
       select patid, count(distinct bmk_type) as bmk_cnt, min(age_at_bmk) as age_at_bmk
       from  all_bmk_incld
       where age_at_bmk between 40 and 60 and result_num is not null
       group by patid 
       having count(distinct bmk_type) >= 3 and sum(elevated_ind) > 1
)
select a.* exclude rn 
from (
       select distinct a.*, b.age_at_bmk as index_age,
       row_number() over (partition by a.patid, a.bmk_type order by a.bmk_date desc) as rn
from all_bmk_incld a 
join bmk_full b 
on a.patid = b.patid
where a.age_at_bmk between 40 and 60 and a.result_num is not null
) a
where a.rn = 1
;

select count(distinct patid), count(*) from bmk_index_age
;
-- 58164	174679

select * from bmk_index_age 
limit 5;
 
create or replace table bmk_index as
with pvt_val as (
       select * from (
              select patid, index_age, bmk_type, result_num
              from bmk_index_age
       )
       pivot (
              max(result_num)
              for bmk_type in (
                     'BMI',
                     'SBP',
                     'A1C',
                     'LDL'
              )
       ) AS
       p(patid, index_age, BMI, SBP, A1C, LDL)
       order by patid
)
, pvt_ind as (
       select * from (
              select patid, index_age, bmk_type, elevated_ind
              from bmk_index_age
       )
       pivot (
              max(elevated_ind)
              for bmk_type in (
                     'BMI',
                     'SBP',
                     'A1C',
                     'LDL'
              )
       ) AS
       p(patid, index_age, BMI_HIGH, SBP_HIGH, A1C_HIGH, LDL_HIGH)
       order by patid
)
select a.*, b.* exclude (patid, index_age), 
from pvt_val a 
join pvt_ind b
on a.patid = b.patid
;

select count(distinct patid), count(*) from bmk_index
;
-- 58164	58164

select * from bmk_index
limit 5
;

-- exclusion: any elevated bmk before index_age
create or replace table excld_prior_elevated_bmk as 
select distinct a.patid
from all_bmk_incld a
join bmk_index_age b 
on a.patid = b.patid and a.elevated_ind = 1 and a.age_at_bmk < b.index_age
;
select count(*) from excld_prior_elevated_bmk;
-- 16138

-- exclusion: any high-risk diease before 40
create or replace table excld_prior_disease as 
select distinct a.patid
from PCORNET_CDM.CDM.DEID_DIAGNOSIS d
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC demo on d.patid = demo.patid
join bmk_index_age a on a.patid = d.patid
where (
      d.dx like 'C0%' or
      d.dx like 'C1%' or
      d.dx like 'C2%' or
      d.dx like 'C3%' or
      d.dx like 'C4%' or
      d.dx like 'C5%' or
      d.dx like 'C6%' or
      d.dx like 'C7%' or
      d.dx like 'C8%' or
      d.dx like 'C9%' or
      d.dx like 'D0%' or
      d.dx like 'D37%' or
      d.dx like 'D38%' or
      d.dx like 'D39%' or
      d.dx like 'D40%' or
      d.dx like 'D41%' or
      d.dx like 'D42%' or
      d.dx like 'D43%' or
      d.dx like 'D44%' or
      d.dx like 'D45%' or
      d.dx like 'D46%' or
      d.dx like 'D47%' or
      d.dx like 'D48%' or
      d.dx like '14%' or
      d.dx like '15%' or
      d.dx like '16%' or
      d.dx like '17%' or
      d.dx like '18%' or
      d.dx like '19%' or
      d.dx like '20%' or
      d.dx like '23%' or
      d.dx like 'I50%' or
      d.dx like '428%' or
      d.dx like 'N18%' or
      d.dx like 'Z99.2%' or
      d.dx like '585.6%' or
      d.dx like 'K72.1%' or
      d.dx like 'K72.9%' or
      d.dx like '571.2%' or
      d.dx like '571.5%' or
      d.dx like 'J44%' or
      d.dx like 'J96.1%' or
      d.dx like '496%' or
      d.dx like '518.83%' or
      d.dx like 'I21%' or
      d.dx like 'I25%' or
      d.dx like '410%' or
      d.dx like '414%' or
      d.dx like 'I63%' or
      d.dx like 'I69%' or
      d.dx like '434%' or
      d.dx like '438%' or
      d.dx like 'G12.2%' or
      d.dx like '335.2%' or
      d.dx like 'G10%' or
      d.dx like '333.4%' or
      d.dx like 'G20%' or
      d.dx like '332%' or
      d.dx like 'G30%' or
      d.dx like '331.0%'
      ) 
      and 
     datediff(year,demo.birth_date, coalesce(d.dx_date,d.admit_date)) < a.index_age
;

select count(*) from excld_prior_elevated_bmk;
-- 5033

create or replace table bmk_midlife_elig as 
select a.*, demo.sex, demo.race, demo.hispanic
from bmk_index a
join PCORNET_CDM.cdm.DEMOGRAPHIC demo on a.patid = demo.patid
where not exists (
       select 1 from excld_prior_elevated_bmk b 
       where a.patid = b.patid
) and not exists (
       select 1 from  excld_prior_disease d 
       where a.patid = d.patid
)
;

select count(distinct patid), count(*) from bmk_midlife_elig;
-- 40,202

select * from bmk_midlife_elig
limit 5;

/*
identify exposure
*/
select * from SOC_RX_REF limit 5; 

select * from PCORNET_CDM.CDM.DEID_PRESCRIBING  limit 5;
create or replace table all_rel_rx as 
select a.patid, 
       coalesce(p.rx_start_date,p.rx_order_date) as rx_date,
       datediff(year,d.birth_date,coalesce(p.rx_start_date,p.rx_order_date)) as age_at_rx,
       r.cls,
       1 as cls_ind
from bmk_index a 
join PCORNET_CDM.CDM.DEID_PRESCRIBING p on a.patid = p.patid
join SOC_RX_REF r on p.rxnorm_cui = r.rxcui 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d on d.patid = p.patid
where datediff(year,d.birth_date,coalesce(p.rx_start_date,p.rx_order_date)) >= a.index_age
;
select count(distinct patid) from all_rel_rx;
-- 47,982

create or replace table soc_trt as 
select * 
from (
       select distinct patid, cls, cls_ind
       from all_rel_rx
)
pivot (
       max(cls_ind)
       for cls in (
              'AHD',
              'ADD',
              'LLD'
       )
)
as p(patid,AHD_ind,ADD_ind,LLD_ind)
;

select count(distinct patid), count(*) from soc_trt;
-- 47,982

/*
identify outcome/endpoint
*/
create or replace table outcome_dth as 
with calc_age as (
select a.patid, dth.death_date, 
       datediff(year,d.birth_date,dth.death_date) as age_at_death, 
       row_number() over (partition by a.patid order by dth.death_date) as rn
from bmk_index a 
join PCORNET_CDM.cdm.DEID_DEATH dth on a.patid = dth.patid
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d on a.patid = d.patid
)
select patid, 
       age_at_death,
       case when age_at_death <= 75 then 1 else 0 end as premat_dth
from calc_age 
where rn = 1
;

/*
final deid dataset
*/
create or replace table deid_midlife_bmk as 
with combine as (
       select a.patid,
              a.index_age,
              a.bmi,
              a.sbp,
              a.a1c,
              a.ldl,
              coalesce(a.BMI_HIGH,0) as BMI_HIGH,
              coalesce(a.SBP_HIGH,0) as SBP_HIGH,
              coalesce(a.A1C_HIGH,0) as A1C_HIGH,
              coalesce(a.LDL_HIGH,0) as LDL_HIGH,
              coalesce(trt.AHD_ind,0) as AHD_ind,
              coalesce(trt.ADD_ind,0) as ADD_ind,
              coalesce(trt.LLD_ind,0) as LLD_ind,
              coalesce(o.premat_dth,0) as premat_dth
       from bmk_index a 
       left join soc_trt trt on a.patid = trt.patid
       left join outcome_dth o on a.patid = o.patid
)
select c.*, 
       case when c.AHD_ind + ADD_ind + LLD_ind = 0 then 'None'
            when c.AHD_ind + ADD_ind + LLD_ind = 1 then 'Single'
            else 'Multi'
       end as MED_CNT_GRP
from combine c
where c.BMI_HIGH + c.SBP_HIGH + c.A1C_HIGH + c.LDL_HIGH >= 2
;

select count(distinct patid), count(*) from deid_midlife_bmk;
-- 25393	25393
select premat_dth, count(distinct patid), count(*) 
from deid_midlife_bmk
group by premat_dth
;

select * from deid_midlife_bmk limit 5;