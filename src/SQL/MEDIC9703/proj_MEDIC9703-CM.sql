/*                                             
# Description:   
#  - Inclusion criteria: 
        - IP, ED, EI encounters in past 5 years
        - with at least 1 blood culture draw
   - Exclusion criteria: 
        - any encounters with incomplete data to calculate TAT
#  - Exposure: facility location (rural/urban, RUCA); TAT 
#  - Outcome: bacteremia diagnoses within 48 hours
*/

/*
identify eligible patient cohort
*/
-- all ED,EI,IP visits between 06/30/2021 to 06/30/2025
create or replace table all_elig_enc as 
select a.patid, 
       a.encounterid,
       a.enc_type,
       a.admit_date,
       a.discharge_date,
       a.admitting_source,
       a.facility_type,
       a.facility_location,
       a.discharge_disposition,
       a.discharge_status,
       a.drg,
       a.facilityid,
       datediff(year,d.birth_date,a.admit_date) as age_at_enc,
       d.sex, 
       d.race, 
       d.hispanic
from PCORNET_CDM.CDM.DEID_ENCOUNTER a 
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d on a.patid = d.patid
where a.enc_type in ('ED','EI','IP') and 
      a.admit_date between '2021-06-30' and '2025-06-30' and 
      datediff(year,d.birth_date,a.admit_date) >= 18 and 
      a.admitting_source not in ('IP','NH','RH','SN','IH')
;

select count(distinct patid), count(distinct encounterid) from all_elig_enc
;
-- 133856	326271


select facility_location, count(distinct encounterid)
from all_elig_enc 
group by facility_location
;

select facilityid, count(distinct encounterid)
from all_elig_enc 
group by facilityid
order by count(distinct encounterid) desc
;


/*
identify exposure: TAT
*/

-- identify eligible blood culture precedures 
create or replace table lab_bc_incld as
with loinc_b as (
      SELECT distinct split_part(c_basecode,':',2) as loinc 
      FROM ontology.act_ontology.ACT_LOINC_LAB_PROV_V4 
      WHERE c_dimcode LIKE '%ACT%Lab%LOINC%V2_2018AA%A6321000%A23478825%A28298479%A18322541%A18206717%A18166817%' and 
            c_basecode like 'LOINC%'
),   loinc_f as (
      SELECT distinct split_part(c_basecode,':',2) as loinc 
      FROM ontology.act_ontology.ACT_LOINC_LAB_PROV_V4 
      WHERE c_dimcode LIKE '%ACT%Lab%LOINC%V2_2018AA%A6321000%A23478825%A28298479%A18322541%A18206717%A18360666%' and 
            c_basecode like 'LOINC%'
)
select distinct 
       p.patid, 
       p.encounterid,
       TIMESTAMP_NTZ_FROM_PARTS(p.admit_date, e.admit_time) as admit_datetime,
       'b' as bc_type, 
       l.lab_order_date,
       greatest(datediff(day,p.admit_date,l.lab_order_date),0) as hospital_day,
       TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time) as specimen_datetime,
       l.result_date,
       TIMESTAMP_NTZ_FROM_PARTS(l.result_date, l.result_time) as result_datetime,
       greatest(datediff(day,l.lab_order_date,l.result_date),0) as TAT_order_rslt_day,
       datediff(hour, TIMESTAMP_NTZ_FROM_PARTS(p.admit_date, e.admit_time), TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time)) as TAT_admit_spec_hr,
       datediff(hour, TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time),TIMESTAMP_NTZ_FROM_PARTS(l.result_date, l.result_time)) as TAT_spec_rslt_hr
from PCORNET_CDM.CDM.DEID_PROCEDURES p 
join PCORNET_CDM.CDM.DEID_ENCOUNTER e on p.patid = e.patid and p.encounterid = e.encounterid
join all_elig_enc a on p.patid = a.patid and a.encounterid = p.encounterid
join PCORNET_CDM.CDM.DEID_LAB_RESULT_CM l on p.patid = l.patid and p.encounterid = l.encounterid
where p.px = '87040' and 
      exists (select 1 from loinc_b where loinc_b.loinc = l.lab_loinc) and 
      TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time) is not null
union 
select distinct 
       p.patid, 
       p.encounterid,
       TIMESTAMP_NTZ_FROM_PARTS(p.admit_date, e.admit_time) as admit_datetime,
       'f' as bc_type,
       l.lab_order_date,
       greatest(datediff(day,p.admit_date,l.lab_order_date),0) as hospital_day,
       TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time) as specimen_datetime,
       l.result_date,
       TIMESTAMP_NTZ_FROM_PARTS(l.result_date, l.result_time) as result_datetime,
       greatest(datediff(day,l.lab_order_date,l.result_date),0) as TAT_order_rslt_day,
       datediff(hour, TIMESTAMP_NTZ_FROM_PARTS(p.admit_date, e.admit_time), TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time)) as TAT_admit_spec_hr,
       datediff(hour, TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time),TIMESTAMP_NTZ_FROM_PARTS(l.result_date, l.result_time)) as TAT_spec_rslt_hr
from PCORNET_CDM.CDM.DEID_PROCEDURES p 
join PCORNET_CDM.CDM.DEID_ENCOUNTER e on p.patid = e.patid and p.encounterid = e.encounterid
join all_elig_enc a on p.patid = a.patid and a.encounterid = p.encounterid
join PCORNET_CDM.CDM.DEID_LAB_RESULT_CM l on p.patid = l.patid and p.encounterid = l.encounterid
where p.px = '87104'  and 
      exists (select 1 from loinc_f where loinc_f.loinc = l.lab_loinc) and 
      TIMESTAMP_NTZ_FROM_PARTS(l.specimen_date, l.specimen_time) is not null
;

select * from lab_bc_incld 
order by TAT_spec_rslt_hr desc
limit 50;

select count(distinct patid), count(distinct encounterid), count(*) 
from lab_bc_incld;
-- 8980	12149   23849

select count(distinct patid), count(distinct encounterid), count(*) 
from lab_bc_incld
where TAT_spec_rslt_hr > 0
;
-- 16

select count(distinct patid), count(distinct encounterid), count(*) 
from lab_bc_incld
where TAT_order_rslt_day > 0
;
-- 2074	2300	2815

create or replace table lab_bc_elig as 
select distinct
      patid,
      encounterid,
      bc_type,
      min(lab_order_date) as lab_order_date,
      max(result_date) as result_date,
      sum(TAT_order_rslt_day) as  TAT_order_rslt_day    
from lab_bc_incld
-- where TAT_order_rslt_day > 0
group by patid, encounterid, bc_type
;

select count(distinct patid), count(distinct encounterid), count(*) 
from lab_bc_elig;
--8980	12149	17576

select TAT_order_rslt_day, count(distinct patid), count(distinct encounterid), count(*) 
from lab_bc_elig
group by TAT_order_rslt_day
order by TAT_order_rslt_day
;

select * from lab_bc_elig 
order by patid, encounterid
limit 50;


/*
identify outcome/endpoint
*/
create or replace table sep_all_dx as 
select distinct
       a.patid, 
       a.encounterid,
       datediff(day,a.result_date,d.dx_date) as days_bc_sep, 
       case when datediff(day,a.result_date,d.dx_date) <= 2 then 1 else 0 end as sepsis_48h_ind
from lab_bc_elig a 
join PCORNET_CDM.CDM.DEID_DIAGNOSIS d
on a.patid = d.patid and a.encounterid = d.encounterid
where (d.dx like 'A40%' or d.dx like 'A41%' or d.dx like 'R78.81%')  and 
      datediff(day,a.result_date,d.dx_date) >= 0
;
select days_bc_sep, count(distinct patid), count(distinct encounterid), count(*)
from sep_all_dx
group by days_bc_sep
order by days_bc_sep
;

select sepsis_48h_ind, count(distinct patid), count(distinct encounterid), count(*)
from sep_all_dx
group by sepsis_48h_ind
;

create or replace table sep_outcome as 
select patid, encounterid, 
       max(sepsis_48h_ind) as sepsis_48h_ind
from sep_all_dx
group by patid, encounterid
;

/*
final deid dataset
*/
create or replace table DEID_BC_TAT as 
select distinct
       a.patid,
       a.age_at_enc,
       a.sex,
       a.race, 
       a.hispanic,
       a.encounterid,
      --  a.facilityid,
       a.facility_location,
       b.bc_type,
       b.TAT_order_rslt_day,
       coalesce(o.sepsis_48h_ind,0) as sepsis_48h_ind
from all_elig_enc a 
join lab_bc_elig b on a.patid = b.patid and a.encounterid = b.encounterid
left join sep_outcome o on a.patid = o.patid and a.encounterid = o.encounterid
;

select count(distinct patid), count(distinct encounterid), count(*)
from DEID_BC_TAT
;
-- 8980	12149	12149

select sepsis_48h_ind, count(distinct patid), count(distinct encounterid), count(*)
from DEID_BC_TAT
group by sepsis_48h_ind
;

select * from DEID_BC_TAT 
limit 15;
