--BootStrap ------------------------------------------------------
Use Master
;
Create Login ci With Password = '…strongpasswordhere…' 
;
Create Certificate Login_ciadmin
   Encryption By Password = 'randompasswordhere_sh78yjk2nl34kfdscv9zp34md'
   With Subject = 'Permission To Alter Authorization On Database',
   Expiry_Date ='2299-01-01'
Create Login ciadmin From Certificate Login_ciadmin

Alter Server Role sysadmin ADD MEMBER ciadmin;

Create Server Role Role_ci
Alter Server Role Role_ci Add Member ci
Go
;
Create Schema ci
Go
;
Use Master
Create User ci from Login ci
Revoke Execute on Schema::ci From Public;
Grant Execute On Schema::ci to ci
Go
;
Create Or Alter Procedure Ci.CreateDatabaseWithOwner
    @dbname nvarchar(128),
    @dbowner nvarchar(128),
    @appLogin nvarchar(128),
    @appLoginPassword nvarchar(128),
    @appReadonlyLogin nvarchar(128),
    @@appReadonlyLoginPassword nvarchar(128)
As
Begin
    Declare @isCiLogin bit= (Select IS_SRVROLEMEMBER('Role_ci', SYSTEM_USER) |
                                    IS_SRVROLEMEMBER('sysadmin', SYSTEM_USER))
    If ISNULL(@isCiLogin,0)=0
    Begin
      Declare @msg nvarchar(128) = 'Current_User is not in Server Role Role_ci'
      ; Throw 50000, @msg, 1 ;
    End
    Else
    Begin
      Declare @CreateDb nvarchar(max)
      Declare @CreateDbUsers nvarchar(max)
      Set @dbname=QuoteName(@dbname)
      Set @Dbowner=QuoteName(@Dbowner)
      Set @appLogin=QuoteName(@appLogin)
      Set @appReadonlyLogin=QuoteName(@appReadonlyLogin)
      Set @appLoginPassword=REPLACE(@appLoginPassword, '''', '''''')
      Set @@appReadonlyLoginPassword=REPLACE(@@appReadonlyLoginPassword, '''', '''''')

      Set @CreateDb = FormatMessage('
          Begin Try Create Login %s With Password = ''''; Alter Login %s Disable; End Try Begin Catch Print Error_Message() End Catch
          Begin Try Create Database %s; End Try Begin Catch Print Error_Message() End Catch
          Alter Authorization On Database::%s TO %s;
          Begin Try Create Login %s With Password= ''%s'', Default_Database= %s End Try Begin Catch Print Error_Message() End Catch
          Begin Try Create Login %s With Password= ''%s'', Default_Database= %s End Try Begin Catch Print Error_Message() End Catch
          ',
            @Dbowner, @Dbowner,
            @Dbname,
            @Dbname, @Dbowner,
            @appLogin, @appLoginPassword, @Dbname,
            @appReadonlyLogin,@@appReadonlyLoginPassword, @Dbname)

      Set @Createdbusers=FORMATMESSAGE('
          Use %s
          Begin Try
            Create User %s for Login %s
              Alter Role db_datareader Add Member %s
              Alter Role db_datawriter Add Member %s
          End Try Begin Catch Print Error_Message() End Catch
          Begin Try
            Create User %s for Login %s
              Alter Role db_datareader Add Member %s
          End Try Begin Catch Print Error_Message() End Catch
          Begin Try
            Create User %s for Login %s
              Alter Role db_owner Add Member %s
          End Try Begin Catch Print Error_Message() End Catch',
          @Dbname,
            @appLogin,@appLogin,
              @appLogin,
              @appLogin,
            @appReadonlyLogin, @appReadonlyLogin,
              @appReadonlyLogin,
            SYSTEM_USER, SYSTEM_USER,
              SYSTEM_USER)

      Print @Createdb
      Execute sp_executesql @CreateDb

      Print @Createdbusers
      Execute sp_executesql @CreateDbUsers
    End
End;
Go
;
Add Signature To Ci.CreateDatabaseWithOwner
  By Certificate Login_Ciadmin
  With Password = 'randompasswordhere_sh78yjk2nl34kfdscv9zp34md';
Go
;
Create Or Alter Procedure Ci.DropDatabaseWithOwner
    @dbname nvarchar(128),
    @dbowner nvarchar(128),
    @appLogin nvarchar(128),
    @appReadonlyLogin nvarchar(128)
As
Begin
    Set @dbname=QuoteName(@dbname)
    Set @Dbowner=QuoteName(@Dbowner)
    Set @appLogin=QuoteName(@appLogin)
    Set @appReadonlyLogin=QuoteName(@appReadonlyLogin)

    Declare @msg Nvarchar(max)
    Declare @isCiLogin bit= (Select IS_SRVROLEMEMBER('Role_ci', SYSTEM_USER) |
                                    IS_SRVROLEMEMBER('sysadmin', SYSTEM_USER))
    Declare @tableCount int

    Begin Try
      If EXISTS(Select * from sysdatabases where QUOTENAME(Name)=@Dbname)
      Begin
        Declare @checkTables Nvarchar(max)=
          FORMATMESSAGE('Select @rows=Count(*) from %s.Information_Schema.Tables',@Dbname)
        Execute sp_executesql @checkTables, N'@rows int Output', @rows=@tableCount Output
      End
    End Try
    Begin Catch
        Throw
--       Set @msg= FORMATMESSAGE('Error attempting to check tables in %s',@Dbname)
--       ; Throw 50000, @msg, 1 ;
    End Catch

    If ISNULL(@isCiLogin,0)=0
    Begin
      Set @msg = 'Current_User is not in Server Role Role_ci'
      ; Throw 50000, @msg, 1 ;
    End
    Else If @tableCount>0
    Begin
      Set @msg = FORMATMESSAGE('Won''t drop database %s because tables have been created.
      First confirm no data will be lost, then drop the tables. Then you can Drop the database.',
        @Dbname)
      ; Throw 50000, @msg, 1 ;
    End
    Else
    Begin
      Declare @dropDb nvarchar(max)

      Set @dropDb = FormatMessage('
          Begin Try Drop Login %s End Try Begin Catch Print ERROR_MESSAGE() End Catch
          Begin Try Drop Login %s End Try Begin Catch Print ERROR_MESSAGE() End Catch
          Begin Try Drop Database %s End Try Begin Catch Print ERROR_MESSAGE() End Catch
          Begin Try Drop Login %s End Try Begin Catch Print ERROR_MESSAGE() End Catch',
            @appReadonlyLogin,
            @appLogin,
            @Dbname,
            @Dbowner)

      Print @dropDb
      Execute sp_executesql @dropDb
    End
End;
Go
;
Add Signature To Ci.DropDatabaseWithOwner
  By Certificate Login_Ciadmin
  With Password = 'randompasswordhere_sh78yjk2nl34kfdscv9zp34md';
Go
;
--
-- Up ------------------------------------------------------
--

-- Run this bit as the CI login. NO you can't test it with Execute as Login=ci
  use Tempdb

  Execute Master.Ci.CreateDatabaseWithOwner
    'AppName',
    'AppName_DbOwner',
    'AppName',
    '…strongpasswordhere…',
    'AppName_ReadOnly',
    '…strongpasswordhere…'

-- Check ------------------------------------------------------
Use Appname
Select Db_Name() DbName, CURRENT_USER CurrentUser, SESSION_USER, SYSTEM_USER, ORIGINAL_LOGIN()
Select Name from sys.Sysdatabases
Select Name,Dbname,Language,Dbcreator from sys.Syslogins where loginname not like '##%##' and loginname not like 'NT %\%'
Select * from sys.database_principals where name not like '##%##'
Select role.name as database_role, users.name as database_user
  from sys.database_role_members j
  Right join sys.database_principals role on (j.role_principal_id = role.principal_id)
  Right join sys.database_principals users on (j.member_principal_id = users.principal_id)
;
Execute as Login='ci';
  use [appname]
  Create Table A(id int)
  use master
Revert ; Print FORMATMESSAGE('Reverted to %s %s', CURRENT_USER, SYSTEM_USER)
;
Execute as Login='appname';
  use [appname]
  select current_user, session_user, original_login()
  Select * from information_schema.tables
  Insert Into A (id) Values (1)
  Select * from A
  use master
Revert ; Print FORMATMESSAGE('Reverted to %s %s', CURRENT_USER, SYSTEM_USER)
;
Execute as Login='appname_readonly';
  use [appname]
  select current_user, session_user, original_login()
  Select * from information_schema.tables
  Begin Try Insert Into A (id) Values (1) End Try Begin Catch Print ERROR_MESSAGE() End Catch
  Select * from A
  use master
Revert ; Print FORMATMESSAGE('Reverted to %s %s', CURRENT_USER, SYSTEM_USER)
-- DOWN ------------------------------------------------------
;
Use Appname
Drop Table A
;
Execute Master.Ci.DropDatabaseWithOwner
  @dbname = 'AppName',
  @dbowner = 'AppName_DbOwner',
  @appLogin = 'AppName',
  @appReadonlyLogin = 'AppName_Readonly'


-- Delete Bootstrapping ------------------------------------------------------
Drop Procedure ci.CreateDatabaseWithOwner
Drop Procedure ci.DropDatabaseWithOwner
Drop schema ci
Drop user ci
Alter Server Role Role_ci Drop Member ci
Drop Server Role Role_ci
Drop Login ciadmin
Drop Certificate Login_ciadmin
--
Drop Login ci
Select * from Sys.Certificates
Select * from Sys.Sysusers