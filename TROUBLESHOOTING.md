# Troubleshooting

Symptom-oriented. Most entries come from the upstream project's FAQ and are
reproducible field reports, not guesses.

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Stick flashes and returns to the boot menu, or boots straight to Windows; no `loader.log` | The EFI never ran | Check, in order: `EFI\BOOT\BOOTX64.EFI` exists (not a flat `BOOTX64.EFI` at root, not `U:\usbroot\...`); Secure Boot is off; you picked the **`UEFI:`** entry, not a CSM one; the stick is FAT32. No `loader.log` = nothing was written. |
| Black screen or frozen image during the transaction | GOP detach | Normal. Wait; the loader restores the display or chains to Windows. Do not power off mid-transaction unless it is clearly stuck. |
| Windows shows Recovery `0xc000009a` after a green log | v2.1.10 keeps the asset cache across the chain | Put an empty file `tx-free-assets.txt` at the stick root and replay. (v2.1.11 frees it by default.) |
| `0xc000000f` / `0xc0000225` | Two ESPs, chain took the stale one | v2.1.10 resolves by partition identity; update if you built an older tag. |
| Stuck with CSM enabled | CSM boot path | Turn CSM off in firmware and use the `UEFI:` entry; #107 documents the CSM-on GOP behaviour. |
| `MAP_PHYS win32 error 5` from ssdiag | HVCI or a kernel-mode AV filter holds the mapping | 0.6.3+ prints the precondition breakdown. Pausing user-mode AV is not enough; remove/disable the kernel filter or HVCI, reboot. |
| Antivirus flags `ssdiag.exe` | Embedded kernel driver, unsigned host | Expected; it ships as a separate asset for this reason. Restore from quarantine. |
| Gate open but SS values wrong | Selectors reverted | `ssdiag --reapply` (writes SS0/SS1 only behind an open gate; does not write PLM). |
| Status app says `NOT UNLOCKED` while the dump contains `VERDICT [ada]: UNLOCKED` | Older builds parsed the first `SS0 =` in the dump, which belongs to the other family's register window and answers `0xbadf5040` there | Update to 2.2.3+ and re-run `SETUP.cmd -InstallApp`. `0xbadf5040` is `PRIV_VIOLATION` - the die refused the read; on the non-native window it is expected, not a lock state. |
| Unlocked but no speedup | Power wall, quantized path, or workload not using FP32-accumulate tensor | Verify SS0/SS1 first. BF16/FP16/TF32 with FP32 accumulate move; INT8/INT4/FP32 and decode-bound workloads do not. |
| Benchmark says PyTorch is not installed | The benchmark environment is opt-in and multi-GB, so setup never downloads it silently | Run `.\bench.ps1 -Install`, or click **Benchmark** in the status app and answer `y`. The unlock and the status app do not need it. |
| `bench.ps1` finds no supported Python | PyTorch needs CPython 3.10-3.15 | Install Python from python.org, or pass `-Python C:\path\python.exe`. 3.16+ has no wheels yet. |
| Torch installed but `torch.cuda.is_available()` is False | CPU-only wheel, or driver older than the CUDA runtime in the wheel | `.\bench.ps1 -Status` prints the runtime; reinstall with `.\bench.ps1 -Install` (CUDA index pinned in the script) and update the NVIDIA driver. |
| Unlock gone after sleep or power loss | Volatile register state | Expected. Replay the stick. |
| Board powers off at image handoff | Board-specific chain failure | #128 (ASUS B760M) is closed by v2.1.10; update and retry. If it persists, archive `loader.log` and report upstream with board/BIOS. |
| SETUP.cmd says "Multiple removable volumes" | More than one USB drive inserted | Remove extra drives, or run with `-Interactive` to pick the correct one. |
| SETUP.cmd refuses to format stick | Stick is not FAT32 and `-FormatStick -ConfirmFormat` not passed | Re-run with `-FormatStick -ConfirmFormat` to auto-format, or use `-Interactive` to confirm interactively. |
| "GPU Unlock" not in Start Menu | Install-App.ps1 failed or was skipped | Run `SETUP.cmd -InstallApp` as Administrator |
| Scheduled task not running | Task Scheduler disabled or permissions | Check Task Scheduler > Task Scheduler Library > GpuUnlockStatus |
| ssdiag.exe not found | App not installed or install incomplete | Run `SETUP.cmd -InstallApp` as Administrator |
| Uninstaller not in Apps & Features | Install-App.ps1 didn't run elevated | Re-run `SETUP.cmd -InstallApp` as Administrator |

## Windows Application Issues

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Status window won't open | .NET Framework / PowerShell issue | Install .NET 4.7.2+ (built into Win10/11) |
| "Not elevated" in log | Scheduled task lost highest privilege | Re-run `SETUP.cmd -InstallApp` as Administrator |
| Log file growing large | Rotation keeps five files of up to 5 MB | Check `%LOCALAPPDATA%\gpu-unlock-windows\status.log`; delete old `.1`–`.5` files if needed |
| Uninstaller doesn't remove all files | Files in use or permissions | Close GPU Unlock window, run `SETUP.cmd -Uninstall` as Admin |

## Persistent boot without a USB stick (expert)

The upstream project documents but deliberately does not automate this. At your
own risk:

1. Shrink a data volume by ~2 GB (keep the space unallocated or create a FAT32
   partition; it must be FAT32).
2. Copy the stick contents to that partition, preserving `EFI\BOOT\BOOTX64.EFI`.
3. Reboot into the firmware boot menu and pick the entry shown as `UEFI OS` (or
   the volume label). Set it first only if you accept editing boot order.

It is reversible from the firmware boot menu; nothing is flashed. Keep the USB
stick as a fallback.

## Safety

- Do not retry after a fault in the same session: power off fully first.
- This workflow does not touch the ESP, NVRAM BootOrder or VBIOS.
- If the module/loader reports firmware did not stop, power off before retrying.
