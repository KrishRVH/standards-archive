import Base
import ./LAWS.bend as Laws
import ./src/project_name.bend as P

def Laws.half_double(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Laws.half_double(p) : {1n+P.half(P.double(p)) == 1n+_ : Nat}
      {==}
