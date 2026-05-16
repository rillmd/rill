# Claude Code Integration Rules — Rill

Rill is a companion tool for Claude Code. Integration boundaries, CLI usage, shell compatibility.

## Claude Code Integration Boundary (ADR-068, critical)

**Prohibited**:

1. Adopting Agent SDK (`@anthropic-ai/claude-agent-sdk`)
2. Extracting or managing OAuth tokens
3. Using `--bare` mode
4. Using API Keys as default authentication

For automation: `claude -p --output-format stream-json` (designed for Max Plan auth held by Claude Code itself). Alternative architecture: macOS `launchd` / Linux `systemd timer` or `cron` calling `claude -p --output-format stream-json "/distill"` etc. Log to `reports/` or dedicated log file plus 1-line `activity-log.md` entry.

## File Creation: `rill mkfile` Required (ADR-060)

**Use `rill mkfile` for all new file creation.** Ensures timestamp accuracy. Auto-assigns `created` in ISO 8601 — **LLMs must never write `created` directly**.

Format: `rill mkfile {dir} --slug {slug} --type {type}`.

```bash
rill mkfile knowledge/notes --slug whisper-api-comparison --type insight
rill mkfile workspace --slug 2026-04-07-ai-agent-eval --type workspace
rill mkfile tasks --slug review-contract --type task
rill mkfile pages --slug rill-roadmap --type page
```

Exceptions: system files without frontmatter (`.claude/rules/*.md`, subdirectory `CLAUDE.md`); editing existing files (use Edit tool).

## GUI Integration: show paths, don't auto-navigate

Point users at files by displaying repo-relative paths as text — Markdown link `[display name](relative/path.md)` or backticks. The user opens them via the GUI header search box (or `Cmd+P`).

**Do not run `rill open`** to force-navigate. The header search box is the user-controlled entry point — keep the decision to switch views on their side.

Applies to: artifacts produced by `/distill`, `/focus`, `/solve` (list paths at end of run); files the user asked about; related files highlighted in prose. `rill open` CLI exists for manual / scripted use only — skills and ad-hoc turns must not invoke it.

## Activity Log

When adding skills, consider activity-log support. User-initiated activities without file traces should be recorded in `activity-log.md`: add path patterns to the PostToolUse hook, or call `rill activity-log add` at end of skill (ADR-034).

## zsh Compatibility

Claude Code's shell is zsh:

- **Glob zero-match**: prefer the Glob tool, or `ls dir/*.md 2>/dev/null`. `for f in dir/*.md; do ...` errors on zero matches.
- **Reserved variable names**: `status` (read-only), `aliases` (associative array) — use `file_status`, `alias_list`.
- **Prefer the Glob tool** over `for f in dir/*.md`; prefer Grep tool over running `rg` or `grep` directly.

## Other Cross-Cutting

- **`docs/` vs PKM**: `docs/` is documentation about Rill itself (distinct from inbox/, knowledge/, workspace/). ADRs live in `docs/decisions/`. Update `SPEC.md` on system design changes.
- **Binary assets**: PII-bearing source binaries (business cards, scanned contracts, screenshots with real names/emails/phones) — don't commit; excluded by default `.gitignore` per ADR-047 D47-2. Non-PII asset binaries (app icons, logos, doc screenshots, figures) — commit if small (~2 MB soft cap) and user-approved. Prefer SVG / Markdown. Gate is PII content, not format.
- **`_distill/` internal templates**: `.claude/commands/_distill/` holds internal templates for /distill (underscore = not user-invocable, agents Read them, ADR-048).
