# One-time BIOS setup (makes it automatic)

The unlock runs before Windows starts, so the firmware must boot the USB stick
first. Windows cannot change that boot order reliably; it is a one-time firmware
setting. After it, everything is automatic.

## Gigabyte Z790 GAMING X AX (this machine)

1. Keep the USB stick connected.
2. Start > Power > **Restart** (or power on). Press **Del** at the Gigabyte logo
   to enter BIOS. (F2 also works on most builds.)
3. Open the **Boot** tab.
4. In **Boot Option Priorities**, set **Boot Option #1** to the stick's
   **`UEFI:`** entry (e.g. `UEFI: SanDisk Ultra`). Leave Windows Boot Manager
   as #2.
5. If present, set **CSM Support = Disabled** and confirm **Secure Boot = Disabled**.
   (This machine already has Secure Boot off.)
6. Press **F10**, save, and exit.

## What happens from then on

- **Stick connected + restart** → firmware boots the stick → the loader waits
  5 seconds (any key aborts) → unlocks the card → chains into Windows.
- **Stick removed** → firmware falls through to Windows Boot Manager → normal
  boot, no unlock (and the app will say "NOT UNLOCKED").

No F12 press, no Space press, no key sequence.

## Aborting

- During the 5-second countdown: press any key to abort back to the boot menu.
- Before restarting: remove the stick.

## If the stick is not listed

- Use a **rear** USB port (chipset port, not a front-panel or hub).
- The stick must be **FAT32** with `EFI\BOOT\BOOTX64.EFI` (SETUP.cmd does this).
- Disable **Fast Boot** so USB devices are enumerated.
- Disable **CSM** if the entry only appears as legacy/non-`UEFI:`.

## To undo

Either remove the stick, or set **Boot Option #1** back to
**Windows Boot Manager**. Nothing is flashed and no Windows boot entry is
modified, so removing the stick is always a safe fallback.
