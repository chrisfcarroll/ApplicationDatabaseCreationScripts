#! /usr/bin/env pwsh # nb you still have to chmod this file to run from a unix shell

<#
  .SYNOPSIS
  Run an unattended install of Umbraco 9, specifying installer and database details, 
  creating both an AspNetCore web application and initialising the given database.
  
   .DESCRIPTION
  Run an unattended install of Umbraco 9, specifying installer and database details.

  - The databaseName to be used must already exist on the -dbServer
  - The applicationDbUserId must have access and DDL permissions in the database

  This script will create a new AspNetCore Umbraco9 web application using the currently
  installed dotnet new umbraco template.The web application will in turn initialise 
  the database.

  .LINK
  https://github.com/chrisfcarroll/ApplicationDatabases/WellKnownApplications
  https://our.umbraco.com/Documentation/Fundamentals/Setup/Install/Unattended-Install-v9

#>


Param(
  [string]$installerName="Installer",
  [Parameter(Mandatory=$true)][ValidateScript(
    {try{[System.Net.Mail.MailAddress]$_;return $true;}catch{return $false}})]
  [string]$installerEmail,
  [Parameter(Mandatory=$true)][string]$installerPassword,
  [string]$dbServer=$env:SQLCMDSERVER,
  [string]$databaseName="Umbraco",
  [string]$applicationDbUserId="Umbraco",
  [Parameter(Mandatory=$true)][string]$applicationDbPassword,
  [string]$csprojName="Umbraco9",
  [string]$csprojOutputDir,
  [string]$connectionString,
  [int]$connectionTimeoutSecs=3,

  ##Shows help, then stop.
  [switch]$help,

  ##Shows full help, then stop.
  [switch]$helpFull
  )

if(-not $installerName){ $help=$true }

if($helpFull){ Get-Help $PSCommandPath ; Get-Help $PSCommandPath -Parameter '*' ; Exit }
if($help){ Get-Help $PSCommandPath ; Exit}


function validateParametersElseThrow{

  if(-not $connectionString){
    $requireds= ('$dbServer','$databaseName','$applicationDbUserId','$applicationDbPassword')
    $invalids= $requireds | Where-Object { -not (Invoke-Expression $_) }
    if($invalid.Count){throw "You missed a parameter: $([string]::Join(", ", $invalids))"}
    $script:connectionString= `
      "Server=$dbServer;database=$databaseName;user id=$applicationDbUserId;password=$applicationDbPassword;Connection Timeout=$connectionTimeoutSecs"
  }
  $script:csprojOutputDir= $csprojOutputDir ? $csprojOutputDir :$csprojName
}

function TestDatabaseExistsElseThrow {
  try{
    $connectionString
    $dbName=($connectionString | Select-String -Pattern "(?<=;database=)[^;]+(?=;)" | %{ $_.Matches } | %{ $_.Value } | Select -First 1)
    $conn=[System.Data.SqlClient.SqlConnection]::new($connectionString)
    $gotDb1=$conn.Database
    $conn.Open()
    $cmd=$conn.CreateCommand()
    $cmd.CommandText="Select DB_Name()"
    $gotDb2=$cmd.ExecuteScalar()
    $cmd.Dispose()
    $conn.Dispose()
    "OK: Connected to Database $gotDb2"
  }
  catch{Write-Warning "Failed to connect to $connectionString." ; throw }
  finally{
    if($cmd){$cmd.Dispose()}
    if($conn){$conn.Dispose()}
  }
}

validateParametersElseThrow
TestDatabaseExistsElseThrow

Write-Warning "Please wait a minute. Then, after installation has finished, press Ctrl-C."

dotnet new umbraco --name $csprojName `
        --output $csprojOutputDir `
        --friendly-name $installerName `
        --email $installerEmail `
        --password $installerPassword `
        --connection-string $connectionString `
  && cd $csprojOutputDir && dotnet run
  
