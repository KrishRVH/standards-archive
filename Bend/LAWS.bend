import Base
import ./src/project_name.bend as P

# Halving undoes doubling.
law half_double:
  for n: Nat
  {P.half(P.double(n)) == n : Nat}
