#Dylan Bartos
#Method for automagically removing old cab files
#Warning: This is provided under no warranty, you assume full liability.
#Script deletes all files matching 'cab*' in the 'C:\Windows\Temp directory that were created greater than 1 week ago (AddDays(-7)). This is permanent.
$limit = (get-Date).AddDays(-7)
Get-ChildItem -Path "C:\Windows\Temp" -Filter "cab*" | Where-Object {$_.CreationTime -lt $limit } | Remove-Item -Force