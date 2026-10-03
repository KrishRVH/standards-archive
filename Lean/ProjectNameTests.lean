module

import Plausible.Testable
import ProjectName.Counter

/-!
# ProjectName tests

The proofs in `ProjectName.Counter` cover the kernel's view of every
definition. The `decide` examples check concrete cases in the kernel at build
time. `main` runs the same cases and seeded Plausible properties against the
native binary, where compiler and runtime bugs would show.
-/

open ProjectName

example : advance 10 3 4 = 7 := by decide
example : advanceAll 10 0 [4, 4, 4] = 10 := by decide

/-- Fixed Plausible settings, so every run checks the same samples. -/
def propertyConfig : Plausible.Configuration :=
  { numInst := 1000, maxSize := 200, randomSeed := some 20260903, quiet := true }

/-- Reports one failed example and returns whether it passed. -/
def checkExample (name : String) (actual : Nat) (expected : Nat) : IO Bool := do
  if actual == expected then
    pure true
  else
    IO.eprintln s!"{name}: expected {expected}, got {actual}"
    pure false

open Plausible.Decorations in
/-- Runs one property and returns whether Plausible found no counterexample. -/
def checkProperty (name : String) (property : Prop)
    (decorated : DecorationsOf property := by mk_decorations)
    [Plausible.Testable decorated] : IO Bool := do
  match ← Plausible.Testable.checkIO decorated propertyConfig with
  | .success _ => pure true
  | .gaveUp attempts =>
    IO.eprintln s!"{name}: gave up after {attempts} attempts"
    pure false
  | .failure _ counterexample _ =>
    IO.eprintln s!"{name}: counterexample {counterexample}"
    pure false

/-- Runs every example and property; exits nonzero if any fails. -/
public def main : IO UInt32 := do
  let results : List Bool := [
    ← checkExample "advance below limit" (advance 10 3 4) 7,
    ← checkExample "advance saturates" (advance 10 8 4) 10,
    ← checkExample "advanceAll empty" (advanceAll 100 5 []) 5,
    ← checkExample "advanceAll saturates" (advanceAll 100 0 [30, 50, 40]) 100,
    ← checkProperty "advanceAll closed form"
      (∀ (limit : Nat) (count : Nat) (steps : List Nat),
        advanceAll limit count steps = min limit (count + steps.sum)),
    ← checkProperty "advanceAll bounded"
      (∀ (limit : Nat) (count : Nat) (steps : List Nat), advanceAll limit count steps ≤ limit),
    ← checkProperty "advanceAll append"
      (∀ (limit : Nat) (count : Nat) (first : List Nat) (second : List Nat),
        advanceAll limit (advanceAll limit count first) second =
          advanceAll limit count (first ++ second)),
    ← checkProperty "advance composes"
      (∀ (limit : Nat) (count : Nat) (first : Nat) (second : Nat),
        advance limit (advance limit count first) second =
          advance limit count (first + second))
  ]
  pure (if results.all (fun (passed : Bool) => passed) then 0 else 1)
