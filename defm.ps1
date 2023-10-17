#! /usr/bin/env pwsh

<#
  .SYNOPSIS
  Abbreviations for "dotnet ef migrations <command> ..." and "dotnet ef database update ..."

  defm list [options]
  defm add <name> [options]
  defm remove [options]
  defm up
  defm up <name>
  
   .DESCRIPTION
   
  .LINK
  https://learn.microsoft.com/en-us/ef/core/cli/dotnet#aspnet-core-environment

#>

param(  [ValidateSet(
          'list',
          'add',
          'up',
          'down',
          'remove',
          'script-only',
          'help', '--help')]$command,
        [string]$name,        
        [switch][alias('force')]$offline,
        [switch]$noBuild,
        #DBContext, only ever needed if your project has more than one
        [string]$context,
        #The project to use. Defaults to the current working directory.
        [string]$project,
        #The startup project to use when looking for a context. Defaults to the 
        #current working directory.
        [string]$startupProject,
        #The connection string to the database. Defaults to the one specified in 
        #AddDbContext or OnConfiguring or in the startup Project
        [string]$connection,
        #When adding, also script
        [switch]$script,
        #When adding, also script and use --idempotent
        [switch]$scriptIdempotent,
        #When adding, also script and store script in this directory. 
        #Defaults to ./MigrationScripts. Don't use the same directory as the 
        #project's own Migrations directory.
        [string]$scriptDirectory = "./MigrationScripts",
        #Don't execute just show the command that would be run
        [switch]$dryRun,
        [switch]$help,
        #Don't echo the command to be run before running it
        [switch]$quiet )


$selfHelp = ('help', '--help' -eq $command) -or ($null -eq $command -and $help)
if($selfHelp){get-help $PSCommandPath}

$showHelp = ($name -eq "--help") -or $help

$cmdswitches= 
           ($offline -and ('up','down' -eq $command) ? "--force" : @() ) +
           ($noBuild ? "--no-build" : @()) +
           ($context -and -not ('list','script-only' -eq $command) ? @("--context","$context") : @()) +
           ($project ? "--project","$project" : @()) +
           ($showHelp ? "--help" : @())


$idempotent= $scriptIdempotent ? '--idempotent' : ''
if( ($script -or $scriptIdempotent) -and -not ('add','script-only' -eq $command) ){
  Write-Warning "You asked for script, but only the commands add and script-only are scripted"
}
if($noBuild -and ('add','remove' -eq $command)){
  Write-Warning "Using noBuild with add or remove can result in errors, and break the project build
  if you try to add a duplicate name. If necessary, manually remove errant migrations from the
  Migrations directory."
}


function go{ 
  if(-not $quiet){ Write-Output "$args" }
  if(-not $dryRun){ $cmd,$rest = $args  ; & $cmd @args } 
}

switch ($command)
{
  'add' {
    if(-not $name -and -not $help){
      throw "add requires a migrations name. Example: def add MyName"
    }    
    go dotnet ef migrations add $name @cmdswitches
    if($doScript){
      go dotnet ef migrations script $idempotent -o "$scriptDirectory/$name.sql"
    }
  }

  'remove' {
    go dotnet ef migrations remove @cmdswitches
  }
  'list' {
    go dotnet ef migrations list @cmdswitches
  }
  'up' {
    $argss = @( ,$name -ne $null) + $cmdswitches
    go dotnet ef database update @argss
  }
}
