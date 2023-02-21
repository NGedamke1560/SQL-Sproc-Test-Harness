--Generate Table From sp_describe_first_result_set
CREATE OR ALTER PROCEDURE NG.Generate_Table_Using_sp_describe_first_result_set (
									  @procCall		   NVARCHAR(MAX) = '',
									  @outputTableName NVARCHAR(MAX) = N'#out',
									  @execute		   BIT			= 0,
									  @suppressOutput BIT = 1
								  )
AS
BEGIN

	BEGIN TRY
		/* 
			Code borrowed shamelessly from Russ at SQLMovers.com
			https://www.sqlmovers.com/using-a-temporary-table-to-handle-sp_describe_first_result_set/		
		*/

		--Dynamic SQL string used to store table creation query
		--Will execute if @execute = 1, or just return the contents if @execute = 0
		DECLARE @tableBuildSQL NVARCHAR(MAX) = N'DROP TABLE IF EXISTS ' + @outputTableName + ';';

		--Create table to store columns from sys.sp_describe_first_result_set
		DROP TABLE IF EXISTS #ResultStructure;

		CREATE TABLE #ResultStructure (
										  is_hidden					   BIT			 NOT NULL,
										  column_ordinal			   INT			 NOT NULL,
										  name						   sysname		 NULL,
										  is_nullable				   BIT			 NOT NULL,
										  system_type_id			   INT			 NOT NULL,
										  system_type_name			   NVARCHAR(256) NULL,
										  max_length				   SMALLINT		 NOT NULL,
										  precision					   TINYINT		 NOT NULL,
										  scale						   TINYINT		 NOT NULL,
										  collation_name			   sysname		 NULL,
										  user_type_id				   INT			 NULL,
										  user_type_database		   sysname		 NULL,
										  user_type_schema			   sysname		 NULL,
										  user_type_name			   sysname		 NULL,
										  assembly_qualified_type_name NVARCHAR(4000),
										  xml_collection_id			   INT			 NULL,
										  xml_collection_database	   sysname		 NULL,
										  xml_collection_schema		   sysname		 NULL,
										  xml_collection_name		   sysname		 NULL,
										  is_xml_document			   BIT			 NOT NULL,
										  is_case_sensitive			   BIT			 NOT NULL,
										  is_fixed_length_clr_type	   BIT			 NOT NULL,
										  source_server				   sysname		 NULL,
										  source_database			   sysname		 NULL,
										  source_schema				   sysname		 NULL,
										  source_table				   sysname		 NULL,
										  source_column				   sysname		 NULL,
										  is_identity_column		   BIT			 NULL,
										  is_part_of_unique_key		   BIT			 NULL,
										  is_updateable				   BIT			 NULL,
										  is_computed_column		   BIT			 NULL,
										  is_sparse_column_set		   BIT			 NULL,
										  ordinal_in_order_by_list	   SMALLINT		 NULL,
										  order_by_list_length		   SMALLINT		 NULL,
										  order_by_is_descending	   SMALLINT		 NULL,
										  tds_type_id				   INT			 NOT NULL,
										  tds_length				   INT			 NOT NULL,
										  tds_collation_id			   INT			 NULL,
										  tds_collation_sort_id		   TINYINT		 NULL
									  );

		--Capture column names from stored procedure call
		INSERT #ResultStructure EXEC sys.sp_describe_first_result_set @procCall;

		--Build a query that will create a table with the same structure as the stored procedure results
		SELECT @tableBuildSQL =
			@tableBuildSQL + CASE WHEN column_ordinal = 1
									  THEN 'create table ' + @outputTableName + ' ( '
								 ELSE ', '
							 END + QUOTENAME(name) + N' ' + system_type_name
			+ CASE WHEN column_ordinal = MAX(column_ordinal) OVER ()
					   THEN ');'
				  ELSE ''
			  END
		FROM #ResultStructure;

		--Either build the table and return a message with it's name, or just return the sql to create the table
		IF @execute = 1
		BEGIN
			EXECUTE sp_executesql @tableBuildSQL;


			IF @suppressOutput = 0 SELECT N'Table ' + @outputTableName + ' created';
		END;
		ELSE IF @suppressOutput = 0
		BEGIN
			SELECT @tableBuildSQL;
		END;

	END TRY
	BEGIN CATCH
		SELECT 'Something went wrong with running your input SQL string',
			   @procCall;
	END CATCH;

END;