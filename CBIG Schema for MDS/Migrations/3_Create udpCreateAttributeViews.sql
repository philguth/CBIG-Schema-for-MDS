-- <Migration ID="33c6b716-340e-4cc0-a7f8-99e98370d476" />
GO
/****** Object:  StoredProcedure [mdm].[udpCreateAttributeViews]    Script Date: 6/20/2017 11:01:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[cbig].[udpCreateAttributeViews]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [cbig].[udpCreateAttributeViews] AS' 
END
GO

/*  
==============================================================================  
 Copyright (c) Microsoft Corporation. All Rights Reserved.  
==============================================================================  
  
    EXEC cbig.udpCreateAttributeViews 1, 1, 1, 1, NULL, 'TEST';  
    EXEC cbig.udpCreateAttributeViews 1, 2, 1, 1, NULL, 'TEST';  
    EXEC cbig.udpCreateAttributeViews 1, 3, 1, NULL, 9, 'TEST';  
    EXEC cbig.udpCreateAttributeViews 111111, 1; --invalid  
*/  
ALTER PROCEDURE [cbig].[udpCreateAttributeViews]   
(  
    @Entity_ID                 INT,  
    @MemberType_ID             TINYINT,  
    @Version_ID                 INT ,  
    @VersionFlag_ID             INT,  
    @SubscriptionViewName      SYSNAME,  
    @IncludeSoftDeletedMembers BIT,  
    @CorrelationID             UNIQUEIDENTIFIER = NULL,  -- This parameter is populated from the c# layer and provides end to end traceability  
	@AttributeGroup_Name	   NVARCHAR(50)
)  
--WITH EXECUTE AS 'mds_schema_user'  
AS BEGIN  
    SET NOCOUNT ON;  
  
    DECLARE  
        @MemberType_Leaf                TINYINT = 1,  
        @MemberType_Consolidated        TINYINT = 2,  
        @MemberType_Collection          TINYINT = 3;  
  
    --Defer view generation if we are in the middle of an upgrade or demo-rebuild  
    IF APPLOCK_MODE(N'public', N'DeferViewGeneration', N'Session') = N'NoLock'   
    BEGIN  
  
        DECLARE @ViewName               SYSNAME,  
                @EntityTable            SYSNAME,  
                @HierarchyTable         SYSNAME,  
                @HierarchyParentTable   SYSNAME,  
                @CollectionTable        SYSNAME,  
                @Select                 NVARCHAR(MAX) = N'',  
                @From                   NVARCHAR(MAX) = N'',  
                @ViewColumn             nvarchar(120), --specifically made to be less than 128 for truncation reasons  
                @TableColumn            SYSNAME,  
                @DomainTable            SYSNAME,  
                @DomainEntity_ID        INT,  
                @AttributeType_ID       INT,  
                @MainTable              SYSNAME;  
              
        SELECT  
            @EntityTable = EntityTable,  
            @CollectionTable = CollectionTable,  
            @HierarchyTable = HierarchyTable,  
            @HierarchyParentTable = HierarchyParentTable,  
            @ViewName = @SubscriptionViewName  
        FROM mdm.tblEntity  
        WHERE   ID = @Entity_ID  
            -- Ensure that the specified member type is supported  
            AND CASE @MemberType_ID   
                    WHEN @MemberType_Leaf           THEN EntityTable -- EntityTable should never be null  
                    WHEN @MemberType_Consolidated   THEN HierarchyTable  
                    WHEN @MemberType_Collection     THEN CollectionTable  
                    END IS NOT NULL  
  
        IF @ViewName IS NULL --Ensure row actually exists  
        BEGIN  
            RAISERROR('MDSERR100010|The Parameters are not valid.', 16, 1);  
            RETURN(1);  
        END;  
          
        SELECT  
            @EntityTable = E.EntityTable,  
            @CollectionTable = E.CollectionTable,  
            @HierarchyTable = E.HierarchyTable,  
            @HierarchyParentTable = E.HierarchyParentTable,  
            @ViewName = @SubscriptionViewName  
        FROM mdm.tblEntity E   
        INNER JOIN mdm.tblModel M ON E.Model_ID = M.ID  
        WHERE E.ID = @Entity_ID;  
  
        DECLARE @ConflictingColumnName NVARCHAR(100);  
        --Get the Attributes for the Entity and then find the corresponding lookup table  
        DECLARE @TempTable TABLE(  
                ViewColumn          NVARCHAR(100) COLLATE database_default  
                ,TableColumn        SYSNAME COLLATE database_default  
                ,AttributeType_ID   INT  
                ,DomainEntity_ID    INT NULL  
                ,DomainTable        SYSNAME COLLATE database_default NULL  
                ,SortOrder          INT);  
        INSERT INTO @TempTable  
        SELECT  
            ViewColumn,  
            TableColumn,  
            AttributeType_ID,  
            DomainEntity_ID,  
            DomainTable,  
            SortOrder  
        FROM       
            --Previous - mdm.udfEntityAttributesGetList(@Entity_ID, @MemberType_ID)   
			cbig.udfEntityAttributesGetList(@Entity_ID, @MemberType_ID, @AttributeGroup_Name)   
        ORDER BY   
            SortOrder ASC;  
  
        SET @MainTable = CASE  
            WHEN @MemberType_ID = @MemberType_Leaf THEN @EntityTable--Leaf (EN)    
            WHEN @MemberType_ID = @MemberType_Collection THEN @CollectionTable --Collection (CN)   
            ELSE @HierarchyParentTable  --Consolidated (HP)   
            END;  
  
        WHILE EXISTS(SELECT 1 FROM @TempTable)   
        BEGIN  
          
            SELECT TOP 1   
                @ViewColumn = ViewColumn,  
                @TableColumn = TableColumn,  
                @AttributeType_ID = AttributeType_ID,  
                @DomainEntity_ID = DomainEntity_ID,  
                @DomainTable = DomainTable  
            FROM @TempTable  
            ORDER BY   
                SortOrder ASC;  
  
            IF @DomainEntity_ID IS NULL BEGIN   
                --Check for name validation, if there are some DBA which their _Code/_Name/_ID columns have conflicts with some FFA attribute names.            
                DECLARE @ViewColumnPrefix NVARCHAR(120) = CASE  
                    WHEN @ViewColumn LIKE N'%_Code' THEN LEFT(@ViewColumn, LEN(@ViewColumn) - LEN(N'_Code'))  
                    WHEN @ViewColumn LIKE N'%_Name' THEN LEFT(@ViewColumn, LEN(@ViewColumn) - LEN(N'_Name'))  
                    WHEN @ViewColumn LIKE N'%_ID'   THEN LEFT(@ViewColumn, LEN(@ViewColumn) - LEN(N'_ID'))  
                    ELSE NULL  
                    END;  
                IF (@ViewColumnPrefix IS NOT NULL)  
                BEGIN  
                    SELECT TOP 1 @ConflictingColumnName = Name   
                    FROM mdm.tblAttribute   
                    WHERE tblAttribute.Entity_ID = @Entity_ID   
                        AND tblAttribute.AttributeType_ID = 2   
                        AND tblAttribute.Name = @ViewColumnPrefix;  
                    IF (@ConflictingColumnName IS NOT NULL)  
                    BEGIN        
                        RAISERROR('MDSERR100059|There are at least two attribute names in conflict in the existing or new subscription view. Free-form attribute names cannot start with an existing domain-based attribute name and end with "_Code", "_Name" or "_ID". Attribute names are: |%s|%s|', 16, 1, @ConflictingColumnName, @ViewColumn);  
                        RETURN;       
                    END  
                END  
                IF @ViewColumn = N'Owner_ID' AND @MemberType_ID = @MemberType_Collection   
                BEGIN --Collection  
                    SET @Select = CONCAT(@Select, N'  
    ,', QUOTENAME(@ViewColumn), N'.UserName AS [Owner_ID]');  
                    SET @From = CONCAT(@From, N'  
LEFT JOIN mdm.tblUser AS Owner_ID ON Owner_ID.ID = T.Owner_ID');  
                END ELSE   
                BEGIN  
                    SET @Select = CONCAT(@Select, N'  
    ,T.', QUOTENAME(@TableColumn), N' AS ', QUOTENAME(@ViewColumn));  
                END; --if  
  
            END ELSE   
            BEGIN  
                --Check for name validation, if there are some DBA which their _Code/_Name/_ID columns have conflicts with some FFA attribute names.      
                SELECT TOP 1 @ConflictingColumnName = Name FROM mdm.tblAttribute WHERE tblAttribute.Entity_ID = @Entity_ID AND     
                        tblAttribute.AttributeType_ID = 1 AND (tblAttribute.Name =@ViewColumn  + N'_Code' OR tblAttribute.Name = @ViewColumn  + N'_Name' OR tblAttribute.Name = @ViewColumn  + N'_ID' );  
                IF (@ConflictingColumnName IS NOT NULL)  
                BEGIN        
                    RAISERROR('MDSERR100059|There are at least two attribute names in conflict in the existing or new subscription view. Free-form attribute names cannot start with an existing domain-based attribute name and end with "_Code", "_Name" or "_ID". Attribute names are: |%s|%s|', 16, 1, @ConflictingColumnName, @ViewColumn);  
                    RETURN;       
                END  
                SET @Select = CONCAT(@Select, N'  
    ,', QUOTENAME(@ViewColumn), N'.Code AS ', QUOTENAME(@ViewColumn + N'_Code'), N'  
    ,', QUOTENAME(@ViewColumn), N'.Name AS ', QUOTENAME(@ViewColumn + N'_Name'), N'  
    ,T.', QUOTENAME(@TableColumn), N' AS ', QUOTENAME(@ViewColumn + N'_ID'));  
                     
                SET @From = CONCAT(@From, N'  
LEFT JOIN mdm.', QUOTENAME(@DomainTable), N' AS ', QUOTENAME(@ViewColumn), N' ON ', QUOTENAME(@ViewColumn), N'.ID = T.', QUOTENAME(@TableColumn), N'  
    AND ', QUOTENAME(@ViewColumn), N'.Version_ID = T.Version_ID')  
  
                END; --if  
  
                DELETE FROM @TempTable WHERE ViewColumn = @ViewColumn;  
  
            END; --while  
  
            SET @Select = CONCAT(CASE   
                WHEN EXISTS(SELECT 1 FROM sys.views WHERE [name] = @ViewName AND [schema_id] = SCHEMA_ID('mdm')) THEN N'ALTER'  
                ELSE N'CREATE' END, N' VIEW mdm.', QUOTENAME(@ViewName), N'  
/*WITH ENCRYPTION*/  
AS SELECT   
     T.ID AS ID  
    ,T.MUID AS MUID   
    ,V.Name AS VersionName  
    ,V.Display_ID AS VersionNumber  
    ,V.ID AS Version_ID  
    ,DV.Name AS VersionFlag',  
                CASE WHEN @MemberType_ID = @MemberType_Consolidated THEN N'  
    ,H.Name as Hierarchy' END, @Select, N'  
    ,T.EnterDTM AS EnterDateTime  
    ,UE.UserName AS EnterUserName  
    ,(SELECT Display_ID FROM mdm.tblModelVersion WHERE ID = T.EnterVersionID) AS EnterVersionNumber  
    ,T.LastChgDTM AS LastChgDateTime  
    ,UC.UserName AS LastChgUserName  
    ,(SELECT Display_ID FROM mdm.tblModelVersion WHERE ID = T.LastChgVersionID) AS LastChgVersionNumber  
    ,LV.ListOption AS ValidationStatus',  
                CASE WHEN @IncludeSoftDeletedMembers = 1 THEN N'  
    ,LS.ListOption AS State' END, N'  
FROM mdm.', QUOTENAME(@MainTable), N' AS T  
INNER JOIN mdm.tblModelVersion AS V ON V.ID = T.Version_ID ',  
                CASE @MemberType_ID   
                    WHEN @MemberType_Consolidated THEN N'  
INNER JOIN mdm.tblHierarchy H ON H.ID = T.Hierarchy_ID'  
                    WHEN @MemberType_Collection THEN N'AND V.Status_ID <> 0'   
                    END,   
                @From,  
                CASE WHEN @IncludeSoftDeletedMembers = 1 THEN N'  
LEFT JOIN mdm.tblList LS ON LS.OptionID = T.Status_ID AND LS.ListCode = ''lstStatus'''  
                    END, N'  
LEFT JOIN mdm.tblUser UE ON T.EnterUserID = UE.ID  
LEFT JOIN mdm.tblUser UC ON T.LastChgUserID = UC.ID   
LEFT JOIN mdm.tblList LV ON LV.OptionID = T.ValidationStatus_ID AND LV.ListCode = ''lstValidationStatus''   
LEFT JOIN mdm.tblModelVersionFlag AS DV ON DV.ID =  V.VersionFlag_ID  
WHERE V.',      CASE   
                    WHEN (@Version_ID IS NOT NULL)     THEN CONCAT(N'ID = ', @Version_ID)  
                    WHEN (@VersionFlag_ID IS NOT NULL) THEN CONCAT(N'VersionFlag_ID = ', @VersionFlag_ID)  
                    END,   
                CASE WHEN @IncludeSoftDeletedMembers = 0 THEN N'  
    AND T.Status_ID = 1' END, -- otherwise all the members are included regardless of their Status_ID  
                    N';');  
  
            --PRINT(@Select);  
            EXEC sp_executesql @Select;  
  
    END; --if  
  
    SET NOCOUNT OFF;  
END; --proc
GO


