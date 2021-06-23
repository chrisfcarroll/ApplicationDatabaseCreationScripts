#! /usr/bin/env pwsh # nb you still have to chmod this file to run from a unix shell
Param(
  [string]$installerName="Installer",
  [Parameter(Mandatory=$true)][string]$installerPassword,
  [Parameter(Mandatory=$true)][ValidateScript(
    {try{[System.Net.Mail.MailAddress]$_;return $true;}catch{return $false}})]
  [string]$installerEmail,
  [string]$dbServer=$env:SQLCMDSERVER,
  [string]$dbDatabaseName="Umbraco",
  [string]$applicationDbUserId="Umbraco",
  [Parameter(Mandatory=$true)][string]$applicationDbPassword,
  [string]$csprojName="Umbraco9",
  [string]$csprojOutputDir,
  [string]$connectionString,
  [int]$connectionTimeoutSecs=3
  )

function validateParametersElseThrow{

  if(-not $connectionString){
    $requireds= ('$dbServer','$dbDatabaseName','$applicationDbUserId','$applicationDbPassword')
    $invalids= $requireds | Where-Object { -not (Invoke-Expression $_) }
    if($invalid.Count){throw "You missed a parameter: $([string]::Join(", ", $invalids))"}
    $script:connectionString= `
      "Server=$dbServer;database=$dbDatabaseName;user id=$applicationDbUserId;password=$applicationDbPassword;Connection Timeout=$connectionTimeoutSecs"
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
  
