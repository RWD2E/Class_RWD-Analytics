/*                                           
# Description: This script is for extracting an example study cohort
#  - Inclusion criteria: 
        - at least 2 diagnoses codes of ALS at different date
        - initial diagnosis code occured 
#  - Exposure: use of Riluzole
#  - Outcome: all-cause mortality
*/

/* 
create a patient table with following informations in separate columns: 
- DX_CNT: counts of distinct ALS diagnosis (on different dates)
- DX_DATE1: first date of ALS diagnosis
*/

select * from deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_obs_clin
where lower(raw_obsclin_name) like '%glasgow%'
;

-- collect all diagnoses about ALS
create or replace table all_als_dx as 
select * 
from deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_diagnosis
where dx in ('335.20','G12.21')
-- where (dx_type = '09' and dx = '335.20') or (dx_type = '10' and dx='G12.21')
;
-- inspect the table
select * from all_als_dx limit 5;

-- gather some summary statistics needed for following steps
create or replace table als_incld as 
select patid,
       count(distinct dx_date) as dx_cnt, 
       min(dx_date) as dx_date1
from all_als_dx
group by patid
;
-- inspect the table
select * from als_incld;

/*
create a patient demographic table with the following information: 
- AGE_AT_DX_DATE1: age at first ALS diagnosis date
- SEX
- RACE
- ETHNICITY
*/
-- attach needed information from demographic table and calculate age at index date
create or replace table als_incld_demo as
select als_incld.*,
       demo.sex, 
       demo.race,
       demo.hispanic as ethnicity,
       datediff(year,demo.birth_date,als_incld.dx_date1) as age_at_dx_date1
from als_incld
join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_demographic demo
on als_incld.patid = demo.patid
where als_incld.dx_cnt >= 2
;
-- check for duplicates
select count(*), count(distinct patid) 
from als_incld_demo
;
       
/*
create an exposure table of riluzole use status with following information collected in separate columns: 
- RILUZOLE_IND: an indicator of riluzole use
- RILUZOLE_DUR: days difference between first riluzole use and last riluzole use
*/
-- build a look up table of rxnorm_cui/rxcui codes for the medication with ingredient "riluzole"
create or replace table riluz_rxnorm as
select rxcui 
from ontology.rxnorm.rxnconso
where lower(str) like '%riluzol%' and sab = 'RXNORM'
;

-- collect all prescriptions of riluzole
create or replace table all_riluzole_als as
select pr.*
from deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_prescribing pr
join als_incld_demo als 
on pr.patid = als.patid
join riluz_rxnorm rxn 
on pr.rxnorm_cui = rxn.rxcui
;
-- inspect the table
select * from all_riluzole_als
order by patid, rx_order_date;

-- gather some summary statistics for riluzole use
create or replace table als_riluz as
select patid, datediff(day, min(rx_start_date), max(rx_start_date)) as riluzole_dur, 
       1 as riluzole_ind 
from all_riluzole_als
group by patid
;
-- check for duplicates
select count(*), count(distinct patid) 
from als_riluz;


/*
create an outcome table with following information collected in separate columns: 
- OUTCOME_STATUS: an indicator of mortality: 1 if a death date is observed; 0 otherwise
- OUTCOME_DATE: date of the outcome: death date if DEATH_IND = 1; last encounter date if DEATH_IND = 0
*/
-- collect all death date data
create or replace table outcome_death as 
select distinct dth.patid, dth.death_date::date as death_date
from deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_death dth 
join als_incld_demo als 
on dth.patid = als.patid 
;
-- duplicate check
select count(*), count(distinct patid)
from outcome_death;
-- it seems that there could be multiple death records per patient

-- inspect the duplicated cases
with patid_dup as (
    select patid, count(distinct death_date)
    from outcome_death
    group by patid
    having count(distinct death_date) > 1
)
select a.* 
from outcome_death a
join patid_dup b
on a.patid = b.patid
order by a.patid, a.death_date
;

-- create a helper table to identify conflict death dates
create or replace table outcome_death_dup as 
select patid, count(distinct death_date) as dup_cnt
from outcome_death 
group by patid
;

-- create final deduplicated death table 
create or replace table outcome_death_dedup as
select dth.patid, 
       1 as outcome_status,
       dth.death_date as outcome_date
from outcome_death dth 
where exists (
 select 1 from outcome_death_dup dup where dup.patid = dth.patid and dup.dup_cnt = 1
)
;
-- duplicate check
select count(*), count(distinct patid)
from outcome_death_dedup;

-- create a censor table for patients who are still alive
create or replace table outcome_censor as 
select a.patid, 
       max(b.admit_date) as censor_date
from als_incld_demo a 
join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_encounter b
on a.patid = b.patid
where b.admit_date::date <= '2024-12-31'
group by a.patid
;

-- putting the death table and censor table together
create or replace table outcome_final as 
select demo.patid, 
       case when dth.outcome_status = 1 then 1 else 0 end as outcome_status,
       case when dth.outcome_date is not null then dth.outcome_date else cs.censor_date end as outcome_date
from als_incld_demo demo
left join outcome_death_dedup dth
on demo.patid = dth.patid
left join outcome_censor cs
on demo.patid = cs.patid
;
-- think about why I have to do "left join"

--inspect the table
select * from outcome_final;

/*
now, putting everything together and create final analytic dataset
*/
create or replace table als_riluzole_death_final as 
select demo.*,
       case when r.riluzole_ind = 1 then 1 else 0 end as riluzole_ind,
       case when r.riluzole_dur is not null then r.riluzole_dur else 0 end as riluzole_dur,
       o.outcome_status,
       o.outcome_date
from  als_incld_demo demo
left join als_riluz r 
on demo.patid = r.patid
left join outcome_final o 
on demo.patid = o.patid
;
-- think about why I have to do "left join"

select count(*), count(distinct patid) from als_riluzole_death_final;

select * from als_riluzole_death_final limit 5;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

/*add baseline BMI*/
create or replace table als_elig_bmi as 
with ht as (
    select a.patid, median(v.ht) as ht, 
    from als_incld_demo a 
    join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_vital v 
    on a.patid = v.patid
    group by a.patid
),  wt as (
    select patid, wt
    from (
        select a.patid, v.wt, 
               row_number() over (partition by a.patid order by abs(datediff(day,a.dx_date1::date,v.measure_date::date))) as rn 
        from als_incld_demo a 
        join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_vital v 
        on a.patid = v.patid 
        -- where datediff(year,a.dx_date1::date,v.measure_date::date) between 2 and -10
    )
    where rn = 1
), bmi as (
    select patid, original_bmi as bmi
    from (
        select a.patid, v.original_bmi, 
               row_number() over (partition by a.patid order by abs(datediff(day,a.dx_date1::date,v.measure_date::date))) as rn 
        from als_incld_demo a 
        join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_vital v 
        on a.patid = v.patid 
        -- where datediff(year,a.dx_date1::date,v.measure_date::date) between 2 and -10
    )
    where rn = 1
)
select a.patid, 
       ht.ht,
       wt.wt,
       coalesce(bmi.bmi,wt.wt/(ht.ht*ht.ht)*703) as bmi
from als_incld_demo a 
left join ht on a.patid = ht.patid
left join wt on a.patid = wt.patid
left join bmi on a.patid = bmi.patid
;

select * from als_elig_bmi;

select distinct code_grp from class_member_bbme8550_db.public.cci_ref;

/*add CCI*/
create or replace table als_bl_cci as 
with dx_all as (
    select a.patid, 
           c.code_grp,
           c.score,
           row_number() over (partition by a.patid,c.code_grp order by datediff(day,coalesce(b.dx_date,b.admit_date),a.dx_date1)) as rn
    from als_incld_demo a
    join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_diagnosis b
    on a.patid = b.patid and coalesce(b.dx_date,b.admit_date)<= a.dx_date1
    join class_member_bbme8550_db.public.cci_ref c 
    on b.dx = c.code and b.dx_type = c.code_type
), dx_cci_tot as (
    select patid, sum(score) as cci_tot
    from dx_all 
    where rn = 1
    group by patid
), cci_unpvt as (
    select * 
    from (
        select patid, code_grp, 1 as ind 
        from dx_all where rn = 1
    ) 
    pivot (max(ind) for code_grp in (
        'mi','chf','pvd','dementia','cpd','rheumd','pud','mld','diab','diabwc','hp','rend','canc','msld','metacanc','cevd','aids'))
        as p(patid,mi,chf,pvd,dementia,cpd,rheumd,pud,mld,diab,diabwc,hp,rend,canc,msld,metacanc,cevd,aids)
)
select a.patid, 
       coalesce(tot.cci_tot,0) as cci_tot,
       coalesce(cci.mi,0) as cci_mi,
       coalesce(cci.chf,0) as cci_chf,
       coalesce(cci.pvd,0) as cci_pvd,
       coalesce(cci.dementia,0) as cci_dementia,
       coalesce(cci.cpd,0) as cci_cpd,
       coalesce(cci.rheumd,0) as cci_rheum,
       coalesce(cci.pud,0) as cci_pud,
       coalesce(cci.mld,0) as cci_mld,
       coalesce(cci.diab,0) as cci_diab,
       coalesce(cci.diabwc,0) as cci_diabwc,
       coalesce(cci.hp,0) as cci_hp,
       coalesce(cci.rend,0) as cci_rend,
       coalesce(cci.canc,0) as cci_canc,
       coalesce(cci.msld,0) as cci_msld,
       coalesce(cci.metacanc,0) as cci_metacanc,
       coalesce(cci.cevd,0) as cci_cevd,
       coalesce(cci.aids,0) as cci_aids
from als_incld_demo a 
left join dx_cci_tot tot on a.patid = tot.patid
left join cci_unpvt cci on a.patid =  cci.patid
;

select * from als_bl_cci;

/*add baseline function*/
create or replace table als_bl_fs as 
with fs_stk as (
    select a.patid,
           b.obsclin_result_text,
           b.obsclin_result_num,
           b.obsclin_date,
           b.obsclin_code,
           b.raw_obsclin_name,
           row_number() over (partition by a.patid order by datediff(day,b.obsclin_date,a.dx_date1)) as rn
    from als_incld_demo a 
    join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_obs_clin b 
    on a.patid = b.patid
    where b.raw_obsclin_name in (
        'LUE Grip Strength',
        'RUE Grip Strength',
        'Characteristics of Speech'
    ) and 
    datediff(day,b.obsclin_date,a.dx_date1) <= 60
), fs_unpvt as (
    select *
    from (select patid,raw_obsclin_name,obsclin_result_text from fs_stk where rn = 1)
        pivot(max(obsclin_result_text) for raw_obsclin_name in ('LUE Grip Strength','RUE Grip Strength','Characteristics of Speech'))
        as p(patid,lgs,rgs,speech)
    order by patid
)
select a.patid,
       coalesce(replace(trim(b.lgs,' '),'###',''),'Fair') as lgs,
       coalesce(replace(trim(b.rgs,' '),'###',''),'Fair') as rgs,
       coalesce(replace(trim(b.speech,' '),'###',''),'Normal') as speech
from als_incld_demo a
left join fs_unpvt b 
on a.patid = b.patid
;

select * from als_bl_fs;


/*add baseline symptoms*/
create or replace table als_bl_sos as 
with sos_dx as (
    select a.patid, 
           c.endpt_grp,
           c.endpt,
           row_number() over (partition by a.patid,c.endpt order by datediff(day,coalesce(b.dx_date,b.admit_date),a.dx_date1)) as rn
    from als_incld_demo a
    join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_diagnosis b
    on a.patid = b.patid and datediff(day,coalesce(b.dx_date,b.admit_date),a.dx_date1) <= 60
    join class_member_bbme8550_db.public.als_stage_ref c 
    on b.dx = c.cd and b.dx_type = c.cd_type
),  sos_px as (
    select a.patid, 
           c.endpt_grp,
           c.endpt,
           row_number() over (partition by a.patid,c.endpt order by datediff(day,coalesce(b.px_date,b.admit_date),a.dx_date1)) as rn
    from als_incld_demo a
    join deidentified_pcornet_CDM_C016R033.CDM_C016R033.deid_procedures b
    on a.patid = b.patid and datediff(day,coalesce(b.px_date,b.admit_date),a.dx_date1) <= 60
    join class_member_bbme8550_db.public.als_stage_ref c 
    on b.px = c.cd and b.px_type = c.cd_type
),  sos_unpvt as (
    select * 
    from (
        select patid, endpt, rn from sos_dx where rn = 1
        union 
        select patid, endpt, rn from sos_px where rn = 1
    ) 
    pivot (max(rn) for endpt in ('nutrition-support','respiratory-support'))
    as p(patid, nutr_supp, resp_supp)
)
select a.patid, 
      coalesce(b.nutr_supp,0) as nutr_supp,
      coalesce(b.resp_supp,0) as resp_supp
from als_incld_demo a 
left join sos_unpvt b 
on a.patid = b.patid
;

select * from als_bl_sos;
