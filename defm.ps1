#! /usr/bin/env pwsh

<#
  .SYNOPSIS
  Abbreviations for "dotnet ef migrations <command> ..." and "dotnet ef database update ..."

  defm list [options]
  defm add <name> [options]
  defm remove [options]
  defm up
  defm up <name>
  defm up <from> <to>
  defm script

  To see options for each command, use defm <command> -help
  
   .DESCRIPTION

   Note that dotnet ef migrations has no down command. Instead, use list to see migration
   names, and use up <name> to go down. You can always use up 0 to go down to initial database.
   
  .LINK
  https://learn.microsoft.com/en-us/ef/core/cli/dotnet#using-the-tools

#>

param(  [ValidateSet(
          'list',
          'add',
          'up',
          'down',
          'remove',
          'script',
          'help', '--help')]$command,
        [string]$name,        
        [switch][alias('force')]$offline,
        [switch][alias('no-build')]$noBuild,
        #DBContext, only ever needed if your project has more than one
        [string]$context,
        #The target project to which the commands will add or remove files. 
        #Defaults to the current directory.
        [string][alias('target')]$project,
        #The startup project is the one the tools will build and run when looking for
        # a context, a model, or a connectionstring. Defaults to the current directory
        #current working directory.
        [string]$startupProject,
        #The connection string to the database. Defaults to the one specified in 
        #AddDbContext or OnConfiguring or in the startup Project
        [string]$connection,
        #When adding, also script
        [switch]$script,
        #When adding, also script and use --idempotent
        [switch][alias('idempotent')][alias('script-idempotent')]$scriptIdempotent,
        #When adding, also script and store script in this directory. 
        #Defaults to ./MigrationScripts. Avoid using the same directory as the 
        #project's own /Migrations/ directory, because that be emptied 
        [string][alias('out-dir')]$scriptDirectory,
        #Don't execute just show the command that would be run
        [switch]$dryRun,
        [switch]$help,
        #Don't echo the command to be run before running it
        [switch]$quiet )


$selfHelp = ('help', '--help' -eq $command -or -not $command)

$showHelp = ($name -eq "--help") -or $help

$idempotent= $scriptIdempotent ? '--idempotent' : ''
$doScript = ($command -eq 'script') -or $script -or $scriptIdempotent -or $scriptDirectory
if( $doScript -and -not ('add','script' -eq $command) ){
  Write-Warning "You asked for script, but only the commands add and script-only are scripted"
}
if($doScript -and -not $name){
  Write-Information "To output to a file, specify both -scriptDirectory and -name"
  $scriptOut = $null
} else{
  $scriptOut = (($scriptDirectory) ? $scriptDirectory : "./MigrationScripts") + "/$name.sql"
}


$cmdswitches= 
           ($offline -and ('up','down' -eq $command) ? @("--force") : @() ) +
           ($noBuild ? @("--no-build") : @()) +
           ($context -and -not ('list','script' -eq $command) ? @("--context","$context") : @()) +
           ($project ? "--project","$project" : @()) +
           ($startupProject ? "--startup-project","$startupProject" : @()) +
           ($showHelp ? @("--help") : @()) +
           $args

$scriptSwitches=           
           ($scriptIdempotent ? @("--idempotent") : @()) +
           ($scriptOut ? "-o","$scriptOut" : @())

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
      go dotnet ef migrations script @($cmdswitches + $scriptSwitches)
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
 'script' {
    $rest = $cmdswitches + $scriptSwitches
    go dotnet ef migrations script @rest
  }
  default {
    get-help $PSCommandPath @args
  }
 }
