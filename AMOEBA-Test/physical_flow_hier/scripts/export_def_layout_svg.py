#!/usr/bin/env python3
"""Export an Innovus DEF layout into a lightweight vector SVG.

This is intended for paper figures. It does not try to redraw every routed wire;
instead it visualizes the post-route DEF as die outline, standard-cell placement
density, and hierarchy boxes for repeated AMOEBA CGRA cores. The source DEF
remains the authoritative physical database handoff.
"""

import argparse
import html
import math
import re
from collections import defaultdict, namedtuple
from pathlib import Path


Component = namedtuple("Component", ["name", "master", "x", "y", "orient"])
DefLayout = namedtuple("DefLayout", ["units", "die", "components"])


UNITS_RE = re.compile(r"UNITS\s+DISTANCE\s+MICRONS\s+(\d+)\s*;", re.IGNORECASE)
DIE_RE = re.compile(
    r"DIEAREA\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+"
    r"\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*;",
    re.IGNORECASE,
)
COMPONENT_SECTION_RE = re.compile(
    r"COMPONENTS\s+\d+\s*;(?P<body>.*?)END\s+COMPONENTS",
    re.IGNORECASE | re.DOTALL,
)
COMPONENT_RE = re.compile(
    r"-\s+(?P<name>\S+)\s+(?P<master>\S+).*?"
    r"\+\s+(?:PLACED|FIXED|COVER)\s+"
    r"\(\s*(?P<x>-?\d+)\s+(?P<y>-?\d+)\s*\)\s+"
    r"(?P<orient>\S+)",
    re.IGNORECASE | re.DOTALL,
)
CGRA_RE = re.compile(r"cgra__([0-9]+)")


PALETTE = {
    "core": "#f0b44c",
    "noc": "#44a3d8",
    "controller": "#9b78d6",
    "loop": "#ef746f",
    "tile": "#76b56f",
    "other": "#9a9a9a",
}


def parse_def(path):
    text = path.read_text(errors="ignore")
    units_match = UNITS_RE.search(text)
    units = int(units_match.group(1)) if units_match else 1000

    die_match = DIE_RE.search(text)
    if die_match:
        die = tuple(int(v) for v in die_match.groups())
    else:
        die = (0, 0, 1, 1)

    section_match = COMPONENT_SECTION_RE.search(text)
    components = []
    if section_match:
        body = section_match.group("body")
        for statement in body.split(";"):
            match = COMPONENT_RE.search(statement)
            if not match:
                continue
            components.append(
                Component(
                    name=match.group("name"),
                    master=match.group("master"),
                    x=int(match.group("x")),
                    y=int(match.group("y")),
                    orient=match.group("orient"),
                )
            )

    if not die_match and components:
        xs = [component.x for component in components]
        ys = [component.y for component in components]
        margin = max(max(xs) - min(xs), max(ys) - min(ys), units) // 20
        die = (min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin)

    if not components:
        raise ValueError(f"No placed components found in DEF: {path}")
    return DefLayout(units=units, die=die, components=components)


def classify(component):
    name = component.name.lower()
    master = component.master.lower()
    if CGRA_RE.search(name):
        return "core"
    if "router" in name or "noc" in name or "mesh" in name or "router" in master:
        return "noc"
    if "loop_controller" in name or "loopcontroller" in name:
        return "loop"
    if "controller" in name:
        return "controller"
    if "tile" in name:
        return "tile"
    return "other"


def cgra_id(component):
    match = CGRA_RE.search(component.name)
    return int(match.group(1)) if match else None


def svg_rect(x, y, w, h, **attrs):
    parts = [f'x="{x:.3f}"', f'y="{y:.3f}"', f'width="{w:.3f}"', f'height="{h:.3f}"']
    for key, value in attrs.items():
        attr_name = key[:-1] if key.endswith("_") else key
        parts.append(f'{attr_name.replace("_", "-")}="{value}"')
    return f"<rect {' '.join(parts)} />"


def svg_text(x, y, text, **attrs):
    parts = [f'x="{x:.3f}"', f'y="{y:.3f}"']
    for key, value in attrs.items():
        attr_name = key[:-1] if key.endswith("_") else key
        parts.append(f'{attr_name.replace("_", "-")}="{value}"')
    return f"<text {' '.join(parts)}>{html.escape(text)}</text>"


def export_svg(layout, output, title, max_bins):
    x0, y0, x1, y1 = layout.die
    die_w = max(1, x1 - x0)
    die_h = max(1, y1 - y0)

    page_w = 1400.0
    margin_l, margin_r, margin_t, margin_b = 130.0, 40.0, 95.0, 90.0
    layout_w = page_w - margin_l - margin_r
    layout_h = layout_w * die_h / die_w
    page_h = layout_h + margin_t + margin_b
    scale = layout_w / die_w

    def sx(x):
        return margin_l + (x - x0) * scale

    def sy(y):
        return margin_t + (y1 - y) * scale

    bin_count_x = max(12, min(max_bins, int(math.sqrt(len(layout.components))) * 2))
    bin_count_y = max(12, min(max_bins, round(bin_count_x * die_h / die_w)))
    bin_w = die_w / bin_count_x
    bin_h = die_h / bin_count_y

    bins = defaultdict(int)
    max_count = 1
    for component in layout.components:
        bx = min(bin_count_x - 1, max(0, int((component.x - x0) / bin_w)))
        by = min(bin_count_y - 1, max(0, int((component.y - y0) / bin_h)))
        key = (bx, by, classify(component))
        bins[key] += 1
        max_count = max(max_count, bins[key])

    cgra_groups = defaultdict(list)
    for component in layout.components:
        cid = cgra_id(component)
        if cid is not None:
            cgra_groups[cid].append(component)

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{page_w:.0f}" height="{page_h:.0f}" viewBox="0 0 {page_w:.0f} {page_h:.0f}">',
        '<style>',
        'text { font-family: Arial, Helvetica, sans-serif; fill: #111; }',
        '.title { font-size: 32px; font-weight: 700; }',
        '.label { font-size: 18px; font-weight: 600; }',
        '.small { font-size: 14px; }',
        '.axis { stroke: #111; stroke-width: 2; fill: none; }',
        '.grid { stroke: #d8d8d8; stroke-width: 1; stroke-dasharray: 5 5; }',
        '.core-box { fill: none; stroke: #111; stroke-width: 2.5; }',
        '.die { fill: #fbfbfb; stroke: #111; stroke-width: 3; }',
        '</style>',
        svg_text(page_w / 2, 42, title, text_anchor="middle", class_="title"),
        svg_rect(margin_l, margin_t, layout_w, layout_h, class_="die"),
    ]

    # Light major grid, useful when the SVG is cropped into a paper figure.
    for i in range(1, 4):
        gx = margin_l + layout_w * i / 4
        gy = margin_t + layout_h * i / 4
        lines.append(f'<line x1="{gx:.3f}" y1="{margin_t:.3f}" x2="{gx:.3f}" y2="{margin_t + layout_h:.3f}" class="grid" />')
        lines.append(f'<line x1="{margin_l:.3f}" y1="{gy:.3f}" x2="{margin_l + layout_w:.3f}" y2="{gy:.3f}" class="grid" />')

    # Density bins. Larger bins keep the SVG compact while preserving real DEF placement.
    for (bx, by, kind), count in sorted(bins.items()):
        opacity = min(0.88, 0.12 + 0.76 * math.log1p(count) / math.log1p(max_count))
        rect_x0 = x0 + bx * bin_w
        rect_y0 = y0 + by * bin_h
        rect_x1 = rect_x0 + bin_w
        rect_y1 = rect_y0 + bin_h
        lines.append(
            svg_rect(
                sx(rect_x0),
                sy(rect_y1),
                max(0.4, bin_w * scale),
                max(0.4, bin_h * scale),
                fill=PALETTE[kind],
                fill_opacity=f"{opacity:.3f}",
                stroke="none",
            )
        )

    # Hierarchy boxes around placed cells belonging to each CGRA instance.
    for cid, group in sorted(cgra_groups.items()):
        xs = [component.x for component in group]
        ys = [component.y for component in group]
        gx0, gx1 = min(xs), max(xs)
        gy0, gy1 = min(ys), max(ys)
        pad = max(die_w, die_h) * 0.004
        gx0, gx1 = gx0 - pad, gx1 + pad
        gy0, gy1 = gy0 - pad, gy1 + pad
        lines.append(
            svg_rect(
                sx(gx0),
                sy(gy1),
                max(1.0, (gx1 - gx0) * scale),
                max(1.0, (gy1 - gy0) * scale),
                class_="core-box",
            )
        )
        lines.append(
            svg_text(
                sx(gx0) + 6,
                sy(gy1) + 22,
                f"CGRA {cid}",
                class_="small",
                font_weight="700",
            )
        )

    die_w_um = die_w / layout.units
    die_h_um = die_h / layout.units
    lines.append(svg_text(margin_l, page_h - 50, f"Die: {die_w_um:.2f} um x {die_h_um:.2f} um", class_="label"))
    lines.append(svg_text(margin_l, page_h - 25, f"Components: {len(layout.components):,}; source: post-route DEF", class_="small"))

    legend_x = margin_l + layout_w - 470
    legend_y = page_h - 65
    for i, (kind, color) in enumerate(PALETTE.items()):
        x = legend_x + (i % 3) * 155
        y = legend_y + (i // 3) * 24
        lines.append(svg_rect(x, y - 12, 16, 16, fill=color, fill_opacity="0.70", stroke="#333", stroke_width="0.5"))
        lines.append(svg_text(x + 23, y + 1, kind, class_="small"))

    lines.append('</svg>')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--def-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--title", default="AMOEBA Post-Route Layout")
    parser.add_argument("--max-bins", type=int, default=180)
    args = parser.parse_args()

    layout = parse_def(args.def_file)
    export_svg(layout, args.output, args.title, args.max_bins)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
