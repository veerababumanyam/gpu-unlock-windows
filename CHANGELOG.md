# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `Register-ScheduledTask`/`Unregister-ScheduledTask` helpers shadowed the
  ScheduledTasks commands and recursed into themselves, so the `GpuUnlockStatus`
  logon check was never registered (and never removed). The helpers are renamed,
  and a registration failure now fails the install.
- `Unlock` imported its submodules with `-Global`, so the module exported no
  functions and `Remove-Module Unlock` left every command behind. Nested imports
  stay in module scope now.
- `setup.ps1` ignored non-zero child exits and the elevated child's exit code,
  then printed "Setup completed successfully". Failures now propagate.
- Apps & Features launched `Uninstall.ps1` directly instead of through
  `powershell.exe` and kept application files. It now runs
  `powershell.exe -File ... -Remove -Silent -Force`.
- The uninstall entry's `DisplayIcon` pointed at an icon the installer never
  creates; it now falls back to the system icon.
- Log rotation kept four files instead of the configured five; the helper is
  now `Invoke-LogRotation`, so importing the module no longer warns about an
  unapproved verb.
- `SETUP.cmd -WhatIf` no longer runs the application installer.
- The optional Pester suite now runs on Pester 5+: the module import moved into
  `BeforeAll` and the removed `Should -HaveProperty` operator was replaced with
  a portable property check.

## [2.1.0] - 2026-11-07

### Changed
- Module reorganized into `Unlock\` (`Unlock.psd1` + focused submodules) while
  keeping the same public functions.
- `SETUP.cmd` now self-elevates once so a double-click can prepare the stick and
  install the app.
- `-Interactive` is the default: the installer prompts to pick a drive when more
  than one removable volume is present and confirms FAT32 formatting.
- Windows application installs to `%ProgramFiles%\GPU Unlock`, with shortcuts,
  an elevated logon task, `Apps & Features` uninstall entry and `HKCU` settings.

### Fixed
- `Get-UnlockConfig` resolved the config one directory above the repository.
- `-Family all` was rejected by staging/stick parameter validation.
- Duplicate `WhatIf` parameter caused a metadata error in the installer scripts.
- Two module import paths pointed outside the repository.
- The uninstaller could not locate `Install-App.ps1`.
- Test runner no longer uses the PowerShell 7-only ternary operator, so it runs
  on the built-in Windows PowerShell 5.1.

## [1.0.0] - 2026-11-07

### Added
- One-time setup for NVIDIA tensor-rate unlock on Windows
- USB stick preparation with SHA-256 verified assets from physicsdolphin/nv-uefi-unlocker v2.1.10
- Support for RTX 20 (tu10x), RTX 30 (ga102), RTX 40 (ad102) GPU families
- Automatic UEFI boot execution with 5-second countdown abort window
- Windows status application (WinForms) with Desktop/Start Menu shortcuts
- Elevated logon background check via scheduled task (GpuUnlockStatus)
- CLI verification tool (verify.ps1) using ssdiag.exe
- Test suite (dependency-free `run-tests.ps1` and optional Pester)
- Documentation: README, BIOS-SETUP.md, TROUBLESHOOTING.md

### Security
- All downloads SHA-256 verified against upstream release manifest
- No ESP, NVRAM BootOrder, or VBIOS modifications
- USB stick removal = complete rollback
- Elevation only where required (ssdiag kernel mapping, status check)
