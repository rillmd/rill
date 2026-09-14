#!/usr/bin/env python3
"""Opt-in CLI comparison in new synthetic vaults. Requires existing CLI login."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
CASES = json.loads(Path(__file__).with_name("cases.json").read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root):
    """Read-only content snapshot; exclude Git internals, never follow symlinks."""
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            path = Path(directory) / name
            key = str(path.relative_to(root))
            if path.is_symlink():
                result[key] = "link:" + os.readlink(path)
            elif path.is_file():
                result[key] = digest(path)
    return result


def execute(argv, cwd, env, timeout, stem):
    """Keep failure, empty output and timeout distinct; terminate the process group."""
    start = time.monotonic()
    record = {"argv": argv, "status": "not-run", "exit_code": None}
    with stem.with_suffix(".stdout.jsonl").open("w") as out, stem.with_suffix(".stderr.log").open("w") as err:
        try:
            proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                    stdout=out, stderr=err, start_new_session=True)
            try:
                record["exit_code"] = proc.wait(timeout=timeout)
                record["status"] = "finished" if proc.returncode == 0 else "failed"
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                finally:
                    # The group can outlive its leader. Kill remaining children
                    # even when wait() already returned for the CLI parent.
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    proc.wait()
                record["status"] = "timeout"
                record["exit_code"] = proc.returncode
        except OSError as exc:
            record["error"] = str(exc)
    record["elapsed_seconds"] = round(time.monotonic() - start, 3)
    return record


def checked(argv, cwd, env):
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                            text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError("Setup failed: " + result.stderr + result.stdout)
    return result.stdout


def setup(base):
    source = base / "source"
    source.mkdir()
    # Copy only deployment inputs. No Git directory, real vault, sessions,
    # worktrees, credentials, test results or user plugin data are copied.
    for name in ["bin", "lib", "skills", "templates", "plugins", "eval"]:
        if (ROOT / name).is_dir():
            shutil.copytree(ROOT / name, source / name)
    (source / ".claude").mkdir()
    for name in ["rules", "commands", "agents"]:
        if (ROOT / ".claude" / name).is_dir():
            shutil.copytree(ROOT / ".claude" / name, source / ".claude" / name)
    for name in ["SPEC.md", "taxonomy.md", "VERSION", "CLAUDE.md", "AGENTS.md"]:
        if (ROOT / name).is_file():
            shutil.copy2(ROOT / name, source / name)
    containers = ["inbox", "inbox/journal", "inbox/meetings", "inbox/tweets",
                  "inbox/web-clips", "inbox/sources", "knowledge/notes", "knowledge/people",
                  "knowledge/orgs", "knowledge/self", "projects", "workspace", "tasks",
                  "pages", "reports/daily", "reports/newsletter"]
    for container in containers:
        schema = ROOT / container / "CLAUDE.md"
        destination = source / container / "CLAUDE.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(schema, destination)
    home = base / "registry-home"
    home.mkdir()
    env = dict(os.environ, RILL_SOURCE=str(source), HOME=str(home),
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    env.pop("RILL_HOME", None)
    template = base / "template"
    checked([source / "bin/rill", "init", template, "--name", "comparison", "--no-default"], base, env)
    env["RILL_HOME"] = str(template)
    command = template / ".claude/commands/foundation-note.md"
    command.write_text("# Foundation note\n\nRead `foundation-assets/finding.txt` next to this workflow. "
                       "Create exactly one knowledge note using rill mkfile, type insight, "
                       "source inbox/journal/2030-01-02.md. Preserve its generated created field. "
                       "Include every factual detail and the marker from the resource. "
                       "Do not run distill, contact services, commit or push.\n")
    assets = command.parent / "foundation-assets"
    assets.mkdir()
    assets.joinpath("finding.txt").write_text("Marker: violet-orbit. In a synthetic benchmark, "
                                             "a cache reduced median latency from 120 ms to 45 ms.\n")
    # Update exercises legacy command -> Codex skill distribution.
    checked([source / "bin/rill", "update"], template, env)
    checked([source / "bin/rill", "mkfile", "inbox/journal", "--date", "2030-01-02", "--type", "journal"], template, env)
    journal = template / "inbox/journal/2030-01-02.md"
    with journal.open("a") as f:
        f.write("\n# Synthetic cache benchmark\n\nA cache reduced median latency from 120 ms to 45 ms "
                "in a synthetic benchmark. This suggests caching repeated reads can reduce latency. "
                "This is a technical observation, not a task or a commitment.\n")
    # Remove only the known init-owned welcome note from this synthetic template.
    welcome = template / "knowledge/notes/welcome-to-rill.md"
    if welcome.exists():
        welcome.unlink()
    for container in containers:
        for filename in ("CLAUDE.md", "AGENTS.md"):
            if not (template / container / filename).is_file():
                raise RuntimeError("Missing installed container schema: " + container + "/" + filename)
    checked([source / "bin/rill", "doctor", "codex"], template, env)
    # The fixture does not need onboarding or external synchronization.
    return template, source


def command_for(harness, model, prompt, vault):
    if harness == "codex":
        return ["codex", "exec", "--ignore-user-config", "--ephemeral", "--sandbox", "workspace-write",
                "-c", 'approval_policy="never"', "-c", 'web_search="disabled"',
                "-c", 'shell_environment_policy.inherit="all"',
                "--json", "--color", "never", "--model", model, "--cd", str(vault), prompt]
    settings = {"sandbox": {"enabled": True, "failIfUnavailable": True,
                             "autoAllowBashIfSandboxed": True, "allowUnsandboxedCommands": False}}
    return ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
            "--model", model, "--max-turns", "80", "--no-session-persistence",
            "--setting-sources", "project", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
            "--settings", json.dumps(settings), "--permission-mode", "acceptEdits",
            "--disallowedTools", "WebSearch,WebFetch,Bash(git push *)"]


def grade(vault, case, original, previous_notes=None):
    errors = []
    if digest(vault / "inbox/journal/2030-01-02.md") != original:
        errors.append("Original journal changed")
    notes = sorted(p for p in (vault / "knowledge/notes").glob("*.md")
                   if p.name not in ("AGENTS.md", "CLAUDE.md"))
    if len(notes) != case["expected_notes"]:
        errors.append("Expected exactly %s note(s), found %s" % (case["expected_notes"], len(notes)))
    body = "\n".join(p.read_text() for p in notes)
    for term in case["required_terms"]:
        if term.lower() not in body.lower():
            errors.append("Missing fact: " + term)
    for p in notes:
        text = p.read_text()
        match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.S)
        header = match[1] if match else ""
        for key in ("created", "type", "source"):
            if not re.search(r"^" + key + r":\s*\S", header, re.M):
                errors.append(p.name + ": missing " + key)
        if not re.search(r"^created: \d{4}-\d\d-\d\dT", header, re.M):
            errors.append(p.name + ": invalid created timestamp")
        if not re.search(r"^type: (record|insight|reference)\s*$", header, re.M):
            errors.append(p.name + ": invalid note type")
        if not re.search(r"^source: .*2030-01-02", header, re.M):
            errors.append(p.name + ": wrong source")
    if case.get("repeats", 1) > 1:
        processed = vault / "inbox/journal/.processed"
        lines = processed.read_text().splitlines() if processed.is_file() else []
        if lines.count("2030-01-02.md") != 1:
            errors.append("Journal must be marked processed exactly once")
    names = [p.name for p in notes]
    if previous_notes is not None and names != previous_notes:
        errors.append("Repeat changed the note set (duplicate or replacement)")
    return errors, names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", choices=["codex", "claude", "both"], default="both")
    parser.add_argument("--case", choices=list(CASES), action="append")
    parser.add_argument("--codex-model", required=True)
    parser.add_argument("--claude-model", required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--watch", type=Path, action="append", default=[], help="Read-only contamination snapshot")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    base = Path(tempfile.mkdtemp(prefix="rill-comparison-")).resolve()
    print("Results: " + str(base), flush=True)
    report = {"schema_version": 1, "source_revision": checked(["git", "rev-parse", "HEAD"], ROOT, os.environ).strip(),
              "source_dirty": bool(checked(["git", "status", "--porcelain"], ROOT, os.environ)),
              "case_sha256": digest(Path(__file__).with_name("cases.json")), "runs": []}
    watched = {str(p.resolve()): snapshot(p.resolve()) for p in args.watch}
    outside = base / "outside-canary.txt"
    outside.write_text("comparison canary\n")
    canary = digest(outside)
    try:
        template, source = setup(base)
        report["source_sha256"] = hashlib.sha256(json.dumps(snapshot(source), sort_keys=True).encode()).hexdigest()
        report["fixture_sha256"] = hashlib.sha256(json.dumps(snapshot(template), sort_keys=True).encode()).hexdigest()
        harnesses = ["codex", "claude"] if args.harness == "both" else [args.harness]
        for harness in harnesses:
            model = getattr(args, harness + "_model")
            version = subprocess.run([harness, "--version"], text=True, capture_output=True, timeout=30)
            if version.returncode:
                raise RuntimeError(harness + " --version failed")
            for case_name in args.case or CASES:
                case = CASES[case_name]
                run_dir = base / (harness + "-" + case_name)
                vault = run_dir / "vault"
                shutil.copytree(template, vault)
                env = dict(os.environ, RILL_HOME=str(vault), RILL_SOURCE=str(source),
                           PATH=str(vault / ".rill/bin") + os.pathsep + os.environ["PATH"],
                           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
                checked(["git", "init", "-q"], vault, env)
                # No remotes. The test identity is local to this repository.
                checked(["git", "config", "user.name", "Fixture Runner"], vault, env)
                checked(["git", "config", "user.email", "fixture@localhost"], vault, env)
                checked(["git", "add", "."], vault, env)
                checked(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "Synthetic fixture"], vault, env)
                original = digest(vault / "inbox/journal/2030-01-02.md")
                previous_notes = None
                for repeat in range(case["repeats"]):
                    prompt = case["prompt"] + "\nWork only in the current synthetic vault. Do not change harness settings or run rill update/init. Do not read other vaults. Use English for all generated content."
                    argv = command_for(harness, model, prompt, vault)
                    record = execute(argv, vault, env, args.timeout, run_dir / ("run-" + str(repeat + 1)))
                    record.update(harness=harness, model=model, version=version.stdout.strip(), case=case_name, repeat=repeat + 1)
                    errors, names = grade(vault, case, original, previous_notes)
                    output = (run_dir / ("run-" + str(repeat + 1) + ".stdout.jsonl")).read_text()
                    events = []
                    for line in output.splitlines():
                        try:
                            event = json.loads(line)
                            if isinstance(event, dict):
                                events.append(event)
                        except json.JSONDecodeError:
                            pass
                    if harness == "codex":
                        complete = any(e.get("type") == "turn.completed" for e in events)
                    else:
                        complete = any(e.get("type") == "result" and not e.get("is_error") and e.get("subtype") == "success" for e in events)
                    if not complete:
                        errors.append("No successful CLI completion event")
                    if record["status"] != "finished":
                        errors.append("CLI did not finish successfully")
                    if digest(outside) != canary:
                        errors.append("Outside canary changed")
                    for path, before in watched.items():
                        if snapshot(Path(path)) != before:
                            errors.append("Watched directory changed: " + path)
                    record["usage_events"] = [e for e in events if e.get("type") in ("turn.completed", "result")]
                    record["reported_models"] = sorted({str(e.get("model")) for e in events if e.get("model")})
                    record["errors"] = errors
                    record["passed"] = not errors
                    record["notes"] = names
                    report["runs"].append(record)
                    (base / "results.json").write_text(json.dumps(report, indent=2) + "\n")
                    print(harness, case_name, repeat + 1, "PASS" if not errors else "FAIL", errors, flush=True)
                    previous_notes = names
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        report["setup_error"] = str(exc)
    report["passed"] = bool(report["runs"]) and "setup_error" not in report and all(r["passed"] for r in report["runs"])
    (base / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
