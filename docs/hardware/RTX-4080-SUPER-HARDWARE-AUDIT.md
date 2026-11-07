# RTX 4080 SUPER — physical VRAM, tensor-rate and lock audit

**Report ID:** `GPU-HW-2026-11-07-4080S` | **Date:** 2026-11-07 17:52 CET | **Target:** NVIDIA GeForce RTX 4080 SUPER, AD103, `10de:2702` | **Audit type:** read-only BAR0 MMIO register audit
**Result:** **PASS — 16 GiB physical; 16,376 MiB usable; 8 MiB VBIOS reserve; tensor-rate override live.**

| Document control | |
|---|---|
| Prepared for | Local workstation |
| Prepared by | Hardware audit using `ssdiag` 0.6.14 and the signed `pmxdrv.sys` BAR0 transport |
| GPU | NVIDIA GeForce RTX 4080 SUPER, AD103, `10de:2702` |
| PCI address | `0000:04:00.0` |
| VBIOS | `95.03.44.00.4e` |
| Board / GPU part | `0x400` / `2702-400-A1` |
| Host platform | Gigabyte Z790 GAMING X AX, BIOS F14, Intel i9-14900K, 96 GiB DDR5 |
| OS | Windows, kernel `10.0.26300` |
| Evidence | [`evidence/ssdiag-live.txt`](evidence/ssdiag-live.txt), [`evidence/hardware-snapshot.txt`](evidence/hardware-snapshot.txt) |
| Audit scope | VRAM capacity and reservations, tensor-rate selectors, TPC floorsweep, PCIe/BAR/power limits |
| Out of scope | Stress testing, memory integrity testing, VBIOS modification, TPC enablement |

---

## 1. Executive summary

This card is a **16 GiB RTX 4080 SUPER**. The physical GDDR6X population is 16,384 MiB. The VBIOS publishes **16,376 MiB** as usable framebuffer, withholding **8 MiB**. The Windows driver additionally reserves **329 MiB**, leaving **16,047 MiB** visible to applications. There is **no hidden 24 GB or 32 GB pool** behind a fuse, WPR window, or driver lock.

The tensor-rate override is **currently active**: `FEAT_PLM = 0xffffffff`, `SS0 = 0x88888888`, `SS1 = 0x00000008`, `READOUT_1 = 0x00000000`. The card has **40 active TPCs / 80 SMs / 320 tensor cores**; GPC3 has 2 TPCs (4 SMs / 16 tensor cores) disabled by binning. That TPC cut is **not** the tensor-rate limiter and has no supported enable path.

Two platform limits matter more than any remaining GPU “lock”:

- **PCIe is electrically x4**, not x16. The card is on the PCH root port `00:1c.4`; it trains Gen1 x4 at idle and can train Gen4 x4, but never x16 in this slot.
- **BAR1 is 256 MiB of a 16 GiB-capable aperture.** Re-Size BAR is not enabled. This is a CPU mapping window, not lost VRAM.

The 320 W power limit is a VBIOS power-table cap. It limits sustained tensor gains but is not a fuse and is not part of the tensor unlock.

### 1.1 Headline numbers

| Question | Answer |
|---|---:|
| Raw GDDR6X population | **16,384 MiB (16 GiB)** |
| VBIOS usable FB | **16,376 MiB** |
| VBIOS/hardware reserve | **8 MiB (0.049%)** |
| Driver/WDDM reserve at snapshot | **329 MiB** |
| Application-visible total | **16,047 MiB (15.67 GiB)** |
| Hidden/unlockable extra VRAM | **0 MiB** |
| Tensor-rate lock | **Open / full rate** |
| Active tensor hardware | **40 TPC / 80 SM / 320 tensor cores** |
| Disabled TPCs | **2 TPC / 4 SM / 16 tensor cores** in GPC3 |
| CPU-visible VRAM aperture | **256 MiB** (BAR1; 16 GiB capable) |
| PCIe | **Gen4 x16 capable, x4 electrical** |
| Power limit | **320 W** |
| ECC | **Off** |
| MIG | **N/A** |

---

## 2. Scope and method

### 2.1 Why direct BAR0 reads

`nvidia-smi` and NVAPI report the driver's view. That is useful for live used/free memory, but it is not authoritative for physical capacity or hardware reservations. This audit reads the GPU's own BAR0 registers through a kernel mapping and interprets them using NVIDIA's published register semantics.

### 2.2 Measurement chain

1. `ssdiag` 0.6.14 was built from source (`tools/ssdiag` in the upstream project).
2. It embeds the Intel-signed, hash-pinned `pmxdrv.sys`, loads it as a demand-start service for the probe, maps the GPU's physical BAR0, and removes the service on exit.
3. The local build was instrumented with one extra read: `NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE` at BAR0 offset `0x100ce0`. Upstream 0.6.14 does not print this register.
4. `nvidia-smi` was used only as a secondary cross-check of the live memory split and PCIe/power state.
5. The audit performed **no GPU register writes**. The tensor override was already live from the user's USB boot; this audit only read it.

The temporary kernel driver is visible to EDR/anti-cheat as a service install (SCM event 7045), even though it is removed on exit. That is a property of this measurement method, not of the card.

### 2.3 Register semantics

The interpretation was checked against NVIDIA's open-source kernel module source, not inferred from the driver's displayed numbers:

- `kmemsysReadUsableFbSize_GA102` reads `NV_USABLE_FB_SIZE_IN_MB` at `0x1183a4` and states: *“VBIOS Devinit calculates the usable FB size calculated and published in NV_USABLE_FB_SIZE_IN_MB.”*
- `kmemsysReadUsableFbSize_GP102` reads `NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE` at `0x100ce0`, decodes `LOWER_MAG << (LOWER_SCALE + 20)`, and applies `15/16` only when the ECC bit is set.

That is why 16,384 MiB and 16,376 MiB are both correct: one is the raw MMU local-memory range, the other is the VBIOS-declared usable FB after its carveout.

---

## 3. Target identity

| Property | Value |
|---|---|
| Marketing name | NVIDIA GeForce RTX 4080 SUPER |
| Architecture | Ada Lovelace, AD103 |
| PCI vendor/device | `10de:2702` |
| Subsystem | `1569:f304` |
| PCI address | `0000:04:00.0` |
| VBIOS | `95.03.44.00.4e` |
| Board ID | `0x400` |
| GPU part number | `2702-400-A1` |
| CUDA compute capability | 8.9 |
| Active SMs | 80 |
| Active tensor cores | 320 |
| Memory bus | 256-bit |
| Reported power limit | 320 W (min 150 W, max 320 W) |

The GPU is a display-class function on the Intel PCH root port `00:1c.4` (`8086:7a3c`), not on the CPU PEG port.

---

## 4. Raw register evidence

All values below are direct BAR0 reads from the audit run. The full dump is in [`evidence/ssdiag-live.txt`](evidence/ssdiag-live.txt).

| Register | BAR0 offset | Raw value | Meaning |
|---|---:|---:|---|
| `NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE` | `0x100ce0` | `0x00000209` | `LOWER_MAG=32`, `LOWER_SCALE=9`, `ECC=0` → **16,384 MiB** |
| `NV_USABLE_FB_SIZE_IN_MB` | `0x1183a4` | `0x00003ff8` | **16,376 MiB** usable FB |
| `WPR2_LO` | `0x1fa824` | `0x1ffffe00` | empty-window default |
| `WPR2_HI` | `0x1fa828` | `0x00000000` | **no active WPR2 window** |
| `MMU_LOCK_LO` | `0x1fa82c` | `0x1ffffff0` | empty lock window |
| `MMU_LOCK_HI` | `0x1fa830` | `0x00000000` | **no active MMU lock window** |
| `VGA_WORKSPACE` | `0x625f04` | `0x00000001` | VGA workspace flag set |
| `PSTRAPS_SET0` | `0x101000` | `0x00400080` | BAR straps |
| `PSTRAPS_SET1` | `0x10100c` | `0x02013000` | BAR straps |
| `FEAT PLM` | `0x823800` | `0xffffffff` | **OPEN** |
| `FEAT SS0` | `0x82381c` | `0x88888888` | all rate fields at full-rate value |
| `FEAT SS1` | `0x823820` | `0x00000008` | low nibble `8` |
| `FEAT READOUT_1` | `0x823818` | `0x00000000` | **full speed, no throttle fields** |
| `WPR_PLM` | `0x1fa7c4` | `0x0004cb8f` | closed |
| `WPR_CFG_PLM` | `0x1fa7cc` | `0x0004cb8f` | closed |
| `FBPA_PLM` | `0x9a0148` | `0xffffff0f` | closed |
| `MMU_PLM` | `0x1fa7c8` | `0x0045cb8f` | closed |
| `FUSE_OPT_FEATURE_OVR` | `0x8203f0` | `0x00000000` | override path not blocked here |
| `FUSE_VER` | `0x824140` | `0x00000001` | fuse version 1 |
| `OPT_GPC_DISABLE` | `0x9a014c` | `0x00000000` | no GPC-level disable fuse |
| `OPT_GPC_DEFECTIVE` | `0x9a0168` | `0x00000000` | no GPC-level defect fuse |
| `DISABLE_FUSE_PROG` | `0x82007c` | `0xbadf5040` | `PRIV_VIOLATION` (not readable at this level) |

### 4.1 Decoding `LOCAL_MEMORY_RANGE`

```text
raw          = 0x00000209
LOWER_MAG    = (raw >> 4) & 0x3f = 32
LOWER_SCALE  = raw & 0xf        = 9
ECC          = (raw >> 30) & 1  = 0
bytes        = 32 << (9 + 20)   = 0x400000000
             = 17,179,869,184 bytes
             = 16,384 MiB
```

Because ECC is off, the `15/16` correction does not apply.

### 4.2 Why 16,384 and 16,376 are both real

| Value | Source | Interpretation |
|---:|---|---|
| 16,384 MiB | `LOCAL_MEMORY_RANGE` | raw MMU local-memory range |
| 16,376 MiB | `NV_USABLE_FB_SIZE_IN_MB` | VBIOS-declared usable FB after its carveout |
| 8 MiB | difference | VBIOS/firmware reserve |

The VBIOS does not publish a “raw minus reserve” breakdown in these registers. The 8 MiB is a measured difference, not a named field.

---

## 5. VRAM accounting

| Slice | MiB | GiB | % of raw | Nature |
|---|---:|---:|---:|---|
| Raw GDDR6X population | 16,384 | 16.000 | 100.000% | 8 × 2 GiB packages |
| VBIOS usable-FB ceiling | 16,376 | 15.992 | 99.951% | `NV_USABLE_FB_SIZE_IN_MB` |
| **VBIOS/hardware reserve** | **8** | **0.0078** | **0.049%** | not in the usable-FB register |
| Driver/WDDM reserved | 329 | 0.321 | 2.008% | software reservation |
| **Application-visible total** | **16,047** | **15.672** | **97.942%** | 16,376 − 329 |
| Used at 17:52 snapshot | 13,250 | 12.939 | 80.872% | desktop/apps, transient |
| Free at 17:52 snapshot | 2,798 | 2.732 | 17.078% | transient |

`nvidia-smi` reported `16376 / 329 / 13250 / 2798 MiB` at the same time. The one-MiB rounding in `329 + 13250 + 2798 = 16377` is normal MiB rounding in NVAPI.

### 5.1 What the 8 MiB is — and is not

- **Not WPR2.** `WPR2_HI = 0` means no window is active. `WPR2_LO = 0x1ffffe00` is the documented empty-window default. Reading `0x1ffffe00` as “512 MiB locked” is a misread.
- **Not ECC.** ECC is off (`LOCAL_MEMORY_RANGE` ECC bit = 0), and NVAPI reports ECC N/A.
- **Not a fixed 1 MiB VGA hole.** The VGA workspace flag is set, but the withheld amount scales with capacity: 8 GiB field captures report 8,188 MiB (4 MiB withheld), 6 GiB captures report 6,141 MiB (3 MiB withheld), and this 16 GiB board reports 16,376 MiB (8 MiB withheld). That is exactly **1/2048 of raw capacity** in each case.
- **A capacity-scaled VBIOS/firmware carveout.** The register only publishes the usable value; it does not name the consumer. The safe conclusion is: 8 MiB is unavailable as framebuffer and is not recoverable by the tensor unlock.

### 5.2 What the 329 MiB is

`nvidia-smi`'s “Reserved” is the WDDM/KMD reservation: driver internal allocations, page tables, display/scanout and protected structures. It is software, not physically dead DRAM. It can change with driver version, display topology and mode. It is not a hardware lock and cannot be reclaimed by a register write.

### 5.3 Is any VRAM “locked”?

| Definition | Amount | Verdict |
|---|---:|---|
| Physically absent | 0 MiB beyond 16 GiB | No hidden capacity |
| VBIOS/hardware reserve | **8 MiB** | Real, not unlockable |
| Driver/WDDM reserve | **329 MiB** | Software accounting; not a fuse |
| BAR1 CPU aperture | **256 MiB mapped of 16 GiB** | Mapping window, not lost VRAM |
| WPR2 protected window | **0 MiB active** | Empty at audit time |
| ECC reserve | **0 MiB** | ECC off |

The only true hardware reservation is **8 MiB**. The 329 MiB is software; the 256 MiB BAR1 is an aperture.

---

## 6. Tensor-rate state

The card is **unlocked at the time of the audit**:

```text
FEAT PLM       = 0xffffffff   OPEN
FEAT SS0       = 0x88888888   all eight decoded rate fields = 0 (override + full rate)
FEAT SS1       = 0x00000008   low nibble = 8
FEAT READOUT_1 = 0x00000000   full speed
VERDICT [ada]: UNLOCKED (override values live)
```

The tool's `SS0` decode is `[0* 0* 0* 0* 0* 0* 0* 0*]`. In its field semantics, `0` means override plus full rate; locked states carry non-zero fractional fields. `READOUT_1 = 0` means none of the compute-throttle fields are set.

This is a **rate-selector override**, not an overclock and not a VRAM change:

- It removes the half-rate clamp on the FP32-accumulate tensor paths: FP16, BF16, TF32 and the FP8 path in the same family.
- FP16-with-FP16-accumulate already runs full rate and is a control (no gain).
- FP32 SIMT and the tested INT8/cuBLAS path are unaffected.
- The override is volatile across a full power loss. Sleep/FLR behavior varies by platform; a cold boot requires replaying the USB stage.

### 6.1 What the rate actually is

- Active tensor hardware: **80 SM × 4 tensor cores = 320 tensor cores**.
- Unlocked FP16/BF16 dense rate law: **1,024 FLOP/SM/clk** for the FP32-accumulate path; locked is **512 FLOP/SM/clk**.
- At the card's 2.55 GHz rated boost: `80 × 1024 × 2.55 ≈ 208.9 TFLOPS` FP16/BF16 dense.
- The published same-die `2702` measurement is **101.0 TFLOPS locked → 202.7 TFLOPS unlocked (2.01×)** for FP16/BF16 FP32-accumulate, with the FP16-accumulate control flat at 1.00×. The live selector read matches the unlocked state.
- At the 320 W board limit, sustained cuBLAS gains are typically lower (about **1.66–1.78×** on 4080 SUPER reports) because the doubled toggle rate reaches the power wall. The 2.01× figure is the short-burst/raw-pipeline ceiling.

**No fresh CUDA GEMM was run in this audit.** The 202.7 TFLOPS number is a same-die reference measurement; the live `SS0/SS1/READOUT_1` values are direct hardware reads from this card.

---

<!-- pagebreak -->

## 7. Tensor hardware and TPC floorsweep

`ssdiag` read the per-GPC effective TPC masks (`STATUS`, bit n = TPC n of that GPC):

```text
GPC0 6/6   GPC1 6/6   GPC2 6/6   GPC3 4/6 (TPC4,TPC5 off)
GPC4 6/6   GPC5 6/6   GPC6 6/6   GPC7 0/6 (unused eighth slot)
```

| Item | Count |
|---|---:|
| Active TPCs | **40** |
| Active SMs | **80** |
| Active tensor cores | **320** |
| GPC3 disabled TPCs | **2** |
| GPC3 disabled SMs | **4** |
| GPC3 disabled tensor cores | **16** |

`OPT_GPC_DISABLE = 0` and `OPT_GPC_DEFECTIVE = 0`. The tool reports no defect bit on the disabled TPCs and labels them “override candidates (write path out of scope).”

### 7.1 Interpreting GPC7 and the 8-TPC verdict

The tool's generic verdict says “8 TPCs fused off in 2 GPCs” because it counts the all-off GPC7 slot. AD103 is a 7-GPC/80-SM-class die; GPC7 is the unused eighth register slot, not 12 recoverable SMs. The real binning cut is the **2 TPCs in GPC3**.

This is **die binning**, not the tensor-rate lock. There is no supported or validated write path to turn those 2 TPCs on. Treat any such attempt as experimental and potentially destabilizing; it is not part of this unlock.

---

## 8. Platform limits

### 8.1 BAR1 / Resizable BAR

Config space reports:

```text
BAR1 supported [16G/8G/4G/2G/1G/512M/256M/128M/64M] current 256 MiB (size_idx 8)
```

Only **256 MiB of the 16 GiB** is mapped into the CPU's PCIe BAR window. The card supports a 16 GiB BAR1; the current 256 MiB setting is a firmware/BIOS configuration (Above 4G Decoding / Re-Size BAR). Enabling ReBAR would make the full VRAM CPU-visible, but it would **not** add a byte of VRAM or change the 16,376 MiB usable ceiling.

### 8.2 PCIe link

```text
LnkCap max Gen4 x16 | LnkSta Gen1 x4 (downgraded)
```

The GPU is on Intel PCH root port `00:1c.4` (`8086:7a3c`), not the CPU PEG port. At idle the link drops to Gen1 (normal power saving); the **x4 width is the real limitation**. The card can do Gen4 x16, but this slot/riser is wired x4. That is a platform bandwidth bottleneck, not a GPU lock. Moving the card to the CPU x16 slot, or replacing an x4 riser/adapter, is the fix.

### 8.3 Power limit

NVAPI reports 320 W current/default, min 150 W, max 320 W. This is a VBIOS power-table cap, not a hardware fuse. It limits sustained tensor gains; changing it requires a VBIOS/power-table modification, not the tensor unlock.

### 8.4 ECC and MIG

ECC is off (`ECC=0` in `LOCAL_MEMORY_RANGE`; NVAPI N/A). MIG is N/A on this GeForce SKU. Neither consumes a hidden VRAM pool here.

---

## 9. What can and cannot be unlocked

| Item | Status | Can it be unlocked? |
|---|---|---|
| Tensor-rate selectors | **Open** (`PLM=0xffffffff`, `SS0=0x88888888`, `SS1=0x8`) | Already unlocked; volatile, replay after cold boot |
| VBIOS 8 MiB reserve | Withheld | No; outside the usable-FB ceiling |
| WDDM 329 MiB reserve | Software | No register unlock; may change with driver/display configuration |
| BAR1 256 MiB aperture | Firmware setting | Yes, via BIOS ReBAR; does not add VRAM |
| GPC3 TPC4/TPC5 | Binning | No supported path; experimental only |
| GPC7 | Unpopulated slot | No; not 12 real SMs |
| 320 W power cap | VBIOS | VBIOS/power-table modification only |
| PCIe x4 | Platform wiring | Move to CPU x16 slot or replace riser |
| WPR/FBPA/MMU PLMs | Closed | Not opened by the tensor unlock; no capacity gain |
| ECC reserve | Off | No reserve to reclaim |
| MIG | N/A | Not applicable |

### 9.1 Can more VRAM be unlocked?

**No.** The physical population is 16 GiB (8 × 2 GiB GDDR6X). The card exposes 16,376 MiB as usable FB and 16,047 MiB to applications after the driver reserve. The 8 MiB is a VBIOS/firmware carveout; the 329 MiB is a driver reservation. There is no 24 GB/32 GB array behind a fuse, and no register in this dump represents an additional capacity pool.

The “32 GB RTX 4080 SUPER” cards in circulation are physical mods with different memory packages, not a software unlock.

---

## 10. Evidence quality and limitations

| Claim | Evidence | Confidence |
|---|---|---|
| Raw 16,384 MiB / usable 16,376 MiB | BAR0 MMIO + NVIDIA register semantics | High |
| 8 MiB VBIOS reserve | Difference of two hardware registers | High for amount; medium for purpose |
| 329 MiB driver reserve | NVAPI snapshot | Medium (software accounting) |
| Tensor override live | BAR0 `PLM/SS0/SS1/READOUT_1` | High |
| 40 TPC / 80 SM / 320 tensor cores | BAR0 TPC map + CUDA SM count | High raw; medium interpretation |
| PCIe x4 | PCI config space `LnkSta` | High |
| 320 W limit | NVAPI | Medium (secondary) |
| Used/free memory | NVAPI snapshot | Low/transient |

### 10.1 Limitations

- The 8 MiB VBIOS reserve is measured as a difference; the register does not name its consumer. The 1/2048 pattern across 6/8/16 GiB field captures is strong evidence of a capacity-scaled firmware carveout, but the exact purpose is not documented in these registers.
- The TPC interpretation uses the AD103 7-GPC/80-SM topology and the live 80-SM CUDA report. The raw `STATUS` words are hardware reads; the “GPC7 is unpopulated” reading is an inference from the SKU topology, not a separate fuse read.
- No fresh CUDA GEMM was run. The 202.7 TFLOPS figure is a same-die reference measurement; the live selector values are direct hardware reads.
- Current used/free numbers are a transient desktop snapshot. Close applications for a clean free-VRAM measurement.
- The audit did not test memory integrity, ECC, overclocking, or TPC enablement.
- `ssdiag` deploys a signed kernel driver for the duration of the probe. It is removed on exit; the SCM 7045 event remains in the log. EDR/anti-cheat may notice it.

---

## 11. Reproduction

The raw read is in [`evidence/ssdiag-live.txt`](evidence/ssdiag-live.txt). The added register read is:

```text
BAR0 + 0x100ce0   NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE
                  LOWER_MAG   = (v >> 4) & 0x3f
                  LOWER_SCALE = v & 0xf
                  ECC         = (v >> 30) & 1
                  bytes       = (LOWER_MAG << (LOWER_SCALE + 20))
                  if ECC: bytes = bytes / 16 * 15
```

`FB_SIZE_MIB` is `BAR0 + 0x1183a4`, low 16 bits, in MiB. The FEAT cluster is `0x823800/0x823818/0x82381c/0x823820`. The TPC map is `CTRL = 0x820838 + 4*g`, `STATUS = 0x820c38 + 4*g`.

Recommended sequence:

1. `ssdiag --dry-run` — confirm the GPU is enumerated and the platform gates.
2. Run `ssdiag` elevated — it loads the driver, reads BAR0, and removes the service.
3. Keep the raw output with the audit record.
4. Do not write `SS0/SS1` unless you are intentionally re-applying the tensor override.
5. Do not write TPC `CTRL` registers; no supported path exists.

---

## 12. Conclusion

The card is a **16 GiB RTX 4080 SUPER** with **16,376 MiB of hardware-usable framebuffer**. The only true hardware reservation is **8 MiB** (0.049%), a capacity-scaled VBIOS/firmware carveout. The **329 MiB** shown by NVAPI is a software/driver reservation, and the **256 MiB BAR1** is a CPU aperture, not lost VRAM.

The tensor-rate lock is **currently removed** and the selectors are at full rate. The 2 disabled TPCs in GPC3 are binning, not the tensor-rate limiter. The meaningful remaining bottlenecks are the **x4 PCIe link**, the **256 MiB BAR1 window**, and the **320 W VBIOS power cap**.

**There is no additional VRAM to unlock.** The physical memory does not exist beyond 16 GiB; the 8 MiB VBIOS reserve and 329 MiB driver reserve are not a hidden capacity pool.

---

## Appendix A — evidence files

| File | SHA-256 |
|---|---|
| [`evidence/ssdiag-live.txt`](evidence/ssdiag-live.txt) | `eb5faf9583bd9692d5bb74009b4f3d003ea25117b75d9e08237b702a67c8f0d2` |
| [`evidence/hardware-snapshot.txt`](evidence/hardware-snapshot.txt) | `bf262278e89cdc7926b78a654f7992b7a92df13a864d8d59b883c20ec3fbcca4` |

The raw log includes the platform gates, the GPU instance path, BAR0 ranges, the core/debug block, the FEAT clusters, the Ada fuse/TPC block, the per-GPC TPC floorsweep, the PCIe/gen2 probe, the FEAT sweep, the PLM survey and the final verdict.

## Appendix B — document history

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-07 | Initial hardware audit for the local RTX 4080 SUPER |

---

*This report is a read-only hardware audit. It is not a warranty, a stress-test qualification, or an endorsement of TPC/fuse modification. The tensor unlock remains volatile and must be replayed after a cold boot.*
