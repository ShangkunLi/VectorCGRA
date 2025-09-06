"""
==========================================================================
FpMulRTL_test.py
==========================================================================
Test cases for floating-point muliplier.

Author : Cheng Tan
  Date : August 10, 2023
"""

from pymtl3 import *
from pymtl3.stdlib.test_utils import (run_sim,
                                      config_model_with_cmdline_opts)
from ..FpMulRTL import FpMulRTL
from ...pymtl3_hardfloat.HardFloat.converter_funcs import (floatToFN,
                                                           fNToFloat)
from ....lib.basic.val_rdy.SinkRTL import SinkRTL as TestSinkRTL
from ....lib.basic.val_rdy.SourceRTL import SourceRTL as TestSrcRTL
from ....lib.messages import *
from ....lib.opt_type import *
from ....mem.const.ConstQueueRTL import ConstQueueRTL

round_near_even = 0b000

def test_elaborate(cmdline_opts):
  exp_nbits = 4
  sig_nbits = 11
  data_bitwidth = 1 + exp_nbits + sig_nbits
  DataType       = mk_data(16, 1)
  PredType       = mk_predicate(1, 1)
  data_mem_size  = 8
  num_inports    = 2
  num_outports   = 1
  ConfigType     = mk_ctrl(num_inports, num_outports)
  FuInType       = mk_bits(clog2(num_inports + 1))
  pick_register  = [FuInType(x + 1) for x in range(num_inports)]
  src_in0        = [DataType(2,  1), DataType(7,  1), DataType(4,  1)]
  src_in1        = [                 DataType(3,  1)                 ]
  src_const      = [DataType(5,  1),                  DataType(7,  1)]
  sink_out       = [DataType(10, 0), DataType(21, 0), DataType(28, 1)]
  src_opt        = [ConfigType(OPT_MUL_CONST, pick_register),
                    ConfigType(OPT_MUL,       pick_register),
                    ConfigType(OPT_MUL_CONST, pick_register)]
  dut = FpMulRTL(DataType, PredType, ConfigType, num_inports,
                 num_outports, data_mem_size,
                 data_bitwidth = data_bitwidth,
                 exp_nbits = exp_nbits,
                 sig_nbits = sig_nbits)
  dut = config_model_with_cmdline_opts(dut, cmdline_opts, duts = [])

#-------------------------------------------------------------------------
# Test harness
#-------------------------------------------------------------------------

class TestHarness(Component):

  def construct(s, FunctionUnit, DataType, PredType, ConfigType,
                data_bitwidth,
                num_inports, num_outports, data_mem_size,
                exp_nbits, sig_nbits,
                src0_msgs, src1_msgs, src_const,
                ctrl_msgs, sink_msgs):

    s.src_in0  = TestSrcRTL (DataType,   src0_msgs)
    s.src_in1  = TestSrcRTL (DataType,   src1_msgs)
    s.src_opt  = TestSrcRTL (ConfigType, ctrl_msgs)
    s.sink_out = TestSinkRTL(DataType,   sink_msgs)

    s.const_queue = ConstQueueRTL(DataType, src_const)
    s.dut = FunctionUnit(DataType, PredType, ConfigType,
                         num_inports, num_outports,
                         data_mem_size,
                         data_bitwidth,
                         exp_nbits,
                         sig_nbits)

    connect(s.src_in0.send,    s.dut.recv_in[0]        )
    connect(s.src_in1.send,    s.dut.recv_in[1]        )
    connect(s.dut.recv_const,  s.const_queue.send_const)
    connect(s.src_opt.send,    s.dut.recv_opt          )
    connect(s.dut.send_out[0], s.sink_out.recv         )

  def done(s):
    return s.src_in0.done() and s.src_in1.done() and \
           s.src_opt.done() and s.sink_out.done()

  def line_trace(s):
    return s.dut.line_trace()

def mk_float_to_bits_fn(DataType, exp_nbits = 4, sig_nbits = 11):
  return lambda f_value, predicate: (
      DataType(floatToFN(f_value,
                         precision = 1 + exp_nbits + sig_nbits),
               predicate))

def test_mul():
  FU            = FpMulRTL
  exp_nbits     = 4
  sig_nbits     = 11
  data_bitwidth = 1 + exp_nbits + sig_nbits
  DataType      = mk_data(data_bitwidth, 1)
  f2b           = mk_float_to_bits_fn(DataType, exp_nbits, sig_nbits)
  PredType      = mk_predicate(1, 1)
  data_mem_size = 8
  num_inports   = 2
  num_outports  = 1
  ConfigType    = mk_ctrl(num_inports, num_outports)
  FuInType      = mk_bits(clog2(num_inports + 1))
  pick_register = [FuInType(x + 1) for x in range(num_inports)]
  src_in0       = [f2b(2.2,  1), f2b(7.7,  1), f2b(4.4,   1) ]
  src_in1       = [              f2b(3.3,  0)                ]
  src_const     = [f2b(5.5,  1),               f2b(7.7,   1) ]
  sink_out      = [f2b(12.1, 1), f2b(25.4, 0), f2b(33.88, 1) ] # 25.41 -> 25.4
  src_opt       = [ConfigType(OPT_FMUL_CONST, pick_register),
                   ConfigType(OPT_FMUL,       pick_register),
                   ConfigType(OPT_FMUL_CONST, pick_register)]
  th = TestHarness(FU, DataType, PredType, ConfigType,
                   data_bitwidth, num_inports, num_outports,
                   data_mem_size, exp_nbits, sig_nbits,
                   src_in0, src_in1, src_const, src_opt,
                   sink_out)
  run_sim(th)
