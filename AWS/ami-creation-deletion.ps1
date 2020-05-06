#Requires -Modules @{ModuleName='AWSPowerShell.NetCore';ModuleVersion='3.3.590.0'}

#Specify Environment Variables#
#$EC2Tag = "Auto-Ami" #The Boolean tag used to enable/disable ami creation/deletion
#$Debug = "False" #Logs expected ouput rather than executing any action
#$AMIsToKeep = 7 #Stores X number of AMIs

#Collect Environment Variables from Lambda#
$EC2Tag = $env:EC2Tag
$Debug = $env:Debug
$AMIsToKeep = $env:AMIsToKeep -as [int]

#Pulls Tags and Instances from AWS
$Instances = Get-Ec2Tag -Filter @{Name="resource-type";Value="instance"}, @{Name="key";Value="Name"}
$NamedInstances = $Instances | Select-Object @{Name="InstanceID";Expression={$PSItem.ResourceID}}, @{Name="Name";Expression={$PSItem.Value}}
$Instances = Get-Ec2Tag -Filter @{Name="resource-type";Value="instance"}, @{Name="key";Value=$EC2Tag} 
$Instances = $Instances | Select-Object @{Name="InstanceID";Expression={$PSItem.ResourceID}}, @{Name="AutoAmi";Expression={$PSItem.Value}} | Where-Object {$_.AutoAmi.ToUpper() -eq "TRUE"}

#Joins key/value pairs into the Instances object
$Instances | ForEach-Object {
    #Adds Name tag
    For ($i=0; $i -le ($NamedInstances.PSObject.Properties.Value.Name.Count - 1); $i++){
        If ($_.InstanceID -eq $NamedInstances[$i].InstanceID){
            $_ | Add-Member -MemberType NoteProperty -Name "Name" -Value $NamedInstances[$i].Name
        }
    }
}

#Main Execution
If ($Debug -eq $True){
    Write-Host "Instances set to AMI:"
    $Instances | ForEach-Object {Write-Host "$($_.InstanceID) = $($_.Name)"}

    Write-Host "AMIs set to unregister/snapshots set to delete:"
    $Instances | ForEach-Object {
        $AMIs = Get-EC2Image -Filters @{Name="description"; Values="Automatic AMI created for $($_.InstanceID)"} | Sort-Object -Property CreationDate -Descending
        
        #Remove AMIs older than 7 days
        For ($i=$AMIsToKeep; $i -le ($AMIs.Count - 1); $i++){
            Write-Host $AMIs[$i].ImageId
            $AMIs[$i].BlockDeviceMapping.EBS.SnapshotId
        }
    }
} ElseIf ($Debug -eq $False){
    $Instances | ForEach-Object {
        #Create new AMI and tag
        $Guid = $(New-Guid).ToString().SubString(0,5)
        $NewAMI = New-EC2Image -InstanceID $_.InstanceID -Name "$(Get-Date -Format 'yyyyMMdd')_$($_.Name)_AutoAmi-$Guid" -Description "Automatic AMI created for $($_.InstanceID)" -NoReboot $True
        $NewTag = New-Object Amazon.EC2.Model.Tag
        $NewTag.Key = "Name"
        $NewTag.Value = "$($_.Name)_AutoAmi-$Guid"
        New-EC2Tag -Resource $NewAMI -Tag $NewTag

        $AMIs = Get-EC2Image -Filters @{Name="description"; Values="Automatic AMI created for $($_.InstanceID)"} | Sort-Object -Property CreationDate -Descending
        #Tag snapshots
        $AMIs[0].BlockDeviceMapping.EBS.SnapshotId | ForEach-Object {New-EC2Tag -Resource $_ -Tag $NewTag}

        #Remove AMIs older than 7 days
        For ($i=$AMIsToKeep; $i -le ($AMIs.Count - 1); $i++){
            Unregister-EC2Image -ImageID $AMIs[$i].ImageId
            $AMIs[$i].BlockDeviceMapping.EBS.SnapshotID | ForEach-Object {Remove-EC2Snapshot -SnapshotId $_ -Confirm:$false}
        }
    }
}