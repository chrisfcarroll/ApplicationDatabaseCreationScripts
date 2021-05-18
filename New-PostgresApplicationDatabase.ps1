#! /usr/bin/env pwsh

<#
  .SYNOPSIS
  Create a Postgres application database and roles for owner, application, and application_readonly
  
   .DESCRIPTION
  Create a Postgres application database and create roles for owner, application, and application_readonly.
  
  - the owner role has no login. the user that runs this script will be assigned to that role
  - the application and application_readonly roles will be login roles with password either specified by you
    or generated by this script. 
  - If the passwords are generated by this script, they will be printed as the first 
    2 lines of output of this script. 
  - If the script scram_postgres_password.py exists in the path, the passwords will be scram encrypted.

  - Optionally install common extensions UUID, plv8 and trigram
  - Optionally create functions for view and drop database connections
   
  .LINK
  https://gist.github.com/chrisfcarroll/ed3f8c368ad6bdbbe8a71d4c3afa48f7
  
  .LINK
  For Scram encryption (requires python3): https://gist.github.com/chrisfcarroll/4c819af67ec5485ed0d6aef7863562a4
#>
Param(
  ##A name for the new database
  [string][ValidatePattern('(".+"|[^"]+)')]$databaseName="appname",
  ##The postgres Host you wish to target
  [string][Alias('H')]$postgresHost="localhost",
  ##The postgres username to login with to run this script. Defaults to the OS username running this script.
  [string][Alias('U')]$adminUser=[Environment]::UserName,
  ##The name of the Role to create to own the new database
  [string]$databaseOwner,
  ##The name of the Role to Create having read & write access to the new database
  [string]$appAccount,
  ##The password to use for -appAccount. If not is given, one will be generated and displayed as the
  ##first line of output of this script.
  [string]$appAccountPassword,
  ##The name of the Role to Create having read access to the new database
  [string]$readonlyAppAccount,
  ##The password to use for -appAccount. If not is given, one will be generated and displayed as the
  ##second or first line of output of this script.
  [string]$readonlyAppAccountPassword,
  ##The postgres template to use for the new database. The default is template1 but if you specify 
  ##-dbLocale or -dbEncoding then template0 must be used.
  [string]$template,
  ##An abbreviation for -template 'template0'
  ##If you specify -template0 but don't set -dbLocale or -dbEncoding then :
  ## • Locale will be auto-detected for localhost, but an exception will be thrown for a remote host
  ## • Encoding will be set to UTF-8
  [switch]$template0,
  ##If this parameter is set, then template will be set to 'template0'.
  ##Leave this blank (defaults to UTF-8) for simple worldwide compatibility.
  [string]$encoding,
  ##If this parameter is set, then template will be set to 'template0'. The Locale you choose
  ## must be supported by the Operating System that the postgres instance is running on.
  [string]$locale,
  ##If set the extension uuid-ossp will be added, to add uuid functions to the database
  [bool]$addUUID=$true,
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
  [switch]$helpAvailableLocales,
  ## Delete the Database and the associated Roles
  [switch][Alias("Down")]$deleteDatabaseAndRoles
)

function runOrDryRun($command, $db, [switch]$onErrorStop){
  if($dryRun){ "-d $db :`n$command" }
  else{
    $r= ($command | psql -v ON_ERROR_STOP=$(if($onErrorStop){'ON'}else{'OFF'}) -X --echo-all `
          --host=$postgresHost -d $db -U $adminUser)
    return $? ? $r : $?
  }
}
function help{ Get-Help $PSCommandPath ; Get-Help $PSCommandPath -Parameter '*' }
if($help){help; Exit}
function helpAvailableLocales{ [CultureInfo]::GetCultures( [CultureTypes]::AllCultures ) }
if($helpAvailableLocales){helpAvailableLocales; Exit}

function isQuoted([string]$str){return $str -like '"*"'}
function quote([string]$str){return ((isQuoted $str) ? $str : '"'+$str+'"') }
function unQuote([string]$str){return ((isQuoted $str) ? $str.Substring(1,$str.Length-2) : $str) }
function isValidPostgressIdentifier([string]$str){return ($str -cmatch '^[_\p{Ll}][_\p{Ll}\p{Mn}\d]*$') -or ($str -like '"*"') }
function qadd([string]$left,[string]$right,$quotemark='"'){
  $isQl=(isQuoted $left)
  $isQr=(isQuoted $right)
  $l= $isQl ? $left.Substring(1,$left.Length-2)   : $left
  $r= $isQr ? $right.Substring(1,$right.Length-2) : $right
  $a= ($isQl -or $isQr) ? (quote ($l + $r) ) : ($l + $r)
  return $a
}

function sanitiseAndAutocompleteParameters{
  if(-not (isValidPostgressIdentifier $databaseName)){
    $script:databaseName= $databaseName.ToLower()
    if(isValidPostgressIdentifier $databaseName){
      if(-not $deleteDatabaseAndRoles){ Write-Warning "Your database name will be lowercased." }
    }else{
      throw "$databaseName is not a valid postgres database name. Either surround it in `"Double Quotes`" or" + 
            "change it to lowercase letters and numbers with no punctuation."
    }
  }
  $script:databaseOwner= [string]::IsNullOrWhiteSpace( $databaseOwner ) ? (qadd $databaseName "_owner") : $databaseOwner.ToLower()
  $script:appAccount= [string]::IsNullOrWhiteSpace( $appAccount ) ? $databaseName : $appAccount.ToLower()
  $script:readonlyAppAccount= [string]::IsNullOrWhiteSpace( $readonlyAppAccount ) ? (qadd $databaseName "_readonly") : $readonlyAppAccount.ToLower()
}
function validateUpParametersElseForceDryRun{

  $requireds= '$postgresHost','$databaseName','$databaseOwner','$appAccount','$readonlyAppAccount','$adminUser'
  $invalid= $requireds.Where( {-not (Invoke-Expression $_)})
  if($invalid.Count){
    $script:dryRun=$true
    write-warning "dry running because you missed a parameter: $invalid"
  }

  $identifiers= '$databaseName','$databaseOwner','$appAccount','$readonlyAppAccount'
  $invalid= $identifiers.Where( {-not (isValidPostgressIdentifier (Invoke-Expression $_))})
  if($invalid.Count){
    $script:dryRun=$true
    write-warning "dry running because some parameters are not valid postgress identifiers: $invalid"
    write-warning "NB to supply a quoted string in powershell,bash,etc you must quote the quotes, e.g.:  `'`"Quoted Name!`"`' "
  }
}
function validateDownParametersElseForceDryRun{
  $requireds= ('$postgresHost','$databaseName','$databaseOwner','$appAccount','$readonlyAppAccount')
  $invalids= $requireds | Where-Object { -not (Invoke-Expression $_) }

  if($invalid.Count){
    $dryRun=$true
    write-warning "dry running because you missed a parameter: $([string]::Join(", ", $invalids))"
  }
}
sanitiseAndAutocompleteParameters
if($deleteDatabaseAndRoles){validateDownParametersElseForceDryRun}else{validateUpParametersElseForceDryRun}

function New-Password([int]$length=12){ 
  1..($length * 3) |
          ForEach-Object{ Get-Random -Minimum 48 -Maximum 122 } |
          Where-Object { $_ -lt 58 -or $_ -gt 64 } | Where-Object {$_ -lt 91 -or $_ -gt 96 } |
          ForEach-Object{ [Char]$_ } | Select-Object -first $length | 
          ForEach-Object {$agg=""} {$agg += $_} {$agg} 
}

function defaultLocaleForLocalhost{
  $lc= if($IsWindows){ 
    (Get-UICulture).Name
  }else{
     $(locale | grep LC_COLLATE | sed 's/LC_COLLATE=\"//' | sed 's/\"//') 
  }
  return $lc
}
function defaultEncodingUTF8{return 'UTF-8'}

function deduceTemplateLocaleEncodingElseThrow{
  if($template0){$script:template='template0'}

  if(($encoding -or $locale) -and -not $template)
  {
    $script:didAutoSetTemplate0=$true
    $script:template='template0'
  }

  $result=switch($template)
  {
    'template0'
    {
      $locale= $locale ? $locale : (defaultLocaleForLocalhost)
      $encoding= $encoding ? $encoding : (defaultEncodingUTF8)
      $script:didAutodetectLocale= $locale -and -not $script:dbLocale
      "TEMPLATE = template0 Encoding=`'$encoding`' Locale= `'$locale`'"
    }
    {[string]::IsNullOrWhiteSpace($_)}
                                      {""}
    default {"TEMPLATE= $template"}
  }
  return $result
}

function Up{

  if(-not $appAccountPassword){
    $appAccountPassword= New-Password 20
    $appAccountPassword
    $didGeneratePassword=$true
  }
  if(-not $readonlyAppAccountPassword){
    $readonlyAppAccountPassword= New-Password 20
    $readonlyAppAccountPassword
    $didGeneratePassword=$true
  }

  if(get-command scram_postgres_password.py -ErrorAction SilentlyContinue){
    $canScramEncrypt=$true
    $appAccountPassword= scram_postgres_password.py $appAccount $appAccountPassword
    $readonlyAppAccountPassword=scram_postgres_password.py $readonlyAppAccount $readonlyAppAccountPassword
  }
  elseif (Get-Command md5)
  {
    $appAccountPassword= "md5" + $(md5 ($appAccountPassword + $appAccount))
    $readonlyAppAccountPassword = "md5" + $(md5 ($readonlyAppAccountPassword + $readonlyAppAccount))
  }

  if($didGeneratePassword)
  {
    write-warning "-----------------------------------------------------
You did not provide passwords, so passwords were created and shown above this line."
  }
  
  $templateAndLocaleSettings=deduceTemplateLocaleEncodingElseThrow
  if($didAutoSetTemplate0){"Setting template=template0 because you specified Locale or Encoding"}
  if($didAutodetectLocale){"Detected localhost locale as $locale."}
  if($didAutodetectLocale -and -not ($postgresHost -match "^(localhost|127.0.0.\d+|::1?)$")){
    throw "When connecting to a remote server, you must specify the locale. It can only be auto-detected on localhost."
  }

  "
-----------------------------------------------------
  Will log in to Host=$postgresHost as User=$adminUser to create:
  
    Database= $databaseName 
    with
    database Owner=$databaseOwner $templateAndLocaleSettings
    application Login=$appAccount
    application readonly login=$readonlyAppAccount
    add UUID extension: $addUUID
    add Trigram extension: $addTrigram
    add plv8 extension: $addPlv8
    Create Functions for View and Drop Connections: $addFunctionsForPSAndDropConnections
    Passwords generate by: $(if($didGeneratePassword){"This script"}else{"You"})
    $(if($canScramEncrypt){"Passwords will be stored as scram-hashes"})
  "

  "
-----------------------------------------------------

starting ...
"
  runOrDryRun @"
    Create Role $databaseOwner CreateDb CreateRole ;
    Grant $databaseOwner to current_user ;
    CREATE DATABASE $databaseName With Owner $databaseOwner $templateAndLocaleSettings;
    Alter Database $databaseName set client_encoding='UTF8' ;
    Create Role $appAccount Login Password `'$appAccountPassword`' ;
    Create Role $readonlyAppAccount Login Password `'$readonlyAppAccountPassword`' ;
    Grant Connect , Temporary on Database $databaseName TO $appAccount ;
    Grant Connect , Temporary on Database $databaseName TO $readonlyAppAccount ;
    Grant $readonlyAppAccount to $appAccount;
    Grant $appAccount to $databaseOwner;
    Revoke Connect On Database $databaseName From Public;
"@  'postgres'
  
  
  if($addFunctionsForPSAndDropConnections)
  {
    "    Adding functions ps() and DropConnections() ..."
    
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
"@ $databaseName
  }
  
  if($addUUID){
    "    Adding extension uuid-ossp to database $databaseName ..."
    runOrDryRun 'Create Extension If Not Exists "uuid-ossp" ;' $databaseName
  }
  
  if($addTrigram){
    "    Adding extension pg_trgm to database $databaseName ..."
    runOrDryRun 'Create Extension If Not Exists "pg_trgm" ;' $databaseName
  }
  
  if($addPlv8){
    "    Adding extension plv8 to database $databaseName ..."
    runOrDryRun 'Create Extension If Not Exists "plv8" ;' $databaseName
    
      if(-not $?){
        write-warning "Create Extension plv8 failed. Trying to first install to db=postgres"
        runOrDryRun 'Create Extension If Not Exists "plv8" ;' 'postgres'
        runOrDryRun 'Create Extension If Not Exists "plv8" ;' $databaseName
    
        if(-not $? -and (Test-Path $PSScriptRoot/install-postgres-plv8-extension.ps1)){
          write-warning "Create Extension plv8 failed. Trying to install plv8 to your postgres instance"
          start -verb runas powershell "$PSScriptRoot/install-postgres-plv8-extension.ps1"
          write-error "rerun this script after the server has restarted."
          exit 1
        }
      }
  }
}

function Down{

  "-----------------------------------------------------
  Will log in to Host=$postgresHost as User=$adminUser to Drop Database and Roles:
    
      database Owner=$databaseOwner
      Application Login=$appAccount
      Application Readonly Login=$readonlyAppAccount

  -----------------------------------------------------

  starting ...
"
$dbExists= (psql -l | select-string "^\s$(unQuote $databaseName)\s+\|\s+") -and $true
$tablesExist= $dbExists -and -not (runOrDryRun @"
    Do `$`$
    Begin
    If Exists (select * from information_schema.tables 
            where table_schema not in ('pg_catalog','information_schema')) Then
        Raise Exception 'Tables Exist' ;
    End If;
    End `$`$     
"@ $databaseName 'ON')

  if ($dbExists -and $tablesExist)
  {
    write-warning "Aborted Drop Database $databaseName and Roles because tables have been created. First Drop the Tables."
  }
  else
  {
    runOrDryRun @"
      Revoke all On Database $databaseName from $appAccount ;
      Revoke all On Database $databaseName from $readonlyAppAccount ;
      Alter Database $databaseName Owner to $adminUser ; 
      Drop role $appAccount ;
      Drop role $readonlyAppAccount ;
      Drop role $databaseOwner ;
      Drop Database $databaseName;    
"@ 'postgres'
  }
}

if($deleteDatabaseAndRoles){Down}else{Up}