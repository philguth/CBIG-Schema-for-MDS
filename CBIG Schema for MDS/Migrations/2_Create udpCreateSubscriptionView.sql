-- <Migration ID="a9d47950-2d8a-4df3-b8c5-bc5c9a16f7ed" />
GO
/****** Object:  StoredProcedure [cbig].[udpCreateSubscriptionViews]    Script Date: 6/20/2017 10:22:47 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[cbig].[udpCreateSubscriptionViews]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [cbig].[udpCreateSubscriptionViews] AS' 
END
GO

/*  
==============================================================================  
 Copyright (c) Microsoft Corporation. All Rights Reserved.  
==============================================================================  
        EXEC cbig.udpCreateSubscriptionViews 1,1,1,1, 'TEST'  
*/  
ALTER PROCEDURE [cbig].[udpCreateSubscriptionViews]  
(  
    @SubscriptionView_ID        INT = NULL,   
    @Entity_ID                  INT,  
    @DerivedHierarchy_ID        INT,  
    @ModelVersion_ID            INT,  
    @ModelVersionFlag_ID        INT,  
    @ViewFormat_ID              INT,  
    @Levels                     SMALLINT,  
    @SubscriptionViewName       sysname,  
    @IncludeSoftDeletedMembers  BIT,  
    @CorrelationID              UNIQUEIDENTIFIER = NULL,  -- This parameter is populated from the c# layer and provides end to end traceability  
              @AttributeGroupName                             sysname
)  
/*WITH*/  
AS BEGIN  
    SET NOCOUNT ON;  
  
    DECLARE  
        @MemberType_Leaf                TINYINT = 1,  
        @MemberType_Consolidated        TINYINT = 2,  
        @MemberType_Collection          TINYINT = 3;  
  
    --Defer view generation if we are in the middle of an upgrade or demo-rebuild  
    IF APPLOCK_MODE(N'public', N'DeferViewGeneration', N'Session') = N'NoLock' BEGIN  
  
        -- Views for Entity  
        IF (@Entity_ID IS NOT NULL) BEGIN  
  
            /*********************************************  
                Available view formats for Entity are:  
                  
                1 - Leaf  
                2 - Consolidated  
                3 - Collection Attributes  
                4 - Collection  
                5 - Parent Child  
                6 - Levels  
                9 - LeafHistory  
                10 - ConsolidatedHistory  
                11 - CollectionHistory  
                12 - LeafType2  
                13 - ConsolidatedType2  
                14 - CollectionType2  
  
                Available view formats for Derived Hierarchy are:  
  
                7 - Parent Child  
                8 - Levels   
            *********************************************/  
  
            -- Leaf attributes  
            IF (@ViewFormat_ID = 1)  
            BEGIN  
                EXEC cbig.udpCreateAttributeViews @Entity_ID, @MemberType_Leaf, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName, @IncludeSoftDeletedMembers, @AttributeGroupName; --Leaf  
            END  
            ELSE IF (@ViewFormat_ID = 2)  
            BEGIN  
                EXEC mdm.udpCreateAttributeViews @Entity_ID, @MemberType_Consolidated, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName, @IncludeSoftDeletedMembers; --Consolidated  
            END  
            ELSE IF (@ViewFormat_ID = 3)  
            BEGIN  
                EXEC mdm.udpCreateAttributeViews @Entity_ID, @MemberType_Collection, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName, @IncludeSoftDeletedMembers; --Collection  
            END  
            ELSE IF (@ViewFormat_ID = 4)  
            BEGIN  
                EXEC mdm.udpCreateCollectionViews @Entity_ID, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName, @IncludeSoftDeletedMembers;   
            END  
            ELSE IF (@ViewFormat_ID = 5)  
            BEGIN  
               EXEC mdm.udpCreateParentChildViews @Entity_ID, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 6)  
            BEGIN  
                EXEC mdm.udpCreateLevelViews @Entity_ID, @Levels, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 9)  
            BEGIN  
                EXEC mdm.udpCreateHistoryViews @Entity_ID, @MemberType_Leaf, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END ELSE IF (@ViewFormat_ID = 10)  
            BEGIN  
                EXEC mdm.udpCreateHistoryViews @Entity_ID, @MemberType_Consolidated, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 11)  
            BEGIN  
                EXEC mdm.udpCreateHistoryViews @Entity_ID, @MemberType_Collection, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 12)  
            BEGIN  
                EXEC mdm.udpCreateType2Views @Entity_ID, @MemberType_Leaf, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 13)  
            BEGIN  
                EXEC mdm.udpCreateType2Views @Entity_ID, @MemberType_Consolidated, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE  
            IF (@ViewFormat_ID = 14)  
            BEGIN  
                EXEC mdm.udpCreateType2Views @Entity_ID, @MemberType_Collection, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE  
            BEGIN  
                RAISERROR('MDSERR100014|The View Format ID is not valid.', 16, 1);  
                RETURN;  
            END;  
        END   
        --Views for Derived Hierarchy  
        ELSE BEGIN  
            IF (@ViewFormat_ID = 7)  
            BEGIN  
                EXEC mdm.udpCreateDerivedHierarchyParentChildView @DerivedHierarchy_ID, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE IF (@ViewFormat_ID = 8)  
            BEGIN  
                EXEC mdm.udpCreateDerivedHierarchyLevelView @DerivedHierarchy_ID, @Levels, @ModelVersion_ID, @ModelVersionFlag_ID, @SubscriptionViewName;  
            END  
            ELSE  
            BEGIN  
                RAISERROR('MDSERR100014|The View Format ID is not valid.', 16, 1);  
                RETURN;  
            END;  
        END  
          
    END; --if  
  
    SET NOCOUNT OFF;  
END; --proc
GO
