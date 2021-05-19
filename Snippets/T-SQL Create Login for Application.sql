--BootStrap
Use Master
Create Login ci With Password = '…strongpasswordhere…'
Grant Alter Any Login To ci
Grant Create Any Database To ci
Create Login ApplicationDatabaseOwner With Password = '…strongpasswordheretoo…'
Alter Login Applicationdatabaseowner Disable
Grant Impersonate On Login::Applicationdatabaseowner To ci
;
--Up
Execute as Login='ci'
Go
Create Database AppName
Alter Authorization ON database::Appname TO ApplicationDatabaseOwner ;
;
Select Name from sys.Sysdatabases
Select Name,Dbname,Language,Dbcreator from sys.Syslogins where Isntgroup=0 and Isntuser=0 and Name Not Like '##MS_%'
;
Execute as Login='ApplicationDatabaseOwner'
Go
Use AppName
Create Login AppName with password='', Default_Database =Appname
Create Login AppNameReadonly with password='', Default_Database= Appname
Create User AppName for Login AppName With Default_Schema= dbo
Create User AppName_readonly for Login AppName_readonly With Default_Schema= dbo
Alter Role db_datareader Add Member Appname
Alter Role db_datawriter Add Member Appname
Alter Role db_datareader Add Member Appname_Readonly
Go
-- DOWN
;
Drop User Appname
Drop User Appname_Readonly
Revert
Drop database Appname

-- Delete Bootstrapping
Revoke Impersonate on Login::umbraco_green_owner from ci
