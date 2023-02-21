DROP TABLE IF EXISTS #OpenJobQueries

SELECT IDENTITY(INT, 1, 1) AS RowNumber,  CONVERT(NVARCHAR(200), TextData) AS TextDataString, *
INTO #OpenJobQueries
FROM
	fn_trace_gettable(
						 'K:\Users\Nathan\Documents\Freelancing\[TraceResults].trc',
						 DEFAULT
					 );
GO

DROP TABLE IF EXISTS #OpenJobQueries_Refactor

SELECT IDENTITY(INT, 1, 1) AS RowNumber,  CONVERT(NVARCHAR(200), TextData) AS TextDataString, *
INTO #OpenJobQueries_Refactor
FROM
	fn_trace_gettable(
						 'K:\Users\Nathan\Documents\Freelancing\[TraceResults].trc',
						 DEFAULT
					 );
GO


--SELECT SUM(duration) FROM #OpenJobQueries 

SELECT O.duration			   AS Original_Duration,
	   R.duration			   AS Refactor_Duration,
	   O.duration - R.duration AS Duration_Difference,
	   (CAST((O.duration - R.duration) AS DECIMAL)/ CAST(o.duration AS DECIMAL)*100) AS Percentage_Difference
FROM (
		 SELECT SUM(Duration) AS duration
		 FROM #OpenJobQueries
		 WHERE TextDataString <> '' --LIKE '%[PROC_NAME]%'
	 )		 AS O
INNER JOIN (
			   SELECT SUM(Duration) AS duration
			   FROM #OpenJobQueries_Refactor
			   WHERE TextDataString <> '' --LIKE '%[PROC_NAME]%'
		   ) AS R
	ON 1 = 1;


SELECT duration, TextDataString FROM #OpenJobQueries  WHERE TextDataString != ''
SELECT duration, TextDataString FROM #OpenJobQueries_Refactor  WHERE TextDataString != ''

SELECT EventClass, ObjectName, * FROM #OpenJobQueries 
WHERE 
EventClass IN (
	10 --RPC:Completed
	,12 --SQL:BatchCompleted
)
--EventClass NOT IN (
--	122 --showplanxml
--	,45 --SP:StmtCompleted
--)
AND EVentClass = 12



SELECT ISNULL(ObjectName, textdatastring) AS [Total Duration in MS], SUM(duration)/1000 AS [Total Duration in MS]
FROM #OpenJobQueries 
WHERE EventClass IN (
	10 --RPC:Completed
	,12 --SQL:BatchCompleted
)
AND EventClass <= 500
AND TextDataString <> N'exec sp_reset_connection'
GROUP BY ISNULL(ObjectName, textdatastring), EventClass
ORDER BY EventClass, ISNULL(ObjectName, textdatastring);