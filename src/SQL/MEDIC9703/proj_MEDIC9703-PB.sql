/*                                             
# Description: This script is for extracting an uncomplicated T2DM cohort with their diagnozing HbA1C and Fasting Glucose: 
#  - Inclusion criteria: 
        - at least 1 diagnosis code of uncomplicated T2DM code: 250.0, E11.9
   - Exclusion criteria: 
        - pre-existing T2DM (250, E11)
        - T1DM (E10, 250.x1)
        - Gestational DM (O24.4,648.0)
#  - Exposure: Rural/Urban, ADI
#  - Outcome: FBG and HbA1C at initial diagnosis 
*/

/*
identify eligible patient cohort
*/
-- collect all T2DM diagnoses
create or replace table all_t2dm_dx as 
select a.*, 
       count(distinct coalesce(a.dx_date, a.admit_date)) over (partition by a.patid) as dx_cnt,
       row_number() over (partition by a.patid order by coalesce(a.dx_date, a.admit_date)) as rn,
       row_number() over (partition by a.patid, case when dx like '250.0%' or dx like 'E11.9%' then 1 else 0 end order by coalesce(a.dx_date, a.admit_date)) as rn_NC 
from PCORNET_CDM.CDM.deid_diagnosis a
where dx like '250%' or 
      dx like 'E11%'
;
-- inspect the table
select * from all_t2dm_dx
where rn > 1 and rn_NC = 1
limit 5;

-- 1st dm to be uncomplicated t2dm
-- exclud t1dm and gestational dm
create or replace table ut2dm_incld as
with excld as (
    select distinct patid
    from PCORNET_CDM.CDM.deid_diagnosis
    where dx like 'E10%' or 
          dx like '250.%1' or 
          dx like 'O24.4%' or 
          dx like '648.0%'
) 
select a.patid,
       a.encounterid,
       coalesce(a.dx_date, a.admit_date) as ut2dm_dx1_date,
       a.enc_type,
       a.dx
from all_t2dm_dx a 
where a.rn = 1 and a.rn_NC = 1 and 
      not exists (select 1 from excld where a.patid = excld.patid) and 
      ut2dm_dx1_date >= '2010-01-01'
;

-- inspect the table
select * from ut2dm_incld 
limit 5
;

-- attach needed information from demographic table and calculate age at index date
create or replace table ut2dm_incld_demo as
select ut2dm_incld.*,
       demo.sex, 
       demo.race,
       demo.hispanic,
       datediff(year,demo.birth_date,ut2dm_incld.ut2dm_dx1_date) as age_at_dx_date1,
from ut2dm_incld
join PCORNET_CDM.CDM.deid_demographic demo
on ut2dm_incld.patid = demo.patid
;
-- check for duplicates
select count(*), count(distinct patid) 
from ut2dm_incld_demo
;
-- 65370

/*
identify exposure: Rurality, ADI
*/
create or replace table ut2dm_geocode as 
with geocode_rk as (
    select a.patid, 
        a.ut2dm_dx1_date,
        b.address_period_start,
        b.address_period_end,
        b.FIPS_BLOCK_GROUP_ID_2020,
        b.FIPS_TRACT_ID_2020, 
        datediff(day,a.ut2dm_dx1_date, b.address_period_start) as Days_DX1_Addr,
        row_number() over (partition by a.patid order by abs(datediff(day,a.ut2dm_dx1_date, b.address_period_start))) as rn
    from ut2dm_incld_demo a 
    join PCORNET_CDM.CDM.private_geocoded_address_view b
    on a.patid = b.patid
    where substr(b.FIPS_TRACT_ID_2020,1,2) = '29'
)
select geocode_rk.* exclude rn 
from geocode_rk
where rn = 1
;

select * from ut2dm_geocode
limit 5;

select count(*), count(distinct patid) 
from ut2dm_geocode
;
-- 44,404

create or replace table ut2dm_rural_adi as
with geocode_rk as (
    select distinct
        a.patid, 
        -- a.FIPS_BLOCK_GROUP_ID_2020,
        -- a.FIPS_TRACT_ID_2020,
        adi.ADI_STATERANK,
        case when adi.ADI_STATERANK in ('1','2','3') then 'low'
             when adi.ADI_STATERANK in ('4','5','6','7') then 'mid'
             when adi.ADI_STATERANK in ('8','9','10') then 'high'
             else 'NI'
        end as ADI_STATERANK_GRP,
        -- ruca.URBANCORETYPE,
        case when ruca.URBANCORE = 1 then 0 else 1 end as RURAL_RUCA,
        case when hrsa.COUNTY_ELIGIBILITY = 'Fully FORHP Rural' then 1 else 0 end as RURAL_HRSA,
        row_number() over (partition by a.patid order by ruca.URBANCORE, adi.ADI_STATERANK desc) as rn
    from ut2dm_geocode a 
    left join SDOH_DB.ADI.ADI_BG_2020 adi on a.FIPS_BLOCK_GROUP_ID_2020 = adi.geocodeid
    left join SDOH_DB.RUCA.RUCA_CT_2020 ruca on a.FIPS_TRACT_ID_2020 = ruca.TRACTFIPS20
    left join SDOH_DB.HRSA.FORHP_RURAL_CN hrsa on substr(a.FIPS_TRACT_ID_2020,1,5) = hrsa.FIPS_2023
    where adi.ADI_STATERANK not in ('GQ','GQ-PH','PH')
)
select geocode_rk.* exclude rn 
from geocode_rk
where rn = 1
;
select * from ut2dm_rural_adi
-- where RURAL_RUCA is null
limit 5
;
select count(*), count(distinct patid) 
from ut2dm_rural_adi
;
-- 43242

create or replace table ut2dm_incld_demo_rural_adi as 
select a.*, 
       b.* exclude patid 
from ut2dm_incld_demo a 
join ut2dm_rural_adi b 
on a.patid = b.patid
;
select count(*), count(distinct patid) 
from ut2dm_incld_demo_rural_adi
;
-- 43,242

/*
identify outcome: fasting glucose and HbA1C within +- 4 months since initial DM diagnosis
*/
create or replace table all_hba1c as 
select a.patid, 
       b.lab_order_date,
       b.specimen_date,
       b.result_date,
       b.result_num, 
       b.result_unit,
       datediff(month,a.ut2dm_dx1_date,coalesce(b.specimen_date,b.result_date,b.lab_order_date)) as MONTH_DX1_LAB,
       row_number() over (partition by a.patid order by abs(datediff(month,a.ut2dm_dx1_date,coalesce(b.specimen_date,b.result_date,b.lab_order_date)))) as rn
from ut2dm_incld_demo_rural_adi a 
join PCORNET_CDM.cdm.DEID_LAB_RESULT_CM b 
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
   )
   and
   abs(datediff(month,a.ut2dm_dx1_date,coalesce(b.specimen_date,b.result_date,b.lab_order_date))) <= 4 
;

select count(distinct patid) from all_hba1c;
-- 19,029

select * from all_hba1c 
-- where result_unit <> '%'
limit 5; 


select * from PCORNET_CDM.cdm.DEID_LAB_RESULT_CM limit 5;

create or replace table all_fbg as 
select a.patid, 
       b.lab_order_date,
       b.specimen_date,
       b.result_date,
       b.result_num, 
       b.result_unit,
       datediff(month,a.ut2dm_dx1_date,coalesce(b.specimen_date,b.result_date,b.lab_order_date)) as MONTH_DX1_LAB
from ut2dm_incld_demo_rural_adi a 
join PCORNET_CDM.cdm.DEID_LAB_RESULT_CM b 
on a.patid = b.patid and 
   ( b.lab_loinc in (
          '1558-6'
         ,'10450-5'
         ,'1554-5'
         ,'17865-7'
         ,'35184-1'
         ,'101476-0'
         ,'14770-2'
         ,'14771-0'
         ,'76629-5'
         ,'77145-1'
    ) or 
     lower(raw_lab_name) like '%fasting%glucose%'
   )    
   and
   abs(datediff(month,a.ut2dm_dx1_date,coalesce(b.specimen_date,b.result_date,b.lab_order_date))) <= 4 
;
select count(distinct patid) from all_fbg;
-- 153


/*
final dataset
*/

create or replace table DEID_UT2DM_SDH as 
with hba1c_uni as (
       select * from all_hba1c
       where rn = 1
)
select a.patid, 
       a.age_at_dx_date1 as age_at_t2dm,
       a.sex,
       a.race,
       a.hispanic,
       h.result_num as hba1c, 
       s.ADI_STATERANK,
       s.adi_staterank_grp,
       s.rural_ruca,
       s.rural_hrsa
from ut2dm_incld_demo a 
join hba1c_uni h on a.patid = h.patid
join ut2dm_rural_adi s on a.patid = s.patid 
;

select count(distinct patid), count(*) from DEID_UT2DM_SDH;

select * from DEID_UT2DM_SDH 
limit 5;