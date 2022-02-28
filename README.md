# PRTG-WinServices

## Project Owner:

Jannos-443

## Changelog 
### V1.0
- Monitor automatic Windows Services
- Use HTTP Push to avoid local Permission on critical Remote Servers (Backup etc.)

## HOW TO
### Option 1: Execute on Remote Server without PRTG needing local permissions on the Remote Server (HTTP Push Advanced)
1. Place Script on Remote Server (C:\PRTG\PRTG-WinServices.ps1)
2. Create PRTG "HTTP Push Advanced Sensor" and copy the Token (Token is available in the Sensor Settings after creating the Sensor)
   - you should set "no incoming data" to "switch to down status after x minutes"
3. Create Schueduled Task 

Example: 

`powershell.exe -Command "& 'C:\PRTG\PRTG-WinServices.ps1' -ComputerName 'localhost' -HttpPush -HttpServer 'YourPRTGServer' -HttpPort '5050' -HttpToken 'YourHTTPPushToken'"`

![task](media/task.png)


### Option 2: Execute on PRTG Server (EXE Advanced)
1. Place `PRTG-WinService.ps1` under `C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML`

3. Create new Sensor

   | Settings | Value |
   | --- | --- |
   | EXE/Script Advanced | PRTG-WinService.ps1 |
   | Scanning Interval | 10 min |

## Non Domain or IP

If you connect to **Computers by IP** or to **not Domain Clients** please read [Microsoft Docs](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_remote_troubleshooting?view=powershell-7.1#how-to-use-an-ip-address-in-a-remote-command)

you maybe have to add the target to the TrustedHosts on the PRTG Probe and use explicit credentials.

example (replace all currenty entries): 

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "ServerIP1,ServerIP2,ServerHostname1"

example want to and and not replace the list:
    
    $curValue = (Get-Item wsman:\localhost\Client\TrustedHosts).value
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$curValue,NewServer3.test.com"
    
exmaple PRTG parameter with explicit credentials:
    
    -ComputerName "%host" -Username "%windowsuser" -Password "%windowspassword" -Age 1


## Usage

```powershell
-ComputerName "%host" -ExcludePattern '^(Intel.*)$'
```
simple check automatic Services of Remote Computer

```powershell
-ComputerName "%host" -ExcludePattern '^(Intel.*)$'
```
check automatic Services and exclude every service starting with "Intel"

```powershell
-ComputerName "%host" -UserName "YourRemoteComputerUser" -Password "YourRemoteComputerPassword"
```
Use explicit credentials ("Windows credentials of parent device" is the better way)

```powershell
powershell.exe -Command "& 'C:\PRTG\PRTG-WinServices.ps1' -ComputerName 'localhost' -HttpPush -HttpServer 'YourPRTGServer' -HttpPort '5050' -HttpToken 'YourHTTPPushToken'"
```
HTTP Push from Remote Server

```powershell
powershell.exe -Command "& 'C:\PRTG\PRTG-WinServices.ps1' -ComputerName 'localhost' -HttpPush -HttpServer 'YourPRTGServer' -HttpPort '5050' -HttpToken 'YourHTTPPushToken' -ExcludePattern '^(Intel.*)$'"
```
HTTP Push from Remote Server and exclude every service starting with "Intel"



## Examples

![PRTG-WinService](media/ok.png)

![PRTG-WinService](media/error.png)

## Includes/Excludes

You can use the variables to exclude/include Services
The variables take a regular expression as input to provide maximum flexibility.

For more information about regular expressions in PowerShell, visit [Microsoft Docs](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions).

".+" is one or more charakters
".*" is zero or more charakters