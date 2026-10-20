"""Deterministic regression tests; no model calls or production vault inputs."""
import json
import importlib.util
import sys
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Foundation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="rill-foundation-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.vault = self.base / "vault"
        self.vault.mkdir()
        self.env = dict(os.environ, RILL_HOME=str(self.vault), TMPDIR=str(self.base))
        (self.vault / ".rill").mkdir()
        (self.vault / ".rill/managed-files.txt").write_text("managed.md\n")
        (self.vault / "managed.md").write_text("protected\n")
        (self.vault / "sub").mkdir()

    def shell(self, text, *args, cwd=None):
        return subprocess.run(["bash", "-c", text, "test", *map(str, args)],
                              env=self.env, cwd=cwd or self.vault,
                              text=True, capture_output=True, timeout=60)

    def hook(self, payload, expected, event="pre-write"):
        result = subprocess.run([str(ROOT / "bin/rill"), "codex-hook", event],
                                input=json.dumps(payload), cwd=self.vault, env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)

    def test_hook_envelopes_and_denial(self):
        for path, expected in [("note.md", 0), ("managed.md", 2),
                               ("./sub/../managed.md", 2),
                               (str(self.vault / "managed.md"), 2)]:
            for payload in [{"tool_input": {"file_path": path}},
                            {"input": {"path": path}},
                            {"tool_input": json.dumps({"file_path": path})}]:
                self.hook(payload, expected)
        for kind in ["Add File", "Update File", "Delete File", "Move to"]:
            patch = "*** Begin Patch\n*** Update File: note.md\n*** " + kind + ": managed.md\n*** End Patch"
            for payload in [{"tool_input": patch}, {"input": patch},
                            {"tool_input": {"command": patch}},
                            {"arguments": {"patch": patch}}]:
                self.hook(payload, 2)
        self.hook({"tool_input": {"command": "*** Begin Patch\n*** Add File: note.md\n+ok\n*** End Patch"}}, 0)
        for payload in [{}, {"tool_input": {}}, {"tool_input": {"file_path": ""}},
                        {"tool_input": {"file_path": "a\nb"}}, {"tool_input": 5}]:
            self.hook(payload, 2)
        self.hook({"cwd": str(self.vault / "sub"), "tool_input": {"path": "../managed.md"}}, 2)
        (self.vault / "alias.md").symlink_to("managed.md")
        self.hook({"tool_input": {"path": "alias.md"}}, 2)
        # A listed managed symlink must protect its own name and its target.
        (self.vault / "managed-link.md").symlink_to("note.md")
        with (self.vault / ".rill/managed-files.txt").open("a") as f:
            f.write("managed-link.md\n")
        self.hook({"tool_input": {"path": "managed-link.md"}}, 2)
        self.hook({"tool_input": {"path": "note.md"}}, 2)

    def test_post_write_target_and_checkpoint(self):
        note = self.vault / "knowledge/notes/note.md"
        note.parent.mkdir(parents=True)
        original = "---\ncreated: fixture\ntype: note\n---\n\n# Note\n"
        note.write_text(original)
        other = note.with_name("other.md")
        other.write_text(original)
        self.hook({"cwd": str(note.parent), "session_id": "foundation",
                   "tool_input": {"file_path": "note.md"}}, 0, "post-write")
        self.assertIn("\nupdated:", note.read_text())
        self.assertEqual(other.read_text(), original)
        state = self.base / "rill-ckpt-foundation"
        self.assertTrue(state.is_dir())
        state_text = "\n".join(p.read_text() for p in state.rglob("*") if p.is_file())
        self.assertIn("note.md", state_text)
        self.assertNotIn("other.md", state_text)

    def test_child_failure_and_counter_overflow(self):
        lib = ROOT / "test/assertions/lib.sh"
        for command, expected in [("true", 0), ("false", 1), ("bash -c 'exit 42'", 1)]:
            r = self.shell('source "$1"; run_assertion ' + command + '; report_results', lib)
            self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        r = self.shell('source "$1"; for i in {1..256}; do assert_eq x y injected; done; report_results', lib)
        self.assertNotEqual(r.returncode, 0)

    def test_individual_skill_propagates_child_failure(self):
        # Use the real inspect suite. Only replace its child assertion, so the
        # suite must succeed for rc=0 and fail for rc=42 with identical inputs.
        test = self.base / "test"
        (test / "skills").mkdir(parents=True)
        shutil.copytree(ROOT / "test/assertions", test / "assertions")
        shutil.copy2(ROOT / "test/skills/test-inspect.sh", test / "skills/test-inspect.sh")
        for directory in ["inbox", "knowledge/notes"]:
            (self.vault / directory).mkdir(parents=True, exist_ok=True)
        for rc in [0, 42]:
            (test / "assertions/check-no-mutation.sh").write_text("exit " + str(rc) + "\n")
            r = self.shell('bash "$1" --skip-execute "--vault=$2"',
                           test / "skills/test-inspect.sh", self.vault)
            self.assertEqual(r.returncode == 0, rc == 0, r.stdout + r.stderr)

    def test_aggregate_and_ci_exit(self):
        test = self.base / "suite/test"
        test.mkdir(parents=True)
        suite = (ROOT / "test/run-all.sh").read_text()
        (test / "run-all.sh").write_text(suite)
        children = re.findall(r'\$SCRIPT_DIR/([^"\s]+\.(?:sh|py))', suite)
        self.assertGreater(len(children), 10)
        for child in children:
            p = test / child
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("" if p.suffix == ".py" else "exit 0\n")
        self.assertEqual(self.shell('bash "$1"', test / "run-all.sh").returncode, 0)
        (test / "skills/test-distill.sh").write_text("exit 42\n")
        self.assertNotEqual(self.shell('bash "$1"', test / "run-all.sh").returncode, 0)
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        block = workflow.split("name: pure-shell suites", 1)[1].split("run: |", 1)[1].split("\n  guard:", 1)[0]
        command = textwrap.dedent(block).strip()
        self.assertIn('exit "$fail"', command)
        self.assertEqual(self.shell(command, cwd=test.parent).returncode, 0)
        (test / "cli/test-cli-smoke.sh").write_text("exit 42\n")
        self.assertNotEqual(self.shell(command, cwd=test.parent).returncode, 0)


class Comparison(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("comparison", ROOT / "test/harness/compare.py")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_execution_failures_never_pass(self):
        with tempfile.TemporaryDirectory(prefix="rill-runner-test-") as temp:
            base = Path(temp)
            for code, expected in [("print('ok')", "finished"), ("raise SystemExit(7)", "failed"),
                                   ("import time; time.sleep(10)", "timeout")]:
                result = self.module.execute([sys.executable, "-c", code], base, os.environ, 0.1, base / "run")
                self.assertEqual(result["status"], expected)
            result = self.module.execute([str(base / "missing-cli")], base, os.environ, 1, base / "missing")
            self.assertEqual(result["status"], "not-run")

    def test_timeout_kills_children_after_leader_exits(self):
        with tempfile.TemporaryDirectory(prefix="rill-child-timeout-") as temp:
            base = Path(temp)
            code = """import os, signal, time
from pathlib import Path
if os.fork() == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    Path('ready').write_text('ready')
    time.sleep(0.7)
    Path('leaked').write_text('child survived')
    os._exit(0)
time.sleep(10)
"""
            result = self.module.execute([sys.executable, "-c", code], base, os.environ, 0.4, base / "run")
            self.assertEqual(result["status"], "timeout")
            self.assertTrue((base / "ready").exists())
            time.sleep(0.5)
            self.assertFalse((base / "leaked").exists())

    def test_deployment_excludes_private_and_untracked_files(self):
        with tempfile.TemporaryDirectory(prefix="rill-copy-test-") as temp:
            root = Path(temp) / "root"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            fixtures = ["plugins/demo/run.sh", "plugins/local/private/run.sh",
                        "plugins/demo/.config", "plugins/demo/.state/private.txt"]
            for name in fixtures:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text("synthetic sentinel")
            subprocess.run(["git", "-C", str(root), "add", "-f", "."], check=True)
            (root / "plugins/demo/untracked-secret").write_text("synthetic secret")
            source = Path(temp) / "source"
            self.module.copy_deployment(root, source)
            self.assertEqual([str(p.relative_to(source)) for p in source.rglob("*") if p.is_file()],
                             ["plugins/demo/run.sh"])

    def test_snapshot_tracks_directory_symlink_changes(self):
        with tempfile.TemporaryDirectory(prefix="rill-watch-test-") as temp:
            root = Path(temp)
            (root / "one").mkdir()
            (root / "two").mkdir()
            link = root / "alias"
            before = self.module.snapshot(root)
            link.symlink_to("one", target_is_directory=True)
            added = self.module.snapshot(root)
            self.assertNotEqual(before, added)
            link.unlink()
            link.symlink_to("two", target_is_directory=True)
            self.assertNotEqual(added, self.module.snapshot(root))
            link.unlink()
            self.assertEqual(before, self.module.snapshot(root))

    def test_fixture_includes_installed_container_schemas(self):
        with tempfile.TemporaryDirectory(prefix="rill-schema-test-") as temp:
            vault, source = self.module.setup(Path(temp).resolve())
            for container in ["inbox/journal", "knowledge/notes", "tasks", "workspace"]:
                self.assertEqual((vault / container / "CLAUDE.md").read_bytes(),
                                 (ROOT / container / "CLAUDE.md").read_bytes())
                self.assertTrue((vault / container / "AGENTS.md").is_file())
            self.assertFalse((source / ".git").exists())
            self.assertEqual(list((source / "inbox/journal").iterdir()),
                             [source / "inbox/journal/CLAUDE.md"])

    def test_grade_detects_fact_loss_duplicates_and_mutation(self):
        with tempfile.TemporaryDirectory(prefix="rill-grader-test-") as temp:
            vault = Path(temp)
            journal = vault / "inbox/journal/2030-01-02.md"
            journal.parent.mkdir(parents=True)
            journal.write_text("original fixture")
            original = self.module.digest(journal)
            note = vault / "knowledge/notes/note.md"
            note.parent.mkdir(parents=True)
            valid = "---\ncreated: 2030-01-02T01:00+00:00\ntype: insight\nsource: inbox/journal/2030-01-02.md\n---\nviolet-orbit cache 120 45\n"
            note.write_text(valid)
            case = self.module.CASES["create-note"]
            errors, names = self.module.grade(vault, case, original)
            self.assertEqual(errors, [])
            note.write_text(valid.replace("120", ""))
            self.assertTrue(self.module.grade(vault, case, original)[0])
            note.write_text(valid)
            note.with_name("duplicate.md").write_text(valid)
            self.assertTrue(self.module.grade(vault, case, original, names)[0])
            journal.write_text("mutated")
            self.assertIn("Original journal changed", self.module.grade(vault, case, original)[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
