<#
    .SYNOPSIS
    Monitors Windows services that are configured for automatic start with PRTG.

    .DESCRIPTION
    Using WinRM and WMI this script searches for Windows services configured for automatic start, that are not started. As there are
    some services, that are never running, but configured as auto-start by default, exceptions can be configured. These exceptions
    can be made within this script by changing the variable $ExcludeScript. This way, the change applies to all PRTG sensors
    based on this script. If exceptions have to be made on a per sensor level, the script parameter $ExcludePattern can be used.

    1. Run Script from PRTG (Requires Local Admin on Remote Computer)
    Copy this script to the PRTG probe EXE scripts folder (${env:ProgramFiles(x86)}\PRTG Network Monitor\Custom Sensors\EXEXML)
    and create a "EXE/Script Advanced" sensor. Choose this script from the dropdown and set at least:

    + Parameters: -ComputerName "%host"
    + Security Context: Use Windows credentials of parent device
    + Scanning Interval: 5 minutes

    2. Run Script in TaskScheduler from Remote Server (Requires no Remote Access from PRTG Server)
    Copy this script to the Remote Server. Example: C:\PRTG\PRTG-WinServices.ps1

    Create PRTG HTTP Push Data Advanced Sensor and Copy the Token (Token is available in the Sensor Settings after Creating the Sensor)
    - No Incoming Data -> Switch to down status after x minutes (set minimum the Repeat time *2 + 2min)

    Create Scheduled Task on Remote Server
    - Action\Programm: powershell.exe
    - Action\Arguments: -Command "& 'C:\PRTG\PRTG-WinServices.ps1' -ComputerName 'localhost' -HttpPush -HttpServer 'YourPRTGServer' -HttpPort '5050' -HttpToken 'YourHTTPPushToken'"
    - Trigger: Daily 06:00 AM, Repeat task every 5 or 15 min and duration = Indefinitely


    .PARAMETER ComputerName
    The hostname or IP address of the Windows machine to be checked. Should be set to %host in the PRTG parameter configuration.
    Use "localhost" when you run the Script with HTTP Push on a Remote Computer

    .PARAMETER UserName
    Provide the Windows user name to connect to the target host via WinRM. Better way than explicit credentials is to set the PRTG sensor
    to launch the script in the security context that uses the "Windows credentials of parent device".

    .PARAMETER Password
    Provide the Windows password for the user specified to connect to the target machine using WinRM. Better way than explicit credentials is to set the PRTG sensor
    to launch the script in the security context that uses the "Windows credentials of parent device".

    .PARAMETER ExcludePattern
    Regular expression to describe the INTERNAL name (not display name) of Windows services not to be monitored. Easiest way is to
    use a simple enumeration of service names.

      Example: ^(gpsvc|WinDefend|WbioSrvc)$

      Example2: ^(Test123.*|ServiceTest)$ excludes "ServiceTest" and every Service starting with "Test123"

    #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions?view=powershell-7.1

    .PARAMETER IncludePattern
    ExcludePattern just as Include

    .PARAMETER UseDisplayname
    this Parameter forces the Script to use the Displayname values instead of the read service name.
    be careful, you maybe also have to change the Includes/Excludes to match the Displaynames

    .PARAMETER CriticalServicePattern
    Regular expression to describe your Critical Services that has to be present on every device.
    -CriticalServicePattern '^(CsFalconService)$' -> filters for "CsFalconService" Services that are preset. CriticalService will be the number of matching services
    -CriticalServicePattern '^(CsFalconService)$ CriticalServiceMustRun' -> filters for "CsFalconService" Services that are preset and running. CriticalService will be the number of matching services

    .PARAMETER CriticalServiceMustRun
    CriticalServices must be present and state has to be running.
    combine with -CriticalServicePattern

    .PARAMETER CriticalServiceLimit
    default Limit for the Critical Service Count. Does only work one time for channel creation, after that manuel work
    For Example use -CriticalServicePattern '^(WinDefend|Bitdefender)$' -CriticalServiceLimit 2

    .PARAMETER HideTotalServiceCount
    Hides the "Total Services" channel

    .PARAMETER HideAutomaticNotRunning
    Hides the "Automatic Services not running" channel

    .PARAMETER ChannelPerService
    Creates one Channel per Service
    Should not be used with a lot of services, recommended to use with "IncludePattern".

    .PARAMETER HttpPush
    enables HTTP Push in the Sensor (requires HttpToken, HttpServer and HttpPort)

    .PARAMETER HttpToken
    Set your HTTP Push Sensor Token (Token is available in the Sensor Settings after creating the Sensor)

    .PARAMETER HttpServer
    Set the Target HTTP Push Server (YourPRTGServer FQDN)

    .PARAMETER HttpPort
    Use this parameter if you need to use a HTTP Push Port other than 5050

    .PARAMETER HttpPushUseSSL
    Use this parameter to set the HTTP Push to use HTTPS

    .EXAMPLE
    Sample call from PRTG EXE/Script Advanced
    PRTG-WinServices.ps1 -ComputerName %host -ExcludePattern '^(ERP-Service)$'

    Sample call from Task Scheduler on Remote Computer
    -Command "& 'D:\Powershell\PRTG-WinServices.ps1' -ComputerName 'localhost' -HttpPush -HttpServer 'YourPRTGServer' -HttpPort '5050' -HttpToken 'YourHTTPPushToken'"

    .NOTES
    Version:        1.02
    Author:         Jannos-443
    URL:            https://github.com/Jannos-443/PRTG-WinServices
    Creation Date:  22.01.2023
    Purpose/Change: Added ChannelPerService and HideAutomaticNotRunning parameter
    
    This script is based on (https://github.com/debold/PRTG-WindowsServices)    
#>
param(
    [string] $ComputerName = '',                #use "localhost" if you want to run the Script with HTTP Push on a Remote Server
    [string] $UserName = "",
    [string] $Password = "",
    [string] $IncludePattern = '',
    [string] $ExcludePattern = '',
    [Switch] $UseDisplayname,
    [string] $CriticalServicePattern = '',
    [switch] $CriticalServiceMustRun,
    [int] $CriticalServiceLimit = '1',
    [Switch] $HideTotalServiceCount,
    [Switch] $HideAutomaticNotRunning,
    [Switch] $ChannelPerService,                
    [switch] $HttpPush,                         #enables http push, usefull if you want to run the Script on the target Server to reduce remote Permissions
    [string] $HttpToken,                        #http push token
    [string] $HttpServer,                       #http push prtg server hostname
    [string] $HttpPort = "5050",                #http push port (default 5050)
    [switch] $HttpPushUseSSL                    #use https for http push
)
#Catch all unhandled Errors
trap {
    if ($session -ne $null) {
        Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
    }
    $Output = "line:$($_.InvocationInfo.ScriptLineNumber.ToString()) char:$($_.InvocationInfo.OffsetInLine.ToString()) --- message: $($_.Exception.Message.ToString()) --- line: $($_.InvocationInfo.Line.ToString()) "
    $Output = $Output.Replace("<", "")
    $Output = $Output.Replace(">", "")
    $Output = $Output.Replace("#", "")
    Write-Output "<prtg>"
    Write-Output "<error>1</error>"
    Write-Output "<text>$($Output)</text>"
    Write-Output "</prtg>"
    Exit
}

# Error if there's anything going on
$ErrorActionPreference = "Stop"

if ($ComputerName -eq "") {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>You must provide a computer name to connect to</text>"
    Write-Output "</prtg>"
    Exit
}

# Generate Credentials Object, if provided via parameter
try {
    if ($UserName -eq "" -or $Password -eq "") {
        $Credentials = $null
    }
    else {
        $SecPasswd = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credentials = New-Object System.Management.Automation.PSCredential ($UserName, $secpasswd)
    }
}
catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Error Parsing Credentials ($($_.Exception.Message))</text>"
    Write-Output "</prtg>"
    Exit
}

$WmiClass = "Win32_Service"

# Get list of Services.
try {
    if ($null -eq $Credentials) {
        if ($ComputerName -eq "localhost") {
            $Services = Get-CimInstance -Namespace "root\CIMV2" -ClassName $WmiClass
        }
        else {
            $Services = Get-CimInstance -Namespace "root\CIMV2" -ClassName $WmiClass -ComputerName $ComputerName
        }
    }

    else {
        $session = New-CimSession -ComputerName $ComputerName -Credential $Credentials
        $Services = Get-CimInstance -Namespace "root\CIMV2" -ClassName $WmiClass -CimSession $session
        Start-Sleep -Seconds 1
        Remove-CimSession -CimSession $session
    }

}
catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Error connecting to $ComputerName ($($_.Exception.Message))</text>"
    Write-Output "</prtg>"
    Exit
}

# Name = Displayname?
if ($UseDisplayname) {
    $AllServices = New-Object System.Collections.ArrayList
    foreach ($Service in $Services) {
        $ServiceObject = [PSCustomObject]@{
            Name      = $Service.Displayname
            StartMode = $Service.StartMode
            State     = $Service.State
        }
        $null = $AllServices.Add($ServiceObject)
    }
    $Services = $AllServices
}

# hardcoded exclude list that applies to all hosts
$ExcludeScript = '^(MapsBroker|sppsvc|MicrosoftSearchInBing|KDService|gpsvc|DoSvc|wuauserv|ShellHWDetection|MSExchangeNotificationsBroker|BITS|RemoteRegistry|WbioSrvc|TrustedInstaller|gupdate|edgeupdate|Tiledatamodelsvc||clr_optimization_.+|CDPSvc|CDPUserSvc_.+|OneSyncSvc_.+|AppReadiness)$'
$IncludeScript = ''

#Excludes
if ($ExcludePattern -ne "") {
    $Services = $Services | Where-Object { $_.Name -notmatch $ExcludePattern }
}

if ($ExcludeScript -ne "") {
    $Services = $Services | Where-Object { $_.Name -notmatch $ExcludeScript }
}

#Includes
if ($IncludePattern -ne "") {
    $Services = $Services | Where-Object { $_.Name -match $IncludePattern }
}

if ($IncludeScript -ne "") {
    $Services = $Services | Where-Object { $_.Name -match $IncludeScript }
}

$TotalCount = ($Services | Measure-Object).Count

$xmlOutput = '<prtg>'
$OutputText = ""

#Check for not running automatic starting Services
$NotRunning = $Services | Where-Object { ($_.StartMode -eq "Auto") -and ($_.State -ne "Running") }

$NotRunningCount = ($NotRunning | Measure-Object).Count

if ($NotRunningCount -gt 0) {
    $NotRunningTXT = "Automatic service(s) not running: "
    foreach ($NotRun in $NotRunning) {
        $NotRunningTXT += "$($NotRun.Name); "
    }
    $OutputText += "$($NotRunningTXT)"
}

else {
    $OutputText += "All automatic services are running. "
}

#region: ChannelPerService
if ($ChannelPerService){
    foreach($Service in $Services){
        $ServiceState = -1
        Switch ($Service.State)
        {
        "ContinuePending" {$ServiceState = 5}
        "Paused" {$ServiceState = 7}
        "PausePending" {$ServiceState = 6}
        "Running" {$ServiceState = 4}
        "StartPending" {$ServiceState = 2}
        "Stopped" {$ServiceState = 1}
        "StopPending" {$ServiceState = 3}
        }

        $xmlOutput += "<result>
        <channel>$($Service.Displayname)</channel>
        <value>$($ServiceState)</value>
        <ValueLookup>prtg.winservices.state</ValueLookup>
        </result>"
    }
}
#endregion


if (-not $HideAutomaticNotRunning) {
    $xmlOutput += "<result>
        <channel>Automatic Services not running</channel>
        <value>$($NotRunningCount)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>
        "
}

if (-not $HideTotalServiceCount) {
    $xmlOutput += "<result>
    <channel>Total Services</channel>
    <value>$($TotalCount)</value>
    <unit>Count</unit>
    </result>
    "
}

#region: Critical Services
if ($CriticalServicePattern -ne "") {
    if ($CriticalServiceMustRun) {
        $CriticalServices = $Services | Where-Object { ($_.Name -match $CriticalServicePattern) -and ($_.State -eq "Running") }
    }
    else {
        $CriticalServices = $Services | Where-Object { $_.Name -match $CriticalServicePattern }
    }

    $CriticalServicesCount = ($CriticalServices | Measure-Object).Count

    $CriticalServicesText = "Critical Services found: "
    if ($CriticalServicesCount -eq 0) {
        $CriticalServicesText += "None!"
    }
    else {
        foreach ($CriticalService in $CriticalServices) {
            $CriticalServicesText += "$($CriticalService.Name); "
        }
    }

    $xmlOutput += "<result>
        <channel>CriticalService</channel>
        <value>$($CriticalServicesCount)</value>
        <unit>Count</unit>"

    if ($CriticalServiceLimit -ne "") {
        $xmlOutput += "<limitmode>1</limitmode>
            <LimitMinError>$($CriticalServiceLimit)</LimitMinError>"
    }
    $xmlOutput += "</result>"
    $OutputText += " ### $($CriticalServicesText)"
}
#endregion

#Output Text
$OutputText = $OutputText.Replace("<", "")
$OutputText = $OutputText.Replace(">", "")
$OutputText = $OutputText.Replace("#", "")
$xmlOutput += "<text>$($OutputText)</text>"

$xmlOutput += "</prtg>"

#region: Http Push
if ($httppush) {
    if ($HttpPushUseSSL)
    { $httppushssl = "https" }
    else
    { $httppushssl = "http" }

    Add-Type -AssemblyName system.web

    $Answer = Invoke-Webrequest -method "POST" -URI ("$($httppushssl)://$($httpserver):$($httpport)/$($httptoken)?content=$(([System.Web.HttpUtility]::UrlEncode($xmloutput)))") -usebasicparsing

    if ($answer.Statuscode -ne 200) {
        Write-Output "<prtg>"
        Write-Output "<error>1</error>"
        Write-Output "<text>http push failed</text>"
        Write-Output "</prtg>"
        Exit
    }
}
#endregion

#finish Script - Write Output

Write-Output $xmlOutput