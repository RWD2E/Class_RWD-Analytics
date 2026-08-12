/*
Population: established patients with an initial diagnosis of depression or anxiety after 2023/01/01
- Inclusion: 
    - patients with an initial diagnosis of depression or anxiety after 2023/01/01
    - patients with at least 1 in-person encounter within 1-year prior to the initial depression or anxiety diagnosis
Exposure: 
    - initial diagnosis occurred during an AV or ED visit
Outcomes:
    - 30-day, 90-day follow-up visits
Covariates: 
    - age at initial diagnosis
    - sex 
    - race
    - ethnicity
    - RUCA grouping
    - ADI
    - Payer Type
*/

-- extract all patients with at least 1 depression or anxiety diagnosis, with timestamp
create or replace table all_mdd_anx_dx as
select distinct
       dx.patid,
       dx.encounterid,
       coalesce(dx.dx_date::date, dx.admit_date::date) as dx_date,
       dx.enc_type,
       'mdd' as dx_grp,
       row_number() over (partition by dx.patid order by coalesce(dx.dx_date, dx.admit_date)) as rn
from DEIDENTIFIED_PCORNET_CDM.CDM.deid_diagnosis dx
where dx.dx like 'F32%' or 
      dx.dx like 'F33%' or 
      dx.dx like '311%' or dx.dx like '296.2%' or dx.dx like '296.3%' or dx.dx like '300.4%'
union
select distinct
       dx.patid,
       dx.encounterid,
       coalesce(dx.dx_date::date, dx.admit_date::date) as dx_date,
       dx.enc_type,
       'anx' as dx_grp,
       row_number() over (partition by dx.patid order by coalesce(dx.dx_date, dx.admit_date)) as rn
from DEIDENTIFIED_PCORNET_CDM.CDM.deid_diagnosis dx
where dx.dx like 'F40%' or 
      dx.dx like 'F41%' or 
      dx.dx like '300.0%' or dx.dx like '300.02%'
;
select count(distinct patid) as n_patients, 
       count(distinct encounterid) as n_encounters
from all_mdd_anx_dx
;

select * from DEIDENTIFIED_PCORNET_CDM.CDM.deid_provider limit 5;

select * from DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter where facility_type is not null; 

-- summarize to get initial diagnosis dates (index date) and encounter types
-- filter to only after 2023/01/01
-- attach other encounter-level information for the index visit
create or replace table init_mdd_anx as 
with cte as (
    select * exclude (rn)
    from all_mdd_anx_dx 
    where rn = 1 
        and dx_date >= '2023-01-01'
        and enc_type in ('AV', 'ED', 'EI', 'IP', 'OS', 'TH')
)
,   dedup_enc as (
    select cte.*, 
        enc.facility_type, 
        enc.payer_type_primary,
        case when enc.payer_type_primary like '1%' then 'medicare'
             when enc.payer_type_primary like '2%' then 'medicaid'
             when enc.payer_type_primary like '3%' then 'private'
             when enc.payer_type_primary is null or enc.payer_type_primary in ('NI', 'UN', '99', '9999') then 'unknown'
             else 'other'
        end as payer_grp,
        enc.discharge_disposition,
        enc.discharge_status,
        enc.providerid,
        prvdr.provider_specialty_primary,
        row_number() over (
            partition by cte.patid order by 
            case when prvdr.provider_specialty_primary <> 'NI' then 1 else 0 end desc,
            case when REGEXP_LIKE(enc.payer_type_primary, '^[0-9]+$') then 1 else 0 end desc
        ) as enc_rn
    from cte
    left join DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter enc
    on cte.encounterid = enc.encounterid and cte.patid = enc.patid
    left join DEIDENTIFIED_PCORNET_CDM.CDM.deid_provider prvdr
    on enc.providerid = prvdr.providerid
)
select * exclude (enc_rn) 
from dedup_enc
where enc_rn = 1
;
select * from init_mdd_anx 
-- where facility_type is not null
limit 5
;

select count(distinct patid) as n_patients, 
       count(distinct encounterid) as n_encounters 
from init_mdd_anx
;

-- collect all in-person encounters with relative timestamps to index date
create or replace table enc_logs as 
with office_etc as (
    select distinct patid, encounterid, 1 as office_ind 
    from DEIDENTIFIED_PCORNET_CDM.CDM.deid_procedures
    where px in ('99201', '99202', '99203', '99204', '99205', '99211', '99212', '99213', '99214', '99215')
)
select idx.patid, 
       idx.dx_date as index_date, 
       enc.encounterid, 
       enc.enc_type, 
       enc.admit_date::date as admit_date,
       enc.discharge_date::date as discharge_date,
       datediff('day', enc.admit_date::date, enc.discharge_date::date) as los,
       datediff('day',idx.dx_date::date, enc.admit_date::date) as days_from_index,
       coalesce(office_etc.office_ind, 0) as office_ind
from init_mdd_anx idx
join DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter enc on enc.patid = idx.patid
left join office_etc on enc.patid = office_etc.patid and enc.encounterid = office_etc.encounterid
;

select * from enc_logs 
limit 5
;

select office_ind, enc_type, count(distinct patid) as n_patients, 
       count(distinct encounterid) as n_encounters
from enc_logs
group by office_ind, enc_type
order by enc_type, office_ind
;

-- substance use disorder diagonsis
create or replace table bl_sub as
select distinct a.patid, 1 as sub_ind
from init_mdd_anx a
join DEIDENTIFIED_PCORNET_CDM.CDM.deid_diagnosis dx
on a.patid = dx.patid
where (
        dx.dx like 'F10%' or 
        dx.dx like 'F11%' or 
        dx.dx like 'F12%' or 
        dx.dx like 'F13%' or 
        dx.dx like 'F14%' or 
        dx.dx like 'F15%' or 
        dx.dx like 'F16%' or 
        dx.dx like 'F17%' or 
        dx.dx like 'F18%' or 
        dx.dx like 'F19%'
     )
     and dx.dx_date <= a.dx_date
;

-- identify established patients with at least 1-year lookback period 
-- derive 30d, 90d follow-up visit indicator
-- derive baseline visits
create or replace table pats_vis as
with lookback as (
    select patid, index_date,
           min(days_from_index) as days_from_enc1
    from enc_logs
    group by patid, index_date
)
,    bl_av as (
    select patid,
           count(distinct admit_date) as base_op_n
    from enc_logs 
    where days_from_index between -365 and -1 and enc_type = 'AV'
    group by patid
)
,    bl_ip as (
    select patid,
           count(distinct admit_date) as base_ed_n
    from enc_logs 
    where days_from_index between -365 and -1 and enc_type in ('ED', 'EI')
    group by patid
)
,    post_vis as (
    select distinct
           a.patid,
           a.index_date,
           b.dx_date, 
           datediff('day', a.index_date, b.dx_date) as days_from_index,
           b.dx_grp,
           b.enc_type, 
           case when datediff('day', a.index_date, b.dx_date) between 1 and 30 and b.enc_type = 'AV' then 1 else 0 end as fu_30d,
           case when datediff('day', a.index_date, b.dx_date) between 1 and 90 and b.enc_type = 'AV' then 1 else 0 end as fu_90d,
           case when datediff('day', a.index_date, b.dx_date) between 1 and 180 and b.enc_type in ('IP','EI') then 1 else 0 end as acute_180d,
    from lookback a 
    join all_mdd_anx_dx b 
    on a.patid = b.patid
    where b.dx_date > a.index_date and 
          b.enc_type in ('AV', 'ED', 'IP', 'EI') and
          a.days_from_enc1 <= -365
)
select a.patid,
       a.index_date,
       coalesce(b.base_op_n, 0) as base_op_n,
       coalesce(c.base_ed_n, 0) as base_ed_n,
       max(a.fu_30d) as fu_30d,
       max(a.fu_90d) as fu_90d,
       max(a.acute_180d) as acute_180d
from post_vis a
left join bl_av b on a.patid = b.patid
left join bl_ip c on a.patid = c.patid
group by a.patid,a.index_date,coalesce(b.base_op_n, 0), coalesce(c.base_ed_n, 0)
;

select * from pats_vis 
limit 5
;

select count(distinct patid) as n_patients, count(*)
from pats_vis
;

-- attach demographic and sdoh information
create or replace table final_mdd_anx as 
with sdoh_cte as (
    select a.patid, 
           b.ruca,
           row_number() over (partition by a.patid order by abs(datediff('day', a.index_date, coalesce(b.address_period_end,b.address_period_start)))) as rn
    from pats_vis a
    join DEIDENTIFIED_PCORNET_CDM.CDM.deid_lds_address_history b
    on a.patid = b.patid
)
select a.patid, 
       c.index_date,
       a.enc_type as index_setting,
       case when a.enc_type in ('ED','EI') then 1 else 0 end as acute_index_ind,
       round(datediff('day', b.birth_date, c.index_date)/365.25, 0) as age_at_index,
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
       c.base_op_n,
       c.base_ed_n,
       c.fu_30d,
       c.fu_90d,
       c.acute_180d,
       a.payer_grp,
       coalesce(s.sub_ind, 0) as sub_ind,
       r.ruca as ruca_grp
from init_mdd_anx a 
join pats_vis c
on a.patid = c.patid
join DEIDENTIFIED_PCORNET_CDM.CDM.deid_demographic b
on a.patid = b.patid
left join bl_sub s
on a.patid = s.patid
left join sdoh_cte r
on a.patid = r.patid and r.rn = 1
;

select * from final_mdd_anx limit 5;

select count(distinct patid) as n_patients, count(*)
from final_mdd_anx
;
-- 22246

select sub_ind, count(distinct patid) as n_patients, count(*)
from final_mdd_anx
group by sub_ind
;