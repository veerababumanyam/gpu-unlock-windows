# Third-party notices

This repository's own source code is licensed under the MIT License (see
[LICENSE](LICENSE)). That does not change the terms of software it downloads
or invokes at runtime.

## physicsdolphin/nv-uefi-unlocker

- Project: <https://github.com/physicsdolphin/nv-uefi-unlocker>
- Pinned release: `v2.1.10`
- License: **GPL-2.0-only**
- How it is used: `make-usbroot.ps1`, `assets-x86_64-windows.exe` and the
  release archive are downloaded from the upstream GitHub release at setup
  time and are **not** redistributed in this repository. The USB stick built by
  this tool contains those upstream components, so distributing that stick may
  create obligations under the GPL-2.0. Review the upstream license before
  redistributing a prepared stick.
- Upstream source and license:
  <https://github.com/physicsdolphin/nv-uefi-unlocker>

## NVIDIA firmware and driver software

- The upstream build downloads NVIDIA firmware/driver archives from NVIDIA.
- NVIDIA firmware and driver files are governed by NVIDIA's own license terms.
- This repository does not redistribute NVIDIA firmware. The download and
  hash verification happen locally during setup.

## Microsoft Windows components

- The status app uses Microsoft .NET Framework and Windows PowerShell, which
  are included with supported Windows versions and are governed by Microsoft's
  license terms.

## No warranty

The MIT warranty disclaimer applies to this project's own code. Upstream and
vendor components carry their own warranties and terms.
