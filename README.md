# gpu-unlock-windows

One-time setup for an NVIDIA tensor-rate unlock on Windows. After setup: **keep
the USB stick connected and restart** — the unlock runs automatically before
Windows, and a status app confirms it once Windows is up. Remove the stick and
Windows boots normally.

## For non-technical users

1. Double-click **`SETUP.cmd`**.
2. Approve the Windows prompt (it installs the status app + USB stick prep).
3. Do the one-time BIOS step in [docs/BIOS-SETUP.md](docs/BIOS-SETUP.md):
   set the stick (`UEFI: ...`) first in the boot order.
4. Restart with the stick connected. That's it.

From then on:

- **Stick in + restart** → automatic unlock → Windows starts.
- **Stick out** → normal Windows, no unlock.
- **GPU Unlock** (Desktop / Start Menu) shows a green **UNLOCKED** or a
  red **NOT UNLOCKED** with what to do. At every login a background check warns
  you only if something is wrong.

## Why there is a USB stick

The unlock must execute *before* the NVIDIA driver loads; it is a UEFI
pre-driver transaction, not a Windows program. Nothing installed inside Windows
can replace that step. This project wraps the verified, source-available
[physicsdolphin/nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker)
and automates everything around it.

## What SETUP.cmd does

| Step | Detail |
| --- | --- |
| Preflight | UEFI, Secure Boot off, Fast Startup, BitLocker, GPU/BDF |
| Download | Pinned release v2.1.10, every file hash-verified against `SHA256SUMS.txt` |
| Assets | Builds **all supported families** (`ad102` RTX 40, `ga102` RTX 30, `tu10x` RTX 20) onto one stick |
| Stick | **Auto-detects file system; formats to FAT32 if needed (with confirmation)**; backup of existing `EFI/BOOT/BOOTX64.EFI`, copy + SHA-256 verify |
| Automation | `i_know_what_i_am_doing.txt` (5 s auto-run, any key aborts) + `tx-quiet.txt` |
| App | Desktop/Start Menu shortcut + elevated logon check (task `GpuUnlockStatus`) + uninstaller in Apps & Features |

Useful switches:
```
SETUP.cmd -Interactive          # Prompt for drive selection & format (default)
SETUP.cmd -Stick E:             # Use specific drive, still interactive
SETUP.cmd -FormatStick -ConfirmFormat -Stick E:  # Fully non-interactive
SETUP.cmd -Uninstall            # Complete removal
SETUP.cmd -InstallApp -InstallStick  # Install both (default)
SETUP.cmd -InstallApp           # Install only Windows app
SETUP.cmd -InstallStick         # Prepare only USB stick
```

## Supported hardware

RTX 20 (Turing), RTX 30 (Ampere), RTX 40 (Ada) are all built onto the stick and
routed by the loader at runtime. GTX 16 is experimental upstream and not in the
`all` build. Blackwell (RTX 50) is not supported.

## Verification

- Status app: `SS0 = 0x88888888` and SS1 low nibble `0x8` means active.
- CLI: `.\verify.ps1 -Elevate`.
- The unlock is **volatile**: it is re-applied on every restart with the stick.
  Sleep/power loss can clear it; restart with the stick.
- Gains are FP16/BF16/TF32 with FP32 accumulate (roughly 1.5–2x tensor rate).
  FP32, INT8/INT4 and gaming are unchanged.

## Files

| Path | Purpose |
| --- | --- |
| `SETUP.cmd` | Double-click entry point (self-elevates) |
| `setup.ps1` | Main setup orchestrator (USB + App) |
| `install.ps1` | USB stick preparation |
| `Unlock\` | PowerShell module (`Unlock.psd1` + functional submodules) |
| `Uninstall.ps1` | Complete uninstaller |
| `verify.ps1` | CLI check |
| `app/GpuUnlock.ps1` | Status window / logon check |
| `app/Install-App.ps1` | Full Windows installer (shortcuts, task, registry, uninstaller) |
| `tests/run-tests.ps1` | Assertion suite (no external dependencies) |
| `tests/parse-all.ps1` | Syntax check for every PowerShell file |
| `tests/run-tests.Pester.ps1` | Optional Pester 5+ suite |
| `TROUBLESHOOTING.md` | Symptom → fix |
| `docs/BIOS-SETUP.md` | The one-time firmware step |

## Recovery

If the screen stays black or Windows does not start: power off, remove the
stick, boot normally. No ESP, BootOrder or VBIOS changes are made. Keep
`loader.log` from the stick root. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## License

GPL-2.0-only. The upstream tool and NVIDIA firmware terms are downloaded with
the release; firmware is never redistributed here.

