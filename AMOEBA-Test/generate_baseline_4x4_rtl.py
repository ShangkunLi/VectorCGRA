#!/usr/bin/env python3
"""Generate a baseline 4x4 multi-CGRA RTL.

This physical-evaluation design intentionally removes the AMOEBA-specific
loop controller and counter support:

* each CGRA core is the regular VectorCGRA CgraRTL,
* LoopCounter/ExtractPredicate FUs are not instantiated, and
* boundary tile data ports between neighboring CGRAs are tied off instead of
  being connected directly across CGRA boundaries.

The inter-CGRA packet mesh is still present, so the design remains a 4x4
multi-CGRA system with one regular controller per 2x2 CGRA core.
"""

import argparse
import os
import sys
from pathlib import Path


DEFAULT_VECTOR_CGRA_ROOT = Path(__file__).resolve().parents[1]
if not (DEFAULT_VECTOR_CGRA_ROOT / "multi_cgra").exists():
    DEFAULT_VECTOR_CGRA_ROOT = Path("/home/lucas/Project/VectorCGRA")


def add_vector_cgra_to_path(vector_cgra_root):
    project_root = vector_cgra_root.parent
    if str(project_root) not in sys.path:
        sys.path.insert(0, str(project_root))


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate baseline 4x4 multi-CGRA Verilog from PyMTL RTL."
    )
    parser.add_argument(
        "--vector-cgra-root",
        type=Path,
        default=DEFAULT_VECTOR_CGRA_ROOT,
        help="Path to the VectorCGRA PyMTL repository.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "generated",
        help="Directory for generated Verilog.",
    )
    parser.add_argument(
        "--module-name",
        default="BaselineMultiCgra4x4Cgra2x2RTL",
        help="Generated Verilog top module name.",
    )
    parser.add_argument(
        "--output-file",
        default="BaselineMultiCgra4x4Cgra2x2RTL.v",
        help="Generated Verilog filename.",
    )
    parser.add_argument("--multi-cgra-rows", type=int, default=4)
    parser.add_argument("--multi-cgra-columns", type=int, default=4)
    parser.add_argument("--cgra-tile-rows", type=int, default=2)
    parser.add_argument("--cgra-tile-columns", type=int, default=2)
    parser.add_argument("--ctrl-mem-size", type=int, default=20)
    parser.add_argument("--data-mem-size-per-bank", type=int, default=128)
    parser.add_argument("--num-banks-per-cgra", type=int, default=4)
    parser.add_argument("--num-registers-per-reg-bank", type=int, default=32)
    parser.add_argument(
        "--ctrl-steps-per-iter",
        type=int,
        default=20,
        help="Default dynamic control-memory count per iteration.",
    )
    parser.add_argument(
        "--total-ctrl-steps",
        type=int,
        default=20,
        help="Default dynamic control-memory total step budget.",
    )
    parser.add_argument(
        "--combinational-memory",
        action="store_true",
        help="Use combinational data memory access in the generated RTL.",
    )
    return parser.parse_args()


def build_dut(args):
    add_vector_cgra_to_path(args.vector_cgra_root)

    from pymtl3 import Component, update, clog2, mk_bits
    from pymtl3.passes.backends.verilog import VerilogPlaceholderPass
    from pymtl3.passes.backends.verilog.translation.VerilogTranslationPass import (
        VerilogTranslationPass,
    )

    from VectorCGRA.cgra.CgraRTL import CgraRTL
    from VectorCGRA.fu.double.SeqMulAdderRTL import SeqMulAdderRTL
    from VectorCGRA.fu.flexible.FlexibleFuRTL import FlexibleFuRTL
    from VectorCGRA.fu.single.AdderRTL import AdderRTL
    from VectorCGRA.fu.single.CompRTL import CompRTL
    from VectorCGRA.fu.single.GrantRTL import GrantRTL
    from VectorCGRA.fu.single.LogicRTL import LogicRTL
    from VectorCGRA.fu.single.MemUnitRTL import MemUnitRTL
    from VectorCGRA.fu.single.MulRTL import MulRTL
    from VectorCGRA.fu.single.PhiRTL import PhiRTL
    from VectorCGRA.fu.single.RetRTL import RetRTL
    from VectorCGRA.fu.single.SelRTL import SelRTL
    from VectorCGRA.fu.single.ShifterRTL import ShifterRTL
    from VectorCGRA.fu.vector.VectorAdderComboRTL import VectorAdderComboRTL
    from VectorCGRA.fu.vector.VectorMulComboRTL import VectorMulComboRTL
    from VectorCGRA.lib.basic.val_rdy.ifcs import ValRdyRecvIfcRTL as RecvIfcRTL
    from VectorCGRA.lib.basic.val_rdy.ifcs import ValRdySendIfcRTL as SendIfcRTL
    from VectorCGRA.lib.messages import (
        mk_cgra_payload,
        mk_ctrl,
        mk_data,
        mk_inter_cgra_pkt,
        mk_intra_cgra_pkt,
    )
    from VectorCGRA.lib.util.common import MESH
    from VectorCGRA.lib.util.data_struct_attr import kAttrData, kAttrPayload
    import VectorCGRA.mem.data.DataMemControllerRTL as data_mem_controller_module
    from VectorCGRA.noc.PyOCN.pymtl3_net.meshnet.MeshNetworkRTL import (
        MeshNetworkRTL,
    )
    from VectorCGRA.noc.PyOCN.pymtl3_net.ocnlib.ifcs.positions import mk_mesh_pos

    class SpmBankPhysicalStubRTL(Component):
        def construct(
            s,
            DataType,
            MemReadType,
            MemWriteType,
            MemResponseType,
            global_data_mem_size,
            per_bank_data_mem_size,
            is_combinational=True,
        ):
            s.recv_rd = RecvIfcRTL(MemReadType)
            s.recv_wr = RecvIfcRTL(MemWriteType)
            s.send = SendIfcRTL(MemResponseType)

            @update
            def respond_to_read_and_drop_write():
                s.recv_rd.rdy @= s.send.rdy
                s.recv_wr.rdy @= 1
                s.send.val @= s.recv_rd.val
                s.send.msg @= MemResponseType(
                    0, 0, 0, DataType(0, 0, 0, 0), 0, 0, 0
                )

                if s.recv_rd.val:
                    s.send.msg.src @= s.recv_rd.msg.dst
                    s.send.msg.dst @= s.recv_rd.msg.src
                    s.send.msg.addr @= s.recv_rd.msg.addr
                    s.send.msg.data @= DataType(0, 0, 0, 0)
                    s.send.msg.src_cgra @= s.recv_rd.msg.src_cgra
                    s.send.msg.src_tile @= s.recv_rd.msg.src_tile
                    s.send.msg.remote_src_port @= s.recv_rd.msg.remote_src_port

        def line_trace(s):
            return "spm_bank_physical_stub"

    data_mem_controller_module.DataMemWrapperRTL = SpmBankPhysicalStubRTL

    class MeshMultiCgraNoBoundaryTileLinksRTL(Component):
        def construct(
            s,
            CgraPayloadType,
            cgra_rows,
            cgra_columns,
            tile_rows,
            tile_columns,
            ctrl_mem_size,
            data_mem_size_global,
            data_mem_size_per_bank,
            num_banks_per_cgra,
            num_registers_per_reg_bank,
            num_ctrl,
            total_steps,
            mem_access_is_combinational,
            FunctionUnit,
            FuList,
            per_cgra_topology,
            controller2addr_map,
            support_task_switching=False,
        ):
            assert not support_task_switching
            assert per_cgra_topology == MESH

            CgraDataType = CgraPayloadType.get_field_type(kAttrData)
            num_tiles = tile_rows * tile_columns
            num_rd_tiles = tile_rows + tile_columns - 1
            num_cgras = cgra_rows * cgra_columns
            idTo2d_map = {}
            for cgra_row in range(cgra_rows):
                for cgra_col in range(cgra_columns):
                    cgra_id = cgra_row * cgra_columns + cgra_col
                    idTo2d_map[cgra_id] = (cgra_col, cgra_row)

            CtrlPktType = mk_intra_cgra_pkt(
                cgra_columns, cgra_rows, num_tiles, CgraPayloadType
            )
            NocPktType = mk_inter_cgra_pkt(
                cgra_columns, cgra_rows, num_tiles, num_rd_tiles, CgraPayloadType
            )
            MeshPos = mk_mesh_pos(cgra_columns, cgra_rows)
            DataAddrType = mk_bits(clog2(data_mem_size_global))

            s.recv_from_cpu_pkt = RecvIfcRTL(CtrlPktType)
            s.send_to_cpu_pkt = SendIfcRTL(CtrlPktType)

            s.cgra = [
                CgraRTL(
                    CgraPayloadType,
                    cgra_rows,
                    cgra_columns,
                    tile_columns,
                    tile_rows,
                    ctrl_mem_size,
                    data_mem_size_global,
                    data_mem_size_per_bank,
                    num_banks_per_cgra,
                    num_registers_per_reg_bank,
                    num_ctrl,
                    total_steps,
                    mem_access_is_combinational,
                    FunctionUnit,
                    FuList,
                    per_cgra_topology,
                    controller2addr_map,
                    idTo2d_map,
                    has_ctrl_ring=True,
                )
                for _ in range(num_cgras)
            ]
            s.mesh = MeshNetworkRTL(NocPktType, MeshPos, cgra_columns, cgra_rows, 1)

            for cgra_id in range(num_cgras):
                s.mesh.send[cgra_id] //= s.cgra[cgra_id].recv_from_inter_cgra_noc
                s.mesh.recv[cgra_id] //= s.cgra[cgra_id].send_to_inter_cgra_noc
                s.cgra[cgra_id].cgra_id //= cgra_id
                s.cgra[cgra_id].address_lower //= DataAddrType(
                    controller2addr_map[cgra_id][0]
                )
                s.cgra[cgra_id].address_upper //= DataAddrType(
                    controller2addr_map[cgra_id][1]
                )

            s.recv_from_cpu_pkt //= s.cgra[0].recv_from_cpu_pkt
            s.send_to_cpu_pkt //= s.cgra[0].send_to_cpu_pkt

            for cgra_id in range(1, num_cgras):
                s.cgra[cgra_id].recv_from_cpu_pkt.val //= 0
                s.cgra[cgra_id].recv_from_cpu_pkt.msg //= CtrlPktType()
                s.cgra[cgra_id].send_to_cpu_pkt.rdy //= 0

            # Baseline physical design: no direct boundary-tile data links
            # between neighboring CGRAs. All cross-CGRA movement must go
            # through the inter-CGRA packet mesh and regular controllers.
            for cgra_id in range(num_cgras):
                for tile_col in range(tile_columns):
                    s.cgra[cgra_id].send_data_on_boundary_south[tile_col].rdy //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_south[tile_col].val //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_south[tile_col].msg //= (
                        CgraDataType()
                    )
                    s.cgra[cgra_id].send_data_on_boundary_north[tile_col].rdy //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_north[tile_col].val //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_north[tile_col].msg //= (
                        CgraDataType()
                    )
                for tile_row in range(tile_rows):
                    s.cgra[cgra_id].send_data_on_boundary_west[tile_row].rdy //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_west[tile_row].val //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_west[tile_row].msg //= (
                        CgraDataType()
                    )
                    s.cgra[cgra_id].send_data_on_boundary_east[tile_row].rdy //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_east[tile_row].val //= 0
                    s.cgra[cgra_id].recv_data_on_boundary_east[tile_row].msg //= (
                        CgraDataType()
                    )

        def line_trace(s):
            return "baseline_multi_cgra"

    num_cgras = args.multi_cgra_rows * args.multi_cgra_columns
    data_mem_size_global = (
        args.data_mem_size_per_bank * args.num_banks_per_cgra * num_cgras
    )
    per_cgra_data_size = data_mem_size_global // num_cgras
    controller2addr_map = {
        cgra_id: [
            cgra_id * per_cgra_data_size,
            (cgra_id + 1) * per_cgra_data_size - 1,
        ]
        for cgra_id in range(num_cgras)
    }

    num_fu_inports = 4
    num_fu_outports = 2
    num_tile_inports = 4
    num_tile_outports = 4

    DataType = mk_data(32, 1)
    DataAddrType = mk_bits(clog2(data_mem_size_global))
    CtrlType = mk_ctrl(
        num_fu_inports,
        num_fu_outports,
        num_tile_inports,
        num_tile_outports,
        args.num_registers_per_reg_bank,
    )
    CtrlAddrType = mk_bits(clog2(args.ctrl_mem_size))
    CgraPayloadType = mk_cgra_payload(
        DataType,
        DataAddrType,
        CtrlType,
        CtrlAddrType,
    )

    fu_list = [
        AdderRTL,
        MulRTL,
        LogicRTL,
        ShifterRTL,
        PhiRTL,
        CompRTL,
        GrantRTL,
        MemUnitRTL,
        SelRTL,
        RetRTL,
        SeqMulAdderRTL,
        VectorMulComboRTL,
        VectorAdderComboRTL,
    ]

    dut = MeshMultiCgraNoBoundaryTileLinksRTL(
        CgraPayloadType,
        args.multi_cgra_rows,
        args.multi_cgra_columns,
        args.cgra_tile_rows,
        args.cgra_tile_columns,
        args.ctrl_mem_size,
        data_mem_size_global,
        args.data_mem_size_per_bank,
        args.num_banks_per_cgra,
        args.num_registers_per_reg_bank,
        args.ctrl_steps_per_iter,
        args.total_ctrl_steps,
        args.combinational_memory,
        FlexibleFuRTL,
        fu_list,
        MESH,
        controller2addr_map,
        support_task_switching=False,
    )
    return dut, VerilogPlaceholderPass, VerilogTranslationPass


def enable_translation_recursively(component, translation_pass):
    component.set_metadata(translation_pass.enable, True)
    for child in component.get_child_components(repr):
        enable_translation_recursively(child, translation_pass)


def main():
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    dut, placeholder_pass, translation_pass = build_dut(args)
    old_cwd = Path.cwd()
    os.chdir(args.output_dir)
    try:
        dut.elaborate()
        dut.set_metadata(translation_pass.explicit_module_name, args.module_name)
        dut.set_metadata(translation_pass.explicit_file_name, args.output_file)
        dut.apply(placeholder_pass())
        enable_translation_recursively(dut, translation_pass)
        dut.apply(translation_pass())
    finally:
        os.chdir(old_cwd)

    output_path = args.output_dir / args.output_file
    if not output_path.exists():
        raise FileNotFoundError("PyMTL did not emit expected file: {}".format(output_path))
    print(output_path)


if __name__ == "__main__":
    main()
