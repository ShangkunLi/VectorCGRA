#!/usr/bin/env python3
"""Extract paper-facing area breakdowns from a Synopsys DC area report."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_REPORT = SCRIPT_DIR / "physical_flow_baseline" / "reports" / "dc_area.rpt"


@dataclass(frozen=True)
class AreaRow:
    path: str
    area: float
    percent: float
    combinational: float
    noncombinational: float
    black_boxes: float
    design: str


AREA_NUMBERS_RE = re.compile(
    r"([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+"
    r"(\S+)\s*$"
)


def parse_dc_area_report(report_path: Path) -> list[AreaRow]:
    """Parse the hierarchical area table from a DC report_area output."""

    rows: list[AreaRow] = []
    pending_path: str | None = None

    for raw_line in report_path.read_text(errors="ignore").splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue

        if line.startswith(" ") and pending_path:
            match = re.match(r"^\s+" + AREA_NUMBERS_RE.pattern, line)
            if match:
                rows.append(_make_row(pending_path, match.groups()))
                pending_path = None
            continue

        match = re.match(r"^(\S+)\s+" + AREA_NUMBERS_RE.pattern, line)
        if match:
            rows.append(_make_row(match.group(1), match.groups()[1:]))
            pending_path = None
            continue

        token = line.strip()
        if "/" in token or re.match(r"^[A-Za-z_]\w*(?:__[0-9]+)?$", token):
            pending_path = token

    if not rows:
        raise ValueError(f"No hierarchical area rows found in {report_path}")

    return rows


def _make_row(path: str, fields: Iterable[str]) -> AreaRow:
    area, percent, comb, noncomb, black_boxes, design = fields
    return AreaRow(
        path=path,
        area=float(area),
        percent=float(percent),
        combinational=float(comb),
        noncombinational=float(noncomb),
        black_boxes=float(black_boxes),
        design=design,
    )


def is_cgra(path: str) -> bool:
    return re.fullmatch(r"cgra__\d+", path) is not None


def is_cgra_child(path: str, child_name: str) -> bool:
    parts = path.split("/")
    return len(parts) == 2 and is_cgra(parts[0]) and parts[1] == child_name


def is_tile(path: str) -> bool:
    parts = path.split("/")
    return (
        len(parts) == 2
        and is_cgra(parts[0])
        and re.fullmatch(r"tile__\d+", parts[1]) is not None
    )


def is_tile_child(path: str, child_name: str) -> bool:
    parts = path.split("/")
    return (
        len(parts) == 3
        and is_cgra(parts[0])
        and re.fullmatch(r"tile__\d+", parts[1]) is not None
        and parts[2] == child_name
    )


def is_tile_fu(row: AreaRow) -> bool:
    parts = row.path.split("/")
    return (
        len(parts) == 4
        and is_cgra(parts[0])
        and re.fullmatch(r"tile__\d+", parts[1]) is not None
        and parts[2] == "element"
        and re.fullmatch(r"fu__\d+", parts[3]) is not None
    )


def is_dcu_design(design: str) -> bool:
    return design.startswith(
        ("LimitedLoopCounterRTL", "LoopCounterRTL", "Dcu", "DCU")
    )


def sum_area(rows: Iterable[AreaRow], predicate) -> float:
    return sum(row.area for row in rows if predicate(row))


def top_area(rows: list[AreaRow]) -> float:
    for row in rows:
        if "/" not in row.path and not is_cgra(row.path) and row.percent == 100.0:
            return row.area
    raise ValueError("Cannot find the top design row")


def build_breakdown(rows: list[AreaRow], spm_mode: str) -> list[tuple[str, float]]:
    total = top_area(rows)

    tile_area = sum_area(rows, lambda row: is_tile(row.path))
    core_controller_area = sum_area(rows, lambda row: is_cgra_child(row.path, "controller"))
    loop_controller_area = sum_area(rows, lambda row: is_cgra_child(row.path, "loop_controller"))
    noc_area = sum_area(rows, lambda row: row.path == "mesh")

    if spm_mode == "none":
        spm_area = 0.0
    elif spm_mode == "stub":
        spm_area = sum_area(
            rows,
            lambda row: "/data_mem/memory_wrapper__" in row.path
            and row.design.startswith("SpmBankPhysicalStubRTL"),
        )
    elif spm_mode == "controller":
        spm_area = sum_area(rows, lambda row: is_cgra_child(row.path, "data_mem"))
    else:
        raise ValueError(f"Unsupported SPM mode: {spm_mode}")

    element_area = sum_area(rows, lambda row: is_tile_child(row.path, "element"))
    dcu_area = sum_area(
        rows,
        lambda row: is_tile_fu(row) and is_dcu_design(row.design),
    )
    other_fu_area = max(0.0, element_area - dcu_area)
    register_area = sum_area(rows, lambda row: is_tile_child(row.path, "register_cluster"))
    crossbar_area = sum_area(
        rows,
        lambda row: is_tile_child(row.path, "fu_crossbar")
        or is_tile_child(row.path, "routing_crossbar"),
    )
    config_mem_area = sum_area(rows, lambda row: is_tile_child(row.path, "ctrl_mem"))

    known_top_area = (
        tile_area
        + core_controller_area
        + loop_controller_area
        + spm_area
        + noc_area
    )
    other_top_area = max(0.0, total - known_top_area)

    known_tile_area = (
        dcu_area
        + other_fu_area
        + register_area
        + crossbar_area
        + config_mem_area
    )
    other_tile_area = max(0.0, tile_area - known_tile_area)

    return [
        ("Tiles (x64)", tile_area),
        ("  DCUs", dcu_area),
        ("  Other FUs", other_fu_area),
        ("  Register Files", register_area),
        ("  Crossbars", crossbar_area),
        ("  Configuration Memories", config_mem_area),
        ("  Other Tile Logic", other_tile_area),
        ("Core Controllers (x16)", core_controller_area),
        ("Loop Controllers (x16)", loop_controller_area),
        ("SPMs (x16)", spm_area),
        ("Inter-Core NoC", noc_area),
        ("Other", other_top_area),
        ("Total", total),
    ]


def write_csv(rows: list[tuple[str, float]], output_path: Path | None) -> None:
    if output_path is None:
        writer = csv.writer(sys.stdout, lineterminator="\n")
        writer.writerow(["component", "area_um2"])
        writer.writerows((name, f"{area:.4f}") for name, area in rows)
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as outfile:
        writer = csv.writer(outfile, lineterminator="\n")
        writer.writerow(["component", "area_um2"])
        writer.writerows((name, f"{area:.4f}") for name, area in rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract AMOEBA paper area categories from dc_area.rpt.",
    )
    parser.add_argument(
        "report",
        nargs="?",
        type=Path,
        default=DEFAULT_REPORT,
        help=f"Path to dc_area.rpt. Default: {DEFAULT_REPORT}",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Optional output CSV path. Defaults to stdout.",
    )
    parser.add_argument(
        "--spm-mode",
        choices=("none", "stub", "controller"),
        default="controller",
        help=(
            "How to fill SPMs (x16): 'none' reports 0 because the current DC "
            "netlist has no SRAM macro area; 'stub' reports only "
            "SpmBankPhysicalStubRTL wrapper area; 'controller' reports the "
            "full data_mem subsystem area."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = parse_dc_area_report(args.report)
    breakdown = build_breakdown(rows, args.spm_mode)
    write_csv(breakdown, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
