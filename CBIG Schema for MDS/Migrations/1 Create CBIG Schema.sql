-- <Migration ID="210be6fc-21b7-4a10-966e-b619a86dadeb" />
GO
/****** Object:  Schema [cbig]    Script Date: 6/20/2017 10:05:49 AM ******/
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'cbig')
EXEC sys.sp_executesql N'CREATE SCHEMA [cbig]'

GO
