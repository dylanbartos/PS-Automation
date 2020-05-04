Import-Module AWSPowerShell.NetCore

#Specify Environment Variables#
$EC2Tag = "Auto-Ami" #The Boolean tag used to enable/disable ami creation/deletion
$Debug = "True" #Logs expected ouput rather than executing any action
$AMIsToKeep = 7 #Stores X number of AMIs

#Pulls Tags and Instances from AWS
$Instances = Get-Ec2Tag -Filter @{Name="resource-type";Value="instance"}, @{Name="key";Value="Name"}
$NamedInstances = $Instances | Select-Object @{Name="InstanceID";Expression={$PSItem.ResourceID}}, @{Name="Name";Expression={$PSItem.Value}}
$Instances = Get-Ec2Tag -Filter @{Name="resource-type";Value="instance"}, @{Name="key";Value=$EC2Tag} 
$Instances = $Instances | Select-Object @{Name="InstanceID";Expression={$PSItem.ResourceID}}, @{Name="AutoAmi";Expression={$PSItem.Value}} | Where-Object {$_.AutoAmi.ToUpper() -eq "TRUE"}

#Pulls volume IDs
$Volumes = $Instances | ForEach-Object {Get-EC2Volume -Filter @{Name="attachment.instance-id"; Values="$($Instances.InstanceID)"}}

#Joins key/value pairs into the Instance object
$Instances | ForEach-Object {
    #Adds Name tag
    For ($i=0; $i -le ($NamedInstances.PSObject.Properties.Value.Name.Count - 1); $i++){
        If ($_.InstanceID -eq $NamedInstances[$i].InstanceID){
            $_ | Add-Member -MemberType NoteProperty -Name "Name" -Value $NamedInstances[$i].Name
        }
    }

    #Adds volumes
    For ($i=0; $i -le ($volumes.count - 1); $i++){
        If ($Volumes[$i].Attachment.InstanceID -eq $_.InstanceID){
            If ($null -eq $_.Volumes){
                $_ | Add-Member -MemberType NoteProperty -Name "Volumes" -Value @($Volumes[$i].Attachment.VolumeID)
            } ElseIf ($null -ne $_.Volumes){
                $_.Volumes += "$($Volumes[$i].Attachment.VolumeID)" 
            }
        }
    }
}

#Main Execution
If ($Debug -eq $True){
    Write-Host "Instances set to AMI:"
    $Instances | ForEach-Object {Write-Host $_.InstanceID}

    Write-Host "AMIs set to unregister/snapshots set to delete:"
    $Instances | ForEach-Object {
        $AMIs = Get-EC2Image -Filters @{Name="description"; Values="Automatic AMI created for $($_.InstanceID)"} | Sort-Object -Property CreationDate -Descending
        
        #Remove AMIs older than 7 days
        For ($i=$AMIsToKeep; $i -le ($AMIs.Count - 1); $i++){
            Write-Host $AMIs[$i].ImageId
            For ($j=0; $j -le ($Instances.Volumes.Count - 1); $j++){
                #Pull all snapshot for each volume
                $Snapshots = Get-EC2Snapshot -Filter @{Name="volume-id"; Values="$($_.Volumes[$j])"}
                $InstancesTmp = $_ 
                #Filter snapshots by the specific AMI where is being unregistereed
                $Snapshots = $Snapshots | Where-Object {$_.Description -eq "Created by CreateImage($($InstancesTmp.InstanceID)) for $($AMIs[$i].ImageId) from $($InstancesTmp.Volumes[$j])"}
                Write-Host "$($Snapshots.SnapshotId)"
            }
        }
    }
} ElseIf ($Debug -ne $True){
    $Instances | ForEach-Object {
        New-EC2Image -InstanceID $_.InstanceID -Name "$(Get-Date -Format 'yyyyMMdd')_$($_.Name)_AutoAmi-$($(New-Guid).ToString().SubString(0,5))" -Description "Automatic AMI created for $($_.InstanceID)" -NoReboot $True | Out-Null
        
        $AMIs = Get-EC2Image -Filters @{Name="description"; Values="Automatic AMI created for $($_.InstanceID)"} | Sort-Object -Property CreationDate -Descending

        #Remove AMIs older than 7 days
        For ($i=$AMIsToKeep; $i -le ($AMIs.Count - 1); $i++){
            #Grab Snapshots before AMI is unregistered
            $SnapshotIDsToRemove = @()
            For ($j=0; $j -le ($Instances.Volumes.Count - 1); $j++){
                #Pull all snapshots
                $Snapshots = Get-EC2Snapshot -Filter @{Name="volume-id"; Values="$($_.Volumes[$j])"}
                $InstancesTmp = $_ 
                #Filter snapshots to just those that match the AMI    
                $Snapshots = $Snapshots | Where-Object {$_.Description -eq "Created by CreateImage($($InstancesTmp.InstanceID)) for $($AMIs[$i].ImageId) from $($InstancesTmp.Volumes[$j])"}
                $Snapshots | ForEach-Object {$SnapshotIDsToRemove += $_.SnapShotId}
            }
            Unregister-EC2Image -ImageID $AMIs[$i].ImageId
            $SnapshotIDsToRemove | ForEach-Object {Remove-EC2Snapshot -SnapshotId $_ -Confirm:$false}
        }
    }
}