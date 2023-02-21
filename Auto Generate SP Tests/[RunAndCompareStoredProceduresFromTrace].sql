USE WeSuiteMasterContracts;
GO


DROP PROCEDURE IF EXISTS [dbo].[RunAndCompareStoredProceduresFromTrace]
GO


CREATE PROCEDURE [dbo].[RunAndCompareStoredProceduresFromTrace] (
											@altProcTag NVARCHAR(MAX),
											@filePath NVARCHAR(MAX),
											@server NVARCHAR(MAX),
											@databaseName NVARCHAR(MAX),
											@procName NVARCHAR(MAX) NULL = NULL
										  )
AS
BEGIN

	/*********************************** Variable Declaration *****************************************/
	/*Author: Nathan Urban-Gedamke AKA Medieval SQL Guy*/
	/*With help from: https://www.sqlmovers.com/using-a-temporary-table-to-handle-sp_describe_first_result_set/ */
	/* This stored prcedure needs Ad-Hoc Distributed Queries turned on in order to run*/
	/*
		--Turn on AdHoc Queries
		sp_configure 'Show Advanced Options', 1
		GO
		RECONFIGURE
		GO
		sp_configure 'Ad Hoc Distributed Queries', 1
		GO
		RECONFIGURE
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
	*/

	DECLARE @connectionString NVARCHAR(MAX) = 'Driver={ODBC Driver 13 for SQL Server};server=' + @server + ';database=' + @databaseName + ';trusted_connection=Yes;';
	DECLARE @newLineChar NVARCHAR(MAX) = N';' + CAST((CHAR(13) + CHAR(10)) AS NVARCHAR(MAX));
	DECLARE @totalNumTests INT;

	--Dynamic SQL strings
	DECLARE @createTestTablesSQL NVARCHAR(MAX) = 'DECLARE @execCreate NVARCHAR(MAX) = ''''' + @newLineChar;
	DECLARE @truncateTestTablesSQL NVARCHAR(MAX) = '';
	DECLARE @dropTestTablesSQL NVARCHAR(MAX) = '';
	DECLARE @runAllOriginalTestsSQL NVARCHAR(MAX) = 'DECLARE @testStartDate DATETIME, @testEndDate DATETIME' + @newLineChar;
	DECLARE @runAllNewTestsSQL NVARCHAR(MAX) = 'DECLARE @testStartDate DATETIME, @testEndDate DATETIME' + @newLineChar;
	DECLARE @compareResultsSQL NVARCHAR(MAX) = '';
	

	--Stores one row for each unique stored proc 
		--& the name of the table test results are stored to for that proc
	CREATE TABLE #resultTables (
		ID INT IDENTITY,
		SP_Name NVARCHAR(MAX) NOT NULL,
		ResultTableName NVARCHAR(MAX) NOT NULL,
		Column_Names NVARCHAR(MAX) NULL,
		NumberOfTests INT NOT NULL,
		NumberFailed INT NOT NULL,
		AverageRuntimeInMS INT NULL,
		New_AverageRuntimeInMS INT NULL,
		TotalRuntimeInMS INT NULL,
		New_TotalRuntimeInMS INT NULL
	);

	--Table to store metadata from procs in order to create results tables
	Drop  table if exists #ResultStructure
	create table #ResultStructure (is_hidden bit NOT NULL
	, column_ordinal int NOT NULL
	, name sysname NULL
	, is_nullable bit NOT NULL
	, system_type_id int NOT NULL
	, system_type_name nvarchar(256) NULL
	, max_length smallint NOT NULL
	, precision tinyint NOT NULL
	, scale tinyint NOT NULL
	, collation_name sysname NULL
	, user_type_id int NULL
	, user_type_database sysname NULL
	, user_type_schema sysname NULL
	, user_type_name sysname NULL
	, assembly_qualified_type_name nvarchar(4000)
	, xml_collection_id int NULL
	, xml_collection_database sysname NULL
	, xml_collection_schema sysname NULL
	, xml_collection_name sysname NULL
	, is_xml_document bit NOT NULL
	, is_case_sensitive bit NOT NULL
	, is_fixed_length_clr_type bit NOT NULL
	, source_server sysname NULL
	, source_database sysname NULL
	, source_schema sysname NULL
	, source_table sysname NULL
	, source_column sysname NULL
	, is_identity_column bit NULL
	, is_part_of_unique_key bit NULL
	, is_updateable bit NULL
	, is_computed_column bit NULL
	, is_sparse_column_set bit NULL
	, ordinal_in_order_by_list smallint NULL
	, order_by_list_length smallint NULL
	, order_by_is_descending smallint NULL
	, tds_type_id int NOT NULL
	, tds_length int NOT NULL
	, tds_collation_id int NULL
	, tds_collation_sort_id tinyint NULL
	);


	/*********************************** Import the trace file into a trace table *****************************************/
BEGIN TRY
	SELECT
		TestNumber = IDENTITY(INT, 1, 1),
		SP_Name = LTRIM(SUBSTRING(TextData, 5, CHARINDEX('@', TextData) - 6)),
		New_SP_Name = LTRIM(SUBSTRING(TextData, 5, CHARINDEX('@', TextData) - 6)) + @altProcTag,
		ResultTableName = CONVERT(
									 NVARCHAR(MAX),
									 'tmp_' 
									 + REPLACE(LTRIM(SUBSTRING(TextData, 5, CHARINDEX('@', TextData) - 6)),'.', '')
									 + '_Results'
								 ),
		SP_ResultsHash = CONVERT(INT, NULL),
		New_SP_ResultsHash = CONVERT(INT, NULL),
		BothResultsMatch = CONVERT(BIT, NULL),
		RuntimeInMS = CONVERT(INT, NULL),
		New_RuntimeInMS = CONVERT(INT, NULL),
		SP_Execute_String = CONVERT(NVARCHAR(MAX), ''),
		New_SP_Execute_String = CONVERT(NVARCHAR(MAX), ''),
		TextDataAsNvarchar = CONVERT(NVARCHAR(MAX), TextData),
		*
	INTO dbo.#tmp_Dynamic_Tests
	FROM fn_trace_gettable(@filePath, DEFAULT)
	WHERE
		TextData LIKE 'exec%' --Only pull rows that are stored porocedure calls
		AND
		(--filter on procName variable if provided
			@procName IS NULL
			OR
			(
				ObjectName LIKE '%' + @procName + '%'
				OR TextData LIKE '%' + @procName + '%'
			)
		);

	--Get the number of distinct stored procedure calls in the trace table
	SET @totalNumTests =
	(
		SELECT COUNT(1) FROM #tmp_Dynamic_Tests
	);

		--Create string that can be executed to run stored procedure
		UPDATE #tmp_Dynamic_Tests
		SET [SP_Execute_String] = 'OPENROWSET (''SQLNCLI'', ''' + @ConnectionString + ''', ''' +  REPLACE(TextDataAsNvarchar, '''', '''''') + ''')',
			[New_SP_Execute_String] = 'OPENROWSET (''SQLNCLI'', ''' + @ConnectionString + ''', ''' +  REPLACE(REPLACE(TextDataAsNvarchar, '''', ''''''), SP_Name, (New_SP_Name + ' ')) + ''')'
		WHERE SP_Execute_String = '';

		/*********************************** Create one Results Table for each Stored Procedure *****************************************/
		INSERT INTO #resultTables (ResultTableName, SP_Name, NumberOfTests, NumberFailed)
		SELECT ResultTableName, SP_Name, NumberOfTests = COUNT(1), NumberFailed = 0
		FROM #tmp_Dynamic_Tests
		GROUP BY ResultTableName, SP_Name;

		SELECT 
			@createTestTablesSQL =  @createTestTablesSQL 
				+  REPLACE(REPLACE(
					'TRUNCATE TABLE #ResultStructure
					
					Insert #ResultStructure
					exec sys.sp_describe_first_result_set N''$executeSQL'';

					SET @execCreate = ''CREATE table  $tblName ( ID INT IDENTITY(1, 1) , FK_TestNumber INT NOT NULL, Original_Proc BIT NOT NULL, CHECKSUM INT NULL''

					SELECT @execCreate =  @execCreate + '', ''
					+ QUOTENAME (name) + '' '' + system_type_name
					+ case when column_ordinal = max(column_ordinal) over () then '');'' else '''' end
					 from #ResultStructure;
					 
					 EXEC sys.sp_executesql @execCreate', '$tblName', tbl.ResultTableName), '$executeSQL', tbl.SP_Name)
				+ @NewLineChar,
			@truncateTestTablesSQL =  @truncateTestTablesSQL + 'TRUNCATE TABLE ' + ResultTableName + @NewLineChar,
			@dropTestTablesSQL = @dropTestTablesSQL +  N'DROP TABLE IF EXISTS ' + ResultTableName + @NewLineChar
		FROM #resultTables AS tbl;

		--Drop test results tables if they already exist
		EXEC sp_executesql @dropTestTablesSQL;

		--run the proc to create the table
		--SELECT @createTestTablesSQL  --Debug
		EXEC sp_executesql @createTestTablesSQL;

		--Truncate results of table because we are going to populate from scratch below
		--SELECT @truncateTestTablesSQL  --Debug
		--EXEC SP_executesql @truncateTestTablesSQL;

		--Get list of all column names that were returned from each stored procedure
		UPDATE #resultTables
		SET Column_Names = STUFF(
									(
										SELECT ', ' + COLUMN_NAME
										FROM INFORMATION_SCHEMA.COLUMNS
										WHERE
											TABLE_NAME = ResultTableName
											AND COLUMN_NAME NOT IN ( 'ID', 'FK_TestNumber', 'Original_Proc', 'CHECKSUM', 'TimeStamp' )
										FOR XML PATH(''), TYPE
									).value('(./text())[1]', 'VARCHAR(MAX)'), 1, 2, ''
								);

		/*********************************** Run one test for each line in the Trace Table *****************************************/
		--Create Dynamic SQL with one execute for each test
		SELECT @runAllOriginalTestsSQL =  @runAllOriginalTestsSQL
				+ N'SET @testStartDate = (SELECT GETDATE())' + @NewLineChar
				+ N'INSERT INTO ' + CAST([ResultTableName] AS NVARCHAR(MAX)) + N' SELECT ' + CONVERT(NVARCHAR(MAX), [TestNumber]) + N', 1 AS Original_Proc, *, NULL AS [CHECKSUM] FROM ' + CAST([SP_Execute_String] AS NVARCHAR(MAX)) + @NewLineChar
				+ N'SET @testEndDate = (SELECT GETDATE())' + @NewLineChar
				+ N'UPDATE #tmp_Dynamic_Tests SET RuntimeInMS = datediff(millisecond, @testStartDate, @testEndDate) WHERE TestNumber = ' + CONVERT(NVARCHAR(MAX), [TestNumber]) + @NewLineChar
		FROM #tmp_Dynamic_Tests;


		--Dynamic SQL for new proc tests
		SELECT @runAllNewTestsSQL =  @runAllNewTestsSQL
				+ N'SET @testStartDate = (SELECT GETDATE())' + @NewLineChar
				+ N'INSERT INTO ' + CAST([ResultTableName] AS NVARCHAR(MAX)) + N' SELECT ' + CONVERT(NVARCHAR(MAX), [TestNumber]) + N', 0 AS Original_Proc, *, NULL AS [CHECKSUM] FROM ' + CAST([New_SP_Execute_String] AS NVARCHAR(MAX)) + @NewLineChar
				+ N'SET @testEndDate = (SELECT GETDATE())' + @NewLineChar
				+ N'UPDATE #tmp_Dynamic_Tests SET New_RuntimeInMS = datediff(millisecond, @testStartDate, @testEndDate) WHERE TestNumber = ' + CONVERT(NVARCHAR(MAX), [TestNumber]) + @NewLineChar
		FROM #tmp_Dynamic_Tests;

		----Debug printouts. Uses XML path to avoid SSMS truncating the string in the results pane
		--SELECT @runAllOriginalTestsSQL AS [processing-instruction(x)] FOR XML PATH 
		--SELECT @runAllNewTestsSQL AS [processing-instruction(x)] FOR XML PATH 

		--Run both sets of tests
		EXEC SP_executesql @runAllOriginalTestsSQL;
		EXEC SP_executesql @runAllNewTestsSQL;


		/***************************** Evaluate if both original and new version of query produce same results *****************************************/
		--Calculate Checksum for each result row in all result tables
		SELECT 
			@compareResultsSQL = @compareResultsSQL 
				+ N'UPDATE ' + ResultTableName + ' SET [CHECKSUM] = CHECKSUM(' + Column_Names + ')' + @NewLineChar
				--UPDATE [ResultTable] SET CHECKSUM = CHECKSUM([AllColumnsReturnedByProc])
		FROM #resultTables;

		--Compute Checksum for all rows in each test and compare to the modified proc
		SELECT 
			@compareResultsSQL = @compareResultsSQL 
			+ N'UPDATE Test
				SET 
					Test.SP_ResultsHash = ISNULL(OriginalResult.[ResultsChecksum], 0),
					Test.New_SP_ResultsHash =  ISNULL(NewResult.[ResultsChecksum], 0),
					Test.BothResultsMatch = CASE WHEN ISNULL(OriginalResult.[ResultsChecksum], 0) = ISNULL(NewResult.[ResultsChecksum], 0) THEN 1 ELSE 0 END
				FROM #tmp_Dynamic_Tests AS Test
				LEFT JOIN (
					SELECT 
						[TestNumber] = FK_TestNumber, 
						[ResultsChecksum] = CHECKSUM_AGG([CHECKSUM])
					FROM ' + ResultTableName + '
					WHERE Original_Proc = 1
					GROUP BY FK_TestNumber
				) AS OriginalResult
				ON Test.TestNumber = OriginalResult.[TestNumber]
				LEFT JOIN (
					SELECT 
						[TestNumber] = FK_TestNumber, 
						[ResultsChecksum] = CHECKSUM_AGG([CHECKSUM])
					FROM ' + ResultTableName + '
					WHERE Original_Proc = 0
					GROUP BY FK_TestNumber
				) AS NewResult
					ON Test.TestNumber = NewResult.[TestNumber]
				WHERE Test.SP_ResultsHash IS NULL
					AND	Test.ResultTableName = ''' + ResultTableName + '''' + @NewLineChar
		FROM #resultTables;

		--Run comparison of all tests
		--SELECT @compareResultsSQL --Debug
		EXEC SP_executesql @compareResultsSQL;

		--Mark number of failed tests for each stored procedure
		UPDATE #resultTables
		SET NumberFailed = Tests.NumberFailed
		FROM
			#resultTables AS Results
		INNER JOIN
		(
			SELECT
				SP_Name,
				COUNT(BothResultsMatch) AS NumberFailed,
				ISNULL(AVG(RuntimeInMS), 0) AS AverageRuntimeInMS,
				ISNULL(AVG(New_RuntimeInMS), 0) AS New_AverageRuntimeInMS
			FROM #tmp_Dynamic_Tests
			WHERE BothResultsMatch <> 1
			GROUP BY SP_Name
		) AS Tests
			ON Results.SP_Name = Tests.SP_Name;

		--UPDATE Average Runtimes for each Proc
		UPDATE #resultTables
		SET AverageRuntimeInMS = Tests.AverageRuntimeInMS,
			New_AverageRuntimeInMS = Tests.New_AverageRuntimeInMS,
			TotalRuntimeInMS = Tests.TotalRuntimeInMS,
			New_TotalRuntimeInMS = Tests.New_TotalRuntimeInMS
		FROM
			#resultTables AS Results
		INNER JOIN
		(
			SELECT
				SP_Name,
				ISNULL(AVG(RuntimeInMS), 0) AS AverageRuntimeInMS,
				ISNULL(AVG(New_RuntimeInMS), 0) AS New_AverageRuntimeInMS,
				ISNULL(SUM(RuntimeInMS), 0) AS TotalRuntimeInMS,
				ISNULL(SUM(New_RuntimeInMS), 0) AS new_TotalRuntimeInMS
			FROM #tmp_Dynamic_Tests
			GROUP BY SP_Name
		) AS Tests
			ON Results.SP_Name = Tests.SP_Name;


		/***************************************** Report Findings *****************************************/
		SELECT N'Total Number of Tests Run: ' + CAST(@totalNumTests AS NVARCHAR(200));

		SELECT ID,
			   SP_Name,
			   NumberOfTests,
			   NumberFailed,
			   AverageRuntimeInMS,
			   New_AverageRuntimeInMS AS AverageRuntimeInMS_NewProc,
			   TotalRuntimeInMS,
			   New_TotalRuntimeInMS AS TotalRuntimeInMS_NewProc,
			   Column_Names
		FROM #resultTables
		ORDER BY SP_Name;

		IF NOT EXISTS (SELECT 1 FROM #resultTables WHERE NumberFailed <> 0)
		BEGIN
			SELECT TestNumber AS FailedTestNumber,
				   SP_Name,
				   New_SP_Name,
				   RuntimeInMS,
				   New_RuntimeInMS,
				   SP_Execute_String,
				   New_SP_Execute_String
			FROM #tmp_Dynamic_Tests
			WHERE BothResultsMatch <> 1 
			ORDER BY SP_Name;
		END;

		----Debug
		--SELECT * FROM #tmp_Dynamic_Tests WHERE RuntimeInMS < New_RuntimeInMS
		--SELECT * FROM #resultTables
		--SELECT * FROM tmp_dash_SearchLocation_Results

		--Drop test results tables
		EXEC sp_executesql @dropTestTablesSQL;
	END TRY
	BEGIN CATCH
		SELECT * FROM #tmp_Dynamic_Tests;
		SELECT @createTestTablesSQL;
		IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'tmp_NGTestQuery_RESULTS')
		BEGIN
			SELECT 'Results Tables Created'
		END
		SELECT ERROR_MESSAGE();
	END CATCH
END;
GO
