module

/-!
# Saturating counter specification

The contracts the counter in `ProjectName.Counter` meets. Each contract is a
predicate on the implementation, and this module cannot import the
implementation, so no contract can restate it. Each contract has a uniqueness
theorem: at most one function meets it, so the contract fixes the
implementation's behavior completely.
-/

@[expose] public section

namespace ProjectName

/-- `advance limit count step` adds `step` to `count`, saturating at `limit`. -/
def AdvanceSpec (advance : Nat → Nat → Nat → Nat) : Prop :=
  ∀ (limit : Nat) (count : Nat) (step : Nat), advance limit count step = min limit (count + step)

/-- At most one function meets `AdvanceSpec`. -/
theorem AdvanceSpec.unique (first : Nat → Nat → Nat → Nat) (second : Nat → Nat → Nat → Nat)
    (hFirst : AdvanceSpec first) (hSecond : AdvanceSpec second) : first = second := by
  funext (limit : Nat) (count : Nat) (step : Nat)
  exact (hFirst limit count step).trans (hSecond limit count step).symm

/-- `advanceAll limit count steps` adds every step to `count`, saturating at `limit`. Steps are
never negative, so saturating after each step and saturating once at the end agree. -/
def AdvanceAllSpec (advanceAll : Nat → Nat → List Nat → Nat) : Prop :=
  ∀ (limit : Nat) (count : Nat) (steps : List Nat),
    advanceAll limit count steps = min limit (count + steps.sum)

/-- At most one function meets `AdvanceAllSpec`. -/
theorem AdvanceAllSpec.unique (first : Nat → Nat → List Nat → Nat)
    (second : Nat → Nat → List Nat → Nat) (hFirst : AdvanceAllSpec first)
    (hSecond : AdvanceAllSpec second) : first = second := by
  funext (limit : Nat) (count : Nat) (steps : List Nat)
  exact (hFirst limit count steps).trans (hSecond limit count steps).symm

end ProjectName

end
