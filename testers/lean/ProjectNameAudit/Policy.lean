import Lean

/-!
# Audit policy

The project-specific inputs to the audit. Everything else in `ProjectNameAudit`
is generic. Each exception names one declaration and says why it exists.
-/

namespace ProjectNameAudit

open Lean

/-- The role a module plays, which selects the checks it must pass. -/
inductive Role where
  /-- Specifications: contracts, the vocabulary they use, and their uniqueness theorems. They
  import no implementation, so no contract can restate one. -/
  | spec
  /-- Shipped library code: every check applies, and every definition meets a contract. -/
  | library
  /-- The executable entry point: every check applies; `main` is exempt from contracts. -/
  | executable
  /-- Test harness code: no contracts, otherwise the library rules. -/
  | tests
  /-- This audit tool: lexical and formatting rules only. -/
  | audit
  deriving BEq, Repr

/-- Module roots the project owns, with their role. A module belongs to the first root that
is a prefix of its name. -/
def ownedRoots : List (Name × Role) :=
  [(`ProjectName.Spec, .spec), (`ProjectName, .library), (`ProjectNameMain, .executable),
    (`ProjectNameTests, .tests), (`ProjectNameAudit, .audit)]

/-- The role of an owned module, or `none` for a module the project does not own. -/
def roleOf (module : Name) : Option Role :=
  (ownedRoots.find? (fun (entry : Name × Role) => entry.1.isPrefixOf module)).map
    (fun (entry : Name × Role) => entry.2)

/-- Axioms any owned declaration may depend on. `Classical.choice` is excluded, so the
library stays constructive. -/
def allowedAxioms : List Name := [`propext, `Quot.sound]

/-- Extra axioms one declaration may depend on, keyed by module and declaration. -/
def axiomExceptions : List ((Name × Name) × List Name) :=
  [ -- Core `String` operations, including `String.toNat?`, depend on `Classical.choice`.
    -- Parsing therefore stays in the executable, outside the constructive library.
    ((`ProjectNameMain, `main), [`Classical.choice]),
    -- Plausible's generators and its test runner depend on `Classical.choice`.
    ((`ProjectNameTests, `checkProperty), [`Classical.choice]),
    ((`ProjectNameTests, `main), [`Classical.choice])]

/-- Unsafe functions one declaration's compiled code may call, keyed by module and declaration.
The compiler reaches these through core library code it specializes into the caller. -/
def unsafeCallExceptions : List ((Name × Name) × List Name) :=
  [ -- Plausible's runner is specialized with core `Array` iteration, which reads elements
    -- through `Array.ugetBorrowed` after a bounds check.
    ((`ProjectNameTests, `main), [`Array.ugetBorrowed])]

/-- Definitions exempt from meeting a contract, keyed by module and declaration. -/
def contractExemptions : List (Name × Name) :=
  [ -- The `IO` entry point has no pure statement to prove; tests run it end to end.
    (`ProjectNameMain, `main)]

/-- Contracts that deliberately admit more than one implementation, so they have no uniqueness
theorem, keyed by module and contract. Each entry needs a comment that says why. -/
def uniquenessExemptions : List (Name × Name) := []

/-- Dependencies the Lake manifest may contain. Each is pinned to a full commit. -/
def allowedPackages : List String := ["batteries", "plausible", "lean4export", "lean4lean"]

/-- Maximum line length in owned source, matching Mathlib. -/
def maxLineLength : Nat := 100

end ProjectNameAudit
