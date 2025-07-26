"""
==========================================================================
RetRTL_test.py
==========================================================================
Test cases for functional unit Ret.

Author : Cheng Tan
  Date : September 21, 2021
"""

from pymtl3 import *
from ..RetRTL import RetRTL
from ....lib.basic.val_rdy.SourceRTL import SourceRTL as TestSrcRTL
from ....lib.basic.val_rdy.SinkRTL import SinkRTL as TestSinkRTL
from ....lib.opt_type import *
from ....lib.messages import *

#-------------------------------------------------------------------------
# Test harness
#-------------------------------------------------------------------------

class TestHarness(Component):

  def construct(s, FunctionUnit, DataType, PredicateType, CtrlType,
                num_inports, num_outports, data_mem_size, src_in,
                src_opt, sink):

    s.src_in = TestSrcRTL(DataType, src_in)
    s.src_opt = TestSrcRTL(CtrlType, src_opt)
    s.sink = TestSinkRTL(DataType, sink)

    s.dut = FunctionUnit(DataType, PredicateType, CtrlType, num_inports,
                         num_outports, data_mem_size )

    s.src_in.send //= s.dut.recv_in[0]
    s.src_opt.send //= s.dut.recv_opt
    s.dut.send_out[0] //= s.sink.recv

  def done(s):
    return s.src_opt.done() and s.sink.done()

  def line_trace(s):
    return s.dut.line_trace()

def run_sim(test_harness, max_cycles = 20):
  test_harness.elaborate()
  test_harness.apply(DefaultPassGroup())
  test_harness.sim_reset()

  # Run simulation
  ncycles = 0
  print()
  print("{}:{}".format( ncycles, test_harness.line_trace()))
  while not test_harness.done() and ncycles < max_cycles:
    test_harness.sim_tick()
    ncycles += 1
    print("{}:{}".format(ncycles, test_harness.line_trace()))

  # Check timeout
  assert ncycles < max_cycles

  test_harness.sim_tick()
  test_harness.sim_tick()
  test_harness.sim_tick()

def test_Ret():
  FU = RetRTL
  DataType = mk_data(16, 1)
  PredicateType = mk_predicate(1, 1)
  num_inports = 2
  num_outports = 2
  CtrlType = mk_ctrl(num_inports, num_outports)
  data_mem_size = 8
  FuInType = mk_bits(clog2(num_inports + 1))
  src_in =  [DataType(1, 1), DataType(2, 1), DataType(3, 0)]
  src_opt = [CtrlType(OPT_RET, [FuInType(1), FuInType(0)]),
             CtrlType(OPT_RET, [FuInType(1), FuInType(0)]),
             CtrlType(OPT_RET, [FuInType(1), FuInType(0)])]
  sink =    [DataType(1, 1), DataType(2, 1), DataType(3, 0)]
  th = TestHarness(FU, DataType, PredicateType, CtrlType, num_inports,
                   num_outports, data_mem_size, src_in, src_opt,
                   sink)
  run_sim(th)

