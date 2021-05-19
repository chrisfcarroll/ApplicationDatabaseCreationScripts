EXEC sp_serveroption @@SERVERNAME, 'DATA ACCESS', TRUE
Go
Declare
    @localLanguage Varchar(50)= 'British'
SELECT * FROM OPENQUERY( Z600, 'EXEC sp_helplanguage') where alias like '%' + @Locallanguage + '%'
Go
Use master
Go
Create or Alter View dbo.HelpLanguage As SELECT * FROM OPENQUERY( Z600, 'EXEC sp_helplanguage')
Grant Select on dbo.Helplanguage To Public;
EXEC sp_configure 'default language', 23 -- 'British English';
RECONFIGURE
GO
;
Alter Login Dev With Default_Language = British
GO
;
SELECT
    Db_Name() DbName, CONVERT (varchar(50), DATABASEPROPERTYEX(Db_Name(),'collation')) CurrentDbCollation,
    CONVERT (varchar(50), DATABASEPROPERTYEX('master','collation')) MasterCollation,
    CONVERT (varchar(50), DATABASEPROPERTYEX('tempdb','collation')) TempDbCollation,
    CONVERT (varchar(50), SERVERPROPERTY('collation')) ServerDefaultCollation
