#!/usr/bin/env python3
"""Build docs/GPU-Unlock-Guide.pdf from the project documentation.

This is a maintainer tool, not a runtime dependency. It needs ReportLab:

    python -m pip install reportlab

Run from anywhere:

    python docs/build-guide.py
"""

from datetime import date
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    HRFlowable,
    Image,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parent.parent
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
OUTPUT = ROOT / "docs" / "GPU-Unlock-Guide.pdf"
SCREENSHOT = ROOT / "docs" / "images" / "setup-wizard.png"

INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#4B5563")
ACCENT = colors.HexColor("#1D4ED8")
SOFT = colors.HexColor("#EFF6FF")
RULE = colors.HexColor("#D1D5DB")
HEAD_BG = colors.HexColor("#1F2937")

PAGE_W, PAGE_H = A4
MARGIN_X = 20 * mm
MARGIN_TOP = 20 * mm
MARGIN_BOTTOM = 20 * mm


def styles():
    base = ParagraphStyle(
        "Body",
        fontName="Helvetica",
        fontSize=10.2,
        leading=14.2,
        textColor=INK,
        spaceAfter=6,
        alignment=TA_LEFT,
    )
    return {
        "Body": base,
        "Small": ParagraphStyle("Small", parent=base, fontSize=8.6, leading=11.4, textColor=MUTED),
        "Bullet": ParagraphStyle("Bullet", parent=base, leftIndent=12, bulletIndent=2, spaceAfter=4),
        "H1": ParagraphStyle(
            "H1", parent=base, fontName="Helvetica-Bold", fontSize=17, leading=21,
            textColor=ACCENT, spaceBefore=14, spaceAfter=7, keepWithNext=1,
        ),
        "H2": ParagraphStyle(
            "H2", parent=base, fontName="Helvetica-Bold", fontSize=12.2, leading=15,
            textColor=INK, spaceBefore=10, spaceAfter=4, keepWithNext=1,
        ),
        "CoverTitle": ParagraphStyle(
            "CoverTitle", parent=base, fontName="Helvetica-Bold", fontSize=30, leading=35,
            textColor=INK, spaceAfter=8,
        ),
        "CoverSub": ParagraphStyle(
            "CoverSub", parent=base, fontName="Helvetica", fontSize=13, leading=17,
            textColor=MUTED, spaceAfter=16,
        ),
        "Code": ParagraphStyle(
            "Code", parent=base, fontName="Courier", fontSize=8.2, leading=11,
            textColor=INK, backColor=colors.HexColor("#F3F4F6"), borderPadding=5,
            leftIndent=4, spaceBefore=4, spaceAfter=8,
        ),
        "TableCell": ParagraphStyle("TableCell", parent=base, fontSize=8.6, leading=11.2, spaceAfter=0),
        "TableHead": ParagraphStyle(
            "TableHead", parent=base, fontName="Helvetica-Bold", fontSize=8.8,
            leading=11.4, textColor=colors.white, spaceAfter=0,
        ),
        "TOC0": ParagraphStyle("TOC0", parent=base, fontName="Helvetica-Bold", fontSize=10.5, leading=16, textColor=INK),
        "TOC1": ParagraphStyle("TOC1", parent=base, fontSize=9.5, leading=14, leftIndent=14, textColor=MUTED),
    }


S = styles()


class GuideDoc(BaseDocTemplate):
    def __init__(self, filename, **kwargs):
        BaseDocTemplate.__init__(self, filename, pagesize=A4, **kwargs)
        frame = Frame(
            MARGIN_X,
            MARGIN_BOTTOM,
            PAGE_W - 2 * MARGIN_X,
            PAGE_H - MARGIN_TOP - MARGIN_BOTTOM,
            id="body",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        self.addPageTemplates([PageTemplate(id="guide", frames=[frame], onPage=decorate)])
        self._outline = 0

    def afterFlowable(self, flowable):
        if not isinstance(flowable, Paragraph):
            return
        name = flowable.style.name
        if name not in ("H1", "H2"):
            return
        level = 0 if name == "H1" else 1
        text = flowable.getPlainText()
        if text == "Contents":
            return
        key = "outline-%d" % self._outline
        self._outline += 1
        self.canv.bookmarkPage(key)
        self.canv.addOutlineEntry(text, key, level=level, closed=False)
        self.notify("TOCEntry", (level, text, self.page))


def decorate(canvas, doc):
    page = canvas.getPageNumber()
    canvas.saveState()
    if page > 1:
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.5)
        canvas.line(MARGIN_X, PAGE_H - 13 * mm, PAGE_W - MARGIN_X, PAGE_H - 13 * mm)
        canvas.setFont("Helvetica", 7.8)
        canvas.setFillColor(MUTED)
        canvas.drawString(MARGIN_X, PAGE_H - 10 * mm, "GPU Unlock for Windows")
        canvas.drawRightString(PAGE_W - MARGIN_X, PAGE_H - 10 * mm, "Setup and user guide")
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN_X, 13 * mm, PAGE_W - MARGIN_X, 13 * mm)
    canvas.setFont("Helvetica", 7.8)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN_X, 9 * mm, "GPU Unlock Guide - v%s" % VERSION)
    canvas.drawRightString(PAGE_W - MARGIN_X, 9 * mm, "Page %d" % page)
    canvas.restoreState()


def p(text, style="Body"):
    return Paragraph(text, S[style])


def bullet(text):
    return Paragraph(text, S["Bullet"], bulletText="\u2022")


def h1(text):
    return Paragraph(text, S["H1"])


def code(text):
    return Preformatted(text.strip("\n"), S["Code"])


def callout(title, text):
    data = [[Paragraph("<b>%s</b><br/>%s" % (title, text), S["Body"])]]
    table = Table(data, colWidths=[PAGE_W - 2 * MARGIN_X])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SOFT),
                ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#BFDBFE")),
                ("LINEBEFORE", (0, 0), (0, -1), 3, ACCENT),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def table(headers, rows, widths):
    data = [[Paragraph(h, S["TableHead"]) for h in headers]]
    data += [[Paragraph(str(cell), S["TableCell"]) for cell in row] for row in rows]
    width = PAGE_W - 2 * MARGIN_X
    scaled = [width * w for w in widths]
    result = Table(data, colWidths=scaled, repeatRows=1)
    result.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.4, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9FAFB")]),
            ]
        )
    )
    return result


def numbered(items):
    return [Paragraph(item, S["Bullet"], bulletText="%d." % (i + 1)) for i, item in enumerate(items)]


def story():
    out = []

    # Cover
    out.append(Spacer(1, 8 * mm))
    out.append(p("GPU Unlock for Windows", "CoverTitle"))
    out.append(p("Setup and user guide", "CoverSub"))
    out.append(HRFlowable(width="100%", thickness=1.2, color=ACCENT, spaceBefore=0, spaceAfter=12))
    out.append(
        p(
            "A guided installer for the NVIDIA tensor-rate unlock. The USB stick runs the "
            "unlock before Windows starts; the status app confirms it afterwards.",
        )
    )
    out.append(Spacer(1, 5 * mm))
    if SCREENSHOT.exists():
        img = Image(str(SCREENSHOT))
        max_w = PAGE_W - 2 * MARGIN_X
        scale = max_w / img.imageWidth
        img.drawWidth = max_w
        img.drawHeight = img.imageHeight * scale
        if img.drawHeight > 92 * mm:
            scale = (92 * mm) / img.drawHeight
            img.drawWidth *= scale
            img.drawHeight *= scale
        out.append(img)
    out.append(Spacer(1, 6 * mm))
    out.append(
        p(
            "<b>Version %s</b> &nbsp;&nbsp; %s<br/>"
            "This guide covers setup, the one-time BIOS step, daily use, verification, "
            "troubleshooting and removal." % (VERSION, date.today().isoformat()),
            "Small",
        )
    )
    out.append(Spacer(1, 4 * mm))
    out.append(
        callout(
            "Read this first",
            "Keep the USB stick connected after setup. Windows only receives the unlock when the "
            "firmware boots the stick first. Without the stick, Windows boots normally.",
        )
    )
    out.append(PageBreak())

    # Contents
    out.append(h1("Contents"))
    toc = TableOfContents()
    toc.levelStyles = [S["TOC0"], S["TOC1"]]
    toc.dotsMinLevel = 0
    out.append(toc)
    out.append(PageBreak())

    out.append(h1("Quick start"))
    out.append(p("For a normal install you need to choose the USB stick and approve the administrator prompt. The wizard detects everything else."))
    out += numbered(
        [
            "Download or clone the project to a folder on the PC.",
            "Double-click <b>SETUP.cmd</b> and approve the Windows administrator prompt.",
            "Click <b>Next</b> through the system check. It verifies Windows, .NET, UEFI, Secure Boot and your NVIDIA card.",
            "Select the USB stick. If it is not FAT32, confirm the format. <b>Formatting erases the stick.</b>",
            "Leave the defaults on the ready page and click <b>Install</b>.",
            "Wait for the download, build and USB copy to finish.",
            "Restart, enter BIOS/UEFI (usually Del or F2), set the <b>UEFI: ...</b> stick entry as Boot Option #1, then save and exit (F10).",
            "Open <b>GPU Unlock</b> from the Desktop or Start Menu. A green <b>UNLOCKED</b> confirms SS0 and SS1.",
        ]
    )
    out.append(callout("What stays automatic", "The wizard checks the OS, installs the app, creates shortcuts, registers the logon check and writes the registry settings. No extra runtime downloads are needed on Windows 10/11."))

    out.append(h1("What setup does"))
    out.append(
        table(
            ["Step", "Detail"],
            [
                ["System check", "Windows 10/11 64-bit, administrator, PowerShell 5.1+, .NET 4.7.2+, UEFI, Secure Boot, Fast Startup, BitLocker, NVIDIA GPU"],
                ["Download", "Pinned upstream release v2.1.10; every file is SHA-256 verified"],
                ["Build", "Generates the files for the detected RTX 20/30/40 family (or all families for a mixed machine)"],
                ["USB", "Selects a removable drive, backs up an existing EFI/BOOT/BOOTX64.EFI, formats to FAT32 when needed, copies and verifies hashes"],
                ["Markers", "Writes the countdown marker and the quiet-console marker"],
                ["Windows app", "Installs to %ProgramFiles%\\GPU Unlock, creates Desktop/Start Menu/uninstall shortcuts and the GpuUnlockStatus logon task"],
                ["Registry", "Records the install path, version and auto-start settings; registers the Apps & Features entry"],
            ],
            [0.2, 0.8],
        )
    )

    out.append(h1("Requirements"))
    out.append(bullet("<b>Windows 10 or 11, 64-bit.</b>"))
    out.append(bullet("<b>UEFI firmware.</b> Legacy/BIOS boot is not supported."))
    out.append(bullet("<b>Secure Boot disabled.</b> The upstream loader is not signed for Secure Boot."))
    out.append(bullet("<b>NVIDIA RTX 20, 30 or 40 series.</b> GTX 16 is experimental upstream; RTX 50 is not supported."))
    out.append(bullet("<b>8 GB or larger USB stick.</b> It must end up FAT32; the wizard offers to format it."))
    out.append(bullet("<b>Internet access</b> for the first download."))
    out.append(bullet("<b>Administrator rights.</b> The wizard requests them."))
    out.append(bullet("<b>BitLocker:</b> keep the recovery key before changing boot settings. The wizard warns but does not disable BitLocker."))

    out.append(h1("Supported hardware"))
    out.append(
        table(
            ["Family", "Cards", "Status"],
            [
                ["ad102", "RTX 40 series (Ada)", "Fully built and supported"],
                ["ga102", "RTX 30 series (Ampere)", "Built and supported"],
                ["tu10x", "RTX 20 series / GTX 16 (Turing)", "RTX 20 supported; GTX 16 experimental upstream"],
                ["-", "RTX 50 (Blackwell)", "Not supported"],
            ],
            [0.18, 0.42, 0.4],
        )
    )
    out.append(p("Mixed-generation machines receive all supported families on one stick. The loader picks the right family at boot."))

    out.append(h1("The one-time BIOS step"))
    out.append(p("Windows cannot reliably change the firmware boot order. Do this once:"))
    out += numbered(
        [
            "Keep the USB stick connected.",
            "Restart and press <b>Del</b> (or <b>F2</b>) at the vendor logo.",
            "Open the <b>Boot</b> tab.",
            "Set the stick's <b>UEFI: ...</b> entry as <b>Boot Option #1</b>.",
            "Set <b>CSM Support = Disabled</b> and <b>Secure Boot = Disabled</b> if present.",
            "Press <b>F10</b>, save and exit.",
        ]
    )
    out.append(callout("Rollback", "Remove the stick and Windows boots normally. This tool does not change the ESP, NVRAM boot order or VBIOS."))

    out.append(h1("Daily use and status"))
    out.append(bullet("<b>Stick in + restart:</b> the loader runs, unlocks the card and chains into Windows."))
    out.append(bullet("<b>Stick out:</b> Windows boots normally."))
    out.append(bullet("<b>Sleep or power loss</b> can clear the volatile register state. Restart with the stick."))
    out.append(bullet("<b>GPU Unlock</b> in the Start Menu or Desktop shows UNLOCKED or NOT UNLOCKED, the GPU bus ID, SS0/SS1 and the raw ssdiag output."))
    out.append(bullet("The app has <b>Check again</b>, <b>Repair selectors</b>, <b>Open guide</b> and <b>Open log</b> buttons."))
    out.append(bullet("The logon task runs 15 seconds after login and warns only when the unlock is not active."))

    out.append(h1("Verification"))
    out.append(p("A successful unlock reports <b>SS0 = 0x88888888</b> and an SS1 value whose low nibble is <b>0x8</b>."))
    out.append(p("From an elevated PowerShell you can also run:"))
    out.append(code(".\\verify.ps1 -Elevate"))
    out.append(p("The status app's log is at <b>%LOCALAPPDATA%\\gpu-unlock-windows\\status.log</b> and rotates automatically (five files, 5 MB each)."))

    out.append(h1("Troubleshooting"))
    out.append(
        table(
            ["Symptom", "Action"],
            [
                ["Stick not listed, or boots straight to Windows", "Check EFI\\BOOT\\BOOTX64.EFI exists, Secure Boot is off, the UEFI: entry is first, and the stick is FAT32. No loader.log means the EFI never ran."],
                ["Black screen or frozen image during the unlock", "Usually the GOP handoff. Wait; the loader restores the display or chains to Windows. Power off only if clearly stuck."],
                ["Windows Recovery 0xc000009a after a green log", "Put an empty tx-free-assets.txt at the stick root and replay."],
                ["0xc000000f or 0xc0000225", "Two ESPs or a stale chain. Update to the pinned release and replay."],
                ["MAP_PHYS win32 error 5 from ssdiag", "HVCI or a kernel-mode antivirus filter holds the mapping. Disable the filter or HVCI and reboot."],
                ["Antivirus flags ssdiag.exe", "Expected for the unsigned diagnostic with an embedded kernel driver. Restore it from quarantine."],
                ["Unlocked but no speedup", "Verify SS0/SS1. The gains are FP16/BF16/TF32 with FP32 accumulate; INT8/INT4, FP32 and decode-bound work do not move."],
                ["Unlock gone after sleep or power loss", "Expected. Restart with the stick."],
                ["Scheduled task or shortcut missing", "Run SETUP.cmd as administrator and choose Install app. Check Task Scheduler for GpuUnlockStatus."],
                ["Uninstaller missing from Apps & Features", "Run UNINSTALL.cmd from the project or reinstall the app."],
            ],
            [0.38, 0.62],
        )
    )
    out.append(p("The full symptom list, including upstream field reports, is in TROUBLESHOOTING.md."))

    out.append(h1("Uninstall"))
    out.append(p("Double-click <b>UNINSTALL.cmd</b>, use <b>Uninstall GPU Unlock</b> in the Start Menu, or use <b>Apps & Features</b>."))
    out.append(p("The uninstaller removes the scheduled task, shortcuts, Apps & Features entry, HKCU settings, installed files, cache and installer logs."))
    out.append(p("It leaves the USB stick and the local stick-backup folder alone by default. The wizard can optionally remove generated stick files; the stick's EFI boot loader is left in place."))
    out.append(code(".\\Uninstall.ps1 -Remove -Force\n.\\Uninstall.ps1 -Remove -Force -CleanStick\n.\\Uninstall.ps1 -Remove -Force -RemoveBackups"))

    out.append(h1("Advanced command line"))
    out.append(code(".\\setup.ps1 -Family localhost -Stick E: -FormatStick -ConfirmFormat\n.\\install.ps1 -Family localhost -Stick E:\n.\\setup.ps1 -InstallApp\n.\\setup.ps1 -DryRun\n.\\verify.ps1 -Elevate"))
    out.append(p("Useful switches: -Family ad102|ga102|tu10x|all|localhost, -Stick, -FormatStick -ConfirmFormat, -Cache, -InstallApp, -InstallStick, -NoApp, -NoStick, -NoDesktop, -NoStartMenu, -NoAutoStart, -Silent, -SkipElevation."))

    out.append(h1("Safety and recovery"))
    out.append(bullet("No ESP, NVRAM BootOrder, VBIOS or firmware changes are made by this tool."))
    out.append(bullet("The USB stick is the rollback: remove it and Windows boots normally."))
    out.append(bullet("An existing EFI/BOOT/BOOTX64.EFI is backed up before a stick is changed."))
    out.append(bullet("Every release file is SHA-256 verified against the pinned manifest."))
    out.append(bullet("Do not retry after a boot fault in the same session; power off fully first."))
    out.append(bullet("Keep loader.log from the stick root for boot-problem reports."))

    out.append(h1("License and third-party notices"))
    out.append(p("This project's own code is <b>MIT licensed</b>: free for personal and commercial use, modification and redistribution. See LICENSE."))
    out.append(p("The setup downloads the upstream physicsdolphin/nv-uefi-unlocker components, which are <b>GPL-2.0-only</b>, and NVIDIA firmware under NVIDIA's terms. Those components are not redistributed in this repository; a prepared USB stick contains them. See THIRD-PARTY-NOTICES.md before redistributing a stick."))
    out.append(callout("No warranty", "The software is provided as is, without warranty. The MIT disclaimer applies to this project's own code; upstream and vendor components carry their own terms."))

    return out


def main():
    doc = GuideDoc(
        str(OUTPUT),
        title="GPU Unlock for Windows - Setup and user guide",
        author="GPU Unlock Project",
        subject="Setup, BIOS, verification, troubleshooting and uninstall guide",
        creator="GPU Unlock docs/build-guide.py",
    )
    doc.multiBuild(story())
    print(OUTPUT)


if __name__ == "__main__":
    main()
