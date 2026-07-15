#!/usr/bin/env python3

import unittest

from extract_dc_area_breakdown import AreaRow, build_breakdown, is_dcu_design


class ExtractDcAreaBreakdownTest(unittest.TestCase):
    def test_limited_loop_counter_is_a_dcu(self):
        self.assertTrue(is_dcu_design("LimitedLoopCounterRTL__34612bfe96034fdc_63"))

    def test_dcu_area_is_extracted_from_tile_fu(self):
        rows = [
            AreaRow("top", 100.0, 100.0, 0.0, 0.0, 0.0, "TopRTL"),
            AreaRow("cgra__0/tile__0", 20.0, 20.0, 0.0, 0.0, 0.0, "TileRTL"),
            AreaRow(
                "cgra__0/tile__0/element",
                10.0,
                10.0,
                0.0,
                0.0,
                0.0,
                "ElementRTL",
            ),
            AreaRow(
                "cgra__0/tile__0/element/fu__10",
                3.0,
                3.0,
                0.0,
                0.0,
                0.0,
                "LimitedLoopCounterRTL__hash",
            ),
        ]

        breakdown = dict(build_breakdown(rows, "none"))

        self.assertEqual(breakdown["  DCUs"], 3.0)
        self.assertEqual(breakdown["  Other FUs"], 7.0)


if __name__ == "__main__":
    unittest.main()
