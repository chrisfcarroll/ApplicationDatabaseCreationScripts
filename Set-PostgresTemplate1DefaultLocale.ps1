#! /usr/bin/env pwsh

<#
  .SYNOPSIS
  Update Postgres template1 —the default template database— to your preferred Locale settings.

#>

Param(
  $dbLocale,
  $postgresHost="localhost",
  [string]$adminUser=[Environment]::UserName,
  $dbEncoding='UTF-8',
  [switch]$createViewAndDropConnectionFunctions,
  [switch]$addPlv8,
  [switch]$addTrigram,
  [switch]$addUUID,
  [switch]$dryRun
)

function defaultLocaleForLocalhost{
  $nixenUK='en_GB'
  $windowsenUK="English_United Kingdom"
  $nixenUS="en_US"
  $windowsenUS="English_United States"
  $lc= if($IsWindows){$windowsenUK}else{$nixenUK}
  return $lc
}
if(-not $dbLocale){$dbLocale= defaultLocaleForLocalhost}

function runOrDryRun($command, $db, [switch]$onErrorStop){
  if($dryRun){ "-d $db :  $command" }
  else{
    $command | psql -v ON_ERROR_STOP=$(if($onErrorStop){1}else{0}) -X --echo-all `
          --host=$postgresHost -d $db -U $superuser
    return $?
  }
}
function validateParametersElseForceDryRun{
    $invalid= ('$postgresHost','$dbLocale','$dbEncoding','$adminUser').Where(
        {-not $ExecutionContext.InvokeCommand.ExpandString($_)})
    if($invalid.Count){
      $script:dryRun.IsPresent=$true
      write-warning "dry running because you missed a parameter: $invalid"
    }
}
validateParametersElseForceDryRun

"
-----------------------------------------------------
  Will log in to Host=$postgresHost as user=$adminUser to Drop then Create Template Database Template1:
  
    with
    Encoding=$dbEncoding
    Locale and Collation=$dbLocale
    add UUID extension: $addUUID
    add Trigram extension: $addTrigram
    add plv8 extension: $addPlv8
    Create Functions for View and Drop Connections: $createViewAndDropConnectionFunctions
-----------------------------------------------------

starting ...
"

runOrDryRun @"
    ALTER database template1 is_template=false;
    DROP database template1;
    CREATE DATABASE template1
    WITH OWNER = postgres
       ENCODING = '$dbEncoding'
       TABLESPACE = pg_default
       LC_COLLATE = '$dbLocale'
       LC_CTYPE = '$dbLocale'
       CONNECTION LIMIT = -1
       TEMPLATE template0;
    ALTER database template1 is_template=true;
"@  'postgres'


if($createViewAndDropConnectionFunctions)
{
  "    Adding View and Drop Connections Functions to database template1 ..."
  
  runOrDryRun @"
Create or Replace Function ps() 
  Returns Table (pid int, datname name, usename name, application_name text, client_addr inet) 
  Language SQL 
  As 'Select a.pid, a.datname, a.usename, a.application_name, a.client_addr from pg_stat_activity a' ;

Create or Replace Function DropConnections(id int, database name)
  Returns Void
  Language PlpgSQL
  As `$`$
  Begin
    If (id is null and database is null ) Then Raise 'At least one of id or database must be not-null' ; End If;
    Perform pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE ( pg_stat_activity.datname = database Or database is null)
      AND ( pid = id or id is null);
  End `$`$;
"@ 'template1'
}

if($addUUID){
  "    Adding extension uuid-ossp to database template1 ..."
  runOrDryRun 'Create Extension If Not Exists "uuid-ossp" ;' 'template1'
}

if($addTrigram){
  "    Adding extension pg_trgm to database template1 ..."
  runOrDryRun 'Create Extension If Not Exists "pg_trgm" ;' 'template1'
}

if($addPlv8){
  "    Adding extension plv8 to database template1 ..."
  runOrDryRun 'Create Extension If Not Exists "plv8" ;' 'template1'
  
    if(-not $?){
      write-warning "Create Extension plv8 failed. Trying to first install to db=postgres"
      'Create Extension If Not Exists "plv8" ;' | psql --host=$postgresHost -d postgres -U $adminUser -X --echo-all
      'Create Extension If Not Exists "plv8" ;' | psql --host=$postgresHost -d lb -U $adminUser -X --echo-all
  
      if(-not $?){
        write-warning "Create Extension plv8 failed. Trying to install plv8 to your postgres instance"
        start -verb runas powershell "$PSScriptRoot/install-postgres-plv8-extension.ps1"
        write-error "rerun this script after the server has restarted."
        exit 1
      }
    }
}
