# Run as the user who should see the change in Explorer

# Get current computer name
$Name = $env:COMPUTERNAME

# Registry path for "This PC" caption in the nav pane
$ThisPcKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{20D04FE0-3AEA-1069-A2D8-08002B30309D}'

# Ensure the key exists, then set default value to the computer name
if (-not (Test-Path $ThisPcKey)) {
    New-Item -Path $ThisPcKey -Force | Out-Null
}
Set-ItemProperty -Path $ThisPcKey -Name '(Default)' -Value $Name    # [web:4][web:6]

# Rename C: volume to "OS"
$drive = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = 'C:'"   # [web:2][web:5]
if ($drive) {
    $drive | Set-CimInstance -Property @{ Label = 'OS' }                        # [web:2][web:8]
}

# Optionally restart Explorer so the "This PC" label updates immediately
Stop-Process -Name explorer -Force
Start-Process explorer.exe
