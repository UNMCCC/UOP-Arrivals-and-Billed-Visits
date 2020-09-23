USE [dbUNMCCC]
GO

/****** Object:  StoredProcedure [ccc].[MQ_UOP_Billed_Visits_sp]    Script Date: 9/23/2020 10:58:09 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO










/* Purpose:		UNMCCC Billed Visits by E&M code 
** Created By:	Debbie Healy
** Data Source:	mgbbrpsqldbs1\unmmgsqlunmccc\unmmgdss
** Schema:		dss
** Criteria:	Extract UNMCCC Charges for closed IDX posting periods
**				Includes both Group 3 (Billable) and Group 4 (Non-Billable charges)
**				Based on DATE CHARGE IS POSTED, not on date of service
**				Includes charge corrections 
**				Includes all billing areas except 'UNMCC MEMORIAL MEDICAL 4557' and 'GILA REGIONAL MC 4560' (we post payments only, but do not bill for them)
** Date Range:	This query is written to extract charges from all IDX posting periods for the FY18 through "today" 
** Billed Visits:   SUM # number of units to adjust for charge corrected invoices (which have negative units) -- so that these will not be over counted.  
**					Can't exclude FSC 5 - Do not Bills because the original charge will have FSC 5, but it is the one that should be counted.
**				    Provider visits have units=1, so this method MOSTLY works for counting.  It doesn't work when the orig invoice is prior to the reporting period or when there is a DOS change.
** 05/02/2019 - use IDX facility name - tableau reporting name will be mapped after upload.
**
** NOTE:  THIS RE-RUNS the entire timeframe with each run from 07/01/2018 onward -- may need to add date ranges at some point */


/* Drop temp table, if it exists */


CREATE procedure [ccc].[MQ_UOP_Billed_Visits_sp]



AS

IF OBJECT_ID('tempdb..#chgs') IS NOT NULL
	DROP TABLE #chgs ;	
IF OBJECT_ID('tempdb..#dos_mrn_npi') IS NOT NULL
	DROP TABLE #dos_mrn_npi ;		
IF OBJECT_ID('tempdb..#units') IS NOT NULL
	DROP TABLE  #units ;	
IF OBJECT_ID('tempdb..#dos_mrn_npi') IS NOT NULL
	DROP TABLE #dos_mrn_npi ;	
IF OBJECT_ID('tempdb..#dtls') IS NOT NULL
	DROP TABLE #dtls ;	
IF OBJECT_ID('tempdb..#data') IS NOT NULL
	DROP TABLE #data ; 
IF OBJECT_ID('tempdb..#RPT') IS NOT NULL
	DROP TABLE #RPT ;

/* Extract Charges */
		
-- drop table #chgs

select distinct   dos, mrn, npi, fac_name, post_pd, units, post_dt
INTO #chgs
from (
SELECT 
	inv.grp,
	inv.div_key as div_num,
	div.div_name,
	fac.fac_name,   -- provide this field for Tableau
	case when fac.fac_name in ('UNMCC CRTC', 'UNMCC 1201')		then '1201'
		when fac.fac_name = 'UNMCC SF'							then 'Christus'
		when fac.fac_name in ('NB/PED INPATIENT', 'UH OR',  'UH Inpatient Adult') then 'UH Inpatient'
		when fac.fac_name in ('ER OBSERVATION UNIT', 'UNMH-EMERGENCY CNTR', 'CTH PEDS WELL CHILD', 'UNMMG CARDIOLOGY', 'ALBUQUERQUE JOB CORPS') then 'Other Clinic'
		else 'Unknown'
	end Tableau_location,	  -- to be mapped in Tableau	
	inv.inv_num,
	txn.txn_num,
	txn.post_pd,
	txn.inv_ser_dt_key as dos,
	txn.post_dt_key as post_dt,
	inv.pt_key as mrn,
	pt.pt_name,
	prov.prov_name IDX_prov_name,
	provunq.prov_unq_name,
	case when provunq.prov_unq_name is null and prov.prov_name is not null then prov.prov_name
		else provunq.prov_unq_name 
	end provider,		
	prov.prov_NPI_num as NPI,
	prov_unq_som_dept_name as SOM_Department,
	prov_unq_som_div_name as SOM_Division,
	prc.proc_cd,
	prc.proc_name,
	txn.chg_amt,
	cast(txn.units_tot as int) as units,
	case 
		when proc_cd between '99201' and '99205' then '1 - New Patient'
		when proc_cd between '99211' and '99215' then '2 - Established Patient'
		when proc_cd between '99241' and '99245' then '3 - Office Consultation'
		when proc_cd between '99251' and '99255' then '4 - Inpatient Consultation'
		else 'Other Follow-up'
	end CPT_Cat,
	case when proc_cd between '99201' and '99205' then 'YES' else 'NO'
	end isNP
FROM [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.inv_fct inv
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.inv_txn_fct txn		on inv.inv_num = txn.inv_num
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.div_dim div			on inv.div_key = div.div_key
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.fac_dim fac			on fac.fac_key	= inv.fac_key
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.date_yearmo_dim yrmo	on txn.post_pd = yrmo.yearmo_key	  -- get posting period data for charge posting period
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.prov_dim prov		on inv.prov_key = prov.prov_key
LEFT  JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.prov_unq_dim provunq	on prov.prov_npi_num = provunq.prov_unq_npi_num 
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.pt_dim pt			on inv.pt_key = pt.pt_key
INNER JOIN [MGBBRPSQLDBS1\UNMMGSQLDWPROD].unmmgdss.dss.proc_dim prc			on txn.proc_key = prc.proc_key
WHERE inv.div_key = '4500' -- CANCER CENTER 4500
	AND txn.post_pd >= '201707'
	AND txn.bill_area_key not in ('4557','4560') -- non-billable billing areas - report payments only
	AND txn.pay_key = 99	-- CHARGES
	and (					-- only this list of E&M codes (Provider office visits)
       proc_cd between '99201' and '99205'
   or proc_cd between '99211' and  '99215'
   or proc_cd between '99241' and '99245'
   or proc_cd between '99251' and '99255'  -- corrected on 9/16/19 after confirming with Marlena(previously read "...and '99254')
	) --------------------------------------NOTE:  CCC is only selecting these E&Ms to be consistent with current reporting - there are E&Ms outside this range for ER/UH visits
 ) as A 
order by dos, mrn, npi, fac_name, post_pd



/* Get max post_date */
declare @maxPostDt   varchar(8)
select @maxPostDt = MAX(post_dt)  
from #chgs
select @maxPostDt

/* Sequence extract by dos, mrn, npi and order by post_pd */
--drop table #dos_mrn_npi

select
	Row_Number() over (partition by   dos, mrn, npi order by  dos, mrn, npi,  post_pd ) as seqNO,
	A.* 
into #dos_mrn_npi
from( 
select 
	dos,
	NPI,
	mrn,
	post_pd,
	post_dt,   -- this is actually max_post_dt to check the last posted date 
	fac_name as Location,
	units
from #chgs
) as A
order by  dos, mrn, npi, post_pd

 
--drop table #units
/* sum units to handle charge correction reversals -- this works because provider E&M visits are 1 unit each*/
select 
	dos,
	mrn,
	NPI,
	sum(units) as tot_units
into #units
from #chgs
group by dos,npi,mrn

/* Join sequenced mrn, dos, npi details with total unit count */
-- drop table #dtls
select 
	#dos_mrn_npi.seqNo,
	#units.tot_units,
	#dos_mrn_npi.dos,
	#dos_mrn_npi.mrn,
	#dos_mrn_npi.npi,
	#dos_mrn_npi.post_pd,
	#dos_mrn_npi.post_dt,
	#dos_mrn_npi.location,
	#dos_mrn_npi.units
into #dtls
from #units
left join #dos_mrn_npi on  #units.dos = #dos_mrn_npi.dos and  #units.mrn = #dos_mrn_npi.mrn and  #units.npi = #dos_mrn_npi.npi 
order by #dos_mrn_npi.dos, #dos_mrn_npi.mrn, #dos_mrn_npi.NPI

--=====================================
-- Details for Marlena
--select * from #dtls 
--where dos >= '20200701' 
--and seqNo = 1
--order by post_dt Desc 
--=====================================

--drop table #data
/* accumulate data -- seqNo = 1 gets first posting of a charge which is the posting period the visit should be counted for*/
/* Note - summing units works to correctly account for charge corrections.  The orig inv is counted, subsequent ones cancel out */
select npi, dos, location, post_pd, Units_npi_dos as billed_visits
into #data
from (
select npi, dos, location, post_pd, SUM(tot_units) as Units_npi_dos  -- there will only be 1 post pd which is first time charge was posted 
from (
	select 
		#dtls.dos,
		#dtls.npi,
		#dtls.location,
		#dtls.tot_units,
		#dtls.post_pd,
		#dtls.post_dt
	from #dtls
	where seqNo = 1
) as A
group by npi, dos, location, post_pd
) as B
where Units_npi_dos <> 0
 

/*  Create Tableau formatted data and update table */
-- drop table #rpt1
/*  ORIGINAL CODE -- REMOVED reporting month (can be constructed in Tableau), reformated DOS (yyyymmdd) and added MAX POSTING DATE (ask Angie if others are including posting date in extract
select 
	NPI,
	Location,
	'Cancer Center' as Organization,
	RIGHT(left(dos,6),2) + '/' +  RIGHT(DOS,2)  + '/' + LEFT(DOS,4) as Appt_date, 
	RIGHT(LEFT(post_pd,6),2) + '/01/' + LEFT(post_pd,4) as Reporting_Month,
	Billed_visits,
	post_pd as post_pd_yyyymm,
	GETDATE() as create_DtTm
into #RPT1
from #data
order by  NPI,  location,  DOS, post_pd
*/


select 
	NPI,
	Location,
	'Cancer Center' as Organization,
	dos as Appt_date, 
	Billed_visits,
	post_pd as post_pd,
	@maxPostDt  as post_date,  
	GETDATE() as create_DtTm
into #RPT
from #data
order by  NPI,  location,  DOS, post_pd
/************************************************************************************************************************** 
select COUNT(*) as rpt from #rpt
select SUM(billed_visits) as rptv from #rpt

select COUNT(*) as rpt1 from #rpt1
select SUM(billed_visits) as rpt1v from #rpt1

 *************************************************************************************************************************/


truncate table ccc.MQ_UOP_Billed_Visits

insert into ccc.MQ_UOP_Billed_Visits
select * from #rpt




GO

