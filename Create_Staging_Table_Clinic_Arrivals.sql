USE [dbUNMCCC]
GO

/****** Object:  Table [ccc].[MQ_UOP_Clinic_Arrivals]    Script Date: 9/23/2020 11:01:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ccc].[MQ_UOP_Clinic_Arrivals](
	[npi] [varchar](20) NULL,
	[appt_date] [varchar](8) NULL,
	[organization] [varchar](20) NULL,
	[location] [varchar](40) NULL,
	[clinic_arrivals] [int] NULL,
	[run_date] [datetime] NULL
) ON [PRIMARY]
GO

