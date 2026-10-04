from std.testing import TestSuite, assert_equal

from project_name import clamp


def test_clamp_keeps_value_inside_range() raises:
    assert_equal(clamp(5, 0, 10), 5)


def test_clamp_lifts_value_below_range() raises:
    assert_equal(clamp(-3, 0, 10), 0)


def test_clamp_lowers_value_above_range() raises:
    assert_equal(clamp(12, 0, 10), 10)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
