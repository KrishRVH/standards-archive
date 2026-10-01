#!/usr/bin/env python3
"""Check standards profile fixtures against the copyable templates."""

import filecmp
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    print("Python 3.11+ is required for tomllib. Run this through mise.", file=sys.stderr)
    raise SystemExit(2) from None


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "standards.manifest.toml"
REQUIRED_PROFILE_KEYS = {"name", "template", "tester", "task_prefix", "task_fragment", "mirror"}
OPTIONAL_PROFILE_KEYS = {"dagger", "fixture_checks", "required_tester_files", "shared_mirror"}
PROFILE_KEYS = REQUIRED_PROFILE_KEYS | OPTIONAL_PROFILE_KEYS
REQUIRED_TASK_SUFFIXES = ("fmt", "fmt:check", "lint", "test", "standards", "standards:check")
AGGREGATE_MARKER_CASES = {
    "c": ("CMakeLists.txt", "src/main.c"),
    "cpp": ("CMakeLists.txt", "src/library.hpp"),
    "elixir": ("mix.exs",),
    "fortran": ("fpm.toml",),
    "godot": ("project.godot", "src/features/player/state/machine/main.gd"),
    "haskell": ("project.cabal",),
    "js": ("package.json", "jsconfig.json"),
    "lua": (".luarc.json",),
    "odin": ("src/project_name/project_name.odin",),
    "php": ("composer.json",),
    "roc": ("main.roc",),
    "spark": ("alire.toml", "src/project.ads"),
    "zig": ("build.zig",),
}
DAGGER_MIRROR = ("dagger/package.json", "dagger/tsconfig.json", "dagger/src/index.ts")
FULL_CONFIG_MIRROR = (".gitleaks.toml",)
ROOT_SHARED_MIRROR = (".gitleaks.toml",)
HYGIENE = ROOT / "Mise" / "tasks" / "hygiene"
# A clean tree of legitimate layouts, allowances, and exemptions must pass with no
# findings; removing any allowance or exemption makes one of these fail. A dirty
# tree must report exactly the expected findings.
HYGIENE_CLEAN = {
    "src/reports/summary.rs": "pub fn summary() {}\n",
    "src/lib.rs": "#![forbid(unsafe_code)]\n",
    "api/v1/routes.go": "package v1\n",
    "docs/pickup_rules.md": "# Pickup rules\n",
    "docs/blog/2026-01-01-launch.md": "# Launch\n",
    "migrations/V1__init.sql": "create table t (id int);\n",
    "vendor/parser/parser_v2.c": "int parse;\n",
    "README.md": (
        "`mise run known:task`, `mise run kt`, `mise run rust:...`, `mise run //sub:sub:only`,\n"
        "`mise run //sub:so`, `mise run sub:only`, `mise run //:known:task`,\n"
        "`mise run //testers/...:standards`, `mise run build-${TARGET}`, `mise run build-\"${TARGET}\"`,\n"
        '`cd sub && mise run only:here`, `cd "sub project" && mise run only:here`\n'
    ),
    "scripts/setup.sh": "#!/bin/sh\ncat <<EOF\nRun tasks such as mise run build.\nEOF\n",
    "tests/fixtures/tasks.md": "`mise run missing:fixture`\n",
}
HYGIENE_DIRTY = {
    "docs/research/engine.md": ("# Engine\n", ["history directory `research/`; git holds history"]),
    "archive/plan.md": ("# Plan\n", ["history directory `archive/`; git holds history"]),
    "src/parser_v2.rs": ("pub fn parse() {}\n", ["versioned file name; replace the old version in place"]),
    "src/main.rs.orig": ("fn main() {}\n", ["leftover file name; rename in place or delete it"]),
    "migrations/V2__add.sql.bak": ("alter table t;\n", ["leftover file name; rename in place or delete it"]),
    "HANDOFF.md": ("# Handoff\n", ["handoff note; keep task notes in untracked .scratch/"]),
    "docs/2026-01-01-audit.md": ("# Audit\n", ["dated name; current docs carry no dates"]),
    "docs/tasks.md": (
        "`mise run missing:task`, `mise run //sub:missing`, and `mise run //:sub:only`\n",
        [
            "unknown mise task `//sub:missing`",
            "unknown mise task `missing:task`",
            "unknown mise task `//:sub:only`",
        ],
    ),
    "src/sparse_v2.rs": ("pub fn sparse() {}\n", ["versioned file name; replace the old version in place"]),
    "scripts/check.sh": ("#!/bin/sh\nmise run gone:task\n", ["unknown mise task `gone:task`"]),
}
HYGIENE_TASKS = '[{"name":"//:known:task","aliases":["kt"]},{"name":"//sub:sub:only","aliases":["so"]}]'
# Left untracked in each tree; every other seeded file is staged.
HYGIENE_UNTRACKED = {"README.md", "scripts/setup.sh", "scripts/check.sh"}


def load_profiles() -> dict[str, dict[str, object]]:
    try:
        with MANIFEST.open("rb") as manifest:
            data = tomllib.load(manifest)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"invalid TOML in {rel(MANIFEST)}: {error}") from None

    profiles = data.get("profiles", {})
    if not isinstance(profiles, dict):
        raise SystemExit("standards.manifest.toml must contain a [profiles] table")
    return profiles


def load_toml(path: Path) -> dict[str, object]:
    with path.open("rb") as file:
        return tomllib.load(file)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def same_file(left: Path, right: Path) -> bool:
    return left.is_file() and right.is_file() and filecmp.cmp(left, right, shallow=False)


def compare_file(profile_id: str, label: str, left: Path, right: Path) -> list[str]:
    if not left.is_file():
        return [f"{profile_id}: missing canonical {label}: {rel(left)}"]
    if not right.is_file():
        return [f"{profile_id}: missing fixture {label}: {rel(right)}"]
    if not filecmp.cmp(left, right, shallow=False):
        return [f"{profile_id}: {label} drift: {rel(left)} != {rel(right)}"]
    return []


def is_relative_path(value: str) -> bool:
    path = Path(value)
    return (
        bool(path.parts)
        and value == path.as_posix()
        and not path.is_absolute()
        and ".." not in path.parts
        and "." not in path.parts
    )


def validate_profiles(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    if not profiles:
        return ["standards.manifest.toml must define at least one profile"]

    seen: dict[str, dict[str, str]] = {
        "tester": {},
        "template": {},
        "task_prefix": {},
        "task_fragment": {},
    }

    for profile_id, profile in profiles.items():
        if not isinstance(profile, dict):
            errors.append(f"{profile_id}: profile entry must be a table")
            continue

        unknown = set(profile) - PROFILE_KEYS
        missing = REQUIRED_PROFILE_KEYS - set(profile)
        if unknown:
            errors.append(f"{profile_id}: unknown keys: {', '.join(sorted(unknown))}")
        if missing:
            errors.append(f"{profile_id}: missing keys: {', '.join(sorted(missing))}")
            continue

        for key in ("name", "template", "tester", "task_prefix", "task_fragment"):
            value = profile[key]
            if not isinstance(value, str) or not value:
                errors.append(f"{profile_id}: {key} must be a non-empty string")
                continue
            if key in {"template", "tester", "task_fragment"} and not is_relative_path(value):
                errors.append(f"{profile_id}: {key} must be a normalized relative path")
            if key in seen:
                previous = seen[key].get(value)
                if previous is not None:
                    errors.append(f"{profile_id}: {key} duplicates {previous}: {value}")
                seen[key][value] = profile_id

        mirror = profile["mirror"]
        if not isinstance(mirror, list):
            errors.append(f"{profile_id}: mirror must be a list")
            continue
        for item in mirror:
            if not isinstance(item, str) or not is_relative_path(item):
                errors.append(f"{profile_id}: mirror entries must be normalized relative paths: {item!r}")

        for key in ("required_tester_files", "shared_mirror"):
            entries = profile.get(key, [])
            if not isinstance(entries, list):
                errors.append(f"{profile_id}: {key} must be a list")
                continue
            for item in entries:
                if not isinstance(item, str) or not is_relative_path(item):
                    errors.append(f"{profile_id}: {key} entries must be normalized relative paths: {item!r}")

        dagger = profile.get("dagger", False)
        if not isinstance(dagger, bool):
            errors.append(f"{profile_id}: dagger must be a boolean")

        if isinstance(profile["task_prefix"], str) and isinstance(profile["task_fragment"], str):
            fragment = ROOT / "Mise" / "conf.d" / profile["task_fragment"]
            errors.extend(fixture_check_errors(profile_id, profile, fragment))

    return errors


def fixture_check_errors(profile_id: str, profile: dict[str, object], fragment: Path) -> list[str]:
    """Each extra fixture gate check must be a task of the profile's own fragment."""
    checks = profile.get("fixture_checks")
    if checks is None:
        return []
    if not isinstance(checks, list) or not all(isinstance(check, str) for check in checks):
        return [f"{profile_id}: fixture_checks must be a list of task names"]
    prefix = profile["task_prefix"]
    try:
        tasks = load_toml(fragment).get("tasks", {})
    except (OSError, tomllib.TOMLDecodeError):
        tasks = {}
    errors = []
    for check in checks:
        if not check.startswith(f"{prefix}:"):
            errors.append(f"{profile_id}: fixture_checks entry {check!r} must start with {prefix}:")
        elif not isinstance(tasks, dict) or check not in tasks:
            errors.append(f"{profile_id}: fixture_checks entry {check!r} is not a task in {rel(fragment)}")
    return errors


def check_tester_inventory(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    declared: dict[Path, str] = {}

    for profile_id, profile in profiles.items():
        tester = ROOT / str(profile["tester"])
        declared[tester] = profile_id
        fixture_config = tester / ".config" / "mise" / "config.toml"
        if not fixture_config.is_file():
            errors.append(f"{profile_id}: missing fixture config {rel(fixture_config)}")

    discovered = {config.parents[2] for config in (ROOT / "testers").glob("*/.config/mise/config.toml")}
    for tester in sorted(discovered - set(declared), key=rel):
        errors.append(f"{rel(tester)}: tester fixture is not declared in standards.manifest.toml")

    return errors


def check_mise_lockfiles(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    root_lock = ROOT / ".config" / "mise" / "mise.lock"
    if not root_lock.is_file():
        errors.append(f"root: missing mise lockfile {rel(root_lock)}")
    for profile_id, profile in profiles.items():
        lockfile = ROOT / str(profile["tester"]) / ".config" / "mise" / "mise.lock"
        if not lockfile.is_file():
            errors.append(f"{profile_id}: missing fixture mise lockfile {rel(lockfile)}")
    return errors


def check_task_surface(profile_id: str, task_fragment: Path, prefix: str) -> list[str]:
    errors: list[str] = []
    if not task_fragment.is_file():
        return [f"{profile_id}: missing task fragment {rel(task_fragment)}"]

    try:
        data = load_toml(task_fragment)
    except tomllib.TOMLDecodeError as error:
        return [f"{profile_id}: invalid TOML in {rel(task_fragment)}: {error}"]

    tasks = data.get("tasks", {})
    if not isinstance(tasks, dict):
        return [f"{profile_id}: {rel(task_fragment)} must contain a [tasks] table"]

    for suffix in REQUIRED_TASK_SUFFIXES:
        task_name = f"{prefix}:{suffix}"
        if task_name not in tasks:
            errors.append(f"{profile_id}: {rel(task_fragment)} missing task {task_name}")
    return errors


def check_aggregate_dispatch(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    config = ROOT / "Mise" / "config.toml"
    try:
        data = load_toml(config)
    except tomllib.TOMLDecodeError as error:
        return [f"invalid TOML in {rel(config)}: {error}"]

    if data.get("min_version") != "2026.6.12":
        errors.append(f'{rel(config)} must set min_version = "2026.6.12"')

    tasks = data.get("tasks", {})
    if not isinstance(tasks, dict):
        return [f"{rel(config)} must contain a [tasks] table"]

    dispatcher = tasks.get("_dispatch")
    if not isinstance(dispatcher, dict):
        return [f"{rel(config)} missing aggregate dispatcher task _dispatch"]
    script = dispatcher.get("run")
    if not isinstance(script, str):
        return [f"{rel(config)} aggregate dispatcher _dispatch must contain a run script"]
    if dispatcher.get("hide") is not True:
        errors.append(f"{rel(config)} aggregate dispatcher _dispatch must be hidden")
    if dispatcher.get("usage") != 'arg "task"':
        errors.append(f'{rel(config)} aggregate dispatcher _dispatch must declare usage \'arg "task"\'')

    for task_name in REQUIRED_TASK_SUFFIXES:
        task = tasks.get(task_name)
        if not isinstance(task, dict):
            errors.append(f"{rel(config)} missing aggregate task {task_name}")
            continue
        expected = [{"task": "_dispatch", "args": [task_name]}]
        if task.get("run") != expected:
            errors.append(f"{rel(config)} aggregate task {task_name} must run {expected!r}")
        expected_depends = ["secrets", "hygiene"] if task_name == "standards:check" else None
        if task.get("depends") != expected_depends:
            errors.append(
                f"{rel(config)} aggregate task {task_name} must set depends to {expected_depends!r}"
            )

    prefixes = {str(profile["task_prefix"]) for profile in profiles.values()}
    marker_prefixes = set(AGGREGATE_MARKER_CASES)
    if prefixes != marker_prefixes:
        missing = prefixes - marker_prefixes
        stale = marker_prefixes - prefixes
        if missing:
            errors.append(f"aggregate marker cases missing task prefixes: {', '.join(sorted(missing))}")
        if stale:
            errors.append(f"aggregate marker cases contain stale task prefixes: {', '.join(sorted(stale))}")

    try:
        with tempfile.TemporaryDirectory(prefix="standards-dispatch-") as temporary:
            temporary_root = Path(temporary)
            bin_dir = temporary_root / "bin"
            bin_dir.mkdir()
            fake_mise = bin_dir / "mise"
            fake_mise.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MISE_DISPATCH_LOG\"\n",
                encoding="utf-8",
            )
            fake_mise.chmod(0o755)

            def execute(case: str, task_name: str, markers: tuple[str, ...]) -> tuple[list[str], str, int]:
                workspace = temporary_root / case
                workspace.mkdir()
                for marker in markers:
                    path = workspace / marker
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.touch()
                log = workspace / "dispatch.log"
                environment = {
                    "LC_ALL": "C",
                    "MISE_DISPATCH_LOG": str(log),
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                    "usage_task": task_name,
                }
                result = subprocess.run(
                    ["sh", "-c", script],
                    cwd=workspace,
                    env=environment,
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=5,
                )
                commands = log.read_text(encoding="utf-8").splitlines() if log.is_file() else []
                return commands, result.stderr, result.returncode

            positive_cases = [(prefix, prefix, markers) for prefix, markers in AGGREGATE_MARKER_CASES.items()]
            for case, prefix, markers in positive_cases:
                commands, stderr, returncode = execute(case, "fmt", markers)
                expected = [f"run {prefix}:fmt"]
                if returncode != 0:
                    errors.append(f"aggregate marker case {case} failed: {stderr.strip()}")
                elif commands != expected:
                    errors.append(
                        f"aggregate marker case {case} dispatched {commands!r}; expected {expected!r}"
                    )

            for case, markers in {
                "cmake-without-source": ("CMakeLists.txt",),
                "godot-without-gdscript": ("project.godot",),
                "package-without-js-config": ("package.json",),
                "spark-without-source": ("alire.toml",),
                "markdown-only": (".markdownlint-cli2.jsonc",),
                "shell-only": (".shellcheckrc",),
            }.items():
                commands, stderr, returncode = execute(case, "fmt", markers)
                if returncode != 0:
                    errors.append(f"aggregate negative marker case {case} failed: {stderr.strip()}")
                elif commands:
                    errors.append(f"aggregate negative marker case {case} dispatched {commands!r}")

            commands, stderr, returncode = execute(
                "standards-check-secrets", "standards:check", ("package.json", "jsconfig.json")
            )
            expected = ["run js:standards:check"]
            if returncode != 0:
                errors.append(f"aggregate standards:check case failed: {stderr.strip()}")
            elif commands != expected:
                errors.append(
                    f"aggregate standards:check dispatched {commands!r}; expected {expected!r}"
                )

            commands, _, returncode = execute("invalid-task", "invalid", ())
            if returncode != 2 or commands:
                errors.append("aggregate dispatcher must reject unsupported task names without dispatching")
    except (OSError, subprocess.SubprocessError) as error:
        errors.append(f"could not exercise aggregate marker routing: {error}")
    return errors


def check_hygiene_task() -> list[str]:
    errors: list[str] = []
    if not os.access(HYGIENE, os.X_OK):
        errors.append(f"{rel(HYGIENE)} must be executable for mise to list it")
    text = HYGIENE.read_text(encoding="utf-8")
    pinned = next((line for line in text.splitlines() if line.startswith("# MISE tools=")), "")
    python = load_toml(ROOT / ".config" / "mise" / "config.toml").get("tools", {}).get("python")
    if pinned != f'# MISE tools={{python="{python}"}}':
        errors.append(f"{rel(HYGIENE)} must pin the root python {python}")

    try:
        with tempfile.TemporaryDirectory(prefix="standards-hygiene-") as temporary:
            temporary_root = Path(temporary)
            bin_dir = temporary_root / "bin"
            bin_dir.mkdir()
            fake_mise = bin_dir / "mise"
            fake_mise.write_text(f"#!/bin/sh\nprintf '%s' '{HYGIENE_TASKS}'\n", encoding="utf-8")
            fake_mise.chmod(0o755)
            environment = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', os.defpath)}"}

            def git(workspace: Path, *arguments: str) -> None:
                subprocess.run(["git", *arguments], cwd=workspace, check=True, capture_output=True)

            def seed(name: str, files: dict[str, str]) -> Path:
                workspace = temporary_root / name
                workspace.mkdir()
                if files:
                    git(workspace, "init", "-q")
                for path, content in files.items():
                    target = workspace / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(content, encoding="utf-8")
                staged = [path for path in files if path not in HYGIENE_UNTRACKED]
                if staged:
                    git(workspace, "add", "--", *staged)
                return workspace

            def run_hygiene(workspace: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [sys.executable, str(HYGIENE)],
                    cwd=workspace,
                    env={**environment, **overrides},
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=60,
                )

            outside_tree = seed("outside", {})
            outside = run_hygiene(outside_tree)
            if outside.returncode != 0 or "skipped" not in outside.stdout:
                errors.append("hygiene must skip outside a git work tree, as in the Dagger check")
            broken = run_hygiene(outside_tree, GIT_DIR=str(temporary_root / "missing-git-dir"))
            if broken.returncode != 1:
                errors.append("hygiene must fail, not skip, when GIT_DIR names no repository")

            # Clean-only index entries: a deleted tracked file, a gitlink, and a
            # tracked file behind a directory that became a symlink out of the tree.
            clean_tree = seed("clean", {**HYGIENE_CLEAN, "archive/deleted.md": "# Gone\n"})
            (clean_tree / "archive" / "deleted.md").unlink()
            git(clean_tree, "update-index", "--add", "--cacheinfo", f"160000,{'1' * 40},modules/engine_v2")
            (clean_tree / "modules" / "engine_v2").mkdir(parents=True)
            (clean_tree / "linked").mkdir()
            (clean_tree / "linked" / "config.toml").write_text("[tasks.a]\n", encoding="utf-8")
            git(clean_tree, "add", "--", "linked/config.toml")
            (clean_tree / "linked" / "config.toml").unlink()
            (clean_tree / "linked").rmdir()
            external = temporary_root / "external"
            external.mkdir()
            (external / "config.toml").write_text('run = "mise run missing:external"\n', encoding="utf-8")
            (clean_tree / "linked").symlink_to(external)
            # A symlink that core.symlinks=false wrote out as a plain file.
            link_text = "mise run missing:symlinked\n"
            (clean_tree / "docs" / "shortcut.sh").write_text(link_text, encoding="utf-8")
            blob = subprocess.run(
                ["git", "hash-object", "-w", "docs/shortcut.sh"],
                cwd=clean_tree,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            git(clean_tree, "update-index", "--add", "--cacheinfo", f"120000,{blob},docs/shortcut.sh")
            clean = run_hygiene(clean_tree)
            if clean.returncode != 0 or clean.stderr:
                errors.append(f"hygiene must pass a clean tree; exit {clean.returncode}: {clean.stderr.strip()}")

            dirty_tree = seed("dirty", {path: content for path, (content, _) in HYGIENE_DIRTY.items()})
            git(dirty_tree, "update-index", "--skip-worktree", "src/sparse_v2.rs")
            (dirty_tree / "src" / "sparse_v2.rs").unlink()
            (dirty_tree / "src" / "link_old.rs").symlink_to("parser_v2.rs")
            git(dirty_tree, "add", "--", "src/link_old.rs")
            dirty = run_hygiene(dirty_tree)
            expected = {"hygiene: src/link_old.rs: leftover file name; rename in place or delete it"} | {
                f"hygiene: {path}: {message}" for path, (_, messages) in HYGIENE_DIRTY.items() for message in messages
            }
            reported = set(dirty.stderr.splitlines())
            if dirty.returncode != 1:
                errors.append(f"hygiene must fail a dirty tree; exit {dirty.returncode}")
            errors.extend(f"hygiene missed: {line}" for line in sorted(expected - reported))
            errors.extend(f"hygiene reported unexpectedly: {line}" for line in sorted(reported - expected))
    except (OSError, subprocess.SubprocessError) as error:
        errors.append(f"could not exercise the hygiene task: {error}")
    return errors


def bun_pin(fragment: Path) -> str | None:
    """The fragment's exact tools.bun pin, or None when it pins no Bun."""
    try:
        pin = load_toml(fragment).get("tools", {}).get("bun")
    except (OSError, tomllib.TOMLDecodeError):
        return None
    if isinstance(pin, dict):
        pin = pin.get("version")
    return pin if isinstance(pin, str) else None


def package_manager_errors(profile_id: str, package_json: Path, pin: str, fragment: str) -> list[str]:
    """Bun reads packageManager and mise reads tools.bun; both must name one release."""
    try:
        actual = json.loads(package_json.read_text(encoding="utf-8")).get("packageManager")
    except (OSError, ValueError, AttributeError):
        actual = None
    if actual != f"bun@{pin}":
        return [f"{profile_id}: packageManager {actual!r} must be 'bun@{pin}' to match {fragment} tools.bun"]
    return []


def check_bun_pins(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    for profile_id, profile in profiles.items():
        fragment = ROOT / "Mise" / "conf.d" / str(profile["task_fragment"])
        pin = bun_pin(fragment)
        if pin is not None:
            package_json = ROOT / str(profile["template"]) / "package.json"
            errors.extend(package_manager_errors(profile_id, package_json, pin, rel(fragment)))
    markdown = ROOT / ".config" / "mise" / "conf.d" / "20-markdown.toml"
    root_pin = bun_pin(markdown)
    if root_pin is not None:
        errors.extend(package_manager_errors("root", ROOT / "package.json", root_pin, rel(markdown)))

    # Seeded proof: a mismatch must be reported and an agreeing pair must pass.
    with tempfile.TemporaryDirectory(prefix="standards-bun-pin-") as temporary:
        root = Path(temporary)
        fragment = root / "20-seed.toml"
        fragment.write_text('[tools]\nbun = "1.2.3"\n', encoding="utf-8")
        for label, manager, should_fail in (("agree", "bun@1.2.3", False), ("mismatch", "bun@1.2.2", True)):
            package_json = root / f"{label}.json"
            package_json.write_text(json.dumps({"packageManager": manager}), encoding="utf-8")
            found = package_manager_errors(label, package_json, bun_pin(fragment) or "", "seed")
            if bool(found) != should_fail:
                errors.append(f"bun pin rule mishandled the seeded {label} case: {found!r}")
    return errors


def check_fixture_checks_contract() -> list[str]:
    """Prove the fixture_checks rules on seeded profiles and fixture configs."""
    errors: list[str] = []
    min_version = load_toml(ROOT / "Mise" / "config.toml").get("min_version")
    with tempfile.TemporaryDirectory(prefix="standards-fixture-checks-") as temporary:
        root = Path(temporary)
        fragment = root / "20-x.toml"
        # y:extra exists, so only the prefix rule can reject it.
        fragment.write_text(
            '[tasks."x:standards:check"]\nrun = "true"\n[tasks."x:extra"]\nrun = "true"\n'
            '[tasks."y:extra"]\nrun = "true"\n'
        )
        cases = {
            "declared": (["x:extra"], False),
            "unknown": (["x:missing"], True),
            "wrong-prefix": (["y:extra"], True),
        }
        for label, (checks, should_fail) in cases.items():
            found = fixture_check_errors(label, {"task_prefix": "x", "fixture_checks": checks}, fragment)
            if bool(found) != should_fail:
                errors.append(f"fixture_checks validation mishandled the {label} case: {found!r}")

        def fixture(name: str, check_depends: list[str]) -> Path:
            tester = root / name
            config = tester / ".config" / "mise" / "config.toml"
            config.parent.mkdir(parents=True)
            config.write_text(
                f'min_version = "{min_version}"\n[settings]\nlockfile = true\n'
                '[tasks.standards]\ndepends = ["x:standards"]\n'
                f'[tasks."standards:check"]\ndepends = {check_depends!r}\n'.replace("'", '"')
            )
            return tester

        complete_fixture = fixture("complete", ["x:standards:check", "x:extra"])
        complete = check_fixture_config("complete", complete_fixture, "x", ["x:extra"])
        if complete:
            errors.append(f"fixture_checks rejected a fixture that runs its declared check: {complete!r}")
        if not check_fixture_config("omitted", fixture("omitted", ["x:standards:check"]), "x", ["x:extra"]):
            errors.append("fixture_checks accepted a fixture whose standards:check omits a declared check")
    return errors


def check_fixture_config(profile_id: str, tester: Path, prefix: str, fixture_checks: list[str]) -> list[str]:
    errors: list[str] = []
    fixture_config = tester / ".config" / "mise" / "config.toml"
    canonical_config = ROOT / "Mise" / "config.toml"

    if not fixture_config.is_file():
        return [f"{profile_id}: missing fixture config {rel(fixture_config)}"]

    full_config = same_file(canonical_config, fixture_config)
    if full_config:
        for item in FULL_CONFIG_MIRROR:
            errors.extend(compare_file(profile_id, "full-config shared file", ROOT / "shared" / item, tester / item))
        fixture_hygiene = tester / ".config" / "mise" / "tasks" / "hygiene"
        errors.extend(compare_file(profile_id, "full-config hygiene task", HYGIENE, fixture_hygiene))
        if fixture_hygiene.is_file() and not os.access(fixture_hygiene, os.X_OK):
            errors.append(f"{profile_id}: {rel(fixture_hygiene)} must be executable for mise to list it")
        if fixture_checks:
            errors.append(f"{profile_id}: fixture_checks needs a minimal fixture config")
    else:
        try:
            data = load_toml(fixture_config)
        except tomllib.TOMLDecodeError as error:
            return [f"{profile_id}: invalid TOML in {rel(fixture_config)}: {error}"]

        tasks = data.get("tasks", {})
        if not isinstance(tasks, dict):
            return [f"{profile_id}: minimal fixture config must contain [tasks]"]

        settings = data.get("settings", {})
        if not isinstance(settings, dict) or settings.get("lockfile") is not True:
            errors.append(f"{profile_id}: minimal fixture config must set [settings] lockfile = true")

        expected_min_version = load_toml(canonical_config).get("min_version")
        if data.get("min_version") != expected_min_version:
            errors.append(
                f"{profile_id}: minimal fixture config min_version must match {rel(canonical_config)}"
            )

        if set(tasks) != {"standards", "standards:check"}:
            errors.append(
                f"{profile_id}: minimal fixture config must contain only standards and standards:check tasks"
            )

        standards = tasks.get("standards", {})
        standards_check = tasks.get("standards:check", {})
        if not isinstance(standards, dict) or standards.get("depends") != [f"{prefix}:standards"]:
            errors.append(f"{profile_id}: minimal fixture config standards must depend on {prefix}:standards")
        expected_check = [f"{prefix}:standards:check", *fixture_checks]
        if not isinstance(standards_check, dict) or standards_check.get("depends") != expected_check:
            errors.append(f"{profile_id}: minimal fixture config standards:check must depend on {expected_check!r}")

    dagger_fragment = tester / ".config" / "mise" / "conf.d" / "10-dagger.toml"
    canonical_dagger = ROOT / "Mise" / "conf.d" / "10-dagger.toml"
    if dagger_fragment.exists():
        errors.extend(compare_file(profile_id, "Dagger fragment", canonical_dagger, dagger_fragment))

    return errors


def check_root_mise_config(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors: list[str] = []
    config = ROOT / ".config" / "mise" / "config.toml"
    try:
        data = load_toml(config)
    except tomllib.TOMLDecodeError as error:
        return [f"invalid TOML in {rel(config)}: {error}"]

    if data.get("min_version") != "2026.7.0":
        errors.append(f'{rel(config)} must set min_version = "2026.7.0"')
    if data.get("monorepo_root") is not True:
        errors.append(f"{rel(config)} must set monorepo_root = true")

    settings = data.get("settings", {})
    jobs = settings.get("jobs") if isinstance(settings, dict) else None
    if not isinstance(jobs, int) or isinstance(jobs, bool) or jobs < 1:
        errors.append(f"{rel(config)} [settings] jobs must be a positive integer")
    if not isinstance(settings, dict) or settings.get("lockfile") is not True:
        errors.append(f"{rel(config)} [settings] lockfile must be true")

    monorepo = data.get("monorepo", {})
    if not isinstance(monorepo, dict):
        errors.append(f"{rel(config)} must contain a [monorepo] table")
    else:
        if monorepo.get("config_roots") != ["testers/*"]:
            errors.append(f'{rel(config)} [monorepo] config_roots must be ["testers/*"]')
        if monorepo.get("lockfile") is not False:
            errors.append(f"{rel(config)} [monorepo] lockfile must be false")

    tasks = data.get("tasks", {})
    if not isinstance(tasks, dict):
        errors.append(f"{rel(config)} must contain a [tasks] table")
    else:
        standards = tasks.get("standards")
        expected_standards_run = [
            {"task": "md:standards"},
            {"task": "shell:standards"},
            {"task": "//testers/...:standards"},
        ]
        if not isinstance(standards, dict) or standards.get("run") != expected_standards_run:
            errors.append(
                f"{rel(config)} task standards must run {expected_standards_run!r} in order"
            )

        # The scans run before fixture tests write temporary probe files into the tree.
        standards_check = tasks.get("standards:check")
        expected_check_depends = ["secrets", "hygiene"]
        expected_check_run = [
            {
                "tasks": [
                    "standards:drift",
                    "md:standards:check",
                    "shell:standards:check",
                    "//testers/...:standards:check",
                ]
            }
        ]
        if not isinstance(standards_check, dict) or standards_check.get("depends") != expected_check_depends:
            errors.append(f"{rel(config)} task standards:check must depend on {expected_check_depends!r}")
        if not isinstance(standards_check, dict) or standards_check.get("run") != expected_check_run:
            errors.append(f"{rel(config)} task standards:check must run {expected_check_run!r}")

    for profile_id, profile in profiles.items():
        tester = Path(str(profile["tester"]))
        if len(tester.parts) != 2 or tester.parts[0] != "testers":
            errors.append(
                f'{profile_id}: tester {tester} is outside the root monorepo config_roots pattern "testers/*"'
            )

    return errors


def check_root_shared_files() -> list[str]:
    errors: list[str] = []
    for item in ROOT_SHARED_MIRROR:
        errors.extend(compare_file("root", "shared file", ROOT / "shared" / item, ROOT / item))
    errors.extend(compare_file("root", "hygiene task", HYGIENE, ROOT / ".config" / "mise" / "tasks" / "hygiene"))
    return errors


def check_dagger_copy(profile_id: str, tester: Path) -> list[str]:
    errors: list[str] = []
    dagger_fragment = tester / ".config" / "mise" / "conf.d" / "10-dagger.toml"
    if not dagger_fragment.is_file():
        errors.append(f"{profile_id}: missing Dagger fragment {rel(dagger_fragment)}")

    errors.extend(compare_file(profile_id, "Dagger metadata", ROOT / "Dagger" / "dagger.json", tester / "dagger.json"))
    for item in DAGGER_MIRROR:
        errors.extend(compare_file(profile_id, "Dagger module", ROOT / "Dagger" / item, tester / item))
    return errors


def check_profiles(profiles: dict[str, dict[str, object]]) -> list[str]:
    errors = validate_profiles(profiles)
    if errors:
        return errors

    errors.extend(check_tester_inventory(profiles))
    errors.extend(check_mise_lockfiles(profiles))
    errors.extend(check_aggregate_dispatch(profiles))
    errors.extend(check_root_mise_config(profiles))
    errors.extend(check_root_shared_files())
    errors.extend(check_hygiene_task())
    errors.extend(check_fixture_checks_contract())
    errors.extend(check_bun_pins(profiles))

    for profile_id, profile in profiles.items():
        tester = ROOT / str(profile["tester"])
        template = ROOT / str(profile["template"])
        task_fragment = str(profile["task_fragment"])
        task_prefix = str(profile["task_prefix"])
        task_left = ROOT / "Mise" / "conf.d" / task_fragment
        task_right = tester / ".config" / "mise" / "conf.d" / task_fragment

        has_template = template.is_dir()
        has_tester = tester.is_dir()

        if not has_template:
            errors.append(f"{profile_id}: missing template directory {rel(template)}")
        if not has_tester:
            errors.append(f"{profile_id}: missing tester directory {rel(tester)}")

        errors.extend(compare_file(profile_id, "task fragment", task_left, task_right))
        if task_left.is_file():
            errors.extend(check_task_surface(profile_id, task_left, task_prefix))
        if has_tester:
            fixture_checks = profile.get("fixture_checks", [])
            errors.extend(
                check_fixture_config(
                    profile_id, tester, task_prefix, fixture_checks if isinstance(fixture_checks, list) else []
                )
            )
            if profile.get("dagger", False):
                errors.extend(check_dagger_copy(profile_id, tester))

        mirror = profile.get("mirror", [])
        if has_template and has_tester:
            for item in mirror:
                left = template / str(item)
                right = tester / str(item)
                errors.extend(compare_file(profile_id, "mirror", left, right))
        if has_tester:
            for item in profile.get("shared_mirror", []):
                errors.extend(
                    compare_file(profile_id, "shared mirror", ROOT / "shared" / str(item), tester / str(item))
                )
            for item in profile.get("required_tester_files", []):
                required = tester / str(item)
                if not required.is_file():
                    errors.append(f"{profile_id}: missing required tester file {rel(required)}")

    return errors


def main() -> int:
    profiles = load_profiles()
    errors = check_profiles(profiles)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"Checked {len(profiles)} standards profiles.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
