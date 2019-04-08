#Dylan Bartos
#Gather PC Information for replacement
#v0.1

#Create necessary paths
If ((Test-Path "C:\PC-Recon") -eq $false){
    New-Item -Path "C:\PC-Recon" -ItemType Directory
}
If ((Test-Path "C:\PC-Recon\Output.txt") -eq $false){
    New-Item -Path "C:\PC-Recon\Output.txt" -ItemType File
}

#Set Global Vars
$global:outFile = "C:\PC-Recon\Output.txt"

Add-Content -Path $outFile "IDENTIFYING INFORMATION"
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outFile "Hostname: $(hostname)"
Add-Content -Path $outFile "Domain: $((Get-WmiObject -Class Win32_ComputerSystem).Domain)"
Add-Content -Path $outfile "Manufacturer: $((Get-WmiObject -Class Win32_ComputerSystem).Manufacturer)"
Add-Content -Path $outFile "Model: $((Get-WmiObject -Class Win32_ComputerSystem).Model)"
Add-Content -Path $outFile "WinOS: $(Get-WmiObject -Class Win32_OperatingSystem | % caption)"
Add-Content -Path $outfile "WinVer: $((Get-WmiObject -Class Win32_OperatingSystem).Version)"
[double]$totGB = 0; Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {$totGB = $totGB + [double]$_.Capacity}; $totGB = $totGB / 1073741824
Add-Content -Path $outFile "RAM: $totGB GBs"
[double]$hddGB = 0; Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {$hddGB = $hddGB + [double]$_.Size}; $hddGB = [math]::Round($hddGB / 1073741824)
Add-Content -Path $outFile "HDD Size: $hddGB GBs"
Add-Content -Path $outFile "HDD Model: $((Get-WmiObject -Class Win32_DiskDrive).Model)"
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outfile "LOCAL USER ACCOUNTS"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach($user in $(Get-WmiObject -Class Win32_UserAccount -Filter "LocalAccount=True")){
    Add-Content -Path $outFile "$($user.Name)"
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""

Add-Content -Path $outFile "OUTLOOK FILES"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach ($result in $(Get-ChildItem -Path C:\Users -Filter "*.ost" -Recurse -ErrorAction SilentlyContinue)){
    Add-Content -Path $outFile "$($result.DirectoryName)\$result"
}
foreach ($result in $(Get-ChildItem -Path C:\Users -Filter "*.pst" -Recurse -ErrorAction SilentlyContinue)){
    Add-Content -Path $outFile "$($result.DirectoryName)\$result"
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""

Add-Content -Path $outFile "NOAH"
Add-Content -Path $outFile "------------------------------------------------------------"

#GetNoahVersion 
[xml]$xml = Get-Content "C:\ProgramData\HIMSA\Noah\NoahSettings.xml"
$noahVer = $xml.Settings.item.value[1].dataitem.data.'#text'
Add-Content -Path $outFile "Noah Version: $noahVer"

#Get Noah Modules List
$noahArray = @()
[xml]$xml = Get-Content "C:\ProgramData\HIMSA\Noah\ClientSettings.xml"
foreach($item in $xml.Settings.item){
    If ($(Select-String -Pattern "\\Name" -InputObject $item.key.string) -ne $null){
        $noahArray += $item.value.dataitem.data."#text"
    }
}
$noahArray = $($noahArray | Sort-Object)
foreach ($module in $noahArray){
    Add-Content -Path $outFile $module
}

Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outfile "CONNECTED NETWORK ADAPTERS"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach($adapter in $(Get-NetAdapter -Physical | Where-Object -Property "Status" -EQ "Up" | Select-Object -Property InterfaceDescription)){
    Add-Content -Path $outFile $adapter.InterfaceDescription
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outFile "DISCONNECTED NETWORK ADAPTERS"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach($adapter in $(Get-NetAdapter -Physical | Where-Object -Property "Status" -EQ "Disconnected" | Select-Object -Property InterfaceDescription)){
    Add-Content -Path $outFile $adapter.InterfaceDescription
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outfile "CONNECTED DRIVES"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach($drive in $(Get-PSDrive | Where-Object {$_.Provider.Name -EQ "FileSystem"})){
    Add-Content -Path $outFile "$($drive.Name) = $($drive.DisplayRoot)"
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outFile "PRINTERS"
Add-Content -Path $outFile "------------------------------------------------------------"
foreach($printer in $(Get-Printer | Where-Object {($_.PortName -ne "nul:") -and ($_.PortName -ne "PORTPROMPT:")})){
    Add-Content -Path $outFile "$($printer.Name) | $($printer.DriverName) | $($printer.PortName)"
}
Add-Content -Path $outFile "------------------------------------------------------------"
Add-Content -Path $outfile ""
Add-Content -Path $outFile "INSTALLED SOFTWARE"
Add-Content -Path $outFile "------------------------------------------------------------"

#var def
$regArray=@()

#64 Bit Software List
$uninstallKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
$reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine",$nev:computername)
$regkey = $reg.OpenSubKey($uninstallKey)
$subkeys = $regkey.GetSubKeyNames()
foreach($key in $subkeys){
    $aKey = $uninstallKey + "\\" + $key
    $aSubKey = $reg.OpenSubKey($aKey)
    $DisplayName = $aSubKey.GetValue("DisplayName")
    If ($DisplayName -eq $null){
        continue
    }
    $regArray += "$DisplayName"
}

#32 Bit Software List
$uninstallKey = "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
$regkey = $reg.OpenSubKey($uninstallKey)
$subkeys = $regkey.GetSubKeyNames()
foreach($key in $subkeys){
    $aKey = $uninstallKey + "\\" + $key
    $aSubKey = $reg.OpenSubKey($aKey)
    $DisplayName = $aSubKey.GetValue("DisplayName")
    If ($DisplayName -eq $null){
        continue
    }
    $regArray += "$DisplayName"
}

$regArray = $($regArray | Sort-Object)
foreach ($software in $regArray){
    Add-Content -Path $outFile $software
}

Start-Process -FilePath "C:\PC-Recon\Output.txt"