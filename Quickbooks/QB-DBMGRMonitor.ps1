#Dylan Bartos
#PS-Automation
#Script designed to run on an hourly basis and resolve any stopped Quickbooks Database Manager services

$QB = Get-Service -Name QuickBooks* | Sort-Object | Select-Object -First 1 -ErrorAction Ignore
$DNS = Get-Service -Name DNS -ErrorAction Ignore

If (($DNS -eq $null) -or ($QB -eq $null)){
    Exit
}

If ($QB.Status -eq "Running"){
    Exit
}

If ($QB.Status -eq "Stopped") {
    If ($DNS.Status -eq "Stopped"){
        Start-Service $QB, $DNS
    }ElseIf ($DNS.Status -eq "Running"){
        Stop-Service $DNS
        Start-Service $QB, $DNS
    }
}

$QB = Get-Service -Name QuickBooks* | Sort-Object | Select-Object -First 1 -ErrorAction Ignore
$DNS = Get-Service -Name DNS -ErrorAction Ignore

If (($QB.Status -eq "Stopped") -or ($DNS.Status -eq "Stopped")){
    Write-Host "Services were unable to start. Manual check required."
}