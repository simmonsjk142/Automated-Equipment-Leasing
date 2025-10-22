$file = "C:\Users\NERC\Documents\GitHub\Automated-Equipment-Leasing\contracts\EquipLease.clar"
$content = [System.IO.File]::ReadAllText($file)
$content = $content.Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($file, $content, [System.Text.Encoding]::UTF8)
