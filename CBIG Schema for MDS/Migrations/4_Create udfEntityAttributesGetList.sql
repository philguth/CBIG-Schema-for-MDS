-- <Migration ID="326475af-26de-49ea-b64b-219974334d4e" />
GO
/****** Object:  UserDefinedFunction [cbig].[udfEntityAttributesGetList]    Script Date: 6/20/2017 11:38:41 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[cbig].[udfEntityAttributesGetList]') AND type in (N'FN', N'IF', N'TF', N'FS', N'FT'))
BEGIN
execute dbo.sp_executesql @statement = N'
/*
       SELECT * FROM cbig.udfEntityAttributesGetList(1069, 1, [Attribute Group Name] or NULL);;
       SELECT * FROM mdm.udfEntityAttributesGetList(1, 2);
       SELECT * FROM mdm.udfEntityAttributesGetList(1, 3);
       SELECT * FROM mdm.udfEntityAttributesGetList(23, 1);
*/
/*
==============================================================================
Copyright (c) Microsoft Corporation. All Rights Reserved.
==============================================================================
*/
CREATE FUNCTION [cbig].[udfEntityAttributesGetList]
(
       @Entity_ID           INT,
       @MemberType_ID       TINYINT,
       @Attribute_Group_Name nvarchar(50)
) 
RETURNS TABLE
/*WITH SCHEMABINDING*/
AS RETURN     
WITH CTE
AS
       (
SELECT        ag.id , ag.Entity_ID, ag.MemberType_ID, ag.Name,  ag.FreezeNameCode, ag.IsSystem, agd.AttributeGroup_ID, agd.Attribute_ID, agd.SortOrder , agd.DomainBinding, agd.TransformGroup_ID
FROM            mdm.tblAttributeGroup AS ag INNER JOIN
                         mdm.tblAttributeGroupDetail AS agd ON ag.ID = agd.AttributeGroup_ID
WHERE        (ag.Entity_ID = @Entity_ID) AND (ag.Name = @Attribute_Group_Name)
)
       
       SELECT 
              DISTINCT -- OR clause in predicate brings back duplicate rows
              A.Name AS ViewColumn,
              A.TableColumn,
              A.IsSystem,
              A.IsReadOnly,
              A.AttributeType_ID,
              A.DataType_ID,
              A.DomainEntity_ID,
              E.EntityTable AS DomainTable,
              A.SortOrder,
              CASE
              WHEN 
              cte.Name is null and a.IsSystem = 1 THEN @Attribute_Group_Name
              ELSE cte.Name
              END as Name
       FROM 
              mdm.tblAttribute A LEFT OUTER JOIN 
              mdm.tblEntity E ON A.DomainEntity_ID = E.ID
              LEFT OUTER JOIN cte ON a.id = cte.Attribute_ID
       WHERE
              A.Entity_ID = @Entity_ID AND
              A.MemberType_ID = @MemberType_ID AND
              A.AttributeType_ID <> 3;
              --(A.IsSystem = 0 OR A.IsReadOnly = 0);
' 
END

GO
