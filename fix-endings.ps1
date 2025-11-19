$file = "C:\Users\NERC\Documents\GitHub\Automated-Equipment-Leasing\contracts\EquipLease.clar"
[byte[]]$bytes = [System.IO.File]::ReadAllBytes($file)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$text = $text -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($file, $text, [System.Text.Encoding]::UTF8)
Write-Host "Line endings converted to LF"
