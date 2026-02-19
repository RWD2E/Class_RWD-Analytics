/*                        
# File: lab_sql_review.sql                                                 
# Description: This script is for reviewing basic SQL syntax used for querying data in Snowflake data cloud
*/

-- setup worksheet parameters: Role and Warehouse

/* 
  "Select..." 
*/
-- Ex: Spot check first few rows from a CDM table
select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC limit 20;

-- Ex: How many patients in total do we have in our CDM datamart? 
select count(patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC;
select count(distinct patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC;

-- Ex: How many encounters in total do we have in our CDM datamart? 
select count(distinct encounterid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER;

/* 
  "Select...Where..." 
*/
-- Ex: How many Asian females have ever been seen in our healthcare system? 
select count(distinct patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
where sex = 'F' and race = '02';

-- Ex: How many Asian or African American patients have ever been seen in our healthcare system? 
select count(distinct patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
where race='02' or race = '03';

-- Ex: How many patients have ever been seen in our healthcare system who are currently above 65 years old? 
select count(patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
where datediff(year,birth_date,current_date) > 65;

select count(patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
where datediff(day,birth_date,current_date)/365.25 > 65;


/* 
  "Select...Where...In..." 
  "Select...Where...Like..."
*/
-- Ex: How many patients have been diagnosed with ALS? 
select count(distinct patid) from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DIAGNOSIS
where dx in ('335.20','G12.21');

-- Ex: How many patients have been diagnosed with Motor Neuron Disease? 
select count(distinct patid) as pat_cnt from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DIAGNOSIS
where dx like '335.2%' or dx like 'G12.2%';

-- Ex: How many patients have been diagnosed with Hypertensive Disease (I10, I11, I12, I13, I14, I15, I16,401,402,403,404,405)? 
select count(distinct patid) as pat_cnt from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DIAGNOSIS
where dx like 'I10%' or 
      dx like 'I11%' or 
      dx like 'I12%' or
      dx like 'I13%' or 
      dx like 'I15%' or
      dx like 'I16%' or
      dx like '401%' or
      dx like '402%' or
      dx like '403%' or
      dx like '404%' or
      dx like '405%'
;


/* 
  "...Order by..." 
  "...min()...", "max()..."
*/

-- Ex: When is the most recent inpatient visit to our healthcare system? 
select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where enc_type in ('IP','EI') and admit_date < to_date('2022-08-01')
order by admit_date desc
;

select max(admit_date) as recent_admit_date
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where enc_type in ('IP','EI') and admit_date < to_date('2022-08-01')
;

select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where enc_type in ('IP','EI')
order by admit_date
;
-- we have future admit_date that not are realistic


-- Ex: Who is the oldest patient ever recorded in our healthcare system? (assume they are all still alive) 
select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
order by birth_date;

/* 
  "...Group by..." 
*/
-- Ex: How many patients for each racial group?
select race, count(distinct patid) as pat_cnt 
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC
group by race
order by pat_cnt desc;

-- Ex: Generate two frequency tables for different encounter type (e.g., ED, AV, IP,...) in 2019 vs. 2020? 
select enc_type, count(distinct encounterid) as enc_cnt
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where admit_date between to_date('2017-01-01') and to_date('2017-12-31')
group by enc_type
order by enc_cnt desc;

select enc_type, count(distinct encounterid) as enc_cnt
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where admit_date between to_date('2020-01-01') and to_date('2020-12-31')
group by enc_type
order by enc_cnt desc;


/* 
  "Create (or replace) Table..." 
*/
-- Ex: Collect the list of inpatient visits with LOS >= 2 days
-- drop table enc_los_ge2;
create or replace table enc_los_ge2 as 
select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER
where datediff(day,admit_date,discharge_date) >= 2 and enc_type in ('IP','EI');
-- inspect table
select * from enc_los_ge2;

-- Ex: Collect all secrum creatinine lab results
create or replace table lab_scr as
select * from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_LAB_RESULT_CM
where LAB_LOINC in ('2160-0','38483-4');

-- Ex: Collect the list of all Office visits
create or replace table office_vis as 
select patid, encounterid, px_date 
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_PROCEDURES
where PX in ('99201','99202','99203','99204','99205',
             '99212','99213','99214','99215');

-- Ex: Collect all patients who had a record of SBP >= 140mmhg
create or replace table sbp_ge140 as 
select patid, encounterid, measure_date, systolic, diastolic 
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_VITAl
where SYSTOLIC >= 140;

-- Ex: Collect all patients with a historical diagnosis of hypertensive diease
create or replace table htn_history as 
select patid, min(dx_date) as min_dx_date
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DIAGNOSIS
where dx like 'I10%' or 
      dx like 'I11%' or 
      dx like 'I12%' or
      dx like 'I13%' or 
      dx like 'I15%' or
      dx like 'I16%' or
      dx like '401%' or
      dx like '402%' or
      dx like '403%' or
      dx like '404%' or
      dx like '405%' 
group by patid;


/* 
  "...Join...On" 
  "...Left Join...On"
  "...Right Join...On"
*/
-- Ex: How many pediatric patients have ever been hospitalized at MUHC? 
create or replace table peds_ip as
select a.patid, a.birth_date, b.admit_date, b.discharge_date,
       datediff(day,a.birth_date,b.admit_date)/365.25 as age_at_admit
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC a
join DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_ENCOUNTER b
on a.patid = b.patid
where datediff(day,a.birth_date,b.admit_date)/365.25 < 18 and
      b.enc_type in ('IP','EI');
-- inspect results
select * from peds_ip;


-- Ex: How many inpatient encounters with patients staying in hospital for >= 2days and had at least 1 record of elevated serum creatinine during the stay (SCr > 4mg/dL)?
select count(distinct a.patid) as pat_cnt
from enc_los_ge2 a
join lab_scr b
on a.patid = b.patid and a.encounterid = b.encounterid
where b.result_num > 4;

-- Ex: Identify patients with uncontrolled blood pressure
--       a. SBP>=160mmhg at an office visit
create or replace table pt_sbp_ge160 as
select distinct a.patid
from office_vis a
join sbp_ge140 b
on a.patid = b.patid and a.encounterid = b.encounterid
where b.systolic >= 160;

--       b. SBP>=140mmhg at an office visit with a history of hypertensive disease
create or replace table pt_sbp_ge140_htn as
select distinct a.patid
from office_vis a
join sbp_ge140 b
on a.patid = b.patid and a.encounterid = b.encounterid
join htn_history htn
on a.patid = htn.patid;

--       c. SBP>=140mmhg at two different office visits
create or replace table pt_sbp_2ge140 as
select patid, count(distinct encounterid) as vis_cnt
from sbp_ge140
group by patid
having count(distinct encounterid) > 1;

--       d. How many distinct patients with uncontrolled blood pressure
select count(distinct patid) as pat_cnt
from (
   select patid from pt_sbp_ge160
   union 
   select patid from pt_sbp_ge140_htn
   union 
   select patid from pt_sbp_2ge140
);


/* 
  "...Case when..." 
*/
-- Ex: How many patients for each race group? This time we want to do some more groupings: 
--     - group NI and UN into a single UN group, called 'NI'
--     - group minor race groups into 'OT' ('','','','','')
create or replace table race_regroup as 
select patid, race, 
       case when race in ('NI','UN') then 'NI'
            else race
            end as race_group
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_DEMOGRAPHIC;

-- Ex: Following the WHO definition, how many adult patients are underweight, normal, overweight and obese? 
create or replace table bmi_calculated as
select patid, original_bmi, 
       round(wt/(ht*ht)*703) as calculated_bmi,
       NVL(original_bmi, round(wt/(ht*ht)*703)) as combined_bmi 
from DEIDENTIFIED_PCORNET_CDM.CDM_C016R033.DEID_VITAL
where (
       original_bmi is not null or
       (wt is not null and ht is not null)
      ) and 
      ht > 0
;

create or replace table bmi_classified as 
select patid, original_bmi, calculated_bmi,
       case when combined_bmi < 18.5 then 'underweight'
            when combined_bmi >= 18.5 and combined_bmi < 25 then 'normal'
            when combined_bmi >= 25 and combined_bmi < 30 then 'overweight'
            else 'obese'
            end as bmi_category 
from bmi_calculated
;

select bmi_category, count(distinct patid) as pat_cnt
from bmi_classified
group by bmi_category
;



