module

public import ProjectName.Spec.Counter

/-!
# Saturating counter

A counter that advances by non-negative steps and never exceeds a limit. Each
definition meets its contract in `ProjectName.Spec.Counter`.
-/

@[expose] public section

namespace ProjectName

/-- Adds `step` to `count`, saturating at `limit`. -/
def advance (limit : Nat) (count : Nat) (step : Nat) : Nat :=
  min limit (count + step)

/-- Applies every step in order, saturating at `limit` after each one. -/
def advanceAll (limit : Nat) (count : Nat) : List Nat → Nat
  | [] => min limit count
  | step :: rest => advanceAll limit (advance limit count step) rest

/-- `advance` meets its contract. -/
theorem advance_spec : AdvanceSpec advance := by
  intro (limit : Nat) (count : Nat) (step : Nat)
  rfl

/-- `advanceAll` meets its contract. -/
theorem advanceAll_spec : AdvanceAllSpec advanceAll := by
  intro (limit : Nat) (count : Nat) (steps : List Nat)
  induction steps generalizing count with
  | nil =>
    simp only [advanceAll, List.sum_nil, Nat.add_zero]
  | cons step rest ih =>
    simp only [advanceAll, ih, advance, List.sum_cons]
    omega

end ProjectName

end
