#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installerer Expedition Toolkit for lab-maskin lockdown/unlock
    
.DESCRIPTION
    Setter opp komplett toolkit for å "fryse" og "tine opp" lab-maskiner
    - Freeze: Blokkerer Windows Update, dvalemodus, automatiske restarter
    - Thaw: Gjenoppretter normal funksjonalitet
    - Status: Sjekker nåværende tilstand
    
.PARAMETER InstallPath
    Hvor toolkit skal installeres (default: C:\ExpeditionToolkit)
    
.PARAMETER CreateDesktopShortcuts
    Lag snarveier på skrivebordet (default: $true)
    
.PARAMETER InstallScheduledTask
    Installer scheduled task for automatisk freeze ved oppstart (default: $false)
    
.EXAMPLE
    .\Install-ExpeditionToolkit.ps1
    
.EXAMPLE
    .\Install-ExpeditionToolkit.ps1 -InstallPath "D:\Tools\Expedition" -CreateDesktopShortcuts $false
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\ExpeditionToolkit",
    [bool]$CreateDesktopShortcuts = $true,
    [bool]$InstallScheduledTask = $false
)

$ErrorActionPreference = "Stop"

Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        EXPEDITION TOOLKIT INSTALLER                      ║
║        Lab Machine Lockdown System                       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Installerer til: $InstallPath" -ForegroundColor Yellow
Write-Host ""

# Opprett mappestruktur
Write-Host "[1/6] Oppretter mappestruktur..." -ForegroundColor Cyan
$folders = @(
    $InstallPath,
    "$InstallPath\Scripts",
    "$InstallPath\Logs",
    "$InstallPath\Modules"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  ✓ Opprettet: $folder" -ForegroundColor Green
    } else {
        Write-Host "  ℹ Finnes: $folder" -ForegroundColor Gray
    }
}

# Opprett Freeze-ExpeditionMode.ps1
Write-Host "`n[2/6] Installerer Freeze-ExpeditionMode.ps1..." -ForegroundColor Cyan
$freezeScript = @'
#Requires -RunAsAdministrator

$LogPath = "C:\ExpeditionToolkit\Logs"
New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
$LogFile = "$LogPath\Freeze-$(Get-Date -Format yyyyMMdd-HHmm).log"

Start-Transcript -Path $LogFile

Write-Host "=== Starter Expedition Freeze ===" -ForegroundColor Cyan

try {
    # Stop Windows Update services
    Write-Host "Stopper Windows Update tjenester..." -ForegroundColor Yellow
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service usosvc -Force -ErrorAction SilentlyContinue
    Stop-Service UsoSvc -Force -ErrorAction SilentlyContinue
    
    Set-Service wuauserv -StartupType Disabled -ErrorAction Stop
    Set-Service usosvc -StartupType Disabled -ErrorAction SilentlyContinue
    
    # Disable Update Orchestrator tasks
    Write-Host "Deaktiverer Update Orchestrator tasks..." -ForegroundColor Yellow
    $tasks = @(
        "\Microsoft\Windows\UpdateOrchestrator\Reboot",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask",
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
    )
    
    foreach ($task in $tasks) {
        $result = schtasks /Change /TN $task /Disable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Deaktivert: $task" -ForegroundColor Green
        }
    }
    
    # Disable Scheduled Maintenance
    Write-Host "Deaktiverer Scheduled Maintenance..." -ForegroundColor Yellow
    $maintenancePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance"
    if (-not (Test-Path $maintenancePath)) {
        New-Item -Path $maintenancePath -Force | Out-Null
    }
    New-ItemProperty -Path $maintenancePath -Name "MaintenanceDisabled" -Value 1 -PropertyType DWord -Force | Out-Null
    
    # Power configuration
    Write-Host "Konfigurerer strøminnstillinger..." -ForegroundColor Yellow
    powercfg /hibernate off
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    powercfg /change monitor-timeout-ac 0
    powercfg /change disk-timeout-ac 0
    
    # Prevent auto reboot
    Write-Host "Blokkerer automatiske restarter..." -ForegroundColor Yellow
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $auPath)) {
        New-Item -Path $auPath -Force | Out-Null
    }
    New-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 1 -PropertyType DWord -Force | Out-Null
    
    # Disable Windows Update Medic Service
    Write-Host "Hardening Windows Update Medic Service..." -ForegroundColor Yellow
    $medicKey = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if (Test-Path $medicKey) {
        Set-ItemProperty -Path $medicKey -Name "Start" -Value 4 -ErrorAction SilentlyContinue
    }
    
    # Create marker file
    $markerFile = "$LogPath\EXPEDITION_MODE_ACTIVE.marker"
    @{ 
        ActivatedAt = Get-Date
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
    } | ConvertTo-Json | Out-File -FilePath $markerFile -Force
    
    Write-Host "`n=== ✓ Expedition Mode aktivert ===" -ForegroundColor Green
    Write-Host "Maskinen er nå låst mot oppdateringer, dvalemodus og restarter.`n" -ForegroundColor Green
    
} catch {
    Write-Host "`n!!! FEIL: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Stop-Transcript
Read-Host "Trykk Enter for å lukke"
'@

$freezeScript | Out-File "$InstallPath\Scripts\Freeze-ExpeditionMode.ps1" -Encoding UTF8 -Force
Write-Host "  ✓ Installert" -ForegroundColor Green

# Opprett Thaw-ExpeditionMode.ps1
Write-Host "`n[3/6] Installerer Thaw-ExpeditionMode.ps1..." -ForegroundColor Cyan
$thawScript = @'
#Requires -RunAsAdministrator

$LogPath = "C:\ExpeditionToolkit\Logs"
New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
$LogFile = "$LogPath\Thaw-$(Get-Date -Format yyyyMMdd-HHmm).log"

Start-Transcript -Path $LogFile

Write-Host "=== Starter Re-Integrering ===" -ForegroundColor Cyan

try {
    # Restore services
    Write-Host "Gjenoppretter Windows Update tjenester..." -ForegroundColor Yellow
    Set-Service wuauserv -StartupType Manual -ErrorAction Stop
    Set-Service usosvc -StartupType Manual -ErrorAction SilentlyContinue
    
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service usosvc -ErrorAction SilentlyContinue
    
    # Enable tasks
    Write-Host "Aktiverer Update Orchestrator tasks..." -ForegroundColor Yellow
    $tasks = @(
        "\Microsoft\Windows\UpdateOrchestrator\Reboot",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask",
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
    )
    
    foreach ($task in $tasks) {
        $result = schtasks /Change /TN $task /Enable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Aktivert: $task" -ForegroundColor Green
        }
    }
    
    # Remove maintenance override
    Write-Host "Aktiverer Scheduled Maintenance..." -ForegroundColor Yellow
    Remove-ItemProperty `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" `
        -Name "MaintenanceDisabled" -ErrorAction SilentlyContinue
    
    # Remove registry policies
    Write-Host "Fjerner Windows Update policies..." -ForegroundColor Yellow
    Remove-ItemProperty `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
    Remove-ItemProperty `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    
    # Restore Medic Service
    Write-Host "Gjenoppretter Windows Update Medic Service..." -ForegroundColor Yellow
    $medicKey = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if (Test-Path $medicKey) {
        Set-ItemProperty -Path $medicKey -Name "Start" -Value 3 -ErrorAction SilentlyContinue
    }
    
    # Restore power settings
    Write-Host "Gjenoppretter strøminnstillinger..." -ForegroundColor Yellow
    powercfg /hibernate on
    powercfg /change standby-timeout-ac 30
    powercfg /change monitor-timeout-ac 10
    
    # Remove marker file
    $markerFile = "$LogPath\EXPEDITION_MODE_ACTIVE.marker"
    Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
    
    Write-Host "`n=== ✓ Expedition Mode deaktivert ===" -ForegroundColor Green
    Write-Host "Maskinen er tilbake i normal modus.`n" -ForegroundColor Cyan
    Write-Host "Anbefalte neste steg:" -ForegroundColor Yellow
    Write-Host "  1. Koble til nettverket" -ForegroundColor White
    Write-Host "  2. Kjør: Start-Process 'ms-settings:workplace' (Intune sync)" -ForegroundColor White
    Write-Host "  3. Eller kjør manuell Windows Update sjekk`n" -ForegroundColor White
    
} catch {
    Write-Host "`n!!! FEIL: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Stop-Transcript
Read-Host "Trykk Enter for å lukke"
'@

$thawScript | Out-File "$InstallPath\Scripts\Thaw-ExpeditionMode.ps1" -Encoding UTF8 -Force
Write-Host "  ✓ Installert" -ForegroundColor Green

# Opprett Get-ExpeditionStatus.ps1
Write-Host "`n[4/6] Installerer Get-ExpeditionStatus.ps1..." -ForegroundColor Cyan
$statusScript = @'
#Requires -RunAsAdministrator

Write-Host "`n=== Expedition Mode Statuskontroll ===" -ForegroundColor Cyan
Write-Host "Tid: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Maskin: $env:COMPUTERNAME`n" -ForegroundColor Gray

# Check marker file
$markerFile = "C:\ExpeditionToolkit\Logs\EXPEDITION_MODE_ACTIVE.marker"
if (Test-Path $markerFile) {
    $markerData = Get-Content $markerFile -Raw | ConvertFrom-Json
    Write-Host "🔒 STATUS: EXPEDITION MODE AKTIV" -ForegroundColor Red
    Write-Host "   Aktivert: $($markerData.ActivatedAt)" -ForegroundColor Yellow
    Write-Host "   Av bruker: $($markerData.User)" -ForegroundColor Yellow
} else {
    Write-Host "✓ STATUS: NORMAL MODE" -ForegroundColor Green
}

Write-Host "`n--- Windows Update Tjenester ---" -ForegroundColor Cyan
Get-Service wuauserv, usosvc -ErrorAction SilentlyContinue | 
    Format-Table Name, Status, StartType -AutoSize

Write-Host "--- Update Orchestrator Tasks ---" -ForegroundColor Cyan
$tasks = @(
    "\Microsoft\Windows\UpdateOrchestrator\Reboot",
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"
)

foreach ($task in $tasks) {
    $taskInfo = schtasks /Query /TN $task /FO CSV 2>&1 | ConvertFrom-Csv -ErrorAction SilentlyContinue
    if ($taskInfo) {
        $color = if ($taskInfo.Status -eq 'Disabled') {'Red'} else {'Green'}
        $shortName = $task.Split('\')[-1]
        Write-Host "  $shortName : $($taskInfo.Status)" -ForegroundColor $color
    }
}

Write-Host "`n--- Strøminnstillinger ---" -ForegroundColor Cyan
$hibernateCheck = powercfg /a | Select-String "Dvalemodus|Hibernate"
if ($hibernateCheck) {
    Write-Host "  $hibernateCheck" -ForegroundColor Yellow
}

Write-Host "`n--- Registry Policies ---" -ForegroundColor Cyan
$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (Test-Path $auPath) {
    $noReboot = (Get-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue).NoAutoRebootWithLoggedOnUsers
    $noUpdate = (Get-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    
    $rebootColor = if ($noReboot -eq 1) {'Red'} else {'Green'}
    $updateColor = if ($noUpdate -eq 1) {'Red'} else {'Green'}
    
    Write-Host "  NoAutoRebootWithLoggedOnUsers: $noReboot" -ForegroundColor $rebootColor
    Write-Host "  NoAutoUpdate: $noUpdate" -ForegroundColor $updateColor
} else {
    Write-Host "  Ingen update policies aktive" -ForegroundColor Green
}

Write-Host "`n--- Siste Loggfiler ---" -ForegroundColor Cyan
$logs = Get-ChildItem "C:\ExpeditionToolkit\Logs\*.log" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 3

if ($logs) {
    $logs | ForEach-Object {
        Write-Host "  $($_.Name) ($($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray
    }
} else {
    Write-Host "  Ingen loggfiler funnet" -ForegroundColor Gray
}

Write-Host ""
Read-Host "Trykk Enter for å lukke"
'@

$statusScript | Out-File "$InstallPath\Scripts\Get-ExpeditionStatus.ps1" -Encoding UTF8 -Force
Write-Host "  ✓ Installert" -ForegroundColor Green

# Opprett PowerShell modul
Write-Host "`n[5/6] Installerer PowerShell modul..." -ForegroundColor Cyan
$moduleScript = @"
# ExpeditionToolkit PowerShell Module

function Enable-ExpeditionMode {
    <#
    .SYNOPSIS
        Aktiverer Expedition Mode (freezer maskinen)
    #>
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Freeze-ExpeditionMode.ps1`"" -Verb RunAs
}

function Disable-ExpeditionMode {
    <#
    .SYNOPSIS
        Deaktiverer Expedition Mode (tiner opp maskinen)
    #>
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Thaw-ExpeditionMode.ps1`"" -Verb RunAs
}

function Get-ExpeditionStatus {
    <#
    .SYNOPSIS
        Viser status for Expedition Mode
    #>
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Get-ExpeditionStatus.ps1`"" -Verb RunAs
}

Export-ModuleMember -Function Enable-ExpeditionMode, Disable-ExpeditionMode, Get-ExpeditionStatus
"@

$moduleScript | Out-File "$InstallPath\Modules\ExpeditionToolkit.psm1" -Encoding UTF8 -Force
Write-Host "  ✓ Modul installert" -ForegroundColor Green

# Legg til i PowerShell profil
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch "ExpeditionToolkit") {
        Add-Content -Path $profilePath -Value "`n# Expedition Toolkit`nImport-Module '$InstallPath\Modules\ExpeditionToolkit.psm1' -DisableNameChecking"
        Write-Host "  ✓ Lagt til i PowerShell profil" -ForegroundColor Green
    }
} else {
    "# Expedition Toolkit`nImport-Module '$InstallPath\Modules\ExpeditionToolkit.psm1' -DisableNameChecking" | 
        Out-File $profilePath -Encoding UTF8
    Write-Host "  ✓ Opprettet PowerShell profil" -ForegroundColor Green
}

# Opprett desktop shortcuts
if ($CreateDesktopShortcuts) {
    Write-Host "`n[6/6] Oppretter desktop snarveier..." -ForegroundColor Cyan
    $WshShell = New-Object -ComObject WScript.Shell
    $desktop = [System.Environment]::GetFolderPath('Desktop')
    
    # Freeze shortcut
    $shortcut = $WshShell.CreateShortcut("$desktop\🔒 Freeze Lab Machine.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Freeze-ExpeditionMode.ps1`""
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.IconLocation = "imageres.dll,78"
    $shortcut.Description = "Aktiverer Expedition Mode (blokkerer updates)"
    $shortcut.Save()
    Write-Host "  ✓ Freeze snarvei opprettet" -ForegroundColor Green
    
    # Thaw shortcut
    $shortcut = $WshShell.CreateShortcut("$desktop\✓ Thaw Lab Machine.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Thaw-ExpeditionMode.ps1`""
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.IconLocation = "imageres.dll,76"
    $shortcut.Description = "Deaktiverer Expedition Mode (aktiverer updates)"
    $shortcut.Save()
    Write-Host "  ✓ Thaw snarvei opprettet" -ForegroundColor Green
    
    # Status shortcut
    $shortcut = $WshShell.CreateShortcut("$desktop\ℹ️ Expedition Status.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\Get-ExpeditionStatus.ps1`""
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.IconLocation = "imageres.dll,76"
    $shortcut.Description = "Sjekk Expedition Mode status"
    $shortcut.Save()
    Write-Host "  ✓ Status snarvei opprettet" -ForegroundColor Green
}

# Installer scheduled task (valgfritt)
if ($InstallScheduledTask) {
    Write-Host "`nInstallerer Scheduled Task for automatisk freeze ved oppstart..." -ForegroundColor Cyan
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallPath\Scripts\Freeze-ExpeditionMode.ps1`""
    
    $trigger = New-ScheduledTaskTrigger -AtStartup
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    Register-ScheduledTask -TaskName "Expedition Auto-Freeze" `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Aktiverer automatisk Expedition Mode ved oppstart" `
        -Force
    
    Write-Host "  ✓ Scheduled Task installert" -ForegroundColor Green
    Write-Host "  ⚠️  Maskinen vil automatisk fryse ved hver oppstart!" -ForegroundColor Yellow
}

# Oppsummering
Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        ✓ INSTALLASJON FULLFØRT                          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "Installert i: $InstallPath" -ForegroundColor White
Write-Host "`nTilgjengelige kommandoer (i ny PowerShell):" -ForegroundColor Cyan
Write-Host "  Enable-ExpeditionMode   - Freeze maskinen" -ForegroundColor White
Write-Host "  Disable-ExpeditionMode  - Thaw maskinen" -ForegroundColor White
Write-Host "  Get-ExpeditionStatus    - Sjekk status" -ForegroundColor White

if ($CreateDesktopShortcuts) {
    Write-Host "`nDesktop snarveier er også opprettet!" -ForegroundColor Yellow
}

Write-Host "`nLoggfiler lagres i: $InstallPath\Logs" -ForegroundColor Gray
Write-Host ""