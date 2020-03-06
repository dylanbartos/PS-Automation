#PC Deployment Script
#Dylan Bartos
#v2.0

Function Log {
    #Log -Value [string] [-Error | -Complete]
    #Writes parameter $value to host, file and prefixes optional [ERROR] or [COMPLETE]
    param (
        [parameter(Mandatory=$True,position=0)] [string] $Value,
        [Switch] $Error,
        [Switch] $Complete
    )
    If ($Error) {
        Write-Host "[ERROR] $Value"
        Add-Content $xml.LogPath "$(Get-Date) [ERROR] $Value"
    }ElseIf ($Complete){
        Write-Host "[COMPLETE] $Value"
        Add-content $xml.LogPath "$(Get-Date) [COMPLETE] $Value"
    }Else{
        Write-Host "$Value"
        Add-Content $xml.LogPath "$(Get-Date) $Value"
    }
}

Function LoadXML {
    try {
        [xml]$load = Get-Content "$PSSCriptRoot\Deploy-PC.config" -ErrorAction Stop
        $xml = $load.Functions
        return $xml
    }catch{
        Set-Content -Path "$PSScriptRoot\Deploy-PC.log" -Value "Unable to load Deploy-PC.config. Check that file exists."
    }
}

Function Main{
    #Error handling and cycle checks for Windows Updates
    If ($xml.WindowsUpdates.Enabled -eq "1"){
	If ($xml.WindowsUpdates.Cycles -eq "0"){
	    Log "WindowsUpdates.Cycles is 0, but Windows Updates is enabled. Exiting."
	    Exit
	}
        If (($xml.WindowsUpdates.Cycles -gt "1") -and ($xml.WindowsUpdates.AutoLogon -eq "0")){
            Log "WindowsUpdates.Cycles is > 1, but AutoLogon is not configured. Cycles will not execute as intended." -Error
            $check = Read-Host "Accept error and continue with script? (y/n)"
            If (($check -eq "n") -or ($check -eq "N")){
                Exit
            }
        }
       
        #Cycles down through Windows Updates cycles
        If ((Test-Path "$PSScriptRoot\WindowsUpdates.txt") -eq $True){
            $Cycle = Get-Content -Path "$PSScriptRoot\WindowsUpdates.txt"
            If ($Cycle -eq "1"){
                Remove-Item -Path "$PSScriptRoot\WindowsUpdates.txt" -Confirm:$false
                WindowsUpdates
                Restart-Computer -Force
                Exit 
            }Else{
                $Cycle = $Cycle - 1
                Log "Decrease Cycle from $($cycle + 1) to $cycle"
                Set-Content -Path "$PSScriptRoot\WindowsUpdates.txt" -Value "$Cycle"
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" "Deploy-PC" -Value "$PSScriptRoot\Deploy-PC.bat" -type String
                WindowsUpdates
		        Restart-Computer -Force
		        Exit
            }
        }

        #Starts Windows Updates cycles
        If (((Test-Path "$PSScriptRoot\WindowsUpdates.txt") -eq $False) -and ($xml.WindowsUpdates.Cycles -gt "1")){
            Log "Test-Path False"
            New-Item -Path "$PSScriptRoot\WindowsUpdates.txt" -ItemType File | Out-Null
            Set-Content -Path "$PSScriptRoot\WindowsUpdates.txt" -Value "$($xml.WindowsUpdates.Cycles - 1)"
        }

        #Auto Logon Error Handling
        If (($xml.WindowsUpdates.AutoLogon -eq "1") -and ($xml.WindowsUpdates.Cycles -gt "1")){
            If (($xml.WindowsUpdates.Username -eq "") -or ($xml.WindowsUpdates.Password -eq "")){
                Log "AutoLogon is enabled, but Username or Password have not been set." -Error
                Log "AutoLogon fatal error, script exiting." -Error
                Exit
            }
            AutoLogon
        }
    } 

    #Gathers credentials and passes to FileCopy
    If ($xml.FileCopy.Enabled -eq "1"){
        Write-Host "Please enter valid credentails for $($xml.FileCopy.UNCPath)"
        while (($null -eq $user) -or ($null -eq $pass)) {
            $user = Read-Host "Username"
            $pass = Read-Host "Password" -AsSecureString
        }
        $cred = New-Object System.Management.Automation.PSCredential ($user, $pass)
        FileCopy -Credential $cred
    }

    #Imports user list and passes to UserAccount
    If ($xml.UserAccount.Enabled -eq "1"){
        Try {
            Log "Importing CSV file for UserAccount"
            $CSV = Import-Csv -Path $xml.UserAccount.CsvFilePath -ErrorAction Stop
        }Catch{
            Log $error[0].exception.message -Error
        }
        UserAccount -CSV $CSV
    }

    If ($xml.PowerConfig.Enabled -eq "1"){
        PowerConfig
    }

    If ($xml.ComputerName.Enabled -eq "1"){
        ComputerName
    }

    If ($xml.LicenseKey.Enabled -eq "1"){
        LicenseKey
    }

    If ($xml.Software.Enabled -eq "1"){
        Software
    }

    If ($xml.WindowsUpdates.Enabled -eq "1"){
        WindowsUpdates
        Restart-Computer -Force
        Exit
    }
}

Function FileCopy {
    #FileCopy -Credential $PSCredential
    #Receives credentials for unc path, maps to drive letter and transfers directories
    param(
        [parameter(Mandatory=$True,position=0)] [System.Management.Automation.PSCredential] $Credential
    )

    Log "Function: FileCopy"
    If (Test-Path $xml.FileCopy.DestPath){
        Log "$($xml.FileCopy.DestPath) exists."
    } Else {
        Try{
            New-Item -Path $xml.FileCopy.DestPath -ItemType "Directory" -ErrorAction Stop | Out-Null
            Log "Created $($xml.Filecopy.DestPath) directory..."
        }Catch{
            Log $Error[0].exception.message -Error
        }
    }
    
    Try {
        New-PSDrive -Name $xml.FileCopy.MappedLetter -PSProvider FileSystem -Root $xml.FileCopy.UNCPath -Persist -Credential $Credential -ErrorAction Stop
        Log "Mapped $($xml.FileCopy.MappedLetter) drive to $($xml.FileCopy.UNCPath)..."
        Log "Copying files to $($xml.FileCopy.DestPath)..."
        robocopy "$($xml.FileCopy.MappedLetter):\" $xml.FileCopy.DestPath /E
        Log "Deleting mapped drive..."
        Remove-PSDrive -Name $xml.FileCopy.MappedLetter -Force -PSProvider FileSystem -ErrorAction Stop
    }Catch{
        Log $Error[0].exception.message -Error
    }
    Log "Function: FileCopy" -Complete
    Return
}

Function UserAccount {
    #UserAccount -CSV $file
    param(
        [parameter(Mandatory=$true,position=0)]$CSV
    )
    Log "Function: UserAccount"

    If ($xml.UserAccount.DisableRootAdmin -eq "1"){
        Disable-LocalUser -Name "Administrator" -Confirm:$false
    }
    
    Log "Creating user accounts from csv file..."
    Foreach ($user in $CSV) {
        New-LocalUser -Name $user.username -NoPassword -AccountNeverExpires -FullName $user.fullname -Description $user.comment
        If ($user.password -ne "") {
            Set-LocalUser -Name $user.username -Password $(ConvertTo-SecureString -String $user.password -AsPlainText -Force) -PasswordNeverExpires $True
        }
        If ($user.administrator = "True"){
            Add-LocalGroupMember -Group "Administrators" -Member $user.username
        } 
    }
    Log "Function: User Account" -Complete
    Return
}

Function PowerConfig {
    Log "Function: PowerConfig"
    powercfg -x monitor-timeout-ac $xml.PowerConfig.MonitorTimeout
    powercfg -x monitor-timeout-dc $xml.PowerConfig.MonitorTimeout
    powercfg -x disk-timeout-ac $xml.PowerConfig.DiskTimeout
    powercfg -x disk-timeout-dc $xml.PowerConfig.DiskTimeout
    powercfg -x standby-timeout-ac $xml.PowerConfig.StandbyTimeout
    powercfg -x standby-timeout-dc $xml.PowerConfig.StandbyTimeout
    powercfg -x hibernate-timeout-ac $xml.PowerConfig.HibernateTimeout
    powercfg -x hibernate-timeout-dc $xml.PowerConfig.HibernateTimeout
    Log "Function: PowerConfig" -Complete
    Return
}

Function Software {
    Log "Function: Software"
    #Install chocolatey
    If ((Test-Path "C:\ProgramData\Chocolatey\choco.exe") -eq $False){
        Log "Downloading Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    
    #Install software
    Log "Installing software packages..."
    If ($xml.Software.AdobeReader -eq "1") {choco install adobereader -y}
    If ($xml.Software.AdobeFlash -eq "1") {choco install flashplayerplugin -y}
    If ($xml.Software.GoogleChrome -eq "1") {choco install googlechrome -y}
    If ($xml.Software.MozillaFirefox -eq "1") {choco install firefox -y}
    If ($xml.Software.AdblockPlusIE -eq "1") {choco install adblockplusie -y}
    If ($xml.Software.AdblockPlusChrome -eq "1") {choco install adblockpluschrome -y}
    If ($xml.Software.AdblockPlusFirefox -eq "1") {choco install adblockplus-firefox -y}
    If ($xml.Software.Java -eq "1") {choco install jre8 -y}
    If ($xml.Software.Office365Business -eq "1") {choco install office365business -y}
    If ($xml.Software.Office365ProPlus -eq "1") {choco install office365proplus -y}
    If ($xml.Software.SevenZip -eq "1") {choco install 7zip -y}
    If ($xml.Software.Winrar -eq "1") {choco install winrar -y}
    If ($xml.Software.NotepadPlusPlus -eq "1") {choco install notepadplusplus -y}
    If ($xml.Software.SysInternals -eq "1") {choco install sysinternals -y}
    If ($xml.Software.ProcMon -eq "1") {choco install procmon -y}
    If ($xml.Software.VCRedist2010 -eq "1") {choco install vcredist2010 -y}
    If ($xml.Software.DotNet35 -eq "1") {choco install dotnet3.5 -y}
    If ($xml.Software.VCRedist20152019 -eq "1") {choco install vcredist140 -y}
    If ($xml.Software.MsVisualCPlusPlus2012 -eq "1") {choco install msvisualcplusplus2012-redist -y}
    If ($xml.Software.MsVisualCPlusPlus2013 -eq "1") {choco install msvisualcplusplus2013-redist -y}
    If ($xml.Software.VCRedist2008 -eq "1") {choco install vcredist2008 -y}
    
    #Remove default Windows packages
    $packages = @(
        "Microsoft.XboxGameCallableUI";
        "Microsoft.MixedReality.Portal";
        "Microsoft.XboxGamingOverlay";
        "Microsoft.YourPhone";
        "Microsoft.Windows.Cortana";
        "Microsoft.XboxGameOverlay";
        "Microsoft.ZuneVideo";
        "Microsoft.XboxApp";
        "Microsoft.ZuneMusic";
        "Microsoft.Xbox.TCUI";
        "Microsoft.XboxSpeechToTextOverlay";
        "Microsoft.BingWeather";
        "Microsoft.People";
        "Microsoft.WindowsMaps";
        "Microsoft.XboxIdentityProvider";
        "Microsoft.SkypeApp";
        "Microsoft.OneConnect";
        "Microsoft.MicrosoftOfficeHub";
        "Microsoft.Messaging";
        "Microsoft.MicrosoftSolitaireCollection"
    )

    If ($xml.Software.RemoveDefaultPackages -eq "1"){
        ForEach ($package in $packages){
            try{
                Log "Attempting to remove $package."
                Remove-AppxPackage (Get-AppxPackage -AllUsers|Where{$_.Name -match "$package"}).PackageFullName
            }catch{
                Log $error[0].Exception.Message -Error
            }
        }   
    }

    Log "Function: Software" -Complete
    Return
}

Function ComputerName {
    Log "Function: ComputerName"

    #Sets custom name if filled out
    If ($xml.ComputerName.CustomName -ne "") {
        Log "Setting ComputerName to custom name: $($xml.ComputerName.CustomName)"
        Rename-Computer -NewName $xml.ComputerName.CustomName
    }

    #If Dell, sets service tag to computername
    Log "Checking If Manufacturer = Dell"
    $Manuf = Get-WmiObject win32_SystemEnclosure | Select-Object -ExpandProperty Manufacturer
    If (($Manuf -like '*Dell*') -and ($xml.ComputerName.SetToDellServiceTag -eq "1")) {
        $tag = Get-WmiObject win32_SystemEnclosure | Select-Object -ExpandProperty serialnumber
        $comp = Get-ChildItem -Path Env:\ComputerName | Select-Object -ExpandProperty Value
        $chassistype = $(Get-WmiObject win32_SystemEnclosure).ChassisTypes
        If ($tag -ne $comp) {
            If ($chassistype -eq 9 -OR $chassistype -eq 10 -OR $chassistype -eq 14){
                Log "Setting ComputerName to service tag: $tag-LT"
                Rename-Computer -NewName "$tag-LT"
            }
            If ($chassistype -ne 9 -AND $chassistype -ne 10 -AND $chassistype -ne 14){
                Log "Setting ComputerName to service tag: $tag"
                Rename-Computer -NewName "$tag"
            }
        }
    } Else {
        Log "Manufacturer not = Dell OR SetToDellServiceTag is not = 1." -Error
    }
    Log "Function: ComputerName" -Complete
    Return
}

Function WindowsUpdates {
    Log "Function: WindowsUpdates"
    Try {
        Get-InstalledModule PSWindowsUpdate -ErrorAction Stop
    }Catch{
        Log "Installing Nuget..."
        Install-PackageProvider Nuget -Force
        Log "Setting PSGallery to Trusted..."
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Log "Installing Module PSWindowsUpdate..."
        Install-Module PSWindowsUpdate -Force
        Add-WUServiceManager -ServiceID 7971f918-a847-4430-9279-4a52d1efe18d -Confirm:$false
        Add-WUServiceManager -ServiceID 9482f4b4-e343-43b6-b170-9a65bc822c77 -Confirm:$false
        Add-WUServiceManager -ServiceID 117cab2d-82b1-4b5a-a08c-4d62dbee7782 -Confirm:$false
    }
    Log "Checking for updates and installing..."
    Get-WUInstall -MicrosoftUpdate -AcceptAll -Verbose -IgnoreUserInput -IgnoreReboot -Install

    Log "Double checking updates..."
    Get-WUInstall -MicrosoftUpdate -AcceptAll -Verbose -IgnoreUserInput -IgnoreReboot -Install
    
    Log "Windows Updates installed." -Complete
    Return
}

Function LicenseKey {
    #Pulls license key out of WMI and then reinserts it, clears up licensing issues from Dell sometimes
    Log "Function: LicenseKey"
    $key = (Get-WmiObject -Class softwarelicensingservice | Select-Object OA3xOriginalProductKey).OA3xOriginalProductKey
    
    If ($key -ne ""){
        Log "Key = $key"
        Set-Content -Path "C:\licensekey.txt" -Value $key
        Log "Installing key..."
        slmgr -ipk $key
        slmgr -ato
        Log "Key Installed..."
    } Else {
        Log "Key not found." -Error
    }
    Log "Function: LicenseKey" -Complete
    Return
}

Function AutoLogon {
    Log "Function: AutoLogon"
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $RunPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String
    Set-ItemProperty $RegPath "DefaultUsername" -Value $xml.WindowsUpdates.Username -type String
    Set-ItemProperty $RegPath "DefaultPassword" -Value $xml.WindowsUpdates.Password -type String
    Set-ItemProperty $RegPath "AutoLogonCount" -Value ($xml.WindowsUpdates.Cycles - 1) -type DWord
    Set-ItemProperty $RunPath "Deploy-PC" -Value "$PSScriptRoot\Deploy-PC.bat" -type String
    Log "Function: AutoLogon" -Complete
}

#Startup
$global:xml = LoadXML
Main