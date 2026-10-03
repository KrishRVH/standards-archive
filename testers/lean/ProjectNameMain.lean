module

import ProjectName.Counter

/-!
# project_name executable

Reads step sizes from the command line and prints the count saturated at 100.
String parsing stays here, outside the constructive library: core `String`
operations depend on `Classical.choice`.
-/

public section

/-- Prints the saturated count of the given steps, or rejects invalid input. -/
def main (args : List String) : IO UInt32 := do
  match args.mapM String.toNat? with
  | some steps =>
    IO.println (ProjectName.advanceAll 100 0 steps)
    pure 0
  | none =>
    IO.eprintln "every argument must be a natural number"
    pure 2

end
