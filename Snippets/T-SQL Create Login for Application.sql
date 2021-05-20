--BootStrap ------------------------------------------------------
Use Master
Create Login ci With Password = '…strongpasswordhere…'
If Not Exists (Select * from master..syslogins where name = 'ci')
    RaisError ('NOTE the ci Login does not exist', 1,1)

Create Login ApplicationDatabaseOwner With Password = '…strongpasswordheretoo…'
Alter Login Applicationdatabaseowner Disable

Grant Impersonate On Login::Applicationdatabaseowner To ci
Grant Alter Any Login To ci
Grant Create Any Database To ci
;
-- Up ------------------------------------------------------
Execute as Login='ci'
Go
Create Database AppName
Create Login AppName with password='', Default_Database =Appname
Create Login AppName_Readonly with password='', Default_Database= Appname
Alter Authorization ON database::Appname TO ApplicationDatabaseOwner ;
;
Execute as Login='ApplicationDatabaseOwner'
Go
Use AppName
Create User AppName for Login AppName With Default_Schema= dbo
Create User AppName_readonly for Login AppName_readonly With Default_Schema= dbo
Alter Role db_owner Add Member ci
Alter Role db_datareader Add Member Appname
Alter Role db_datawriter Add Member Appname
Alter Role db_datareader Add Member Appname_Readonly
Go
-- Check ------------------------------------------------------
Select Db_Name() DbName, CURRENT_USER CurrentUser, SESSION_USER, SYSTEM_USER, ORIGINAL_LOGIN()
Select Name from sys.Sysdatabases
Select Name,Dbname,Language,Dbcreator from sys.Syslogins where loginname not like '##%##' and loginname not like 'NT %\%'
;
Execute as Login='applicationdatabaseowner'
Go
use [appname]
Create Table A(id int)
Insert into A Values (0)
use master
Revert
;
Execute as Login='appname'
Go
use [appname]
select current_user, session_user, original_login()
Select * from information_schema.tables
Insert Into A (id) Values (1)
Select * from A
use master
Revert
;
Execute as Login='appname_readonly'
Go
use [appname]
select current_user, session_user, original_login()
Select * from information_schema.tables
Insert Into A (id) Values (1)
Select * from A
use master
Revert
-- DOWN ------------------------------------------------------
;
Execute as Login='ci'
Go
Drop Login Appname
Drop Login Appname_Readonly
;
Execute as Login='applicationdatabaseowner'
Go
Drop database Appname
Revert
;

-- Delete Bootstrapping ------------------------------------------------------
-- Revoke Impersonate on Login::Applicationdatabaseowner from ci
-- Drop Login ci
-- Drop Login Applicationdatabaseowner
