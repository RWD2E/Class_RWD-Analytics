/*
Population: patients with Ductal Carcinoma in Situ (DCIS)
 - 
*/

select * from DEIDENTIFIED_PCORNET_CDM.CDM.deid_tumor
limit 5
;

create or replace table dcis_pts as 
with tumor_rk as (
    select  PATID, 
            PRIMARYSITE as DCIS_SITE_CODE,
            HISTOLOGICTYPEICDO3 as DCIS_HIST_CODE,
            BEHAVIORCODEICDO3 as DCIS_BEHAV_CODE,
            GRADEPATHOLOGICAL as DCIS_GRADE,
            LATERALITY as DCIS_LAT,
            coalesce(try_to_number(ESTROGENRECEPTORSUMMARY), 0) as ER_STATUS,
            coalesce(try_to_number(PROGESTERONERECEPSUMMARY), 0) as PR_STATUS,
            case when RXSUMMSURGPRIMSITE = '00' then 'no'
                    when try_to_number(RXSUMMSURGPRIMSITE) between 10 and 29 then 'BCS'
                    when try_to_number(RXSUMMSURGPRIMSITE) between 30 and 80 then 'mastectomy'
                    else 'unknown'
            end as SURGERY_TYPE,
            coalesce(try_to_number(RXSUMMRADIATION), 0) as RAD_IND,
            coalesce(try_to_number(RXSUMMHORMONE), 0) as ENDOCRINE_IND,
            DATEOFDIAGNOSIS as INDEX_DATE, 
            DATEOFLASTCONTACT,
            row_number() over (partition by patid order by DATEOFDIAGNOSIS) as RN
        from DEIDENTIFIED_PCORNET_CDM.CDM.deid_tumor
        where PRIMARYSITE like 'C50%' and HISTOLOGICTYPEICDO3 in ('8500','8501','8503','8507')
              and BEHAVIORCODEICDO3 = '2'
)
select * exclude (RN) from tumor_rk
where RN = 1
;
select * from dcis_pts
limit 5
;

select count(distinct patid) as n_patients, count(*)
from dcis_pts
;

-- get invasive dc 
create or replace table inv_dc as
select  PATID, max(DATEOFDIAGNOSIS) as INV_DUCTAL_DATE, 1 as INV_DUCTAL_IND
from DEIDENTIFIED_PCORNET_CDM.CDM.deid_tumor
where PRIMARYSITE like 'C50%' and HISTOLOGICTYPEICDO3 in ('8500','8501','8503','8507')
    and BEHAVIORCODEICDO3 = '3'
group by PATID
;

select count(distinct patid) as n_patients, count(*)
from inv_dc
;


-- get death and censor endpoints from EHR
create or replace table censor_pts as
select a.patid, 
       max(d.death_date::date) as death_date, 
       max(dx.admit_date::date) as last_enc_date
from dcis_pts a 
left join DEIDENTIFIED_PCORNET_CDM.CDM.deid_death d
on a.patid = d.patid
left join DEIDENTIFIED_PCORNET_CDM.CDM.deid_encounter dx
on a.patid = dx.patid and dx.enc_type in ('AV','OA','ED','EI','IP','IS','OS','TH')
group by a.patid
;

select count(distinct patid) as n_patients, count(*)
from censor_pts
where last_enc_date is not null
;

-- attach demographic and sdoh info
create or replace table final_dc as
with sdoh_cte as (
    select a.patid, 
           b.ruca,
           row_number() over (partition by a.patid order by abs(datediff('day', a.index_date, coalesce(b.address_period_end,b.address_period_start)))) as rn
    from dcis_pts a
    join DEIDENTIFIED_PCORNET_CDM.CDM.deid_lds_address_history b
    on a.patid = b.patid
)
select a.*,
       round(datediff('day', b.birth_date, a.index_date)/365.25, 0) as age_at_index,
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
       r.ruca as ruca_grp,
       inv.INV_DUCTAL_DATE,
       inv.INV_DUCTAL_IND,
       dth.death_date,
       case when dth.death_date is not null then 1 else 0 end as death_ind,
       dth.last_enc_date as CENSOR_DATE
from dcis_pts a
join DEIDENTIFIED_PCORNET_CDM.CDM.deid_demographic b
on a.patid = b.patid
left join inv_dc inv
on a.patid = inv.patid
left join censor_pts dth
on a.patid = dth.patid
left join sdoh_cte r
on a.patid = r.patid and r.rn = 1
;

select * from final_dc
limit 5
;


select count(distinct patid) as n_patients, count(*)
from final_dc
-- where INV_DUCTAL_IND = 1
;

