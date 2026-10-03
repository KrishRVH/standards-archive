import Base

# Doubles a natural number.
def double(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      1n+1n+double(p)

# Halves a natural number, rounding down.
def half(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+0n:
      0n
    case 1n+1n+p:
      1n+half(p)
