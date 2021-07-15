#! /usr/bin/env pwsh

<#
  .SYNOPSIS
  Drop and re-Create postgres database template1 (the default template for Create Database) to have 
  your preferred Locale settings for Encoding, LC_Collate and LC_CType. 

  .Description
  Drop and re-Create postgres database template1 (the default template for Create Database) to have 
  your preferred Locale settings for Encoding, LC_Collate and LC_CType. 
  
  Discover your current OS login's locale with "Get-UICulture" on Windows or "locale" on unix/macOS.
  
  Discover what locales a machine supports using "locale --all" on unix/macOS or on Windows with
  "using namespace System.Globalization; [CultureInfo]::GetCultures( [CultureTypes]::AllCultures )".
  For a remote host, you can't do that, unless you can login to that host.

  Additionally, this script allows you to add common extensions to the template. See the parameter 
  help for -addUUID, -addPlv8, -addTrigram, -addFunctionsForPSAndDropConnections for more.

  If you enjoy simplicity, don't touch encoding, leave it at UTF-8.

#>

using namespace System.Globalization
Param(
  ##the Locale you choose must be supported by the Operating System that the postgres instance is running on.
  [string]$dbLocale,
  ##The postgres Host you wish to target
  [string][Alias('H')]$postgresHost,
  ##The postgres username to login with and to set as the owner of the recreated template1.
  ##Defaults to postgres
  [string][Alias('U')]$user='postgres',
  ##The encoding to set. Leave this at UTF-8 for simple worldwide compatibility
  [string]$dbEncoding='UTF-8',
  ##If set the extension uuid-ossp will be added, to add uuid functions to the database
  [switch]$addUUID,
  ##If set, Functions called ps and DropConnections will be create to view and drop database connections
  [switch]$addFunctionsForPSAndDropConnections,
  ##If set the extension plv8 will be added, for javascript stored function support.
  [switch]$addPlv8,
  ##If set the extension trgm will be added, for trigram and text-search support.
  [switch]$addTrigram,
  ##If set, the SQL scripts will be echoed but not run
  [switch]$dryRun,
  ##Shows help and returns
  [switch]$help,
  ##Show available locales on this machine, and returns
  [switch]$helpAvailableLocales
)

# -----------------------------------------
function help{ Get-Help $PSCommandPath }
if($help){help; Exit}

function helpAvailableLocales{ [CultureInfo]::GetCultures( [CultureTypes]::AllCultures ) }
if($helpAvailableLocales){helpAvailableLocales; Exit}

function validateParametersElseForceDryRun{
    $invalid= ('$postgresHost','$dbLocale','$dbEncoding','$user').Where(
        {-not $ExecutionContext.InvokeCommand.ExpandString($_)})
    if($invalid.Count){
      $script:dryRun=$true
      write-warning "dry running because you missed a parameter: $invalid"
    }
}
validateParametersElseForceDryRun


function defaultLocaleForLocalhost{
  $lc= if($IsWindows){ 
    (Get-UICulture).Name
  }else{
     $(locale | grep LC_COLLATE | sed 's/LC_COLLATE=\"//' | sed 's/\"//') 
  }
  return $lc
}
if(-not $dbLocale)
{
  $dbLocale=defaultLocaleForLocalhost
  "Detected localhost locale as $dbLocale."
  if($postgresHost -ne 'localhost' -and $postgresHost -ne '127.0.0.1'){
    write-warning "When connecting to a remote server, you must specify the locale. It can only be auto-detected on localhost."
    Exit
  }
}

# -----------------------------------------

function runOrDryRun($command, $db, [switch]$onErrorStop){
  if($dryRun){ "-d $db :\n$command" }
  else{
    $command | psql -v ON_ERROR_STOP=$(if($onErrorStop){1}else{0}) -X --echo-all `
          --host=$postgresHost -d $db -U $user
    return $?
  }
}


"
-----------------------------------------------------
  Will log in to Host=$postgresHost as user=$user to Drop then Create template Database template1:
  
    with
    Encoding=$dbEncoding
    Locale and Collation=$dbLocale
    add UUID extension: $addUUID
    add Trigram extension: $addTrigram
    add plv8 extension: $addPlv8
    Create Functions for View and Drop Connections: $addFunctionsForPSAndDropConnections
-----------------------------------------------------

starting ...
"

runOrDryRun @"
    ALTER database template1 is_template=false;
    DROP database template1;
    CREATE DATABASE template1
    WITH 
       ENCODING = '$dbEncoding'
       LC_COLLATE = '$dbLocale'
       LC_CTYPE = '$dbLocale'
       CONNECTION LIMIT = -1
       TEMPLATE template0;
    ALTER database template1 is_template=true;
"@  'postgres'


if($addFunctionsForPSAndDropConnections)
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
      'Create Extension If Not Exists "plv8" ;' | psql --host=$postgresHost -d postgres -U $user -X --echo-all
      'Create Extension If Not Exists "plv8" ;' | psql --host=$postgresHost -d lb -U $user -X --echo-all
  
      if(-not $?){
        write-warning "Create Extension plv8 failed. Trying to install plv8 to your postgres instance"
        start -verb runas powershell "$PSScriptRoot/install-postgres-plv8-extension.ps1"
        write-error "rerun this script after the server has restarted."
        exit 1
      }
    }
}
