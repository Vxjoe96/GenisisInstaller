# Star Wars Genesis – Linux Installer

This project provides an **automated Linux installer** for the **Star Wars Genesis** Starfield modlist.  
It is designed to work on **Arch-based** and **Fedora-based** systems using Steam + Proton, with minimal user interaction and clear safety checks.

The installer handles dependency setup, Proton detection, installer downloads, safe symlink creation, and launches the modlist installer with guided next steps.

---

## Supported Platforms

| Distro | Status |
|------|------|
| Arch Linux / Arch-based | ✅ Supported (via `yay`) |
| Fedora | ✅ Supported (builds `proton-shim` from source) |
| Other distros | ❌ Not currently supported |

---

## Requirements

Before running the script, ensure you have:

- Steam installed
- **Starfield installed and launched at least once**
- Internet access
- A user account with `sudo` privileges

The script assumes:
- Bash
- Steam’s default library layout
- Proton Experimental available in Steam

---

## What the Script Does

1. Detects the system package manager (`yay` or `dnf`)
2. Installs required dependencies:
   - `proton-shim`
   - `fuse`
   - `zip`
   - build tools (Fedora only)
3. Locates the Starfield Proton prefix
4. Creates a symlink:
5. Downloads the **Star Wars Genesis installer** from a permanent GitHub release
6. Launches the installer using Proton
7. Displays clear, step-by-step instructions to complete setup in Jackify

The script **will not overwrite existing directories** without warning.

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/Vxjoe96/GenisisInstaller.git
cd GenisisInstaller
chmod +x install.sh
./install.sh
