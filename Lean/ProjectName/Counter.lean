module

/-!
# Saturating counter

A counter that advances by non-negative steps and never exceeds a limit. Every
definition carries a complete functional specification: a closed form, its
bounds, its monotonicity, and how it composes.
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

/-- `advance` is exactly the clamped sum. -/
theorem advance_eq (limit : Nat) (count : Nat) (step : Nat) :
    advance limit count step = min limit (count + step) := by
  rfl

/-- `advance` never exceeds the limit. -/
theorem advance_le_limit (limit : Nat) (count : Nat) (step : Nat) :
    advance limit count step ≤ limit := by
  unfold advance
  omega

/-- Below the limit, `advance` is plain addition. -/
theorem advance_of_le (limit : Nat) (count : Nat) (step : Nat)
    (h : count + step ≤ limit) : advance limit count step = count + step := by
  unfold advance
  omega

/-- At or past the limit, `advance` returns the limit. -/
theorem advance_of_ge (limit : Nat) (count : Nat) (step : Nat)
    (h : limit ≤ count + step) : advance limit count step = limit := by
  unfold advance
  omega

/-- `advance` never moves below the clamped starting count. -/
theorem min_le_advance (limit : Nat) (count : Nat) (step : Nat) :
    min limit count ≤ advance limit count step := by
  unfold advance
  omega

/-- `advance` is monotone in the starting count. -/
theorem advance_mono_count (limit : Nat) (low : Nat) (high : Nat) (step : Nat)
    (h : low ≤ high) : advance limit low step ≤ advance limit high step := by
  unfold advance
  omega

/-- `advance` is monotone in the step. -/
theorem advance_mono_step (limit : Nat) (count : Nat) (low : Nat) (high : Nat)
    (h : low ≤ high) : advance limit count low ≤ advance limit count high := by
  unfold advance
  omega

/-- A zero step only clamps. -/
theorem advance_zero (limit : Nat) (count : Nat) :
    advance limit count 0 = min limit count := by
  unfold advance
  omega

/-- Two advances compose into one advance by the summed step. -/
theorem advance_advance (limit : Nat) (count : Nat) (first : Nat) (second : Nat) :
    advance limit (advance limit count first) second =
      advance limit count (first + second) := by
  unfold advance
  omega

/-- `advanceAll` on no steps only clamps. -/
theorem advanceAll_nil (limit : Nat) (count : Nat) :
    advanceAll limit count [] = min limit count := by
  rfl

/-- `advanceAll` takes one `advance` and continues with the rest. -/
theorem advanceAll_cons (limit : Nat) (count : Nat) (step : Nat) (rest : List Nat) :
    advanceAll limit count (step :: rest) =
      advanceAll limit (advance limit count step) rest := by
  rfl

/-- `advanceAll` is the limit-clamped sum of the count and every step. -/
theorem advanceAll_eq (limit : Nat) (count : Nat) (steps : List Nat) :
    advanceAll limit count steps = min limit (count + steps.sum) := by
  induction steps generalizing count with
  | nil =>
    simp only [advanceAll, List.sum_nil, Nat.add_zero]
  | cons step rest ih =>
    simp only [advanceAll, ih, advance, List.sum_cons]
    omega

/-- `advanceAll` never exceeds the limit. -/
theorem advanceAll_le_limit (limit : Nat) (count : Nat) (steps : List Nat) :
    advanceAll limit count steps ≤ limit := by
  rw [advanceAll_eq]
  omega

/-- `advanceAll` never moves below the clamped starting count. -/
theorem min_le_advanceAll (limit : Nat) (count : Nat) (steps : List Nat) :
    min limit count ≤ advanceAll limit count steps := by
  rw [advanceAll_eq]
  omega

/-- `advanceAll` is monotone in the starting count. -/
theorem advanceAll_mono_count (limit : Nat) (low : Nat) (high : Nat) (steps : List Nat)
    (h : low ≤ high) : advanceAll limit low steps ≤ advanceAll limit high steps := by
  rw [advanceAll_eq, advanceAll_eq]
  omega

/-- Running two step lists in sequence equals running their concatenation. -/
theorem advanceAll_append (limit : Nat) (count : Nat) (first : List Nat)
    (second : List Nat) :
    advanceAll limit (advanceAll limit count first) second =
      advanceAll limit count (first ++ second) := by
  rw [advanceAll_eq, advanceAll_eq, advanceAll_eq, List.sum_append]
  omega

/-- The order of steps does not change the result. -/
theorem advanceAll_perm (limit : Nat) (count : Nat) (steps : List Nat)
    (reordered : List Nat) (h : steps.Perm reordered) :
    advanceAll limit count steps = advanceAll limit count reordered := by
  rw [advanceAll_eq, advanceAll_eq, List.Perm.sum_nat h]

/-- A single step through `advanceAll` agrees with `advance`. -/
theorem advanceAll_singleton (limit : Nat) (count : Nat) (step : Nat) :
    advanceAll limit count [step] = advance limit count step := by
  rw [advanceAll_eq]
  unfold advance
  simp only [List.sum_cons, List.sum_nil, Nat.add_zero]

end ProjectName

end
