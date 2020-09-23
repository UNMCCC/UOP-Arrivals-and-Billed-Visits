USE [dbUNMCCC]
GO

/****** Object:  StoredProcedure [ccc].[MQ_UOP_Clinic_Arrivals_sp]    Script Date: 9/23/2020 10:58:36 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO











/* PRODUCTION VERSION 11/12/2019 */


CREATE procedure [ccc].[MQ_UOP_Clinic_Arrivals_sp]

AS

--drop table #visits



select 
	fy,
	pat_id1,
	mrn,
	app_Dt,
	bucket,
	nbr_in_bucket,
	PatDosBucket_seq,
	MultipleAppts_Seq,
	staff_id,
	mq_prov_name,
	case when bucket = 'RO Machine' then 'Machine Only' else NPI end NPI,
	isBillable,
	mq_prov_specialty,
	loc_idx,
	activity,
	sch_id
into #visits
from ccc.MQ_visits_in_buckets
where MultipleAppts_Seq = 1  -- multiple appts with same provider for a patient in the same day will count as 1 visit.  multiple appts scheduled to RO machines for a patient in the same day will count as 1 visit
and fy in ('FY18', 'FY19', 'FY20', 'FY21', 'FY22')
and (
		(bucket in ('Patient & Family Services', 'Physician Appointment') and isBillable = 1 )  -- select only billable providers for UOP reporting
	or  (bucket in ('RO Machine'))
	)
/* select distinct fy from ccc.MQ_visits_in_buckets
 select * from #visits where fy = 'fy21'
*/

--drop table #UOP_data
select 
	NPI, 
	app_Dt as appt_date, 
	'Cancer Center' as organization, 
	loc_idx as location, 
	COUNT(*) as clinic_arrivals,
	GETDATE() as run_date
into #UOP_Data
from #visits
group by NPI, app_Dt, loc_idx 
order by NPI,  app_Dt


truncate table ccc.MQ_UOP_Clinic_Arrivals
insert into  ccc.MQ_UOP_Clinic_Arrivals
select * from #UOP_Data
select min(appt_Date) as minApptDt, max(appt_Date) as MaxApptDt from ccc.MQ_UOP_Clinic_Arrivals
 

GO

