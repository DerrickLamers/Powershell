﻿<# 
.SYNOPSIS
Report upon and optionally delete old Exchange 2013 logs and temporary files.

.DESCRIPTION
Report upon and optionally delete old Exchange 2013 logs and temporary files.

.PARAMETER CreateScheduledTask
Use the current parameters and create a scheduled task from the current script. This defaults to the DeleteOldLogs scenario
and only passes the DaysToKeep and ServerFilter parameters.

.PARAMETER DaysToKeep
The number of days of log files to report upon or keep when deleting.

.PARAMETER ServerFilter
If you want to target specific servers pass an appliciable filter.

.PARAMETER FileTypes
If you want to target specific types of files send an array of file types (ie. '*.log','*.blg','*.bak'). Use '*' with
DaysToKeep at 0 in order to force the reporting to use psremoting and return only overall folder sizes as quickly as possible. 

.PARAMETER Scenario
Choose one of 4 precreated scenarios:

.PARAMETER IISLogsOnly
Only target IIS logs.

RetrieveValidFolders – Gather a list of valid Exchange logging and temp folders. Does not calculate sizes.
ReportOldLogSize - Gather a list of valid Exchange logging and temp folders and also enumerate their total 
                   size as well as the size of all the old logs that exist before the specified number of days. 
                   This includes message tracking logs.
DeleteOldLogs – Attempt to delete all logs which are older than the number of days specified. This does NOT include 
                message tracking logs.
DeleteOldLogsTestRun – Same as DeleteOldLogs but without actually deleting anything (adds –WhatIf to all Remove-Item 
                       commands). This does NOT include message tracking logs.

.EXAMPLE
$oldlogs = .\Manage-ExchangeDirectories.ps1 -DaysToKeep 14 -Scenario:ReportOldLogSize -Verbose
$oldlogs | ft -auto

Description
-----------
Get a size report for all servers of logs that are older than 14 days on all servers.

.EXAMPLE
$logdirsize = .\Manage-ExchangeDirectories.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -Verbose
$oldlogs | ft -auto

Description
-----------
Get a size report for all servers of just the directories containing the logs. Using DaysToKeep of zero and FileTypes of
'*' ensures that remoting is used for all calculations thus speeding up results.

.EXAMPLE
$ExchangeFolders = .\Manage-ExchangeDirectories.ps1 -Scenario:RetrieveValidFolders -DaysToKeep 14 -Verbose
$ExchangeFolders | select Server,Path | ft -auto

Description
-----------
Get a general report of all the exchange servers and log paths.

.EXAMPLE
.\Manage-ExchangeDirectories.ps1 -Scenario:DeleteOldLogsTestRun -DaysToKeep 14 -Verbose

Description
-----------
Perform a test run of removal of all .log and .blg files over 14 days old in all directories found on all exchange 2010/2013 servers.

.EXAMPLE
.\Manage-ExchangeDirectories.ps1 -Scenario:DeleteOldLogs -DaysToKeep 14 -Verbose

Description
-----------
Remove all .log and .blg files over 14 days old in all directories found on all exchange 2010/2013 servers.

.EXAMPLE
$logdirsize = .\Manage-ExchangeDirectories.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -ServerFilter 'EXCH2' -Verbose
.\Manage-ExchangeDirectories.ps1 -Scenario:DeleteOldLogs -DaysToKeep 14 -ServerFilter 'EXCH2' -Verbose -FileTypes '*.log','*.blg','*.bak'
$newlogdirsize = .\Manage-ExchangeDirectories.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -ServerFilter 'EXCH2' -Verbose
$logdirsize | %{ $logdir = $_; $newlogdir = $newlogdirsize | where {$_.Description -eq $logdir.description}; New-Object psobject -Property @{'Log' = $logdir.Description;'OldSize' = $logdir.TotalSize;'NewSize' = $newlogdir.Totalsize}}|Select log,Oldsize,Newsize | ft -auto

Description
-----------
For the EXCH2 server perform the following actions:
1. Get a list of directories which can be cleaned, and force the function to only use psremoting to get the total directory size
2. Remove all .log,.blg, and .bak files over 14 days old in all applicable directories found on the server.
3. Get an updated directory size listing using psremoting
4. Display all log types with their prior and new directory size.

.EXAMPLE
.\Manage-ExchangeDirectories.ps1 -Scenario:DeleteOldLogs -DaysToKeep 5 -CreateScheduledTask

Description
-----------
Creates a scheduled task on the current server to run this script every night at 3am and delete logs older than 5 days on all Exchange servers.

.NOTES
- You need to enable psremoting on every server you want to process (use Enable-PSremoting and NOT 'winrm quickconfig' for the best results)
- This script might take some time to run in a larger environment. The processing time is usually when psremoting with FSO cannot be used to 
reliably get folder size (and thus it resorts to slow as hell powershell enumeration of files instead).
- You need to run this directly on an exchange server to do the initial exchange server enumeration unfortunately.
- Run with the -verbose flag to see all the stuff that is going on while waiting :)

Author: Zachary Loeber

Version History:
    1.3 - 10/02/2015
        - Added check for null result on local (fso) based folder size results and use local enumeration of files if needed.
        - Some small fixes for Exchange 2010.
        - Added IISLogsOnly flag.
    1.2 - 12/09/2014
        - Added ability to self-schedule a task to run the script nightly.
    1.1 - 11/17/2014
        - Included some parameters for using remote pssessions in case this will be scheduled to be run from a non-exchange system
    1.0 - 09/27/2014
        - Initial Release

.LINK
www.the-little-things.net

.LINK
https://github.com/zloeber/Powershell/blob/master/Exchange/Manage-ExchangeDirectories.ps1
#> 

param(
    [parameter(Mandatory=$true, HelpMessage='Number of days for old log files.')]
    [int]$DaysToKeep = 14,
    [Parameter(HelpMessage='Select one or more specific Exchange Servers')]
    [string]$ServerFilter = '*',
    [Parameter(HelpMessage='Default file types to clean up or report upon. Usually leave this alone.')]
    [string[]]$FileTypes = @('*.log','*.blg'),
    [Parameter(Mandatory=$true, HelpMessage='Scenario to run.')]
    [ValidateSet('RetrieveValidFolders',
                 'ReportOldLogSize',
                 'DeleteOldLogs',
                 'DeleteOldLogsTestRun')]
    [string]$Scenario,
    [Parameter(HelpMessage='Alternate psremoting port to use.')]
    [int]$port,
    [Parameter(HelpMessage='supply an alternate remote pssession to Exchange.')]
    [System.Management.Automation.Runspaces.PSSession]$RemoteExchangeSession = [System.Management.Automation.Runspaces.PSSession]::$null,
    [Parameter(HelpMessage='supply an alternate server to attempt creation of pssession to Exchange.')]
    [string]$RemoteExchangeSessionServer = $env:COMPUTERNAME,
    [Parameter(HelpMessage='Create a scheduled task for logfile removal with the current parameters.')]
    [switch]$CreateScheduledTask,
    [Parameter(HelpMessage='Only target IIS logs.')]
    [switch]$IISLogsOnly
)

function Get-ScriptName { 
    if($hostinvocation -ne $null) {
        $hostinvocation.MyCommand.path
    }
    else {
        $script:MyInvocation.MyCommand.Path
    }
}

function New-ScheduledPowershellTask {
    <#
    .SYNOPSIS

    .DESCRIPTION

    .PARAMETER 

    .PARAMETER 

    .LINK
    http://www.the-little-things.net
    .LINK
    https://github.com/zloeber/Powershell/
    .NOTES
    Last edit   :   
    Version     :   
    Author      :   Zachary Loeber

    .EXAMPLE


    Description
    -----------
    TBD
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Position=0, HelpMessage='Task Name. If not set a random GUID will be used for the task name.')]
        [string]$TaskName,
        [Parameter(Position=1, HelpMessage='Task Description.')]
        [string]$TaskDescription,
        [Parameter(Position=2, HelpMessage='Task Script.')]
        [string]$TaskScript,
        [Parameter(Position=3, HelpMessage='Task Script Arguments.')]
        [string]$TaskScriptArgs,
        [Parameter(Position=4, HelpMessage='Task Start Time (defaults to 3AM tonight).')]
        [datetime]$TaskStartTime = "$(Get-Date "$(((Get-Date).AddDays(1)).ToShortDateString()) 3:00 AM")"
    )
    begin {
        # The Task Action command
        $TaskCommand = "c:\windows\system32\WindowsPowerShell\v1.0\powershell.exe"

        # The Task Action command argument
        $TaskArg = "-WindowStyle Hidden -NonInteractive -Executionpolicy unrestricted -command `"& `'$TaskScript`' $TaskScriptArgs`""
 
    }
    process {}
    end {
        try {
            # attach the Task Scheduler com object
            $service = new-object -ComObject("Schedule.Service")
            # connect to the local machine. 
            # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381833(v=vs.85).aspx
            $service.Connect()
            $rootFolder = $service.GetFolder("\")
             
            $TaskDefinition = $service.NewTask(0) 
            $TaskDefinition.RegistrationInfo.Description = "$TaskDescription"
            $TaskDefinition.Settings.Enabled = $true
            $TaskDefinition.Settings.AllowDemandStart = $true
             
            $triggers = $TaskDefinition.Triggers
            #http://msdn.microsoft.com/en-us/library/windows/desktop/aa383915(v=vs.85).aspx
            $trigger = $triggers.Create(2) # Creates a daily trigger
            $trigger.StartBoundary = $TaskStartTime.ToString("yyyy-MM-dd'T'HH:mm:ss")
            $trigger.Enabled = $true
             
            # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381841(v=vs.85).aspx
            $Action = $TaskDefinition.Actions.Create(0)
            $action.Path = "$TaskCommand"
            $action.Arguments = "$TaskArg"
             
            #http://msdn.microsoft.com/en-us/library/windows/desktop/aa381365(v=vs.85).aspx
            $rootFolder.RegisterTaskDefinition("$TaskName",$TaskDefinition,6,"System",$null,5) | Out-Null
        }
        catch {
            throw
        }
    }
}

function Get-FolderSize {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage='Directory path')]
        [string]$path,
        [Parameter(HelpMessage='Only include data older than this number of days in calculation. Ignored if set to zero.')]
        [int]$days = 0,
        [Parameter(HelpMessage='Only include files matching this criteria.')]
        [string[]]$criteria = '*',
        [string]$ComputerName,
        [switch]$UseRemoting,
        [int]$port,
        [System.Management.Automation.Runspaces.PSSession]$Session = $null

    )
    $InvokeSplat = @{}

    $LocalPath = $false
    if ($path -like '*:*')
    {
        $LocalPath = $true
    }
    elseif ($path -like '\\*')
    {
        if ($path -match '\\\\(.*?)\\')
        {
            $ComputerName = $Matches[1]
        }
        else
        {
            throw 'Get-FolderSize: Invalid Path!'
        }

        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } 
            catch {}
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
        if ($LocalHost -contains $ComputerName)
        {
            $LocalPath = $true
        }
    }
    
    if (Test-Path $path)
    {
        if (($LocalPath -or $UseRemoting) -and (($days -eq 0) -and ($criteria -eq '*')))
        {   # using fso (faster)
            # convert to local pathname first
            $path = $path -replace '\$',':' -replace '(^\\\\.*?\\)',''
            if ($UseRemoting)
            {
                if ($Session -ne $null)
                {
                    $InvokeSplat.Session = $Session
                }
                else
                {
                    $InvokeSplat.ComputerName = $ComputerName
                    if ($port -ne 0)
                    {
                        $InvokeSplat.Port = $port
                    }
                }
                Write-Verbose "$($MyInvocation.MyCommand): Using remoting with FileSystemObject on $ComputerName to enumerate $path..."
                $RemoteCMDString = "`$objFSO = New-Object -com  Scripting.FileSystemObject; `$objFSO.GetFolder(`'$path`').Size"
                $RemoteCMD = [scriptblock]::Create($RemoteCMDString)
                return $(Invoke-Command @InvokeSplat -ScriptBlock $RemoteCMD)
            }
            else
            {
                Write-Verbose "Get-FolderSize: Using FileSystemObject on localhost to enumerate $path..."
                $objFSO = New-Object -com  Scripting.FileSystemObject
                if (($objFSO.GetFolder($path).Size) -ne $null) {
                    return $objFSO.GetFolder($path).Size
                }
                else {
                    # pure powershell (slower)
                    Write-Verbose "Get-FolderSize: Using powershell to enumerate $path instead as FSO returned null..."
                    $LastWrite = (Get-Date).AddDays(-$days)
                    $colItems = (Get-ChildItem -Recurse $path -Include $criteria -ErrorAction:SilentlyContinue | 
                                    Where {$_.LastWriteTime -le "$LastWrite"} | 
                                        Measure-Object -property length -sum)
                    return $colItems.sum
                }
            }
        }
        else
        {
            # pure powershell (slower)
            Write-Verbose "Get-FolderSize: Using powershell to enumerate $path..."
            $LastWrite = (Get-Date).AddDays(-$days)
            $colItems = (Get-ChildItem -Recurse $path -Include $criteria -ErrorAction:SilentlyContinue | 
                            Where {$_.LastWriteTime -le "$LastWrite"} | 
                                Measure-Object -property length -sum)
            return $colItems.sum
        }
    }
    else
    {
        Write-Warning "$($MyInvocation.MyCommand): Invalid Path!"
    }
}

filter ConvertTo-KMG {
    $bytecount = $_
    switch ([math]::truncate([math]::log($bytecount,1024))) 
    {
          0 {"$bytecount Bytes"}
          1 {"{0:n2} KB" -f ($bytecount / 1kb)}
          2 {"{0:n2} MB" -f ($bytecount / 1mb)}
          3 {"{0:n2} GB" -f ($bytecount / 1gb)}
          4 {"{0:n2} TB" -f ($bytecount / 1tb)}
    default {"{0:n2} KB" -f ($bytecount / 1kb)}
    }
}
            
function Delete-LogFiles {
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage='Server to clean.')]
        [string]$server = 'localhost',
        [Parameter(Mandatory=$true, HelpMessage='Path to clean.')]
        [string]$path,
        [Parameter(HelpMessage='Days to keep.')]
        [int]$days = 14,
        [Parameter(Mandatory=$true, HelpMessage='Path to clean.')]
        [string[]]$FileTypes = @('*.log','*.blg'),
        [Parameter(HelpMessage='Delete empty directories as well.')]
        [switch]$DeleteDirectories,
        [Parameter(HelpMessage='Perform a test run, do not delete anything.')]
        [switch]$testrun
    )
    # Build full UNC path
    $path = $path -replace ':','$'
    $TargetServerFolder = "\\" + $server + "\" + $path
    
    Write-Verbose "$($MyInvocation.MyCommand): Attempting to clean logs located in $TargetServerFolder"
    # Only try to delete files, if folder exists
    if (Test-Path $TargetServerFolder)
    {
        $LastWrite = (Get-Date).AddDays(-$days)

        # Select files to delete
        $Files = Get-ChildItem $TargetServerFolder -Include $FileTypes -Recurse | Where {$_.LastWriteTime -le "$LastWrite"}

        $FileCount = 0
        $DirectoryCount = 0
        $Whatif = @{}
        
        if ($testrun)
        {
            $Whatif.whatif = $true
        }
        # Delete the files
        $Files | Foreach {
            try {
                Remove-Item $_ -Force -Confirm:$false -ErrorAction:Stop @Whatif
                $fileCount++
            }
            catch {}
        }
        Write-Verbose "$($MyInvocation.MyCommand): $fileCount of $($Files.Count) deleted in $TargetServerFolder"
        
        # Delete empty directories (BE CAREFULL WITH THIS!)
        if ($DeleteDirectories) {
            $Directories = Get-ChildItem $TargetServerFolder -Directory -Recurse | Where {$_.LastWriteTime -le "$LastWrite"}
            foreach($Directory in $Directories) {
                if ((Test-Path $Directory.Fullname)) {
                    if ((get-childitem $Directory.Fullname -Recurse -File).Count -eq 0) {
                        Remove-Item $Directory.Fullname -Confirm:$false -ErrorAction:Stop -Force @Whatif
                        $DirectoryCount++
                    }
                }
            }
            Write-Verbose "$($MyInvocation.MyCommand): $DirectoryCount of $($Directories.Count) deleted in $TargetServerFolder"
        }
    }
    else
    {
        # oops, folder does not exist or is not accessible
        Write-Warning "$($MyInvocation.MyCommand): The folder $TargetServerFolder doesn't exist or is not accessible."
    }
}

function Get-OldExchangeLogFileInfo {
    [CmdletBinding()]
    param(
        [parameter(HelpMessage='Number of days for log files retention. Used to determine overall size of files which can be removed.')]
        [int]$DaysToKeep = 14,
        [Parameter(HelpMessage='Default file types to clean up or report upon. Usually leave this alone.')]
        [string[]]$FileTypes = @('*.log','*.blg'),
        [Parameter(HelpMessage='Speeds up operations if just looking for valid paths to clean up.')]
        [switch]$SkipSizeCalculation,
        [Parameter(HelpMessage='By default we ignore message tracking logs. Set this flag to include them.')]
        [switch]$IncludeMessageTrackingLogs,
        [Parameter(HelpMessage='Select one or more specific Exchange Servers')]
        [string]$ServerFilter = '*',
        [int]$port,
        [Parameter(HelpMessage='Only target IIS logs.')]
        [switch]$IISLogsOnly
    )
    begin {
        # Get a list of all Exchange 2013 servers. If unable to do so then go no further
        try {
            $ExchangeServers = @(Get-ExchangeServer | Where {(($_.AdminDisplayVersion -like '*14*') -or ($_.IsE15OrLater)) -and ($_.Name -like $ServerFilter)})
            $ExchangeServers = $ExchangeServers | Select Name,@{'n'='Version';'e'={if ($_.IsE15OrLater){'2013'} else {'2010'}}}
        }
        catch {
            throw
        }
        $AffectedPaths = @()
        $Verbosity=@{}
        if ($PSBoundParameters['Verbose'] -eq $true) {
            $Verbosity.Verbose = $true
        }

        # scripts for remote session execution
        $IisLogPathScript = [scriptblock]::Create('Import-Module WebAdministration; (Get-WebConfigurationProperty "system.applicationHost/sites/siteDefaults" -Name logFile).directory | Foreach {$_ -replace "%SystemDrive%", $env:SystemDrive}')
        $ExchangeInstallPathScript = [scriptblock]::Create('$env:ExchangeInstallPath')
        
        # Note: It is extremely likely that the logging paths are the same as the database paths so I skip over them
        #       by commenting the entries out. Uncomment them at your own discretion (It just may mean increased processing)
        $TransportPaths = @('QueueDatabasePath',
                        #'QueueDatabaseLoggingPath',
                        'IPFilterDatabasePath',
                        #'IPFilterDatabaseLoggingPath',
                        'TemporaryStoragePath')

        $MiscLogTypes = @{
            'ConnectivityLogEnabled' = 'ConnectivityLogPath'
            'IrmLogEnabled' = 'IrmLogPath'
            'HttpProtocolLogEnabled' = 'HttpProtocolLogPath'
            'TransportSyncLogEnabled' = 'TransportSyncLogPath'
            'TransportSyncHubHealthLogEnabled' = 'TransportSyncHubHealthLogPath'
            'AgentLogEnabled' = 'AgentLogPath'
            'FlowControlLogEnabled' = 'FlowControlLogPath'
            'ResourceLogEnabled' = 'ResourceLogPath'
            'DnsLogEnabled' = 'DnsLogPath'
        }
        if ($IncludeMessageTrackingLogs) {
            $MiscLogTypes.MessageTrackingLogEnabled = 'MessageTrackingLogPath'
        }

        function Get-ExchangeFolderInformation {
          [CmdletBinding()]
            param (
                [string]$Server,
                [string]$Path,
                [string]$Description,
                [int]$Days = 14,
                [string[]]$FileTypes = @('*.log','*.blg'),
                [switch]$SkipSizeCalculation,
                [System.Management.Automation.Runspaces.PSSession]$Session
            )
            $Verbosity=@{}
            if ($PSBoundParameters['Verbose'] -eq $true) 
            {
                $Verbosity.Verbose = $true
            }
            $UNC = '\\' + $Server + '\' + ($Path -replace ':','$')
            if (Test-Path $UNC)
            {
                $TotalSize = 0
                $OldSize = 0
                if (-not $SkipSizeCalculation)
                {
                    Write-Verbose "$($MyInvocation.MyCommand): Calculating Disk Utilization: $Description - Total Files Size..."
                    $TotalSize = Get-FolderSize -Path $UNC -UseRemoting @Verbosity
                    Write-Verbose "$($MyInvocation.MyCommand): Calculating Disk Utilization: $Description - Old Files Size..."
                    $OldSize = Get-FolderSize -Path $UNC -Days $Days -Criteria $FileTypes -UseRemoting @Verbosity
                }
                New-Object PSObject -Property @{
                    'Server' = $Server
                    'Path' = $Path
                    'UNC' = $UNC
                    'Description' = $Description
                    'TotalSize' = $TotalSize
                    'OldDataSize' = $OldSize
                }
            }
        }
    }
    process {}
    end {
        foreach ($ExchangeServer in $ExchangeServers) {
            Write-Verbose "$($MyInvocation.MyCommand): Proccessing server $($ExchangeServer.Name)"
            try {
                $pssessionsplat = @{}
                if ($port -ne 0) {
                    $pssessionsplat.port = $port
                }
                $RemoteSession = New-PSSession -ComputerName $ExchangeServer.Name @pssessionsplat -ErrorAction:Stop
                $RemoteSessionConnected = $true
            }
            catch {
                $RemoteSessionConnected = $false
                Write-Warning "$($MyInvocation.MyCommand): Unable to establish psremoting session with $($ExchangeServer.Name)"
            }
            if ($RemoteSessionConnected -eq $true) {
                $GetFolderInfoSplat = @{
                        'Server' = $ExchangeServer.Name
                        'Path' = ''
                        'Days' = $DaysToKeep
                        'Description' = ''
                        'FileTypes' = $Filetypes
                        'SkipSizeCalculation' = $SkipSizeCalculation
                        'Session' = $RemoteSession
                }
                
                Write-Verbose "$($MyInvocation.MyCommand): Processing Server - $($ExchangeServer.Name)"
                
                try {
                    Write-Verbose "Get-OldExchangeLogFileInfo: Remotely determining IIS log file location...."
                    $IisLogPath = Invoke-Command -ScriptBlock $IisLogPathScript -Session $RemoteSession
                }
                catch {
                    $IisLogPath = ''
                    Write-Verbose "Get-OldExchangeLogFileInfo: IIS log path not found on $($ExchangeServer.Name). Please ensure that WinRM is enabled."
                }
                if ($IisLogPath -ne '') {
                    $GetFolderInfoSplat.Path = $IisLogPath
                    $GetFolderInfoSplat.Description = 'IIS Logs'
                    $FolderResults = Get-ExchangeFolderInformation @GetFolderInfoSplat @Verbosity
                    if ($FolderResults -ne $null) {$AffectedPaths += $FolderResults}
                }
                $ExchInstallPath = $null
                if (-not $IISLogsOnly) {
                    $ExchInstallPath = Invoke-Command -ScriptBlock $ExchangeInstallPathScript -Session $RemoteSession
                }
                if ($ExchInstallPath -ne $null) {
                    # First get all the current transport file locations
                    # We can only truly determine where these are via a local config file (unfortunately)
                    $xmlpath = '\\' + "$($ExchangeServer.Name)\$($ExchInstallPath)Bin\EdgeTransport.exe.config" -replace ':','$'
                    try {
                        $xmldata = Get-Content -Path $xmlpath
                        $xml = New-Object -TypeName XML
                        $xml.LoadXml($xmldata)
                        foreach ($TransportPath in $TransportPaths) {
                            $GetFolderInfoSplat.Path = ($xml.configuration.appSettings.add | Where {$_.key -eq $TransportPath}).value
                            $GetFolderInfoSplat.Description = $TransportPath -replace 'Path',''
                            $FolderResults = Get-ExchangeFolderInformation @GetFolderInfoSplat @Verbosity
                            if ($FolderResults -ne $null) {$AffectedPaths += $FolderResults}
                        }
                    }
                    catch {}
                    
                    # Generic exchange logging path
                    $GetFolderInfoSplat.Path = $ExchInstallPath + 'Logging'
                    $GetFolderInfoSplat.Description = "Exchange System Logging"
                    $FolderResults = Get-ExchangeFolderInformation @GetFolderInfoSplat @Verbosity
                    if ($FolderResults -ne $null) {
                        $AffectedPaths += $FolderResults
                    }

                    # Other protocol logs
                    if ($ExchangeServer.Version -eq '2010') {
                        $transportlogs = Get-TransportServer $ExchangeServer.Name | select *log*
                    }
                    else {
                        $transportlogs = Get-TransportService $ExchangeServer.Name | select *log*
                    }
                    $MiscLogTypes.Keys | Foreach {
                        if (($transportlogs.$_) -and ($transportlogs."$($MiscLogTypes[$_])" -ne $null)) {
                            $LogName = $_ -replace 'LogEnabled',''
                            $GetFolderInfoSplat.Path = $transportlogs."$($MiscLogTypes[$_])"
                            $GetFolderInfoSplat.Description = "Transport Logs ($LogName)"
                            $FolderResults = Get-ExchangeFolderInformation @GetFolderInfoSplat @Verbosity
                            if ($FolderResults -ne $null) {$AffectedPaths += $FolderResults}
                        }
                    }
                }
                If ($RemoteSession.ID -ne $null) {
                    Remove-PSSession $RemoteSession
                }
            }
        }
        return $AffectedPaths
    }
}

function Delete-OldExchangeLogs {
    [CmdletBinding()]
    param(
        [parameter(Position=0,HelpMessage='Number of days for log files retention. Used to determine overall size of files which can be removed.')]
        [int]$DaysToKeep = 14,
        [Parameter(HelpMessage='Select one or more specific Exchange Servers')]
        [string]$ServerFilter = '*',
        [string[]]$FileTypes = @('*.log','*.blg'),
        [switch]$testrun,
        [Parameter(HelpMessage='By default we ignore message tracking logs. Set this flag to include them.')]
        [switch]$IncludeMessageTrackingLogs,
        [Parameter(HelpMessage='Only target IIS logs.')]
        [switch]$IISLogsOnly
    )
    $Testrunsplat = @{}
    $IISLogsOnlySplat = @{}
    if ($IISLogsOnly) {
        $IISLogsOnlySplat.IISLogsOnly = $true
    }
    if ($testrun) {
        $Testrunsplat.testrun = $true
    }
    $Verbositysplat = @{}
    if ($PSBoundParameters['Verbose'] -eq $true) {
        $Verbositysplat.Verbose = $true
    }
    $MessageTrackingSplat = @{}
    if ($IncludeMessageTrackingLogs) {
        $MessageTrackingSplat.IncludeMessageTrackingLogs = $true
    }
    
    $oldlogs = @(Get-OldExchangeLogFileInfo -SkipSizeCalculation -ServerFilter $ServerFilter @Verbositysplat @MessageTrackingSplat @IISLogsOnlySplat)
    $oldlogs | Foreach {
        Delete-LogFiles -server $_.Server -path $_.Path -days $DaysToKeep -FileTypes $FileTypes @testrunsplat @Verbositysplat
    }
}

if ($CreateScheduledTask) {
    $ScriptName = Get-ScriptName
    $TaskScriptArgs = "-DaysToKeep:$($DaysToKeep) -ServerFilter:$($ServerFilter) -Scenario:DeleteOldLogs"
    New-ScheduledPowershellTask -TaskName 'Clean Exchange Logs' -TaskDescription 'Clean old exchange logs' -TaskScript $ScriptName -TaskScriptArgs $TaskScriptArgs
    Write-Output "Assuming there were no errors the scheduled task has been created on the localhost as `'Clean Exchange Logs`'"
    Write-Output "You still need to go into scheduled tasks and modify the task to run as an appropriate service account!"
    break
}

# ** Main **
$SessionConnected = $false

# if a session was passed to the script, use it first
if ($RemoteExchangeSession -ne [System.Management.Automation.Runspaces.PSSession]::$null) {
    try {
        Enter-PSSession -Session $RemoteExchangeSession
        $SessionConnected = $true
    }
    catch {
        Break
    }
}
# Next see if we already have a valid session available
$CurrentSessions = @(Get-PSSession | Where {($_.State -eq 'Opened') -and ($_.ConfigurationName -eq 'Microsoft.Exchange')})
if ($CurrentSessions.Count -ge 1) {
    $SessionConnected = $true
}
else {
    # Otherwise try to open a new session.
#    if (!(Get-PSSnapin | where {$_.Name -eq "Microsoft.Exchange.Management.PowerShell.E2010"})) {
#    	try	{
#    		Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction STOP
#    	}
#        catch {
#    		#Snapin was not loaded
#    		Write-Warning $_.Exception.Message
#    		EXIT
#    	}
#    	. $env:ExchangeInstallPath\bin\RemoteExchange.ps1
#    	Connect-ExchangeServer -auto -AllowClobber
#    }
    try {
        $RemoteEx2013Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$($RemoteExchangeSessionServer)/PowerShell/" -Authentication Kerberos
        Import-PSSession $RemoteEx2013Session
        $SessionConnected = $true
    }
    catch {
        Break
    }
}
#}

if ($SessionConnected) {
    $Verbositysplat = @{}
    if ($PSBoundParameters['Verbose'] -eq $true) {
        $Verbositysplat.Verbose = $true
    }

    $CustomPortSplat = @{}
    if ($port -ne 0) {
        $CustomPortSplat.Port = $port
    }

    $IISLogsOnlySplat = @{}
    if ($IISLogsOnly) {
        $IISLogsOnlySplat.IISLogsOnly = $true
    }
    
    switch ($Scenario) {
        'RetrieveValidFolders' {
            Get-OldExchangeLogFileInfo -SkipSizeCalculation -ServerFilter $ServerFilter @CustomPortSplat @Verbositysplat @IISLogsOnlySplat
        }

        'ReportOldLogSize' {
            # Generate a report of total directory size and how much the 'old' log data consumes
            Get-OldExchangeLogFileInfo -DaysToKeep $DaysToKeep -ServerFilter $ServerFilter @CustomPortSplat -IncludeMessageTrackingLogs -FileTypes $FileTypes @Verbositysplat @IISLogsOnlySplat| 
                Select-Object Server,Description,Path,@{n='UsedSize';e={$_.OldDataSize | Convertto-KMG}},@{n='TotalSize';e={$_.TotalSize | Convertto-KMG}}
        }

        'DeleteOldLogs' {
            Delete-OldExchangeLogs -DaysToKeep $DaysToKeep -ServerFilter $ServerFilter -FileType $FileTypes @Verbositysplat @IISLogsOnlySplat
        }

        'DeleteOldLogsTestRun' {
            Delete-OldExchangeLogs -DaysToKeep $DaysToKeep -ServerFilter $ServerFilter -FileType $FileTypes -testrun @Verbositysplat @IISLogsOnlySplat
        }
    }
}
else {
    Write-Error "$($MyInvocation.MyCommand): Not connected to or able to connect to any exchange servers"
}