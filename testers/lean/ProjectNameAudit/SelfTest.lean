import ProjectNameAudit.Environment
import ProjectNameAudit.Source

/-!
# Audit self-test

Proves every audit rule fires. Each case is a small library module that breaks
one rule; the audit must report a finding containing the expected text. A clean
control case must produce no finding at all, so the rules also prove they do
not fire on compliant code. Cases are elaborated in memory, so the self-test
needs no build output.
-/

namespace ProjectNameAudit

open Lean System

/-- A source that must produce a finding containing `expected`, or none when `expected` is
empty. -/
structure SelfTestCase where
  /-- What the case breaks. -/
  name : String
  /-- The complete module source. -/
  source : String
  /-- Text the findings must contain; empty for the clean control. -/
  expected : String

/-- A compliant declaration with its specification, reused by cases that break one thing. -/
def cleanSource : String :=
  "/-! Clean. -/\n\nnamespace SelfTest\n\n/-- Doubles. -/\ndef double (count : Nat) : Nat :=\n" ++
    "  count + count\n\n/-- `double` adds a count to itself. -/\n" ++
    "theorem double_eq (count : Nat) : double count = count + count := by\n  rfl\n\n" ++
    "end SelfTest\n"

/-- Joins source lines, each ending in a newline. -/
def lines (parts : List String) : String :=
  String.join (parts.map (fun (part : String) => part ++ "\n"))

/-- Inserts a declaration into the clean source, before its namespace closes. -/
def withDecl (decl : String) : String :=
  cleanSource.replace "end SelfTest\n" (decl ++ "\nend SelfTest\n")

/-- Every self-test case. -/
def selfTestCases : List SelfTestCase :=
  [⟨"clean control", cleanSource, ""⟩,
    ⟨"sorry", withDecl (lines
        ["/-- Unproved. -/",
         "theorem unproved : double 1 = 2 := by",
         "  sorry"]),
      "banned keyword `sorry`"⟩,
    ⟨"sorry axiom", withDecl (lines
        ["/-- Unproved. -/",
         "theorem unproved : double 1 = 2 := by",
         "  sorry"]),
      "depends on axioms [sorryAx]"⟩,
    ⟨"axiom", withDecl (lines
        ["/-- Assumed. -/",
         "axiom assumed : double 1 = 3"]), "declares an axiom"⟩,
    ⟨"native_decide", withDecl (lines
        ["/-- Native. -/",
         "theorem native : double 1 = 2 := by",
         "  native_decide"]),
      "native_decide.ax"⟩,
    ⟨"decide +native", withDecl (lines
        ["/-- Native. -/",
         "theorem native : double 1 = 2 := by",
         "  decide +native"]),
      "native evaluation bypasses the kernel"⟩,
    ⟨"Classical.choice", withDecl (lines
        ["/-- Classical. -/",
         "theorem classical (count : Nat) :",
         "    double count = 0 ∨ ¬double count = 0 :=",
         "  Classical.em (double count = 0)"]),
      "depends on axioms [Classical.choice"⟩,
    ⟨"partial", withDecl (lines
        ["/-- Loops. -/",
         "partial def spin (count : Nat) : Nat :=",
         "  spin count",
         "",
         "/-- Spec. -/",
         "theorem spin_eq (count : Nat) : spin count = spin count := by",
         "  rfl"]),
      "declares an opaque constant"⟩,
    ⟨"unsafe", withDecl (lines
        ["/-- Unsafe. -/",
         "unsafe def raw (count : Nat) : Nat :=",
         "  count"]),
      "is unsafe"⟩,
    ⟨"noncomputable", withDecl (lines
        ["/-- Chosen. -/",
         "noncomputable def chosen (count : Nat) : Nat :=",
         "  Classical.choose ⟨count, rfl⟩"]),
      "is noncomputable"⟩,
    ⟨"implemented_by", withDecl (lines
        ["/-- Replaced. -/",
         "@[implemented_by double]",
         "def slow (count : Nat) : Nat :=",
         "  2 * count",
         "",
         "/-- Spec. -/",
         "theorem slow_eq (count : Nat) : slow count = 2 * count := by",
         "  rfl"]),
      "has its code replaced"⟩,
    ⟨"extern", withDecl (lines
        ["/-- External. -/",
         "@[extern \"c_double\"]",
         "def external (count : Nat) : Nat :=",
         "  count",
         "",
         "/-- Spec. -/",
         "theorem external_eq (count : Nat) : external count = count := by",
         "  rfl"]),
      "has an external implementation"⟩,
    ⟨"well-founded recursion", withDecl (lines
        ["/-- Halves. -/",
         "def halvings (count : Nat) : Nat :=",
         "  if h : count = 0 then 0 else halvings (count / 2) + 1",
         "termination_by count",
         "decreasing_by omega",
         "",
         "/-- Spec. -/",
         "theorem halvings_zero : halvings 0 = 0 := by",
         "  unfold halvings",
         "  rfl"]),
      "uses well-founded recursion"⟩,
    ⟨"missing spec", withDecl (lines
        ["/-- Triples. -/",
         "def triple (count : Nat) : Nat :=",
         "  count * 3"]),
      "no owned theorem states anything about it"⟩,
    ⟨"missing theorem docstring", withDecl (lines
        ["theorem double_zero : double 0 = 0 := by",
         "  rfl"]), "has no docstring"⟩,
    ⟨"simp without only", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_zero : double 0 = 0 := by",
         "  simp [double]"]),
      "simplifier call without `only`"⟩,
    ⟨"simp?", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_zero : double 0 = 0 := by",
         "  simp? [double]"]),
      "banned keyword `simp?`"⟩,
    ⟨"untyped binder", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_comm (count) : double count = count + count := by",
         "  rfl"]),
      "binder without a type"⟩,
    ⟨"untyped fun", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_fun : (fun count => double count) 1 = 2 := by",
         "  rfl"]),
      "fun binder without a type"⟩,
    ⟨"untyped let", withDecl (lines
        ["/-- Quadruples. -/",
         "def quadruple (count : Nat) : Nat :=",
         "  let twice := double count",
         "  double twice",
         "",
         "/-- Spec. -/",
         "theorem quadruple_eq (count : Nat) : quadruple count = double (double count) := by",
         "  rfl"]),
      "let or have without a type"⟩,
    ⟨"untyped intro", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_all : ∀ (count : Nat), double count = count + count := by",
         "  intro count",
         "  rfl"]),
      "intro without a type"⟩,
    ⟨"missing result type", withDecl (lines
        ["/-- Quadruples. -/",
         "def quadruple (count : Nat) :=",
         "  double (double count)",
         "",
         "/-- Spec. -/",
         "theorem quadruple_eq (count : Nat) : quadruple count = double (double count) := by",
         "  rfl"]),
      "definition without a result type"⟩,
    ⟨"set_option", withDecl (lines
        ["set_option maxHeartbeats 400000 in",
         "/-- Spec. -/",
         "theorem double_zero : double 0 = 0 := by",
         "  rfl"]),
      "banned keyword `set_option`"⟩,
    ⟨"#eval", withDecl (lines
        ["#eval double 2"]), "banned keyword `#eval`"⟩,
    ⟨"# command", withDecl (lines
        ["#version"]), "banned keyword `#version`"⟩,
    ⟨"array literal control", withDecl (lines
        ["/-- Pairs. -/",
         "def pair : Array Nat :=",
         "  #[1, 2]",
         "",
         "/-- Spec. -/",
         "theorem pair_eq : pair = #[1, 2] := by",
         "  rfl"]), ""⟩,
    ⟨"run_tac", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_zero : double 0 = 0 := by",
         "  run_tac pure ()",
         "  rfl"]),
      "banned keyword `run_tac`"⟩,
    ⟨"builtin_ command", withDecl (lines
        ["builtin_initialize started : Nat ← pure 0"]),
      "banned keyword `builtin_initialize`"⟩,
    ⟨"register_ command", withDecl (lines
        ["register_try?_tactic rfl"]),
      "banned keyword `register_try?_tactic`"⟩,
    ⟨"bv_decide", withDecl (lines
        ["/-- Spec. -/",
         "theorem bits : (1 : BitVec 2) + 1 = 2 := by",
         "  bv_decide"]),
      "banned keyword `bv_decide`"⟩,
    ⟨"exact?", withDecl (lines
        ["/-- Spec. -/",
         "theorem double_zero : double 0 = 0 := by",
         "  exact?"]),
      "banned keyword `exact?`"⟩,
    ⟨"macro", withDecl (lines
        ["/-- Shorthand. -/",
         "macro \"twice\" : term => `(2)"]),
      "banned keyword `macro`"⟩,
    ⟨"export", withDecl (lines
        ["/-- Exported. -/",
         "@[export project_double]",
         "def exported (count : Nat) : Nat :=",
         "  count",
         "",
         "/-- Spec. -/",
         "theorem exported_eq (count : Nat) : exported count = count := by",
         "  rfl"]),
      "banned attribute `export`"⟩,
    ⟨"init", withDecl (lines
        ["/-- Startup. -/",
         "def startup : IO Unit :=",
         "  pure ()",
         "",
         "/-- Initialized. -/",
         "@[init startup]",
         "def initialized : Nat :=",
         "  0"]),
      "banned attribute `init`"⟩,
    ⟨"builtin_ attribute", withDecl (lines
        ["/-- Startup. -/",
         "def startup : IO Unit :=",
         "  pure ()",
         "",
         "/-- Initialized. -/",
         "@[builtin_init startup]",
         "def initialized : Nat :=",
         "  0"]),
      "banned attribute `builtin_init`"⟩,
    ⟨"elaborator attribute", withDecl (lines
        ["/-- Elaborates. -/",
         "@[command_elab Lean.Parser.Command.check]",
         "def elaborate (count : Nat) : Nat :=",
         "  count"]),
      "banned attribute `command_elab`"⟩,
    ⟨"parser attribute", withDecl (lines
        ["/-- Parses. -/",
         "@[term_parser]",
         "def parse (count : Nat) : Nat :=",
         "  count"]),
      "banned attribute `term_parser`"⟩,
    ⟨"nolint", withDecl (lines
        ["/-- Exempted. -/",
         "@[nolint docBlame]",
         "def exempted (count : Nat) : Nat :=",
         "  count"]),
      "banned attribute `nolint`"⟩,
    ⟨"trailing whitespace", cleanSource.replace "namespace SelfTest\n" "namespace SelfTest \n",
      "trailing whitespace"⟩,
    ⟨"tab", cleanSource.replace "  count + count\n" "\tcount + count\n", "tab character"⟩,
    ⟨"carriage return", cleanSource.replace "namespace SelfTest\n" "namespace SelfTest\r\n",
      "carriage return"⟩,
    ⟨"bidirectional control", cleanSource.replace "/-- Doubles. -/"
      ("/-- Doubles." ++ (Char.ofNat 0x202E).toString ++ " -/"),
      "invisible or bidirectional control character"⟩,
    ⟨"long line", cleanSource.replace "/-- Doubles. -/"
      ("/-- " ++ "".pushn 'x' 100 ++ " -/"), "line longer than"⟩,
    ⟨"final newline", cleanSource ++ "\n", "file must end with exactly one newline"⟩]

/-- Every finding the audit reports for one case's source, as a library module. -/
def caseFindings (allowInitializers : BaseIO Unit) (source : String) : IO (Array Finding) := do
  let path : FilePath := "ProjectName" / "SelfTest.lean"
  let elaborated : Elaborated ← elaborateFile allowInitializers path source `ProjectName.SelfTest
  let fileMap : FileMap := source.toFileMap
  let mut findings : Array Finding := textFindings path source
  for command in elaborated.commands do
    for stx in command.topDown do
      for message in nodeMessages .library stx do
        let line : Nat := match stx.getPos? with
          | some pos => (fileMap.toPosition pos).line
          | none => 0
        findings := findings.push ⟨s!"{path}:{line}", message⟩
  let owned : Array OwnedDecl := ownedDecls elaborated.env
  pure (findings ++ (← declarationFindings elaborated.env owned))

/-- Runs every case and reports each one whose findings do not match its expectation. -/
def selfTest (allowInitializers : BaseIO Unit) : IO (Array Finding) := do
  let mut failures : Array Finding := #[]
  for testCase in selfTestCases do
    let found : Array Finding ← caseFindings allowInitializers testCase.source
    let rendered : Array String := found.map Finding.render
    let location : String := s!"self-test {testCase.name}"
    if testCase.expected.isEmpty then
      for line in rendered do
        failures := failures.push ⟨location, s!"control case reported {line}"⟩
    else if !rendered.any (fun (line : String) => (line.splitOn testCase.expected).length > 1)
    then
      failures := failures.push ⟨location, s!"expected a finding with `{testCase.expected}`"⟩
  pure failures

end ProjectNameAudit
