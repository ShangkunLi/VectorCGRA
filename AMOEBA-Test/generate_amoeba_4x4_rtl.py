#!/usr/bin/env python3
"""Generate the AMOEBA 4x4 multi-CGRA RTL.

The generated top is a 4x4 mesh of CGRAs. Each CGRA is a 2x2 tile array,
contains the regular CGRA controller, uses regular CGRA tiles, and has
LoopCounter/ExtractPredicate FUs available in every tile.

This generator intentionally keeps the reusable VectorCGRA RTL files
untouched. It defines the AMOEBA physical top locally by composing regular
CGRA tiles, the regular CGRA controller, and one LoopControllerRTL per CGRA.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


DEFAULT_VECTOR_CGRA_ROOT = Path(__file__).resolve().parents[1]
if not (DEFAULT_VECTOR_CGRA_ROOT / "multi_cgra").exists():
    DEFAULT_VECTOR_CGRA_ROOT = Path("/home/lucas/Project/VectorCGRA")


def add_vector_cgra_to_path(vector_cgra_root: Path) -> None:
    project_root = vector_cgra_root.parent
    if str(project_root) not in sys.path:
        sys.path.insert(0, str(project_root))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate AMOEBA 4x4 multi-CGRA Verilog from PyMTL RTL."
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
        default="AmoebaMultiCgra4x4Cgra2x2RTL",
        help="Generated Verilog top module name.",
    )
    parser.add_argument(
        "--output-file",
        default="AmoebaMultiCgra4x4Cgra2x2RTL.v",
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


def build_dut(args: argparse.Namespace):
    add_vector_cgra_to_path(args.vector_cgra_root)

    from pymtl3 import Component, InPort, OutPort, Wire, clog2, mk_bits, update
    from pymtl3.passes.backends.verilog import VerilogPlaceholderPass
    from pymtl3.passes.backends.verilog.translation.VerilogTranslationPass import (
        VerilogTranslationPass,
    )

    from VectorCGRA.controller.ControllerRTL import ControllerRTL
    from VectorCGRA.controller.LoopControllerRTL import LoopControllerRTL
    from VectorCGRA.fu.double.SeqMulAdderRTL import SeqMulAdderRTL
    from VectorCGRA.fu.flexible.FlexibleFuRTL import FlexibleFuRTL
    from VectorCGRA.fu.single.AdderRTL import AdderRTL
    from VectorCGRA.fu.single.CompRTL import CompRTL
    from VectorCGRA.fu.single.ExtractPredicateRTL import ExtractPredicateRTL
    from VectorCGRA.fu.single.GrantRTL import GrantRTL
    from VectorCGRA.fu.single.LogicRTL import LogicRTL
    from VectorCGRA.fu.single.LoopCounterRTL import LoopCounterRTL
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
    from VectorCGRA.lib.cmd_type import (
        CMD_LC_CHILD_COMPLETE,
        CMD_LC_CHILD_RESET,
        CMD_LC_CONFIG_CHILD_COUNT,
        CMD_LC_CONFIG_LOWER,
        CMD_LC_CONFIG_PARENT,
        CMD_LC_CONFIG_STEP,
        CMD_LC_CONFIG_TARGET,
        CMD_LC_CONFIG_UPPER,
        CMD_LC_LAUNCH,
        CMD_LC_SYNC_VALUE,
        CMD_LEAF_COUNTER_COMPLETE,
    )
    from VectorCGRA.lib.messages import (
        mk_cgra_id_type,
        mk_cgra_payload,
        mk_ctrl,
        mk_data,
        mk_inter_cgra_pkt,
        mk_intra_cgra_pkt,
    )
    from VectorCGRA.lib.util.common import (
        KING_MESH,
        MESH,
        PORT_INDEX_EAST,
        PORT_INDEX_NORTH,
        PORT_INDEX_NORTHEAST,
        PORT_INDEX_NORTHWEST,
        PORT_INDEX_SOUTH,
        PORT_INDEX_SOUTHEAST,
        PORT_INDEX_SOUTHWEST,
        PORT_INDEX_WEST,
    )
    from VectorCGRA.lib.util.data_struct_attr import kAttrCtrl, kAttrData, kAttrPayload
    import VectorCGRA.mem.data.DataMemControllerRTL as data_mem_controller_module
    from VectorCGRA.mem.data.DataMemControllerRTL import DataMemControllerRTL
    import VectorCGRA.multi_cgra.MeshMultiCgraRTL as mesh_multi_cgra_module
    from VectorCGRA.noc.PyOCN.pymtl3_net.ocnlib.ifcs.positions import mk_ring_pos
    from VectorCGRA.noc.PyOCN.pymtl3_net.ringnet.RingNetworkRTL import (
        RingNetworkRTL,
    )
    from VectorCGRA.tile.TileRTL import TileRTL

    class LoopControllerWithRouteTargetsRTL(LoopControllerRTL):
        def construct(
            s,
            DataType,
            CtrlType,
            num_ccus=8,
            max_targets_per_ccu=4,
            data_mem_size=8,
            ctrl_mem_size=8,
            num_tiles=4,
            num_cgra_columns=1,
            num_cgra_rows=1,
        ):
            super().construct(
                DataType,
                CtrlType,
                num_ccus,
                max_targets_per_ccu,
                data_mem_size,
                ctrl_mem_size,
                num_tiles,
                num_cgra_columns,
                num_cgra_rows,
            )

            TileIdType = mk_bits(clog2(num_tiles + 1))
            CgraIdType = mk_bits(max(clog2(num_cgra_columns * num_cgra_rows), 1))
            s.send_to_tile_target = OutPort(TileIdType)
            s.send_to_remote_target_cgra = OutPort(CgraIdType)

            @update
            def expose_route_targets():
                active_ccu = s.active_dispatch_ccu
                target_idx = s.ccu_dispatch_idx[active_ccu]
                s.send_to_tile_target @= s.ccu_target_tile_ids[active_ccu][target_idx]
                s.send_to_remote_target_cgra @= (
                    s.ccu_target_cgra_ids[active_ccu][target_idx]
                )

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

    class CgraWithLoopControllerRTL(Component):
        def construct(
            s,
            CgraPayloadType,
            multi_cgra_rows,
            multi_cgra_columns,
            width,
            height,
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
            cgra_topology,
            controller2addr_map,
            idTo2d_map,
            is_multi_cgra=True,
            has_ctrl_ring=True,
        ):
            assert is_multi_cgra
            assert has_ctrl_ring
            assert cgra_topology == MESH or cgra_topology == KING_MESH

            DataType = CgraPayloadType.get_field_type(kAttrData)
            num_tiles = width * height
            num_rd_tiles = height + width - 1
            num_cgras = multi_cgra_rows * multi_cgra_columns
            controller_endpoint = num_tiles
            loop_controller_endpoint = num_tiles + 1

            CgraIdType = mk_cgra_id_type(multi_cgra_columns, multi_cgra_rows)
            CgraXType = mk_bits(max(clog2(multi_cgra_columns), 1))
            CgraYType = mk_bits(max(clog2(multi_cgra_rows), 1))
            CtrlPktType = mk_intra_cgra_pkt(
                multi_cgra_columns, multi_cgra_rows, num_tiles, CgraPayloadType
            )
            NocPktType = mk_inter_cgra_pkt(
                multi_cgra_columns,
                multi_cgra_rows,
                num_tiles,
                num_rd_tiles,
                CgraPayloadType,
            )

            s.num_mesh_ports = 4 if cgra_topology == MESH else 8
            s.num_tiles = num_tiles
            data_mem_num_rd_tiles = height + width - 1
            data_mem_num_wr_tiles = height + width - 1
            CtrlRingPos = mk_ring_pos(num_tiles + 2)
            DataAddrType = mk_bits(clog2(data_mem_size_global))

            s.recv_from_cpu_pkt = RecvIfcRTL(CtrlPktType)
            s.recv_from_inter_cgra_noc = RecvIfcRTL(NocPktType)
            s.send_to_inter_cgra_noc = SendIfcRTL(NocPktType)
            s.send_to_cpu_pkt = SendIfcRTL(CtrlPktType)

            s.recv_data_on_boundary_south = [
                RecvIfcRTL(DataType) for _ in range(width)
            ]
            s.send_data_on_boundary_south = [
                SendIfcRTL(DataType) for _ in range(width)
            ]
            s.recv_data_on_boundary_north = [
                RecvIfcRTL(DataType) for _ in range(width)
            ]
            s.send_data_on_boundary_north = [
                SendIfcRTL(DataType) for _ in range(width)
            ]
            s.recv_data_on_boundary_east = [
                RecvIfcRTL(DataType) for _ in range(height)
            ]
            s.send_data_on_boundary_east = [
                SendIfcRTL(DataType) for _ in range(height)
            ]
            s.recv_data_on_boundary_west = [
                RecvIfcRTL(DataType) for _ in range(height)
            ]
            s.send_data_on_boundary_west = [
                SendIfcRTL(DataType) for _ in range(height)
            ]

            s.tile = [
                TileRTL(
                    CtrlPktType,
                    ctrl_mem_size,
                    data_mem_size_global,
                    num_ctrl,
                    total_steps,
                    4,
                    2,
                    s.num_mesh_ports,
                    s.num_mesh_ports,
                    num_cgras,
                    s.num_tiles,
                    num_registers_per_reg_bank,
                    FuList=FuList,
                )
                for _ in range(s.num_tiles)
            ]
            s.data_mem = DataMemControllerRTL(
                NocPktType,
                data_mem_size_global,
                data_mem_size_per_bank,
                num_banks_per_cgra,
                data_mem_num_rd_tiles,
                data_mem_num_wr_tiles,
                multi_cgra_rows,
                multi_cgra_columns,
                s.num_tiles,
                mem_access_is_combinational,
                idTo2d_map,
            )
            s.controller = ControllerRTL(
                NocPktType,
                multi_cgra_rows,
                multi_cgra_columns,
                s.num_tiles,
                controller2addr_map,
                idTo2d_map,
            )
            s.loop_controller = LoopControllerWithRouteTargetsRTL(
                DataType,
                CgraPayloadType.get_field_type(kAttrCtrl),
                num_ccus=8,
                max_targets_per_ccu=4,
                data_mem_size=data_mem_size_global,
                ctrl_mem_size=ctrl_mem_size,
                num_tiles=s.num_tiles,
                num_cgra_columns=multi_cgra_columns,
                num_cgra_rows=multi_cgra_rows,
            )
            s.ctrl_ring = RingNetworkRTL(
                CtrlPktType, CtrlRingPos, num_tiles + 2, 1
            )
            s.cgra_id = InPort(CgraIdType)
            s.address_lower = InPort(DataAddrType)
            s.address_upper = InPort(DataAddrType)

            s.idTo2d_x_lut = [Wire(CgraXType) for _ in range(num_cgras)]
            s.idTo2d_y_lut = [Wire(CgraYType) for _ in range(num_cgras)]
            for cgra_id, xy in idTo2d_map.items():
                s.idTo2d_x_lut[cgra_id] //= CgraXType(xy[0])
                s.idTo2d_y_lut[cgra_id] //= CgraYType(xy[1])

            s.controller.cgra_id //= s.cgra_id
            s.data_mem.cgra_id //= s.cgra_id
            s.data_mem.address_lower //= s.address_lower
            s.data_mem.address_upper //= s.address_upper

            s.data_mem.recv_from_noc_load_request //= (
                s.controller.send_to_sram_load_request_from_noc
            )
            s.data_mem.recv_from_noc_store_request //= (
                s.controller.send_to_sram_store_request_from_noc
            )
            s.data_mem.recv_from_noc_load_response_pkt //= (
                s.controller.send_to_tile_load_response
            )
            s.data_mem.send_to_noc_load_request_pkt //= (
                s.controller.recv_from_tile_load_request_pkt
            )
            s.data_mem.send_to_noc_load_response_pkt //= (
                s.controller.recv_from_tile_load_response_pkt
            )
            s.data_mem.send_to_noc_store_pkt //= (
                s.controller.recv_from_tile_store_request_pkt
            )
            s.send_to_cpu_pkt //= s.controller.send_to_cpu_pkt

            for tile_id in range(s.num_tiles):
                s.tile[tile_id].tile_id //= tile_id
                s.tile[tile_id].cgra_id //= s.cgra_id
                s.ctrl_ring.send[tile_id] //= s.tile[
                    tile_id
                ].recv_from_controller_pkt
                s.ctrl_ring.recv[tile_id] //= s.tile[
                    tile_id
                ].send_to_controller_pkt

            s.ctrl_ring.recv[controller_endpoint] //= (
                s.controller.send_to_ctrl_ring_pkt
            )

            @update
            def route_cpu_and_noc_to_controllers():
                cpu_cmd = s.recv_from_cpu_pkt.msg.payload.cmd
                cpu_is_lc_config = (
                    (cpu_cmd == CMD_LC_CONFIG_LOWER)
                    | (cpu_cmd == CMD_LC_CONFIG_UPPER)
                    | (cpu_cmd == CMD_LC_CONFIG_STEP)
                    | (cpu_cmd == CMD_LC_CONFIG_CHILD_COUNT)
                    | (cpu_cmd == CMD_LC_CONFIG_TARGET)
                    | (cpu_cmd == CMD_LC_CONFIG_PARENT)
                    | (cpu_cmd == CMD_LC_LAUNCH)
                )
                cpu_is_local_lc = (
                    s.recv_from_cpu_pkt.val
                    & cpu_is_lc_config
                    & (s.recv_from_cpu_pkt.msg.dst_cgra_id == s.cgra_id)
                )

                noc_cmd = s.recv_from_inter_cgra_noc.msg.payload.cmd
                noc_is_lc_config = (
                    (noc_cmd == CMD_LC_CONFIG_LOWER)
                    | (noc_cmd == CMD_LC_CONFIG_UPPER)
                    | (noc_cmd == CMD_LC_CONFIG_STEP)
                    | (noc_cmd == CMD_LC_CONFIG_CHILD_COUNT)
                    | (noc_cmd == CMD_LC_CONFIG_TARGET)
                    | (noc_cmd == CMD_LC_CONFIG_PARENT)
                    | (noc_cmd == CMD_LC_LAUNCH)
                )
                noc_is_lc_remote = (
                    (noc_cmd == CMD_LC_SYNC_VALUE)
                    | (noc_cmd == CMD_LC_CHILD_COMPLETE)
                    | (noc_cmd == CMD_LC_CHILD_RESET)
                )

                s.controller.recv_from_cpu_pkt.val @= s.recv_from_cpu_pkt.val & (
                    ~cpu_is_local_lc
                )
                s.controller.recv_from_cpu_pkt.msg @= s.recv_from_cpu_pkt.msg
                if cpu_is_local_lc:
                    s.recv_from_cpu_pkt.rdy @= s.loop_controller.recv_config.rdy
                else:
                    s.recv_from_cpu_pkt.rdy @= (
                        s.controller.recv_from_cpu_pkt.rdy
                    )

                s.loop_controller.recv_config.val @= 0
                s.loop_controller.recv_config.msg @= CgraPayloadType(0, 0, 0, 0, 0)
                if cpu_is_local_lc:
                    s.loop_controller.recv_config.val @= s.recv_from_cpu_pkt.val
                    s.loop_controller.recv_config.msg @= (
                        s.recv_from_cpu_pkt.msg.payload
                    )
                elif s.recv_from_inter_cgra_noc.val & noc_is_lc_config:
                    s.loop_controller.recv_config.val @= (
                        s.recv_from_inter_cgra_noc.val
                    )
                    s.loop_controller.recv_config.msg @= (
                        s.recv_from_inter_cgra_noc.msg.payload
                    )

                s.loop_controller.recv_from_remote.val @= (
                    s.recv_from_inter_cgra_noc.val
                    & noc_is_lc_remote
                    & (~noc_is_lc_config)
                )
                s.loop_controller.recv_from_remote.msg @= (
                    s.recv_from_inter_cgra_noc.msg.payload
                )

                s.controller.recv_from_inter_cgra_noc.val @= (
                    s.recv_from_inter_cgra_noc.val
                    & (~noc_is_lc_config)
                    & (~noc_is_lc_remote)
                )
                s.controller.recv_from_inter_cgra_noc.msg @= (
                    s.recv_from_inter_cgra_noc.msg
                )
                if noc_is_lc_config:
                    if cpu_is_local_lc:
                        s.recv_from_inter_cgra_noc.rdy @= 0
                    else:
                        s.recv_from_inter_cgra_noc.rdy @= (
                            s.loop_controller.recv_config.rdy
                        )
                elif noc_is_lc_remote:
                    s.recv_from_inter_cgra_noc.rdy @= (
                        s.loop_controller.recv_from_remote.rdy
                    )
                else:
                    s.recv_from_inter_cgra_noc.rdy @= (
                        s.controller.recv_from_inter_cgra_noc.rdy
                    )

            @update
            def route_ring_events_to_regular_or_loop_controller():
                ring_pkt = s.ctrl_ring.send[controller_endpoint].msg
                ring_cmd = ring_pkt.payload.cmd
                is_leaf_complete = ring_cmd == CMD_LEAF_COUNTER_COMPLETE

                s.controller.recv_from_ctrl_ring_pkt.val @= (
                    s.ctrl_ring.send[controller_endpoint].val
                    & (~is_leaf_complete)
                )
                s.controller.recv_from_ctrl_ring_pkt.msg @= ring_pkt
                s.loop_controller.recv_from_tile.val @= (
                    s.ctrl_ring.send[controller_endpoint].val & is_leaf_complete
                )
                s.loop_controller.recv_from_tile.msg @= ring_pkt.payload
                if is_leaf_complete:
                    s.ctrl_ring.send[controller_endpoint].rdy @= (
                        s.loop_controller.recv_from_tile.rdy
                    )
                else:
                    s.ctrl_ring.send[controller_endpoint].rdy @= (
                        s.controller.recv_from_ctrl_ring_pkt.rdy
                    )
                s.ctrl_ring.send[loop_controller_endpoint].rdy @= 1

            @update
            def route_loop_controller_to_ctrl_ring():
                s.ctrl_ring.recv[loop_controller_endpoint].val @= (
                    s.loop_controller.send_to_tile.val
                )
                s.ctrl_ring.recv[loop_controller_endpoint].msg @= CtrlPktType(
                    loop_controller_endpoint,
                    s.loop_controller.send_to_tile_target,
                    s.cgra_id,
                    s.cgra_id,
                    s.idTo2d_x_lut[s.cgra_id],
                    s.idTo2d_y_lut[s.cgra_id],
                    s.idTo2d_x_lut[s.cgra_id],
                    s.idTo2d_y_lut[s.cgra_id],
                    0,
                    0,
                    s.loop_controller.send_to_tile.msg,
                )
                s.loop_controller.send_to_tile.rdy @= (
                    s.ctrl_ring.recv[loop_controller_endpoint].rdy
                )

            @update
            def route_to_inter_cgra_noc():
                s.controller.send_to_inter_cgra_noc.rdy @= 0
                s.loop_controller.send_to_remote.rdy @= 0
                if s.loop_controller.send_to_remote.val:
                    target_cgra = s.loop_controller.send_to_remote_target_cgra
                    s.send_to_inter_cgra_noc.val @= 1
                    s.send_to_inter_cgra_noc.msg @= NocPktType(
                        s.cgra_id,
                        target_cgra,
                        s.idTo2d_x_lut[s.cgra_id],
                        s.idTo2d_y_lut[s.cgra_id],
                        s.idTo2d_x_lut[target_cgra],
                        s.idTo2d_y_lut[target_cgra],
                        loop_controller_endpoint,
                        loop_controller_endpoint,
                        0,
                        0,
                        0,
                        s.loop_controller.send_to_remote.msg,
                    )
                    s.loop_controller.send_to_remote.rdy @= (
                        s.send_to_inter_cgra_noc.rdy
                    )
                else:
                    s.send_to_inter_cgra_noc.val @= (
                        s.controller.send_to_inter_cgra_noc.val
                    )
                    s.send_to_inter_cgra_noc.msg @= (
                        s.controller.send_to_inter_cgra_noc.msg
                    )
                    s.controller.send_to_inter_cgra_noc.rdy @= (
                        s.send_to_inter_cgra_noc.rdy
                    )

            for i in range(s.num_tiles):
                if i // width > 0:
                    s.tile[i].send_data[PORT_INDEX_SOUTH] //= s.tile[
                        i - width
                    ].recv_data[PORT_INDEX_NORTH]
                if i // width < height - 1:
                    s.tile[i].send_data[PORT_INDEX_NORTH] //= s.tile[
                        i + width
                    ].recv_data[PORT_INDEX_SOUTH]
                if i % width > 0:
                    s.tile[i].send_data[PORT_INDEX_WEST] //= s.tile[
                        i - 1
                    ].recv_data[PORT_INDEX_EAST]
                if i % width < width - 1:
                    s.tile[i].send_data[PORT_INDEX_EAST] //= s.tile[
                        i + 1
                    ].recv_data[PORT_INDEX_WEST]

                if cgra_topology == KING_MESH:
                    if i % width > 0 and i // width < height - 1:
                        s.tile[i].send_data[PORT_INDEX_NORTHWEST] //= s.tile[
                            i + width - 1
                        ].recv_data[PORT_INDEX_SOUTHEAST]
                        s.tile[i + width - 1].send_data[
                            PORT_INDEX_SOUTHEAST
                        ] //= s.tile[i].recv_data[PORT_INDEX_NORTHWEST]
                    if i % width < width - 1 and i // width < height - 1:
                        s.tile[i].send_data[PORT_INDEX_NORTHEAST] //= s.tile[
                            i + width + 1
                        ].recv_data[PORT_INDEX_SOUTHWEST]
                        s.tile[i + width + 1].send_data[
                            PORT_INDEX_SOUTHWEST
                        ] //= s.tile[i].recv_data[PORT_INDEX_NORTHEAST]

                    if i // width == 0:
                        s.tile[i].send_data[PORT_INDEX_SOUTHWEST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHWEST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHWEST].msg //= DataType(
                            0, 0
                        )
                        s.tile[i].send_data[PORT_INDEX_SOUTHEAST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHEAST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHEAST].msg //= DataType(
                            0, 0
                        )
                    if i // width == height - 1:
                        s.tile[i].send_data[PORT_INDEX_NORTHWEST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHWEST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHWEST].msg //= DataType(
                            0, 0
                        )
                        s.tile[i].send_data[PORT_INDEX_NORTHEAST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHEAST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHEAST].msg //= DataType(
                            0, 0
                        )
                    if i % width == 0 and i // width > 0:
                        s.tile[i].send_data[PORT_INDEX_SOUTHWEST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHWEST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHWEST].msg //= DataType(
                            0, 0
                        )
                    if i % width == 0 and i // width < height - 1:
                        s.tile[i].send_data[PORT_INDEX_NORTHWEST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHWEST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHWEST].msg //= DataType(
                            0, 0
                        )
                    if i % width == width - 1 and i // width > 0:
                        s.tile[i].send_data[PORT_INDEX_SOUTHEAST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHEAST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_SOUTHEAST].msg //= DataType(
                            0, 0
                        )
                    if i % width == width - 1 and i // width < height - 1:
                        s.tile[i].send_data[PORT_INDEX_NORTHEAST].rdy //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHEAST].val //= 0
                        s.tile[i].recv_data[PORT_INDEX_NORTHEAST].msg //= DataType(
                            0, 0
                        )

                if i // width == 0:
                    s.tile[i].send_data[PORT_INDEX_SOUTH] //= (
                        s.send_data_on_boundary_south[i % width]
                    )
                    s.tile[i].recv_data[PORT_INDEX_SOUTH] //= (
                        s.recv_data_on_boundary_south[i % width]
                    )
                if i // width == height - 1:
                    s.tile[i].send_data[PORT_INDEX_NORTH] //= (
                        s.send_data_on_boundary_north[i % width]
                    )
                    s.tile[i].recv_data[PORT_INDEX_NORTH] //= (
                        s.recv_data_on_boundary_north[i % width]
                    )
                if i % width == 0:
                    s.tile[i].send_data[PORT_INDEX_WEST] //= (
                        s.send_data_on_boundary_west[i // width]
                    )
                    s.tile[i].recv_data[PORT_INDEX_WEST] //= (
                        s.recv_data_on_boundary_west[i // width]
                    )
                if i % width == width - 1:
                    s.tile[i].send_data[PORT_INDEX_EAST] //= (
                        s.send_data_on_boundary_east[i // width]
                    )
                    s.tile[i].recv_data[PORT_INDEX_EAST] //= (
                        s.recv_data_on_boundary_east[i // width]
                    )

                if i % width == 0 or i // width == 0:
                    data_mem_port = width + i // width - 1 if i >= width else i % width
                    s.tile[i].to_mem_raddr //= s.data_mem.recv_raddr[data_mem_port]
                    s.tile[i].from_mem_rdata //= s.data_mem.send_rdata[data_mem_port]
                    s.tile[i].to_mem_waddr //= s.data_mem.recv_waddr[data_mem_port]
                    s.tile[i].to_mem_wdata //= s.data_mem.recv_wdata[data_mem_port]
                else:
                    s.tile[i].to_mem_raddr.rdy //= 0
                    s.tile[i].from_mem_rdata.val //= 0
                    s.tile[i].from_mem_rdata.msg //= DataType(0, 0, 0, 0)
                    s.tile[i].to_mem_waddr.rdy //= 0
                    s.tile[i].to_mem_wdata.rdy //= 0

        def line_trace(s):
            res = "||\n".join(
                [
                    (
                        "\n[cgra"
                        + str(s.cgra_id)
                        + "_tile"
                        + str(i)
                        + "]: "
                    )
                    + tile.line_trace()
                    + tile.ctrl_mem.line_trace()
                    for i, tile in enumerate(s.tile)
                ]
            )
            res += "\n :: [" + s.ctrl_ring.line_trace() + "]\n"
            res += "\n :: [" + s.loop_controller.line_trace() + "]\n"
            res += "\n :: [" + s.data_mem.line_trace() + "]\n"
            return res

    mesh_multi_cgra_module.CgraRTL = CgraWithLoopControllerRTL
    MeshMultiCgraRTL = mesh_multi_cgra_module.MeshMultiCgraRTL

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
        LoopCounterRTL,
        ExtractPredicateRTL,
        SeqMulAdderRTL,
        VectorMulComboRTL,
        VectorAdderComboRTL,
    ]

    dut = MeshMultiCgraRTL(
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


def enable_translation_recursively(component, translation_pass) -> None:
    component.set_metadata(translation_pass.enable, True)
    for child in component.get_child_components(repr):
        enable_translation_recursively(child, translation_pass)


def main() -> None:
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
        raise FileNotFoundError(f"PyMTL did not emit expected file: {output_path}")
    print(output_path)


if __name__ == "__main__":
    main()
