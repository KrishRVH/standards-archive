"""Integer range helpers."""


def clamp(value: Int, low: Int, high: Int) -> Int:
    """Returns `value` limited to the closed range `[low, high]`.

    Args:
        value: The value to limit.
        low: The smallest permitted result.
        high: The largest permitted result; must not be below `low`.

    Returns:
        `low` below the range, `high` above it, and `value` otherwise.
    """
    if value < low:
        return low
    if value > high:
        return high
    return value
