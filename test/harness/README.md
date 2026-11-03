# Rill harness evaluation foundation

This directory compares installed Rill workflows using the actual Codex and
Claude Code CLIs. It complements the deterministic tests in `test/cli/` and the
older Claude skill suites in `test/skills/`; it is not the knowledge-search
quality evaluation provided by `/eval`.

## Run

Log into both CLIs using their normal interactive login flows first. Then run:

```bash
python3 test/harness/compare.py \
  --harness both --codex-model gpt-6-astra --claude-model opus
```

Model arguments are explicit. Choose model names supported by your installed
CLIs and account. `--case create-note` selects the small distribution/resource
case; `--case distill-repeat` runs the real `/distill` workflow twice. The default
runs both. `--timeout` is a per-invocation wall-clock limit in seconds (default
600), and the runner terminates the entire invocation process group on timeout.
This is opt-in: ordinary CI does not call either model or spend model credits.

The runner prints a newly allocated temporary directory containing `results.json`,
raw CLI stdout/stderr and every resulting synthetic vault. It retains failures
for inspection. There is deliberately no existing-vault argument. Inputs are
constructed locally, never read from a production vault. Clean up retained test
directories yourself after reviewing them.

Optional `--watch /path/to/a/vault` takes read-only content snapshots before and
after execution. A change anywhere in the watched directory (excluding Git
internals) fails the comparison. Concurrent legitimate edits also fail this
check; run comparisons when watched vaults are idle. An outside canary adds a
small additional contamination check. Neither check detects every possible
write outside the test area or replaces the OS sandbox.

## What is measured

`cases.json` contains expectations independently of the generated outputs:

- `create-note`: invoke a projected personal command, read its adjacent asset,
  create exactly one note with required facts, source and timestamp metadata.
- `distill-repeat`: extract one reusable cache benchmark finding from a journal;
  preserve the original; record processing exactly once; run again and verify
  that no duplicate or replacement note appears.

A pass requires a zero CLI exit status, a successful structured completion
event, expected artifacts/facts and all invariants. An empty log, missing CLI,
authentication error, timeout or failed completion never counts as a pass.
The per-run record includes CLI version, requested model, arguments, elapsed
seconds, completion/usage events, note names and individual failures. Raw logs
retain resolved model details when the CLI reports them. The source revision,
dirty-state indicator and initial fixture digest identify the evaluated input.

This is a small functional regression set. Keyword checks cannot establish
semantic quality, generalized reliability, or model superiority. Review the
retained notes as well. Repeated trials and a larger, held-out case set are the
next step before removing more rules or comparing quality statistically.

## Isolation and scope

Each harness/case receives a separate copy of the same initialized fixture.
Only allowlisted, Git-tracked deployment inputs are copied from the current checkout; source Git
metadata, worktrees, credentials and real vault contents are excluded. Local plugins, plugin
configuration/state and untracked files are excluded even if present in the checkout.
Symlink deployment inputs fail setup rather than following an external target. The
initialization registry has a separate home. Child processes use the fixture's
`RILL_HOME` and projected `rill` executable on PATH. Repositories have no remote.

The CLIs reuse the operator's existing authentication; no credential file is
copied or printed. Codex ignores user configuration and uses `workspace-write`
with approvals disabled (a denied action fails rather than prompting). Claude
loads project settings only, disables external MCP servers, requires its Bash
sandbox, disallows unsandboxed retries and runs with edit acceptance. User-level
CLI runtime state and authentication stores are still owned by the CLIs; this
is not a separate virtual machine or a claim of identical system prompts.

The runner does not bypass hook trust. Untrusted newly projected hooks may be
skipped by the CLI, so these model runs alone are not evidence that hook
protection was active. `test-evaluation-foundation.sh` independently replays
actual supported hook envelopes and asserts exact blocking exit codes and
post-write side effects. Deployment must still establish hook trust through
the harness's normal mechanism.

Do not publish raw logs without inspecting them: CLI startup may include local
paths or user customization metadata even though all evaluation data is fake.
A public PR should include reviewed aggregate results and limitations.

## Deterministic regression checks

```bash
bash test/cli/test-evaluation-foundation.sh
bash test/cli/test-codex-projection.sh
bash test/cli/test-cli-smoke.sh
bash test/cli/test-track-managed-gitignore.sh
```

The foundation suite injects failures into child assertions, a real individual
skill suite, the aggregate runner and the exact shell block used by CI. It also
covers a 256-failure counter overflow, unknown hook inputs, string/object/command
patch envelopes, multiple targets, moves, relative paths, symlink aliases and
post-write recording. Distribution tests cover init/update, personal assets,
user-owned skills, plugin activation/deactivation and missing metadata.

The legacy skill suites still support assertion-only modes for diagnosis; those
modes do not prove that a model ran. Use this comparison runner for structured
live-run evidence. The aggregate `test/run-all.sh` includes model-backed legacy
suites and must not be mistaken for a model-free CI command.
