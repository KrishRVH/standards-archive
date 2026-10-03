import Batteries.Tactic.Lint
import ProjectNameAudit.Finding
import ProjectNameAudit.Policy

/-!
# Environment audit

Checks the compiled declarations of the owned modules, as the kernel accepted
them: the axioms each one depends on, escape hatches the source rules could miss,
spec coverage, documentation, every Batteries environment linter, and the
compiled IR. Policy exceptions must match a declaration and must still be needed.
-/

namespace ProjectNameAudit

open Lean Batteries.Tactic.Lint

/-- A constant declared in an owned module. -/
structure OwnedDecl where
  /-- The constant's name in the environment; private names are mangled. -/
  name : Name
  /-- The name as written in source, which policy exceptions use. -/
  userName : Name
  /-- The declaring module. -/
  module : Name
  /-- The declaring module's role. -/
  role : Role
  /-- The kernel's view of the constant. -/
  info : ConstantInfo

/-- Renders an owned declaration for findings. -/
def OwnedDecl.label (decl : OwnedDecl) : String :=
  s!"{decl.module}:{decl.userName}"

/-- Adds a constant to `acc` if its module is owned. -/
def addOwned (acc : Array OwnedDecl) (module : Name) (name : Name) (info : ConstantInfo) :
    Array OwnedDecl :=
  match roleOf module with
  | some role =>
    acc.push { name, userName := (privateToUserName? name).getD name, module, role, info }
  | none => acc

/-- Every constant declared in an owned module, imported or elaborated in this environment,
sorted by name. -/
def ownedDecls (env : Environment) : Array OwnedDecl :=
  let imported : Array OwnedDecl := env.constants.map₁.fold
    (fun (acc : Array OwnedDecl) (name : Name) (info : ConstantInfo) =>
      let module? : Option Name := do
        let index : ModuleIdx ← env.getModuleIdxFor? name
        env.header.moduleNames[index.toNat]?
      match module? with
      | some module => addOwned acc module name info
      | none => acc)
    #[]
  let found : Array OwnedDecl := env.constants.map₂.foldl
    (fun (acc : Array OwnedDecl) (name : Name) (info : ConstantInfo) =>
      addOwned acc env.mainModule name info)
    imported
  found.qsort (fun (left : OwnedDecl) (right : OwnedDecl) => left.name.lt right.name)

/-- Whether a declaration is compiler or elaborator output rather than written source. -/
def isGenerated (env : Environment) (decl : OwnedDecl) : Bool :=
  decl.userName.isInternalDetail || env.isAutoDecl decl.name ||
    decl.info matches .ctorInfo _ || decl.info matches .recInfo _

/-- The exception entries for one declaration in a keyed exception list. -/
def exceptionFor (exceptions : List ((Name × Name) × List Name)) (decl : OwnedDecl) :
    List Name :=
  (exceptions.lookup (decl.module, decl.userName)).getD []

/-- Whether a constant is one of the well-founded fixpoint combinators, such as
`WellFounded.fix` or `WellFounded.Nat.fix`, that non-structural recursion compiles to. -/
def isFixpoint (name : Name) : Bool :=
  (`WellFounded).isPrefixOf name &&
    (match name with
      | .str _ last => last.startsWith "fix"
      | _ => false)

/-- Kernel-level escape hatches: axioms, opaque and unsafe constants, `partial` and
noncomputable definitions, well-founded recursion, and replaced or external code. -/
def kernelFindings (env : Environment) (decl : OwnedDecl) : Array Finding :=
  let rules : List (Bool × String) :=
    [(decl.info matches .axiomInfo _, "declares an axiom"),
      (decl.info matches .opaqueInfo _,
        "declares an opaque constant; `partial` definitions do too"),
      (decl.info.isUnsafe, "is unsafe"),
      (isNoncomputable env decl.name, "is noncomputable"),
      (isExtern env decl.name, "has an external implementation"),
      ((Compiler.implementedByAttr.getParam? env decl.name).isSome, "has its code replaced"),
      (decl.info.value?.any (fun (value : Expr) => value.getUsedConstants.any isFixpoint),
        "uses well-founded recursion; recurse structurally")]
  (rules.filterMap (fun (rule : Bool × String) =>
    if rule.1 then some ⟨decl.label, rule.2⟩ else none)).toArray

/-- The axiom rule: a declaration depends on no axiom outside the global allowance and its own
exception, and its exception allows nothing it does not use. -/
def axiomFindings (decl : OwnedDecl) : CoreM (Array Finding) := do
  let used : Array Name ← collectAxioms decl.name
  let excepted : List Name := exceptionFor axiomExceptions decl
  let extra : Array Name := used.filter (fun (axiomName : Name) =>
    !allowedAxioms.contains axiomName && !excepted.contains axiomName)
  let unneeded : List Name := excepted.filter (fun (axiomName : Name) => !used.contains axiomName)
  let mut findings : Array Finding := #[]
  if !extra.isEmpty then
    findings := findings.push ⟨decl.label, s!"depends on axioms {extra.toList}"⟩
  if !unneeded.isEmpty then
    findings := findings.push ⟨decl.label, s!"axiom exception {unneeded} is no longer needed"⟩
  pure findings

/-- The compiled functions an owned declaration's code reaches before leaving compiler-generated
code: the declaration itself and every specialization or auxiliary function it calls, which have
no constant of their own. `fuel` bounds the walk by the number of compiled functions visited. -/
def generatedClosure (env : Environment) (pending : List Name) (seen : NameSet) : Nat → NameSet
  | 0 => seen
  | fuel + 1 =>
    match pending with
    | [] => seen
    | name :: rest =>
      if seen.contains name then generatedClosure env rest seen fuel
      else
        let callees : List Name := match IR.findEnvDecl env name with
          | some decl => (IR.collectUsedDecls env [decl]).toList.filter
              (fun (callee : Name) => !env.contains callee)
          | none => []
        generatedClosure env (callees ++ rest) (seen.insert name) fuel

/-- Compiled code: neither an owned function nor any compiler-generated function it reaches is
external, and none of them calls an unsafe function outside its exception, which must still be
needed. Calls into external runtime primitives such as `Nat.add` are expected; every compiled
program makes them. -/
def irFindings (env : Environment) (decl : OwnedDecl) : Array Finding := Id.run do
  let excepted : List Name := exceptionFor unsafeCallExceptions decl
  let reached : NameSet := generatedClosure env [decl.name] {} 100000
  let mut findings : Array Finding := #[]
  let mut unsafeCalls : NameSet := {}
  for function in reached.toArray do
    match IR.findEnvDecl env function with
    | none => pure ()
    | some compiled =>
      if compiled matches .extern .. then
        findings := findings.push ⟨decl.label, s!"compiles to external `{function}`"⟩
      for callee in IR.collectUsedDecls env [compiled] do
        if (env.find? callee).any (fun (info : ConstantInfo) => info.isUnsafe) then
          unsafeCalls := unsafeCalls.insert callee
  for callee in unsafeCalls.toArray do
    if !excepted.contains callee then
      findings := findings.push ⟨decl.label, s!"compiled code calls unsafe `{callee}`"⟩
  let unneeded : List Name := excepted.filter (fun (callee : Name) => !unsafeCalls.contains callee)
  if !unneeded.isEmpty then
    findings := findings.push ⟨decl.label, s!"unsafe-call exception {unneeded} is no longer needed"⟩
  pure findings

/-- Every exception for a module in the environment names a declaration of that module. -/
def staleExceptionFindings (env : Environment) (owned : Array OwnedDecl) : Array Finding :=
  let keys : List (Name × Name) :=
    axiomExceptions.map (fun (entry : (Name × Name) × List Name) => entry.1) ++
      unsafeCallExceptions.map (fun (entry : (Name × Name) × List Name) => entry.1) ++
      specExemptions
  (keys.filterMap (fun (key : Name × Name) =>
    if !env.header.moduleNames.contains key.1 then none
    else if owned.any (fun (decl : OwnedDecl) => (decl.module, decl.userName) == key) then none
    else some ⟨s!"{key.1}:{key.2}", "exception names no declaration of its module"⟩)).toArray

/-- Spec coverage: every written, non-theorem library or executable declaration appears in the
statement of at least one owned theorem. A spec exemption must still be needed. -/
def specFindings (env : Environment) (owned : Array OwnedDecl) : Array Finding :=
  let mentioned : NameSet := owned.foldl
    (fun (acc : NameSet) (decl : OwnedDecl) =>
      if decl.info.isTheorem then
        decl.info.type.getUsedConstants.foldl
          (fun (set : NameSet) (name : Name) => set.insert name) acc
      else acc)
    {}
  owned.filterMap (fun (decl : OwnedDecl) =>
    let needsSpec : Bool := (decl.role == .library || decl.role == .executable) &&
      !decl.info.isTheorem && !isGenerated env decl
    let exempt : Bool := specExemptions.contains (decl.module, decl.userName)
    if needsSpec && !exempt && !mentioned.contains decl.name then
      some ⟨decl.label, "no owned theorem states anything about it"⟩
    else if exempt && mentioned.contains decl.name then
      some ⟨decl.label, "spec exemption is no longer needed"⟩
    else none)

/-- Documentation: every written owned declaration, theorems included, has a docstring. -/
def docFindings (env : Environment) (owned : Array OwnedDecl) : IO (Array Finding) := do
  let mut findings : Array Finding := #[]
  for decl in owned do
    if !isGenerated env decl then
      if (← findDocString? env decl.name).isNone then
        findings := findings.push ⟨decl.label, "has no docstring"⟩
  pure findings

/-- Every Batteries environment linter, including those disabled by default. -/
def lintFindings (declarations : Array Name) : CoreM (Array Finding) := do
  let everyLinter : List Name := (batteriesLinterExt.getState (← getEnv)).toList.map
    (fun (entry : Name × Name × Bool) => entry.1)
  let linters : Array NamedLinter ← getChecks (slow := true) (runOnly := none)
    (runAlways := some everyLinter)
  let results : Array (NamedLinter × Std.HashMap Name MessageData) ←
    lintCore declarations linters
  let mut findings : Array Finding := #[]
  for (linter, failures) in results do
    for (name, message) in failures.toList do
      findings := findings.push ⟨s!"{name}", s!"{linter.name}: {← message.toString}"⟩
  pure findings

/-- Every owned module must be imported by the audited roots, so none escapes the
environment rules, and must resolve to this project's build output, so a dependency module
of the same name cannot stand in for it. -/
def coverageFindings (env : Environment) (modules : Array Name) : IO (Array Finding) := do
  let buildDir : System.FilePath := (← IO.currentDir) / ".lake" / "build" / "lib" / "lean"
  let mut findings : Array Finding := #[]
  for module in modules do
    if !env.header.moduleNames.contains module then
      findings := findings.push ⟨s!"{module}", "owned module is not imported by the audited roots"⟩
    let olean : System.FilePath ← findOLean module
    if !olean.toString.startsWith buildDir.toString then
      findings := findings.push ⟨s!"{module}", s!"resolves to {olean}, outside this project"⟩
  pure findings

/-- The rules that need no Batteries linters or build output: kernel, IR, axioms, spec coverage,
documentation, and stale exceptions. -/
def declarationFindings (env : Environment) (owned : Array OwnedDecl) : IO (Array Finding) := do
  let docs : Array Finding ← docFindings env owned
  let context : Core.Context := { fileName := "<audit>", fileMap := default }
  let (findings, _) ← (do
    let mut findings : Array Finding := staleExceptionFindings env owned
    for decl in owned do
      findings := findings ++ kernelFindings env decl ++ irFindings env decl
      findings := findings ++ (← axiomFindings decl)
    pure (findings ++ specFindings env owned) : CoreM (Array Finding)).toIO context { env }
  pure (docs ++ findings)

/-- Runs every environment rule over the given root modules. `modules` lists the owned modules
the roots must cover. -/
def environmentAudit (roots : Array Name) (modules : Array Name) : IO (Array Finding) := do
  let imports : Array Import := (roots.push `Batteries.Tactic.Lint).map
    (fun (module : Name) => { module })
  let env : Environment ← importModules imports {} (trustLevel := 1024) (loadExts := true)
  let owned : Array OwnedDecl := ownedDecls env
  let coverage : Array Finding ← coverageFindings env modules
  let declarationRules : Array Finding ← declarationFindings env owned
  let declarations : Array Name := (owned.filter (fun (decl : OwnedDecl) =>
    !isGenerated env decl)).map (fun (decl : OwnedDecl) => decl.name)
  let context : Core.Context := { fileName := "<audit>", fileMap := default }
  let (lints, _) ← (lintFindings declarations).toIO context { env }
  pure (coverage ++ declarationRules ++ lints)

/-- The written declarations of one role under the given roots, for exporting to an external
kernel checker, which rechecks them with everything they depend on. -/
def roleDeclarations (roots : Array Name) (role : Role) : IO (Array Name) := do
  let imports : Array Import := roots.map (fun (module : Name) => { module })
  let env : Environment ← importModules imports {} (trustLevel := 1024)
  let written : Array OwnedDecl := (ownedDecls env).filter (fun (decl : OwnedDecl) =>
    decl.role == role && !isGenerated env decl)
  pure (written.map (fun (decl : OwnedDecl) => decl.name))

end ProjectNameAudit
