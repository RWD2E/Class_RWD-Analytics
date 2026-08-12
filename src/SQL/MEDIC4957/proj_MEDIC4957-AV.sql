/*
Population: T2DM patients
- Inclusion: 
    - patients with at least 2 T2DM diagnoses prior to 2023/01/01
    - patients with no T1DM diagnoses
    - age at diagnosis >= 18
    - at least 2 HbA1C records, with the earlier one recorded after 2023/01/01
Exposure: 
    - T2DM-related telehealth visit
Outcomes:
    - baseline HbA1C
Covariates: 
    - age at initial diagnosis
    - sex 
    - race
    - ethnicity
    - RUCA grouping
    - Payer Type
*/
-- get all t2dm diagnoses
create or replace table all_t2dm_dx as 
select a.*, 
       count(distinct coalesce(a.dx_date, a.admit_date)) over (partition by a.patid) as dx_cnt,
       row_number() over (partition by a.patid order by coalesce(a.dx_date, a.admit_date)) as rn,
       row_number() over (partition by a.patid, case when dx like '250.0%' or dx like 'E11.9%' then 1 else 0 end order by coalesce(a.dx_date, a.admit_date)) as rn_NC 
from DEIDENTIFIED_PCORNET_CDM.CDM.deid_diagnosis a
where dx like '250.%0' or dx like '250.%2' or
      dx like 'E11%'
;

-- get all t2dm diagnoses
create or replace table all_t1dm_dx as 
select a.*, 
       count(distinct coalesce(a.dx_date, a.admit_date)) over (partition by a.patid) as dx_cnt,
       row_number() over (partition by a.patid order by coalesce(a.dx_date, a.admit_date)) as rn,
       row_number() over (partition by a.patid, case when dx like '250.0%' or dx like 'E11.9%' then 1 else 0 end order by coalesce(a.dx_date, a.admit_date)) as rn_NC 
from DEIDENTIFIED_PCORNET_CDM.CDM.deid_diagnosis a
where dx like '250.%1' or dx like '250.%3' or
      dx like 'E10%'
;

-- eligible patients with at least 2 t2dm diagnosis and no t1dm diagnosis
create or replace table pt_init as 
select a.patid, 
       a.encounterid,
       coalesce(a.dx_date::date, a.admit_date::date) as dx1_date,
       a.enc_type
from all_t2dm_dx a
where a.rn = 1 and 
      not exists (select 1 from all_t1dm_dx b where a.patid = b.patid) and 
      dx1_date < '2023-01-01' and 
      a.dx_cnt >= 2
;
select * from pt_init 
limit 5;
select count(distinct patid) as n_patients, count(*)
from pt_init
;

-- get all HbA1C records 
create or replace table all_hba1c as 
select a.patid, 
       b.lab_order_date::date as lab_order_date,
       b.specimen_date::date as specimen_date,
       b.result_date::date as result_date,
       b.result_num, 
       b.result_unit,
       row_number() over (partition by a.patid order by datediff(day,'2023-01-01',coalesce(b.specimen_date,b.result_date,b.lab_order_date))) as rn
from pt_init a 
join DEIDENTIFIED_PCORNET_CDM.CDM.DEID_LAB_RESULT_CM b
on a.patid = b.patid and 
   ( b.lab_loinc in (
          '4548-4'
         ,'4549-2'
         ,'17855-8'
         ,'17856-6'
         ,'41995-2'
         ,'59261-8'
         ,'62388-4'
         ,'71875-9'
         ,'54039-3'
    ) or 
     lower(raw_lab_name) like '%hemoglob%a1c%' or 
     lower(raw_lab_name) like '%hba1c%'
   ) and 
   coalesce(b.specimen_date,b.result_date,b.lab_order_date) >= '2023-01-01'
;

-- get baseline HbA1C records (earliest after 2023/01/01)
create or replace table bl_hba1c as   
select a.patid, 
       coalesce(b.specimen_date,b.result_date,b.lab_order_date) as bl_hba1c_date,
       b.result_num, 
       b.result_unit
from pt_init a
join all_hba1c b
on a.patid = b.patid and
   b.rn = 1 and
   coalesce(b.specimen_date,b.result_date,b.lab_order_date) >= '2023-01-01'
;
select count(distinct patid) as n_patients, count(*)
from bl_hba1c
;

-- include only patients with at least 1 av or th visit during follow-up
-- follow up for 1 year and identify exposure (telehealth visit) 
create or replace table th_1yr as 
with av_any as (
    select a.patid, count(distinct b.admit_date) as av_any_cnt, 1 as av_any_ind
    from bl_hba1c a
    join DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter b
    on a.patid = b.patid and
       b.enc_type = 'AV' and
       b.admit_date between a.bl_hba1c_date and dateadd(day, 365, a.bl_hba1c_date)
    group by a.patid
)
,   th_any as (
    select a.patid, count(distinct b.admit_date) as th_any_cnt, 1 as th_any_ind
    from bl_hba1c a
    join DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter b
    on a.patid = b.patid and
       b.enc_type = 'TH' and
       b.admit_date between a.bl_hba1c_date and dateadd(day, 365, a.bl_hba1c_date)
    group by a.patid
)
,   th_t2dm as (
    select a.patid, count(distinct b.admit_date) as th_t2dm_cnt, 1 as th_t2dm_ind
    from bl_hba1c a
    join all_t2dm_dx b
    on a.patid = b.patid and
       b.enc_type = 'TH' and
       b.admit_date between a.bl_hba1c_date and dateadd(day, 365, a.bl_hba1c_date)
    group by a.patid
)
select a.patid, 
       coalesce(b.av_any_cnt, 0) as av_any_cnt,
       coalesce(b.av_any_ind, 0) as av_any_ind,
       coalesce(c.th_any_cnt, 0) as th_any_cnt,
       coalesce(c.th_any_ind, 0) as th_any_ind,
       coalesce(d.th_t2dm_cnt, 0) as th_t2dm_cnt,
       coalesce(d.th_t2dm_ind, 0) as th_t2dm_ind
from bl_hba1c a
join av_any b on a.patid = b.patid
left join th_any c on a.patid = c.patid
left join th_t2dm d on a.patid = d.patid
;

select * from th_1yr limit 5;

select count(distinct patid) as n_patients, count(*)
from th_1yr
;

select th_any_ind, th_t2dm_ind, count(distinct patid) as n_patients
from th_1yr
group by th_any_ind, th_t2dm_ind
;


-- get outcome HbA1C records (earliest after 1 year of baseline)
create or replace table out_hba1c as 
with oc_rk as(
    select a.patid, 
        a.bl_hba1c_date,
        a.result_num as bl_hba1c_num,
        a.result_unit as bl_hba1c_unit,
        coalesce(b.specimen_date,b.result_date,b.lab_order_date) as oc_hba1c_date,
        b.result_num as oc_hba1c_num, 
        b.result_unit as oc_hba1c_unit, 
        row_number() over (partition by a.patid order by coalesce(b.specimen_date,b.result_date,b.lab_order_date)) as rn
    from bl_hba1c a
    join all_hba1c b
    on a.patid = b.patid and
    coalesce(b.specimen_date,b.result_date,b.lab_order_date) between dateadd(day, 365, a.bl_hba1c_date) and dateadd(day, 730, a.bl_hba1c_date)
)
select * exclude (rn)
from oc_rk
where rn = 1
;

select * from out_hba1c limit 5;

select count(distinct patid) as n_patients, count(*)
from out_hba1c
;

-- add other covariates
create or replace table final_t2dm_th as 
with sdoh_cte as (
    select a.patid, 
           b.ruca,
           row_number() over (partition by a.patid order by abs(datediff('day', a.bl_hba1c_date, coalesce(b.address_period_end,b.address_period_start)))) as rn
    from out_hba1c a
    join DEIDENTIFIED_PCORNET_CDM.CDM.deid_lds_address_history b
    on a.patid = b.patid
)
select a.*,
       round(datediff('day', b.birth_date, a.bl_hba1c_date)/365.25, 0) as age_at_index,
       case when b.sex = 'F' then 1 else 0 end as sex_f,
       case when b.race = '05' then 'white'
            when b.race = '03' then 'black'
            when b.race = '01' then 'aian'
            when b.race = '02' then 'asian'
            when b.race = '04' then 'nhopi'
            when b.race in ('05','OT') then 'other'
            else 'unknown'
        end as race,
       b.hispanic,
       r.ruca as ruca_grp
from out_hba1c a 
join DEIDENTIFIED_PCORNET_CDM.CDM.deid_demographic b
on a.patid = b.patid
join th_1yr s
on a.patid = s.patid
left join sdoh_cte r
on a.patid = r.patid and r.rn = 1
where round(datediff('day', b.birth_date, a.bl_hba1c_date)/365.25, 0) >= 18
;

select * from final_t2dm_th limit 5;

select count(distinct patid) as n_patients, count(*)
from final_t2dm_th
;
-- 7704