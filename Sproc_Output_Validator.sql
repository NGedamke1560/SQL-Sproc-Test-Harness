USE [DATABASER_NAME]

/*
	 Compares two stored procedures to determine if the results are the same.
	 
	 The original purpose was to ensure that a performance tuned version of a query 
		  did not change the output of the original (i.e. a logical bug has been introduced)
	 
	 Input procs must be table valued, ending in a single select statement.

	 **************** WARNING ****************

	 Be sure that both procs have been stripped of all DML and DDL statements before executing.
	 The exception to this is any temp tables used for calculation/optimization, that are cleared and repopulated with each execution.

	 IF YOU IGNORE THIS WARNING
		  Best case scenario, you can not trust the output of this proc, because the underlying data used to generate the sproc results may have changed.
		  Worst case, you have FUBARed the data in the system and need to restore the DB. Congratulations, you are now on your DBA's naughty list!

	 *******************

	 Original Author: Nathan Urban-Gedamke
	 Creation Date: October 2021

*/


--Clears proc cache if needed
--ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

DECLARE @ID INT = 92369 
DECLARE @runBuildProc_ORIG NVARCHAR(MAX) = ''
DECLARE @runBuildProc_EDIT NVARCHAR(MAX) = ''
--Bad comments on the next two lines, I should have explained what the purpose of executing these runBuildProc queries was more thuroughly. 
--I *think* that it was to solve an issue I was having where the test procs required temp tables from a parent proc in order to run properly, but not 100% sure any more
SET @runBuildProc_ORIG = 'EXECUTE dbo.[BuildTempTbl_ORIG] @ID = ' + CONVERT(NVARCHAR(MAX), @ID) --comment out this line to not run the proc indicated before each test proc
SET @runBuildProc_EDIT = 'EXECUTE dbo.[BuildTempTbl] @ID = ' + CONVERT(NVARCHAR(MAX), @ID) --comment out this line to not run the proc indicated before each test proc

DECLARE @errorMess NVARCHAR(MAX);
DECLARE @tablesMatch BIT = 0;
DECLARE @outputSelect NVARCHAR(MAX);
DECLARE @createChecksumColumn NVARCHAR(MAX);
DECLARE @calculateChecksumColumn NVARCHAR(MAX);
DECLARE @Checksum TABLE(tablename NVARCHAR(MAX) NOT NULL, chksum INT NULL);
DECLARE @checksumStatement NVARCHAR(MAX) = N'';
DECLARE @returnDiffStatement NVARCHAR(MAX) = N'';
DECLARE @orderbyClause NVARCHAR(MAX) = N' ORDER BY idnum';

--Replace @originalProc
DECLARE @originalResultsTable NVARCHAR(MAX) = N'##TestQueryResults';
DECLARE @originalProc NVARCHAR(MAX) = N'EXEC NG.[TestQuery] @ID = ' + CONVERT(NVARCHAR(MAX), @ID)
DECLARE @insertStatement NVARCHAR(MAX) = N'INSERT INTO ' + @originalResultsTable  + N' ' + @originalProc;

DECLARE @EDITResultsTable NVARCHAR(MAX) = N'##TestQueryResults_EDIT';
DECLARE @EDITProc NVARCHAR(MAX) = N'EXEC NG.[TestQuery_EDIT] @ID = ' + CONVERT(NVARCHAR(MAX), @ID)
DECLARE @EDITInsertStatement NVARCHAR(MAX) = N'INSERT INTO ' + @EDITResultsTable  + N' ' + @EDITProc;



--run proc to build table(s) required for original query version (overcomes limitation of sp_describe_first_result_set)
IF @runBuildProc_ORIG != ''
    EXEC sp_executesql @runBuildProc_ORIG
--run proc to build table(s) required for optimized test query
IF @runBuildProc_EDIT != ''
    EXEC sp_executesql @runBuildProc_EDIT

/* Insert results from both versions of the proc into temp tables */
	 
	 --Dynamically create table from original proc output
	 EXECUTE [NG].[Generate_Table_Using_sp_describe_first_result_set] 
		 @procCall = @originalProc
		,@outputTableName = @originalResultsTable
		,@execute = 1
		,@suppressOutput = 1;
	 --Execute the original proc to capture the results (proc must have been modified to end with a select statement)
	 EXEC sp_executesql @insertStatement
	 --SELECT * FROM ##TestQueryResults;

	 --Dynamically create table from optimized proc output
	 EXECUTE [NG].[Generate_Table_Using_sp_describe_first_result_set] 
		 @procCall = @EDITProc
		,@outputTableName = @EDITResultsTable
		,@execute = 1
		,@suppressOutput = 1;
	  --Execute the optimized proc to capture the results (proc must have been modified to end with a select statement)
	 EXEC sp_executesql @EDITInsertStatement
	 --SELECT * FROM ##TestQueryResults_EDIT;


/* Check that the result table structures match */
SELECT @errorMess = 'Table Structures are not the same'
FROM(
	SELECT orig.name AS orig_Name, orig.column_id AS orig_column_id, orig.system_type_id orig_system_type_id, 
			new.name new_name, new.column_id AS new_column_id, new.system_type_id AS new_system_type_id
	FROM (SELECT * FROM tempdb.sys.columns WHERE  object_id = OBJECT_ID('tempdb..' + @originalResultsTable))orig
	FULL OUTER JOIN (SELECT * FROM tempdb.sys.columns WHERE object_id = OBJECT_ID('tempdb..' + @EDITResultsTable)) new
		ON new.name = orig.name
		AND new.system_type_id = orig.system_type_id
	WHERE --no matching column
		orig.name IS NULL
		OR new.name IS null
	) test

IF @errorMess IS NULL
BEGIN
	
	SELECT @createChecksumColumn = 
		  N'ALTER TABLE ' + @originalResultsTable + N' ADD Checksum INT;
			ALTER TABLE ' + @EDITResultsTable + N' ADD Checksum INT;'

	 EXEC SP_executesql @createChecksumColumn;

	 --Switch this to HashBytes to remove potential for  incorrect matches (CHECKSUM() can have collisions where values do not match)
	 SELECT @calculateChecksumColumn = 
		  N'UPDATE ' + @originalResultsTable + N' SET Checksum = CHECKSUM(*);
				UPDATE ' + @EDITResultsTable + N' SET Checksum = CHECKSUM(*)'

	  --SELECT @calculateChecksumColumn
	  EXEC SP_executesql @calculateChecksumColumn

	SELECT @checksumStatement = 
		N'SELECT ''' + @originalResultsTable + ''' AS TableName, CHECKSUM_AGG(CHECKSUM) as chksum FROM ' + @originalResultsTable + N'
		UNION ALL
		SELECT ''' + @EDITResultsTable + ''' AS TableName, CHECKSUM_AGG(CHECKSUM) as chksum FROM ' + @EDITResultsTable + N';'

	INSERT INTO @Checksum EXEC SP_executesql @checksumStatement;

	SELECT @tablesMatch = CASE WHEN EXISTS (
										   SELECT 1
										   FROM
											   @Checksum	   orig
										  INNER JOIN @Checksum edit
											  ON orig.tablename = @originalResultsTable
												 AND edit.tablename = @EDITResultsTable
												 AND orig.chksum = edit.chksum
									   )
							   THEN 1
						  ELSE 0
					  END;
	IF @tablesMatch = 1
		SELECT('Both result sets Match')
	ELSE
	BEGIN
		SELECT('There are differences between the result sets')
	  
		  --Also, would be good to get exact columns that have changed, to save having to manually check columns for large values
		SELECT @returnDiffStatement = N'SELECT idnum as idnm, pos1, pos2, pos3, l1, l2, l3, * FROM ('
		+ N'SELECT ''' + @originalProc + N''' AS proc_version, ORIG.* 
		FROM ' + @originalResultsTable + N' ORIG
		WHERE NOT EXISTS (SELECT 1 FROM ' + @EDITResultsTable + ' EDIT WHERE ORIG.CHECKSUM = EDIT.CHECKSUM) 
		UNION ALL
		SELECT ''' + @EDITProc + N''' AS proc_Version, EDIT.* 
		FROM '+ @EDITResultsTable + N' EDIT
		WHERE NOT EXISTS (SELECT 1 FROM ' + @originalResultsTable + N' ORIG WHERE ORIG.CHECKSUM = EDIT.CHECKSUM) 
		) COMP ' + @orderbyClause + CASE WHEN ISNULL(@orderbyClause, N'') = N'' THEN N' ORDER BY Proc_Version' ELSE N', Proc_Version' END + N';'

		--SELECT @returnDiffStatement AS [@returnDiffStatement]
		EXEC SP_executesql @returnDiffStatement;

		SET @outputSelect = 
		  'SELECT ''Results from Original Proc: '+ @originalProc + N''';
		  SELECT * FROM ' + @originalResultsTable + @orderbyClause + N';
		  SELECT ''Results from Edited Proc: '+ @EDITProc + N''';
		  SELECT * FROM ' + @EDITResultsTable + @orderbyClause + N';';

		  EXEC sys.sp_executesql @outputSelect

	END

END;


SELECT @errorMess AS [Error Message]




--SELECT l1, SUM(extcost) FROM ##TestQueryResults GROUP BY l1
--SELECT l1, SUM(extcost) FROM ##TestQueryResults_EDIT GROUP BY l1


