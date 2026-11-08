# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.5] - 2026-11-08

### Added
- Register-level hardware audit for the local RTX 4080 SUPER:
  `docs/hardware/RTX-4080-SUPER-HARDWARE-AUDIT.md` and its printable PDF. It
  records the direct BAR0 reads behind the 16,384 MiB raw / 16,376 MiB usable
  VRAM split, the 8 MiB VBIOS reserve, the 329 MiB driver reserve, the live
  tensor selectors, the TPC floorsweep, and the PCIe/BAR/power limits.
- `docs/build-hardware-audit.py`, the maintainer script that rebuilds the audit
  PDF from the Markdown report.

## [2.2.4] - 2026-11-07

### Added
- `bench.ps1`: installs the benchmark's CUDA PyTorch into a per-user virtual
  environment (`%LOCALAPPDATA%\gpu-unlock-windows\bench\.venv`), reports
  `-Status`, and runs the BF16 GEMM. The environment is only accepted once
  `torch.cuda.is_available()` is true, and the resolved versions are recorded in
  `env.json`. No admin rights and no system-wide Python changes.
- `setup.ps1 -InstallBench` runs that install as part of a scripted setup.
- The status app gains a **Benchmark** button: it offers to install the missing
  environment and then shows the measured TFLOPS.
- `app\Install-App.ps1` now ships `bench.ps1` and `benchmark\` with the app, so
  the button works from the installed copy.

### Changed
- The benchmark's requirements are documented instead of implied: Python
  3.10-3.15 plus a multi-GB CUDA wheel, and explicitly nothing for the unlock or
  the status app. The old claim that setup downloads no extra runtimes was true
  and is now the actual behaviour plus a documented opt-in.

## [2.2.3] - 2026-11-07

### Fixed
- The status app reported `NOT UNLOCKED` with `SS0 = 0xbadf5040` on a card that
  ssdiag itself had just judged `UNLOCKED`. ssdiag prints the FEAT cluster of
  every GPU family on every chip, and the first `SS0 =` in the dump belongs to
  the window the die does not have; that window answers `0xbadf5040`
  (`PRIV_VIOLATION`, a refused read) by design. `ConvertFrom-SsdiagOutput` now
  takes the result from ssdiag's own `VERDICT` line and reports the SS pair of
  that family, so `verify.ps1`, the logon check and the status window agree with
  the diagnostic. The log line carries the detected family.
- Regression coverage for the cross-visibility dump: a real RTX 4080 SUPER
  capture (`tests\fixtures\ssdiag-ada-rtx4080s-live.txt`), plus Turing and
  locked-Ada cases in both the dependency-free and Pester suites.

## [2.2.2] - 2026-11-07

### Fixed
- USB preparation now validates the generated staging files **before** touching
  the stick, and backs up an existing `EFI/BOOT/BOOTX64.EFI` **before** a
  requested FAT32 format could erase it.
- The Turing gate record (`gsp-gate.txt`) is copied to the stick with the other
  verified files.
- A failed BitLocker query is reported as a warning instead of incorrectly
  saying BitLocker is not present.
- The uninstall wizard no longer falls back to `Install-App.ps1`, which cannot
  process the clean-stick options; it now reports a missing `Uninstall.ps1`
  clearly.

## [2.2.1] - 2026-11-07

### Added
- Printable PDF guide at `docs/GPU-Unlock-Guide.pdf`, with a maintainer build
  script at `docs/build-guide.py`.

### Changed
- The setup wizard and the status app's **Open guide** button now open the PDF
  guide. `TROUBLESHOOTING.md` remains as a fallback only.

### Fixed
- Start Menu shortcut creation failed on Windows PowerShell 5.1 because
  `Join-Path` was called with three positional paths. The directory and file
  are now joined separately, and the test suite guards against the pattern.

## [2.2.0] - 2026-11-07

### Added
- `SETUP.cmd` now opens a guided Windows-style wizard: system check, automatic
  GPU family detection, USB drive selection, FAT32 confirmation, progress log
  and a finish page with the BIOS instructions. The CLI `setup.ps1` remains.
- `UNINSTALL.cmd` and `app\UninstallWizard.ps1` provide a guided uninstall. The
  CLI uninstaller now removes the cache and installer logs, keeps the stick
  backup by default, and supports `-CleanStick` and `-RemoveBackups`.
- A Start Menu uninstall shortcut is created with the app.
- `THIRD-PARTY-NOTICES.md` documents the upstream GPL-2.0-only components and
  NVIDIA firmware terms.
- `tests/parse-all.ps1` parses every PowerShell file; the optional Pester suite
  runs on Pester 5+.
- The installed app now carries `VERSION`, `README.md`, `LICENSE` and the
  third-party notices.

### Changed
- This project's code is now **MIT licensed**. Downloaded upstream components
  remain under their own GPL-2.0-only and NVIDIA terms.
- Version 2.2.0 is read from `VERSION` instead of being duplicated in setup and
  installer scripts.
- `SETUP.cmd` is the wizard entry point; use `setup.ps1` for scripted installs
  or `install.ps1` to prepare a stick only.

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
