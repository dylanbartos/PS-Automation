#User presses 4
#Gets processes running on system, sorts by CPU time high to low, outputs grid format GUI.
Get-Process | Sort-Object -Property CPU -Descending | Out-GridView