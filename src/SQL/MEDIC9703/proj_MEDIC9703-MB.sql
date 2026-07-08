/*                                             
# Description: this script is to extract all full-term deliveries or c-sections with single liveborn  
#  - Inclusion criteria: 
        - Delivery of full-term infant: O80 and O60-O77 assertained with Z37.0 outcome; 650, 660, 661, 662, 663, 664, 665 with associated V27.0 outcome; OR
        - 
   - Exclusion criteria: 
        - any encounters with incomplete data to calculate TAT
#  - Exposure: facility location (rural/urban, RUCA); TAT 
#  - Outcome: bacteremia diagnoses within 48 hours
*/

/*
identify eligible patient cohort
*/

create or replace table deliv_incld_dx1 as 
select distinct
       patid, 
       encounterid,
       dx_type,
       dx,
       split_part(dx,'.',1)  as dx_int,
       dx_date,
       admit_date,
       0 as deliv_csec
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where enc_type in ('EI','IP') and 
      split_part(dx,'.',1) in (
            'O80',
            'O60',
            'O61',
            'O62',
            'O63',
            'O64',
            'O65',
            'O66',
            'O67',
            'O68',
            'O69',
            'O70',
            'O71',
            'O72',
            'O73',
            'O74',
            'O75',
            'O76',
            'O77',
            '650',
            '660',
            '661',
            '662',
            '663',
            '664',
            '665'
      ) 
union
select distinct
       patid, 
       encounterid,
       dx_type,
       dx,
       split_part(dx,'.',1)  as dx_int,
       dx_date,
       admit_date,
       1 as deliv_csec
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where enc_type in ('EI','IP') and 
      (
            dx like 'O82%' or 
            dx like '669.7%'
      )
;

select count(distinct patid), count(distinct encounterid) from deliv_incld_dx1
;
-- 31130	43626

create or replace table deliv_incld_dx2 as 
select distinct
       patid, 
       encounterid,
       dx_type,
       dx,
       dx_date,
       admit_date
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where enc_type in ('EI','IP') and 
      (
            dx like 'Z37.0%' or 
            dx like 'V27.0%'
      )
;
select count(distinct patid), count(distinct encounterid) from deliv_incld_dx2
;
-- 40141	55029


create or replace table deliv_incld as 
with deliv_combine as (
      select distinct
             a.patid, 
             a.encounterid,
             a.admit_date,
             max(a.deliv_csec) over (partition by a.patid) as deliv_csec
      from deliv_incld_dx1 a 
      join deliv_incld_dx2 b 
      on a.patid = b.patid and a.encounterid = b.encounterid and a.dx_type = b.dx_type
      where a.admit_date >= '2014-01-01' 
), deliv_diff as (
      select a.*, 
             lag(a.admit_date, 1, '1899-12-31') OVER (PARTITION BY patid ORDER BY admit_date) AS last_admit_date
      from deliv_combine a
), deliv_session as (
      select b.*, 
            case when datediff(day,b.last_admit_date,b.admit_date) > 211 then 1
                 else 0 
            end as new_session_flag
      from deliv_diff b
), deliv_ord as (
      select d.*,
             sum(d.new_session_flag) over (PARTITION BY d.patid ORDER BY d.admit_date) as event_id
      from deliv_session d
), deliv_ord_dedup as (
      select e.*, 
            row_number() over (partition by e.patid, e.event_id order by e.admit_date) as rn
      from deliv_ord e
)
select ord.patid, 
       ord.encounterid,
       ord.admit_date,
       case when ord.deliv_csec = 1 then 'c' else 'v' end as deliv_method,
       ord.event_id as deliv_order, 
       datediff(year,d.birth_date,ord.admit_date) as age_at_deliv,
       d.race,
       d.hispanic
from deliv_ord_dedup ord
join PCORNET_CDM.CDM.DEID_DEMOGRAPHIC d 
on ord.patid = d.patid
where ord.rn = 1 and 
      datediff(year,d.birth_date,ord.admit_date) between 10 and 60 and 
      d.sex = 'F'
;
select * from deliv_incld
-- where deliv_order > 1
limit 5;

select count(distinct patid), count(*) from deliv_incld;

select deliv_method,count(distinct patid), count(*)
from deliv_incld
group by deliv_method
;

create or replace table deliv_excld as 
select distinct patid, encounterid, admit_date, 
       'subse_c' as excld_reason
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where dx like 'O34.21%' or 
      dx like 'O66.41%' or 
      dx like '654.2%' 
union 
select distinct patid, encounterid, admit_date,
       'breech' as excld_reason
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where dx like 'O32.1%' or 
      dx like 'O32.2%' or 
      dx like '652%' 
union 
select distinct patid, encounterid, admit_date,
       'multi_genstation_stillbirth' as excld_reason
from PCORNET_CDM.CDM.DEID_DIAGNOSIS
where dx like 'Z37.1%' or 
      dx like 'Z37.2%' or 
      dx like 'Z37.3%' or 
      dx like 'Z37.4%' or 
      dx like 'Z37.5%' or 
      dx like 'Z37.6%' or 
      dx like 'Z37.7%' or 
      dx like 'Z37.9%' or 
      dx like '651%' or 
      dx like 'V27.1%' or 
      dx like 'V27.2%' or
      dx like 'V27.3%' or 
      dx like 'V27.4%' or 
      dx like 'V27.5%' or 
      dx like 'V27.6%' or 
      dx like 'V27.7%' or 
      dx like 'V27.9%'
;

create or replace table deliv_elig as 
select a.* 
from deliv_incld a 
where not exists (
      select 1 from deliv_excld b 
      where a.patid = b.patid and a.encounterid = b.encounterid
)
;

select count(distinct patid), count(*) from deliv_elig;
-- 14743	18734

select deliv_method,count(distinct patid), count(*)
from deliv_elig
group by deliv_method
;

select * from deliv_elig
limit 5;

/*
identify exposure: Rurality, ADI
*/
create or replace table deliv_geocode as 
with geocode_rk as (
    select a.patid, 
        a.deliv_order,
        a.admit_date,
        b.address_period_start,
        b.address_period_end,
        b.FIPS_BLOCK_GROUP_ID_2020,
        b.FIPS_TRACT_ID_2020, 
        datediff(day,a.admit_date, b.address_period_start) as Days_Index_Addr,
        row_number() over (partition by a.patid, a.deliv_order order by abs(datediff(day,a.admit_date, b.address_period_start))) as rn
    from deliv_elig a 
    join PCORNET_CDM.CDM.private_geocoded_address_view b
    on a.patid = b.patid
    where substr(b.FIPS_TRACT_ID_2020,1,2) = '29'  -- missourian
)
select geocode_rk.* exclude rn 
from geocode_rk
where rn = 1
;

select * from deliv_geocode
limit 5;

select count(*), count(distinct patid) 
from deliv_geocode
;
-- 15400	11855

create or replace table deliv_rural_adi as
with geocode_rk as (
    select distinct
        a.patid, 
        a.deliv_order,
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
        row_number() over (partition by a.patid, a.deliv_order order by ruca.URBANCORE, adi.ADI_STATERANK desc) as rn
    from deliv_geocode a 
    left join SDOH_DB.ADI.ADI_BG_2020 adi on a.FIPS_BLOCK_GROUP_ID_2020 = adi.geocodeid
    left join SDOH_DB.RUCA.RUCA_CT_2020 ruca on a.FIPS_TRACT_ID_2020 = ruca.TRACTFIPS20
    left join SDOH_DB.HRSA.FORHP_RURAL_CN hrsa on substr(a.FIPS_TRACT_ID_2020,1,5) = hrsa.FIPS_2023
    where adi.ADI_STATERANK not in ('GQ','GQ-PH','PH')
)
select geocode_rk.* exclude rn 
from geocode_rk
where rn = 1
;
select * from deliv_rural_adi
-- where RURAL_RUCA is null
limit 5
;
select count(*), count(distinct patid) 
from deliv_rural_adi
;
-- 15047	11603

/*
include other covariates: BMI
*/
create or replace table deliv_elig_bmi as 
with ht as (
    select a.patid, median(v.ht) as ht, 
    from deliv_elig a 
    join PCORNET_CDM.CDM.deid_vital v 
    on a.patid = v.patid
    group by a.patid
),  wt as (
    select patid, deliv_order, wt
    from (
        select a.patid, a.deliv_order, v.wt, 
               row_number() over (partition by a.patid order by abs(datediff(day,a.admit_date,v.measure_date::date))) as rn 
        from deliv_elig a 
        join PCORNET_CDM.CDM.deid_vital v 
        on a.patid = v.patid 
        where datediff(day,a.admit_date,v.measure_date::date) <= -270
    )
    where rn = 1
), bmi as (
    select patid, deliv_order, original_bmi as bmi
    from (
        select a.patid, a.deliv_order, v.original_bmi, 
               row_number() over (partition by a.patid order by abs(datediff(day,a.admit_date,v.measure_date::date))) as rn 
        from deliv_elig a 
        join PCORNET_CDM.CDM.deid_vital v 
        on a.patid = v.patid 
        where datediff(day,a.admit_date,v.measure_date::date) <= -270
    )
    where rn = 1
)
select distinct 
       a.patid, 
       a.deliv_order,
       ht.ht,
       wt.wt,
       round(coalesce(bmi.bmi,wt.wt/(ht.ht*ht.ht)*703)) as bmi
from deliv_elig a 
left join ht on a.patid = ht.patid
left join wt on a.patid = wt.patid and a.deliv_order = wt.deliv_order
left join bmi on a.patid = bmi.patid and a.deliv_order = wt.deliv_order
where round(coalesce(bmi.bmi,wt.wt/(ht.ht*ht.ht)*703)) is not null
;

select count(distinct patid), count(*) from deliv_elig;

/*
final deid dataset
*/
create or replace table DEID_DELIV_SDH as 
select a.patid, 
       a.deliv_method,
       a.deliv_order,
       a.age_at_deliv,
       a.race,
       a.hispanic, 
       b.BMI,
       s.ADI_STATERANK,
       s.adi_staterank_grp,
       s.rural_ruca,
       s.rural_hrsa
from deliv_elig a 
join deliv_elig_bmi b on a.patid = b.patid and b.deliv_order = b.deliv_order
join deliv_rural_adi s on a.patid = s.patid and a.deliv_order = s.deliv_order
;

select count(distinct patid), count(distinct patid || deliv_order), count(*) 
from DEID_DELIV_SDH;
-- 5832	7870


select deliv_method,count(distinct patid), count(*)
from DEID_DELIV_SDH
group by deliv_method
;

select * from DEID_DELIV_SDH 
limit 5;