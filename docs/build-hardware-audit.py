#!/usr/bin/env python3
"""Build docs/hardware/RTX-4080-SUPER-HARDWARE-AUDIT.pdf from the report Markdown.

Maintainer tool only. Requires ReportLab:

    python -m pip install reportlab

Run from anywhere:

    python docs/build-hardware-audit.py

The Markdown file is the canonical source. The parser intentionally supports
only the subset used by the report: headings, paragraphs, bullets, numbered
items, fenced code, pipe tables, horizontal rules, inline code/bold/italic and
links.
"""

from __future__ import annotations

import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    HRFlowable,
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
SOURCE = ROOT / "docs" / "hardware" / "RTX-4080-SUPER-HARDWARE-AUDIT.md"
OUTPUT = ROOT / "docs" / "hardware" / "RTX-4080-SUPER-HARDWARE-AUDIT.pdf"

REPORT_ID = "GPU-HW-2026-11-07-4080S"
REPORT_VERSION = "1.0"
REPORT_DATE = "2026-11-07"

INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#4B5563")
ACCENT = colors.HexColor("#1D4ED8")
SOFT = colors.HexColor("#EFF6FF")
RULE = colors.HexColor("#D1D5DB")
HEAD_BG = colors.HexColor("#1F2937")
CODE_BG = colors.HexColor("#F3F4F6")

PAGE_W, PAGE_H = A4
MARGIN_X = 18 * mm
MARGIN_TOP = 18 * mm
MARGIN_BOTTOM = 18 * mm

# Segoe UI/Consolas give the PDF the same Unicode punctuation the Markdown uses.
FONT_DIR = Path(r"C:\Windows\Fonts")
FONT_BODY = "SegoeUI"
FONT_BODY_BOLD = "SegoeUI-Bold"
FONT_BODY_ITALIC = "SegoeUI-Italic"
FONT_CODE = "Consolas"

for name, filename in [
    (FONT_BODY, "segoeui.ttf"),
    (FONT_BODY_BOLD, "segoeuib.ttf"),
    (FONT_BODY_ITALIC, "segoeuii.ttf"),
    (FONT_CODE, "consola.ttf"),
]:
    path = FONT_DIR / filename
    if path.exists():
        pdfmetrics.registerFont(TTFont(name, str(path)))


def styles() -> dict[str, ParagraphStyle]:
    base = ParagraphStyle(
        "Body",
        fontName=FONT_BODY,
        fontSize=9.4,
        leading=13.0,
        textColor=INK,
        spaceAfter=5,
        alignment=TA_LEFT,
    )
    return {
        "Body": base,
        "Small": ParagraphStyle("Small", parent=base, fontSize=7.8, leading=10.4, textColor=MUTED),
        "Micro": ParagraphStyle("Micro", parent=base, fontSize=6.8, leading=8.6, textColor=MUTED),
        "Bullet": ParagraphStyle("Bullet", parent=base, leftIndent=12, bulletIndent=2, spaceAfter=2.5),
        "H1": ParagraphStyle(
            "H1", parent=base, fontName=FONT_BODY_BOLD, fontSize=15, leading=19,
            textColor=ACCENT, spaceBefore=12, spaceAfter=6, keepWithNext=1,
        ),
        "H2": ParagraphStyle(
            "H2", parent=base, fontName=FONT_BODY_BOLD, fontSize=10.8, leading=14,
            textColor=INK, spaceBefore=8, spaceAfter=3, keepWithNext=1,
        ),
        "H3": ParagraphStyle(
            "H3", parent=base, fontName=FONT_BODY_BOLD, fontSize=9.6, leading=12,
            textColor=INK, spaceBefore=6, spaceAfter=2, keepWithNext=1,
        ),
        "Code": ParagraphStyle(
            "Code", parent=base, fontName=FONT_CODE, fontSize=7.2, leading=9.2,
            textColor=INK, backColor=CODE_BG, borderPadding=4,
            leftIndent=2, spaceBefore=2, spaceAfter=6,
        ),
        "TableCell": ParagraphStyle("TableCell", parent=base, fontSize=7.4, leading=9.6, spaceAfter=0),
        "TableHead": ParagraphStyle(
            "TableHead", parent=base, fontName=FONT_BODY_BOLD, fontSize=7.6,
            leading=9.8, textColor=colors.white, spaceAfter=0,
        ),
        "TOC0": ParagraphStyle("TOC0", parent=base, fontName=FONT_BODY_BOLD, fontSize=10, leading=15, textColor=INK),
        "TOC1": ParagraphStyle("TOC1", parent=base, fontSize=9, leading=13, leftIndent=14, textColor=MUTED),
        "CoverTitle": ParagraphStyle(
            "CoverTitle", parent=base, fontName=FONT_BODY_BOLD, fontSize=28, leading=32,
            textColor=INK, spaceAfter=4,
        ),
        "CoverSub": ParagraphStyle(
            "CoverSub", parent=base, fontName=FONT_BODY, fontSize=13.5, leading=17,
            textColor=ACCENT, spaceAfter=12,
        ),
    }


S = styles()


class AuditDoc(BaseDocTemplate):
    def __init__(self, filename: str, **kwargs):
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
        self.addPageTemplates([PageTemplate(id="audit", frames=[frame], onPage=decorate)])
        self._outline = 0

    def afterFlowable(self, flowable):
        if not isinstance(flowable, Paragraph):
            return
        name = flowable.style.name
        if name not in ("H1", "H2"):
            return
        text = flowable.getPlainText()
        if text == "Contents":
            return
        level = 0 if name == "H1" else 1
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
        canvas.line(MARGIN_X, PAGE_H - 12 * mm, PAGE_W - MARGIN_X, PAGE_H - 12 * mm)
        canvas.setFont(FONT_BODY, 7.4)
        canvas.setFillColor(MUTED)
        canvas.drawString(MARGIN_X, PAGE_H - 9.4 * mm, "RTX 4080 SUPER — physical VRAM, tensor-rate and lock audit")
        canvas.drawRightString(PAGE_W - MARGIN_X, PAGE_H - 9.4 * mm, REPORT_ID)
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN_X, 12 * mm, PAGE_W - MARGIN_X, 12 * mm)
    canvas.setFont(FONT_BODY, 7.4)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN_X, 8.4 * mm, f"{REPORT_ID} · v{REPORT_VERSION}")
    canvas.drawRightString(PAGE_W - MARGIN_X, 8.4 * mm, f"Page {page}")
    canvas.restoreState()


def inline(text: str) -> str:
    """Convert inline Markdown to ReportLab paragraph markup."""
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    code_spans: list[str] = []

    def keep_code(match: re.Match) -> str:
        code_spans.append(
            f'<font face="{FONT_CODE}" size="8.1">{match.group(1)}</font>'
        )
        return f"@@CODE{len(code_spans) - 1}@@"

    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<link href="{m.group(2)}" color="#1D4ED8">{m.group(1)}</link>',
        text,
    )
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)
    text = re.sub(r"@@CODE(\d+)@@", lambda m: code_spans[int(m.group(1))], text)
    return text


def P(text: str, style: str = "Body") -> Paragraph:
    return Paragraph(inline(text), S[style])


def bullet(text: str) -> Paragraph:
    return Paragraph(inline(text), S["Bullet"], bulletText="•")


def numbered(index: int, text: str) -> Paragraph:
    return Paragraph(inline(text), S["Bullet"], bulletText=f"{index}.")


def code(text: str) -> Preformatted:
    return Preformatted(text.rstrip("\n"), S["Code"])


def table(headers: list[str], rows: list[list[str]]) -> Table:
    data = [[P(h, "TableHead") for h in headers]]
    data += [[P(c, "TableCell") for c in row] for row in rows]
    width = PAGE_W - 2 * MARGIN_X
    weights = []
    for idx in range(len(headers)):
        longest = max([len(headers[idx])] + [len(r[idx]) for r in rows if idx < len(r)])
        weights.append(max(8, min(longest, 44)))
    total = sum(weights) or 1
    col_widths = [width * (w / total) for w in weights]
    result = Table(data, colWidths=col_widths, repeatRows=1)
    result.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.35, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9FAFB")]),
            ]
        )
    )
    return result


def split_row(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def is_separator(line: str) -> bool:
    cells = split_row(line)
    return bool(cells) and all(re.fullmatch(r":?-{2,}:?", c.strip()) for c in cells)


def parse(md: str):
    lines = md.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("## "))
    except StopIteration:
        start = 0
    lines = lines[start:]

    story = []
    paragraph: list[str] = []
    i = 0

    def flush():
        nonlocal paragraph
        if paragraph:
            story.append(P(" ".join(paragraph)))
            paragraph = []

    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip()
        stripped = line.strip()

        if not stripped:
            flush()
            i += 1
            continue

        if stripped.startswith("```"):
            flush()
            i += 1
            block = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            i += 1
            story.append(code("\n".join(block)))
            continue

        if stripped == "<!-- pagebreak -->":
            flush()
            story.append(PageBreak())
            i += 1
            continue

        if stripped == "---":
            flush()
            story.append(Spacer(1, 2 * mm))
            story.append(HRFlowable(width="100%", thickness=0.5, color=RULE, spaceBefore=0, spaceAfter=4))
            i += 1
            continue

        if stripped.startswith("### "):
            flush()
            story.append(Paragraph(inline(stripped[4:]), S["H2"]))
            i += 1
            continue
        if stripped.startswith("## "):
            flush()
            story.append(Paragraph(inline(stripped[3:]), S["H1"]))
            i += 1
            continue
        if stripped.startswith("# "):
            flush()
            story.append(Paragraph(inline(stripped[2:]), S["H1"]))
            i += 1
            continue

        if stripped.startswith("|"):
            flush()
            block = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                block.append(lines[i].strip())
                i += 1
            if len(block) >= 2:
                headers = split_row(block[0])
                rows = [split_row(r) for r in block[1:] if not is_separator(r)]
                # Pad short rows so the table renderer never indexes past a row.
                for row in rows:
                    while len(row) < len(headers):
                        row.append("")
                story.append(table(headers, rows))
                story.append(Spacer(1, 2.5 * mm))
            continue

        bullet_match = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet_match:
            flush()
            story.append(bullet(bullet_match.group(1)))
            i += 1
            continue

        number_match = re.match(r"^(\d+)\.\s+(.*)$", stripped)
        if number_match:
            flush()
            story.append(numbered(int(number_match.group(1)), number_match.group(2)))
            i += 1
            continue

        paragraph.append(stripped)
        i += 1

    flush()
    return story


def cover() -> list:
    out = [
        Spacer(1, 10 * mm),
        Paragraph("RTX 4080 SUPER", S["CoverTitle"]),
        Paragraph("Physical VRAM, tensor-rate and lock audit", S["CoverSub"]),
        HRFlowable(width="100%", thickness=1.2, color=ACCENT, spaceBefore=0, spaceAfter=10),
        Paragraph(
            "<b>Read-only BAR0 MMIO audit</b> of the local AD103 card. "
            "The capacity figures come from the GPU's own registers, not from the display driver.",
            S["Body"],
        ),
        Spacer(1, 5 * mm),
    ]

    data = [
        ["Report ID", REPORT_ID],
        ["Report date", "2026-11-07 17:52 CET"],
        ["Target", "NVIDIA GeForce RTX 4080 SUPER, AD103, 10de:2702"],
        ["PCI address", "0000:04:00.0"],
        ["VBIOS", "95.03.44.00.4e"],
        ["Board / GPU part", "0x400 / 2702-400-A1"],
        ["Host", "Gigabyte Z790 GAMING X AX, BIOS F14, i9-14900K, 96 GiB DDR5"],
        ["Method", "ssdiag 0.6.14, signed pmxdrv.sys, BAR0 MMIO"],
        ["Result", "16 GiB physical; 16,376 MiB usable; tensor override live"],
    ]
    cover_table = Table(
        [[Paragraph(f"<b>{k}</b>", S["TableCell"]), Paragraph(v, S["TableCell"])] for k, v in data],
        colWidths=[38 * mm, PAGE_W - 2 * MARGIN_X - 38 * mm],
    )
    cover_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.35, RULE),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F3F4F6")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    out.append(cover_table)
    out.append(Spacer(1, 5 * mm))
    out.append(
        Table(
            [[Paragraph(
                "<b>Headline:</b> 16,384 MiB raw · 16,376 MiB VBIOS-usable · 8 MiB VBIOS reserve · "
                "329 MiB driver reserve · <b>16,047 MiB application-visible</b>. "
                "There is no hidden 24 GB or 32 GB pool.",
                S["Body"],
            )]],
            colWidths=[PAGE_W - 2 * MARGIN_X],
            style=TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), SOFT),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#BFDBFE")),
                    ("LINEBEFORE", (0, 0), (0, -1), 3, ACCENT),
                    ("LEFTPADDING", (0, 0), (-1, -1), 8),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                    ("TOPPADDING", (0, 0), (-1, -1), 7),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ]
            ),
        )
    )
    out.append(Spacer(1, 5 * mm))
    out.append(
        Paragraph(
            "The tensor unlock is already live. This report is a read-only audit; it does not write "
            "FEAT, TPC, WPR or memory-partition registers.",
            S["Small"],
        )
    )
    out.append(PageBreak())
    return out


def story() -> list:
    out = cover()
    out.append(Paragraph("Contents", S["H1"]))
    toc = TableOfContents()
    toc.levelStyles = [S["TOC0"], S["TOC1"]]
    toc.dotsMinLevel = 0
    out.append(toc)
    out.append(PageBreak())
    out += parse(SOURCE.read_text(encoding="utf-8"))
    return out


def main() -> int:
    doc = AuditDoc(
        str(OUTPUT),
        title="RTX 4080 SUPER - physical VRAM, tensor-rate and lock audit",
        author="GPU Unlock hardware audit",
        subject="Read-only BAR0 hardware audit of an NVIDIA RTX 4080 SUPER",
    )
    doc.multiBuild(story())
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
