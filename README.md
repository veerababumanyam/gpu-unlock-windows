# gpu-unlock-windows

Automated Windows installer for the NVIDIA tensor-rate unlock, with preflight
checks, pinned release verification, USB media preparation, and post-boot
verification.

This repo **does not reimplement the unlock**. The unlock is a UEFI pre-driver
transaction (it must run before Windows loads `nvlddmkm`), so it cannot be done
by installing something in Windows. This repo wraps the verified, source-available
tool [physicsdolphin/nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker)
and automates everything around the one physical step: booting the prepared USB
once.

## What it does

1. **Preflight** — UEFI firmware, Secure Boot off, Fast Startup, BitLocker,
   the NVIDIA GPU and its bus ID. Fails with actionable text instead of writing
   a broken stick.
2. **Pinned download** — release `v2.1.10` plus `SHA256SUMS.txt`; every member
   is hash-verified before use. `ssdiag` is fetched and verified separately.
3. **Asset generation** — runs the release's own `make-usbroot.ps1` for the
   detected family (`ad102` for RTX 40, `ga102` for RTX 30, `tu10x` for RTX 20/16),
   downloading the pinned NVIDIA firmware inputs.
4. **USB media** — detects a removable FAT32 volume, backs up an existing
   `EFI/BOOT/BOOTX64.EFI`, copies only the required assets, and verifies every
   copied file by SHA-256.
5. **Verification** — `verify.ps1` runs `ssdiag` elevated and parses `SS0`/`SS1`
   into a pass/fail verdict.

## Quick start

```powershell
# from this folder
.\install.ps1                 # auto-detect GPU, build assets, write the stick
# Restart -> F12 -> UEFI: <stick> -> Space/Enter
.\verify.ps1 -Elevate         # after Windows is back
```

Useful switches:

| Switch | Effect |
| --- | --- |
| `-Stick F:` | Pick the volume explicitly (required if several are inserted) |
| `-Family ad102` | Override auto-detection |
| `-NoStick` | Generate and verify assets only |
| `-DryRun` | Preflight + detection only, no download/copy |
| `-FormatStick -ConfirmFormat` | Format a non-FAT32 stick (erases it) |

## Hardware support

RTX 20 (Turing), RTX 30 (Ampere), RTX 40 (Ada) are routed by the upstream tool.
This installer was exercised on an RTX 4080 SUPER (`10de:2702`) / Z790 / Windows 11.
Blackwell (RTX 50) is unsupported by the upstream tool and is rejected here.

## Verification and expectations

- `verify.ps1` success means `SS0 = 0x88888888` and SS1 low nibble `0x8`.
- The unlock is **volatile**: replay it on every cold boot or power loss. Sleep
  may also clear it. That is inherent to a register-only unlock.
- Gains apply to FP16/BF16/TF32 with FP32 accumulation (roughly 1.5–2x tensor
  rate, workload dependent). FP32, INT8/INT4 and gaming are unchanged.
- `benchmark/bench.py` optionally measures BF16 GEMM if PyTorch is installed.

## Recovery

Do not retry in the same session. Fully power off, remove the stick, boot the
normal Windows entry. This workflow does not modify the ESP, BootOrder or VBIOS.
Keep `loader.log` from the stick root for diagnosis.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for symptom-based fixes and the
manual recipe for booting from an internal FAT32 partition instead of the stick.

## License

The wrapper scripts are GPL-2.0-only. The upstream tool is GPL-2.0-only; its
license and notices are downloaded with the release under `%LOCALAPPDATA%`.
