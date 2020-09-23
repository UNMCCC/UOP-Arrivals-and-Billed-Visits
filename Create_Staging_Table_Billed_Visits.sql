USE [dbUNMCCC]
GO

/****** Object:  Table [ccc].[MQ_UOP_Billed_Visits]    Script Date: 9/23/2020 11:01:16 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ccc].[MQ_UOP_Billed_Visits](
	[npi] [varchar](20) NOT NULL,
	[location] [varchar](40) NULL,
	[organization] [varchar](20) NULL,
	[appt_date] [varchar](8) NULL,
	[billed_visits] [int] NULL,
	[post_pd] [varchar](6) NULL,
	[post_date] [varchar](8) NULL,
	[create_dtTm] [datetime] NULL
) ON [PRIMARY]
GO

