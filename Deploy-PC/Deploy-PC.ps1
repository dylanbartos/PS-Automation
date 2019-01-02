#PC Deployment Script
#Dylan Bartos
#v1.0

Start-Transcript -Path "C:\Deploy-PC-Full.log"

[xml]$global:xml = Get-Content "$PSSCriptRoot\Deploy-PC.config"
$fxml = $global:xml.Functions

Function Main {
    $global:functions = @{}

    #When function is enabled, pull the execution order from settings. Add to hash table.
    If ($fxml.FileCopy.Enabled -eq "1"){
        $global:functions.Add("FileCopy", $fxml.Settings.FileCopyOrder)
    }
    If ($fxml.UserAccount.Enabled -eq "1"){
        $global:functions.Add("UserAccount", $fxml.Settings.UserAccountOrder)
    }
    If ($fxml.PowerConfig.Enabled -eq "1"){
        $global:functions.Add("PowerConfig", $fxml.Settings.PowerConfigOrder)
    }
    If ($fxml.Software.Enabled -eq "1"){
        $global:functions.Add("Software", $fxml.Settings.SoftwareOrder)
    }
    If ($fxml.ComputerName.Enabled -eq "1"){
        $global:functions.Add("ComputerName", $fxml.Settings.ComputerNameOrder)
    }
    If ($fxml.LicenseKey.Enabled -eq "1"){
        $global:functions.Add("LicenseKey", $fxml.Settings.LicenseKeyOrder)
    }
    If ($fxml.WindowsUpdates.Enabled -eq "1"){
        $global:functions.Add("WindowsUpdates", $fxml.Settings.WindowsUpdatesOrder)
    }

    #Sort hash table by order found in Settings
    $global:functions = $global:functions.GetEnumerator() | sort -Property Value
    
    #Initiate the three stages
    If ($fxml.Settings.Stage -eq "1") {
        Log "#############Stage One#############"
        Foreach ($f in $global:functions.Name) {
            If ($fxml.($f).StageOne -eq "1") {
                &$f
            }
        }
        $fxml.Settings.Stage = "2"
        $global:xml.Save("$PSSCriptRoot\Deploy-PC.config")
        AutoLogon
        Restart-Computer -Force -Confirm:$false

    } Elseif ($fxml.Settings.Stage -eq "2") {
        Log "#############Stage Two#############"
        Foreach ($f in $global:functions.Name) {
            If ($fxml.($f).StageTwo -eq "1") {
                &$f
            }
        }
        $fxml.Settings.Stage = "3"
        $global:xml.Save("$PSSCriptRoot\Deploy-PC.config")
        AutoLogon
        Restart-Computer -Force -Confirm:$false

    } Elseif ($fxml.Settings.Stage -eq "3") {
        Log "#############Stage Three#############"
        Foreach ($f in $global:functions.Name) {
            If ($fxml.($f).StageThree -eq "1") {
                &$f
            }
        }
        $fxml.AutoLogon.AutoAdminLogon = "0"
        AutoLogon
        Write-Complete; Log "Computer deployed! Check for [ERRORS]."
        Restart-Computer -Force-Confirm:$false
    }
}

Function FileCopy {
    Log "Function: FileCopy"
    If (Test-Path $fxml.FileCopy.DestPath){
        Log "$($fxml.FileCopy.DestPath) already exists."
    } Else {
        Try{
            New-Item -Path $fxml.FileCopy.DestPath -ItemType "Directory" -ErrorAction Stop | Out-Null
            Log "Created $($fxml.Filecopy.DestPath) directory..."
        }Catch{
            Log "Unable to create $($fxml.Filecopy.DestPath) directory."
            Write-Error; Log "$($fxml.FileCopy.DestPath) does not exist, exiting FileCopy."
            Return
        }
    }
    
    Try {
        New-PSDrive -Name $fxml.FileCopy.MappedLetter -PSProvider FileSystem -Root $fxml.FileCopy.UNCPath -Persist -Credential $cred -ErrorAction Stop
        Log "Mapped $($fxml.FileCopy.MappedLetter) drive to $($fxml.FileCopy.UNCPath)..."
    }Catch{
        Write-Error; Log "Failed to map $($fxml.FileCopy.UNCPath) to $($fxml.FileCopy.MappedLetter). Unable to initiate file copy."
        Log "Please ensure computer is connected to the network, $($fxml.FileCopy.UNCPath) is accessible, and credentials are valid."
        Return
    }

    Log "Copying files to $($fxml.FileCopy.DestPath)..."
    robocopy "$($fxml.FileCopy.MappedLetter):\" $fxml.FileCopy.DestPath /E
    Write-Complete; Log "File transfer!"

    Write-Clean; Log "Deleting mapped drive..."
    Remove-PSDrive -Name $fxml.FileCopy.MappedLetter -Force -PSProvider FileSystem
}

Function UserAccount {
    Log "UserAccount"

    If ($fxml.UserAccount.DisableRootAdmin -eq "1"){
        Log "Disabling root Administrator account..."
        Net User Administrator /active:no
    } Else {
        Log "WARNING: Root Administrator account is active!"
    }
    
    Log "Creating user accounts from csv file..."
    Foreach ($user in $global:csv) {
        If ($user.password -eq ""){
            New-LocalUser -Name $user.username -NoPassword -AccountNeverExpires -FullName $user.fullname -Description $user.comment 
        } Elseif ($user.password -ne "") {
            New-LocalUser -Name $user.username -Password $(ConvertTo-SecureString -String $user.password -AsPlainText -Force) -AccountNeverExpires -FullName $user.fullname -Description $user.comment
        }
        If ($user.administrator = "Yes"){
            Net LocalGroup Administrators $user.username /add
        } 
    }

    Write-Complete; Log "User Accounts configured."
    Return
}

Function PowerConfig {
    Log "PowerConfig"
    Log "Setting power configuration..."
    powercfg -x monitor-timeout-ac $fxml.PowerConfig.MonitorTimeout
    powercfg -x monitor-timeout-dc $fxml.PowerConfig.MonitorTimeout
    powercfg -x disk-timeout-ac $fxml.PowerConfig.DiskTimeout
    powercfg -x disk-timeout-dc $fxml.PowerConfig.DiskTimeout
    powercfg -x standby-timeout-ac $fxml.PowerConfig.StandbyTimeout
    powercfg -x standby-timeout-dc $fxml.PowerConfig.StandbyTimeout
    powercfg -x hibernate-timeout-ac $fxml.PowerConfig.HibernateTimeout
    powercfg -x hibernate-timeout-dc $fxml.PowerConfig.HibernateTimeout
    Write-Complete; Log "Power Config Set."
    Return
}

Function Software {
    Log "Software"
    #Install chocolatey
    If ((Test-Path "C:\ProgramData\Chocolatey\choco.exe") -eq $False){
        Log "Downloading Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    
    #Register upgrade task
    If ($fxml.Software.ChocoUpdateAtBoot -eq "1"){
        Log "Creating Scheduled Task for ChocoUpdateAtBoot..."
        $trigger = New-JobTrigger -AtStartup -RandomDelay 00:15:00
        $action = New-ScheduledTaskAction -Execute "Powershell.exe -Command 'choco upgrade all -y'" -Argument "-NoProfile -WindowStyle Hidden" 
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Chocolatey Upgrade All" -Description "Upgrade check of all installed chocolatey packages at startup."
    }

    #Install software
    Log "Installing software packages..."
    If ($fxml.Software.AdobeReader -eq "1") {choco install adobereader -y}
    If ($fxml.Software.AdobeFlash -eq "1") {choco install flashplayerplugin -y}
    If ($fxml.Software.GoogleChrome -eq "1") {choco install googlechrome -y}
    If ($fxml.Software.MozillaFirefox -eq "1") {choco install firefox -y}
    If ($fxml.Software.AdblockPlusIE -eq "1") {choco install adblockplusie -y}
    If ($fxml.Software.AdblockPlusChrome -eq "1") {choco install adblockpluschrome -y}
    If ($fxml.Software.AdblockPlusFirefox -eq "1") {choco install adblockplus-firefox -y}
    If ($fxml.Software.Java -eq "1") {choco install jre8 -y}
    If ($fxml.Software.Office365Business -eq "1") {choco install office365business -y}
    If ($fxml.Software.Office365ProPlus -eq "1") {choco install office365proplus -y}
    If ($fxml.Software.SevenZip -eq "1") {choco install 7zip -y}
    If ($fxml.Software.Winrar -eq "1") {choco install winrar -y}
    If ($fxml.Software.NotepadPlusPlus -eq "1") {choco install notepadplusplus -y}
    If ($fxml.Software.SysInternals -eq "1") {choco install sysinternals -y}
    If ($fxml.Software.ProcMon -eq "1") {choco install procmon -y}
    
    Write-Complete; Log "Software packages installed."
    Return
}

Function ComputerName {
    Log "ComputerName"

    #Sets custom name if filled out
    If ($fxml.ComputerName.CustomName -ne "") {
        Log "Setting ComputerName to custom name: $($fxml.ComputerName.CustomName)"
        Rename-Computer -NewName $fxml.ComputerName.CustomName
    }

    #If Dell, sets service tag to computername
    Log "Checking If Manufacturer = Dell"
    $Manuf = Get-WmiObject win32_SystemEnclosure | Select -ExpandProperty Manufacturer
    If (($Manuf -like '*Dell*') -and ($fxml.ComputerName.SetToDellServiceTag -eq "1")) {
        $tag = Get-WmiObject win32_SystemEnclosure | Select -ExpandProperty serialnumber
        $comp = Get-ChildItem -Path Env:\ComputerName | Select -ExpandProperty Value
        If ($tag -ne $comp) {
            Log "Setting ComputerName to service tag: $tag"
            Rename-Computer -NewName $tag
        }
    } Else {
        Write-Error; Log "Manufacturer not = Dell OR SetToDellServiceTag is not = 1."
    }
    Write-Complete; Log "ComputerName set."
    Return
}

Function WindowsUpdates {
    Log "WindowsUpdates"
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
    }
    Log "Checking for updates and installing..."
    Get-WUInstall -MicrosoftUpdate -AcceptAll -Verbose -IgnoreUserInput -IgnoreReboot -Install

    Log "Double checking updates..."
    Get-WUInstall -MicrosoftUpdate -AcceptAll -Verbose -IgnoreUserInput -IgnoreReboot -Install
    
    Write-Complete; Log "Windows Updates installed."
    Return
}

Function LicenseKey {
    Log "LicenseKey"
    Log "Retrieving key..."
    $key = (Get-WmiObject -Class softwarelicensingservice | Select-Object OA3xOriginalProductKey).OA3xOriginalProductKey
    
    If ($key -ne ""){
        Log "Key = $key"
        Set-Content -Path "C:\licensekey.txt" -Value $key
        Log "Installing key..."
        slmgr -ipk $key
        slmgr -ato
        Write-Complete; Log "Key Installed..."
    } Else {
        Write-Error; Log "Key not found."
    }
    Return
}

Function AutoLogon {
    Log "AutoLogon"
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $RunPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    Set-ItemProperty $RegPath "AutoAdminLogon" -Value $fxml.AutoLogon.AutoAdminLogon -type String
    Set-ItemProperty $RegPath "DefaultUsername" -Value $fxml.AutoLogon.Username -type String
    Set-ItemProperty $RegPath "DefaultPassword" -Value $fxml.AutoLogon.Password -type String
    Set-ItemProperty $RegPath "AutoLogonCount" -Value "1" -type DWord
    Set-ItemProperty $RunPath "Deploy-PC" -Value $fxml.AutoLogon.ScriptPath -type String
}

Function Log {
    param (
        [Parameter(Mandatory=$True, Position=0)] [string] $text
    )
    Write-Host $text
    Add-Content $fxml.Settings.LogPath "$(Get-Date) $text"
}

Function Write-Complete {
    Write-Host "[" -NoNewline
    Write-Host "COMPLETE" -NoNewline -ForegroundColor Green
    Write-Host "] " -NoNewline
}

Function Write-Clean {
    Write-Host "[" -NoNewline
    Write-Host "CLEAN" -NoNewline -ForegroundColor Yellow
    Write-Host "] " -NoNewline
}

Function Write-Error {
    Write-Host "[" -NoNewline
    Write-Host "ERROR" -NoNewline -ForegroundColor RED
    Write-Host "] " -NoNewline
}

###Startup Prereq Checks###
Log "#############Deploy-PC Started!#############"

#Gather secure credentials for FileCopy
If ($fxml.FileCopy.Password.Enabled -eq "1"){
    If ($fxml.FileCopy.Password -eq ""){
        Log "Deploy-PC.config is missing FileCopy password. Please enter valid credentials to access UNCPath."
        $global:cred = Get-Credential
    }Else{
        $passw = ConvertTo-SecureString $fxml.FileCopy.Password -AsPlainText -Force
        try{
            $global:cred = New-Object System.Management.Automation.PSCredential($fxml.FileCopy.Username, $passw) -ErrorAction Stop
        }catch{
            Log "Deploy-PC.config is missing FileCopy username. Please enter valid credentials to access UNCPath."
            Exit
        }
    }
}

#Import UserAccount.csv for UserAccount
If ($fxml.UserAccount.Enabled -eq "1"){
    Try {
        Log "Importing CSV file for UserAccount"
        $global:csv = Import-Csv -Path $fxml.UserAccount.CsvFilePath -ErrorAction Stop
    }Catch{
        Write-Error; Log "Unable to import csv file ($($fxml.UserAccount.CsvFilePath))"
        Exit
    }
}

#Check that AutoLogon is filled out properly
If ($fxml.AutoLogon.Enabled -eq "1"){
    Log "Verifying AutoLogon account credentials"
    If ($fxml.AutoLogon.Username -eq ""){
        Write-Error; Log "AutoLogon.Username is blank, exiting."
        Exit
    }
    If ($fxml.AutoLogon.Password -eq ""){
        Write-Error; Log "AutoLogon.Password is blank, exiting."
        Exit
    }
    If ($fxml.AutoLogon.ScriptPath -eq ""){
        Write-Error; Log "AutoLogon.ScriptPath is blank, exiting."
        Exit
    }
}

Main