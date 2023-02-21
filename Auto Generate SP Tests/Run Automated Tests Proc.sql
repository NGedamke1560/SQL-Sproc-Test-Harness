USE [DATABASE_NAME]
GO

--SELECT * FROM tmp_Dynamic_Tests WHERE BothResultsMatch != 1

--SELECT * FROM tmp_Dynamic_Tests WHERE SP_ResultsHash IS NULL AND New_SP_ResultsHash IS NULL


sp_configure 'Show Advanced Options', 1
GO
RECONFIGURE
GO
sp_configure 'Ad Hoc Distributed Queries', 1
GO
RECONFIGURE
GO

EXEC [dbo].[RunAndCompareStoredProceduresFromTrace]
	@altProcTag = '_EDIT', --what string did you append to thename of the original SP(s) when you ran the optimized version(s)
	@filePath = 'K:\[TRACE_FILE].trc',
	@server = '[SERVER_NAME]',
	@databaseName = '[DATABASE_NAME]'


GO
--Turn off AdHoc Queries
sp_configure 'Ad Hoc Distributed Queries', 0
GO
RECONFIGURE
GO
sp_configure 'Show Advanced Options', 0
GO
RECONFIGURE
GO