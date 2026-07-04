#!/usr/bin/env python3
"""Remove the hardened CGRA core implementation from a top netlist.

The hierarchical DC stage writes a legal top-level gate netlist, but it still
contains the full module definition for the pre-synthesized CGRA core. For a
hard-macro Innovus flow the top netlist should only instantiate that core; the
core implementation is supplied separately through its LEF/DEF/Verilog views.
"""

import argparse
import re
from pathlib import Path


def remove_module_definition(netlist_text, module_name):
    lines = netlist_text.splitlines(keepends=True)
    out = []
    skipping = False
    removed = False

    module_re = re.compile(r"^\s*module\s+{}\b".format(re.escape(module_name)))

    for line in lines:
        if not skipping and module_re.match(line):
            skipping = True
            removed = True
            out.append(
                "// Removed hardened macro module {}.\n".format(module_name)
            )
            continue

        if skipping:
            if line.strip() == "endmodule":
                skipping = False
            continue

        out.append(line)

    if skipping:
        raise RuntimeError(
            "Reached EOF while removing module {}".format(module_name)
        )
    if not removed:
        raise RuntimeError(
            "Did not find module definition for {}".format(module_name)
        )
    return "".join(out)


def read_core_module(module_names_tcl):
    text = module_names_tcl.read_text()
    match = re.search(r'set\s+CORE_MODULE\s+"([^"]+)"', text)
    if not match:
        raise RuntimeError(
            "Could not find CORE_MODULE in {}".format(module_names_tcl)
        )
    return match.group(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--module-names-tcl", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    core_module = read_core_module(args.module_names_tcl)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        remove_module_definition(args.netlist.read_text(), core_module)
    )
    print("Removed hardened macro module: {}".format(core_module))
    print("Top macro netlist: {}".format(args.output))


if __name__ == "__main__":
    main()
