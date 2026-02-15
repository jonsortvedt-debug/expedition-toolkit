# 🔒 Expedition Toolkit

**Lab Machine Lockdown System** - Prevent unwanted Windows updates, sleep mode, and restarts on lab machines.

## 🎯 Overview

Expedition Toolkit provides a simple way to "freeze" and "thaw" lab machines to prevent interruptions during critical experiments or data collection.

### Features

- ✅ **Freeze Mode**: Blocks Windows Update, automatic restarts, sleep, and hibernate
- ✅ **Thaw Mode**: Restores normal Windows functionality
- ✅ **Status Check**: Quick overview of current lockdown state
- ✅ **Desktop Shortcuts**: One-click operation
- ✅ **PowerShell Module**: Integrate into your workflows
- ✅ **Comprehensive Logging**: Track all freeze/thaw operations

## 🚀 Quick Start

### Installation

1. **Download and run the installer as Administrator:**

```powershell
# Clone the repository
git clone https://github.com/jonsortvedt-debug/expedition-toolkit.git
cd expedition-toolkit

# Run installer
.\Install-ExpeditionToolkit.ps1
```

2. **Installation options:**

```powershell
# Basic installation
.\Install-ExpeditionToolkit.ps1

# Without desktop shortcuts
.\Install-ExpeditionToolkit.ps1 -CreateDesktopShortcuts $false

# With auto-freeze on startup (use with caution!)
.\Install-ExpeditionToolkit.ps1 -InstallScheduledTask $true

# Custom installation path
.\Install-ExpeditionToolkit.ps1 -InstallPath "D:\Tools\Expedition"
```

### Usage

#### Option 1: Desktop Shortcuts
After installation, use the shortcuts on your desktop:
- 🔒 **Freeze Lab Machine** - Activate lockdown
- ✓ **Thaw Lab Machine** - Deactivate lockdown
- ℹ️ **Expedition Status** - Check current state

#### Option 2: PowerShell Commands
Open a new PowerShell window and use:

```powershell
# Freeze the machine
Enable-ExpeditionMode

# Thaw the machine
Disable-ExpeditionMode

# Check status
Get-ExpeditionStatus
```

#### Option 3: Direct Script Execution

```powershell
# Run scripts directly (requires Admin)
C:\ExpeditionToolkit\Scripts\Freeze-ExpeditionMode.ps1
C:\ExpeditionToolkit\Scripts\Thaw-ExpeditionMode.ps1
C:\ExpeditionToolkit\Scripts\Get-ExpeditionStatus.ps1
```

## 📋 What Gets Locked Down?

### Freeze Mode Blocks:

| Component | Action |
|-----------|--------|
| **Windows Update Services** | Stopped and disabled (`wuauserv`, `usosvc`) |
| **Update Orchestrator** | All scheduled tasks disabled |
| **Scheduled Maintenance** | Windows maintenance disabled |
| **Power Management** | Hibernate, sleep, and auto-shutdown disabled |
| **Automatic Restarts** | Registry policies set to prevent auto-reboot |
| **Update Medic Service** | Prevented from re-enabling updates |

### Logs

All operations are logged to:
```
C:\ExpeditionToolkit\Logs\
```

Log files include:
- `Freeze-YYYYMMDD-HHMM.log`
- `Thaw-YYYYMMDD-HHMM.log`
- `EXPEDITION_MODE_ACTIVE.marker` (indicates active freeze)

## ⚙️ Advanced Usage

### Scheduled Task for Auto-Freeze

If you need machines to auto-freeze on every boot:

```powershell
.\Install-ExpeditionToolkit.ps1 -InstallScheduledTask $true
```

**Warning:** Machines will freeze automatically on startup. Remember to manually thaw when needed!

### Unattended Installation

For deployment via Intune, SCCM, or Group Policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "\\server\share\Install-ExpeditionToolkit.ps1" -CreateDesktopShortcuts $true
```

### Integration with Existing Scripts

```powershell
# Import the module in your scripts
Import-Module "C:\ExpeditionToolkit\Modules\ExpeditionToolkit.psm1"

# Use in automation
Enable-ExpeditionMode
# ... run your lab experiment ...
Disable-ExpeditionMode
```

## 🛠️ Troubleshooting

### Machine Still Updates After Freeze

1. Check if Expedition Mode is active:
   ```powershell
   Get-ExpeditionStatus
   ```

2. Re-run freeze:
   ```powershell
   Enable-ExpeditionMode
   ```

3. Check logs in `C:\ExpeditionToolkit\Logs\`

### Can't Thaw Machine

1. Run thaw script manually as Administrator:
   ```powershell
   C:\ExpeditionToolkit\Scripts\Thaw-ExpeditionMode.ps1
   ```

2. Manually restart Windows Update service:
   ```powershell
   Set-Service wuauserv -StartupType Manual
   Start-Service wuauserv
   ```

### PowerShell Commands Not Found

Restart PowerShell or manually import the module:
```powershell
Import-Module "C:\ExpeditionToolkit\Modules\ExpeditionToolkit.psm1"
```

## 📂 File Structure

```
expedition-toolkit/
├── Install-ExpeditionToolkit.ps1       # Main installer
├── README.md                           # This file
├── LICENSE                             # MIT License
└── .gitignore                          # Git ignore rules
```

After installation:
```
C:\ExpeditionToolkit\
├── Scripts/
│   ├── Freeze-ExpeditionMode.ps1      # Lockdown script
│   ├── Thaw-ExpeditionMode.ps1        # Unlock script
│   └── Get-ExpeditionStatus.ps1       # Status checker
├── Modules/
│   └── ExpeditionToolkit.psm1         # PowerShell module
└── Logs/                               # Operation logs
```

## ⚠️ Warnings

- **Admin Rights Required**: All operations require Administrator privileges
- **Security**: Disabling updates can leave machines vulnerable - use only on isolated lab networks
- **Scheduled Tasks**: Auto-freeze on startup should be used carefully
- **Intune/MDM**: May conflict with managed device policies

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License

MIT License - See [LICENSE](LICENSE) file

## 🙋 Support

Found a bug or have a feature request? [Open an issue](https://github.com/jonsortvedt-debug/expedition-toolkit/issues)

---

**Made for lab environments where stability matters more than updates** 🔬