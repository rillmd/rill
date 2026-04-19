# Claude Code Integration Rules — Rill

Rill operates as a companion tool for Claude Code. This document defines integration boundaries, CLI usage, shell compatibility, and other cross-cutting rules.

## Claude Code Integration Boundary (ADR-068, critical)

Rill is a Claude Code CLI companion tool. **The following are prohibited**:

1. **Adopting Agent SDK (`@anthropic-ai/claude-agent-sdk`)**
2. **Extracting or managing OAuth tokens**
3. **Using `--bare` mode**
4. **Using API Keys as default authentication**

### Automated Execution Sessions
- Use `claude -p --output-format stream-json` for automation
- Designed for Max Plan

### Alternative Architecture
When automation is needed:
- macOS: `launchd` (plist)
- Linux: systemd timer or `cron`
- Execution: `claude -p --output-format stream-json "/distill"` etc. (invoke existing skills)
- Auth: Uses the user's Max Plan auth (held by Claude Code itself)
- Logging: `reports/` or dedicated log file + 1-line entry in `activity-log.md`

## File Creation: `rill mkfile` Required (ADR-060)

**Use `rill mkfile` for all new file creation.** Ensures timestamp accuracy.

- Format: `rill mkfile {dir} --slug {slug} --type {type}`
- `rill mkfile` auto-assigns `created` field in ISO 8601 format
- **LLMs must never write `created` values directly**

### Examples

```bash
rill mkfile knowledge/notes --slug whisper-api-comparison --type insight
rill mkfile workspace --slug 2026-04-07-ai-agent-eval --type workspace
rill mkfile tasks --slug review-contract --type task
rill mkfile pages --slug rill-roadmap --type page
```

### Exceptions

- System files like `.claude/rules/*.md`, subdirectory `CLAUDE.md` etc. have no frontmatter, so `rill mkfile` is not needed
- Not needed for editing existing files (use Edit tool)

## GUI Integration: show paths, don't auto-navigate

When you want to point the user at a file you've explored, created, or analyzed, **display the repo-relative path as text** — as a Markdown link `[display name](relative/path.md)` or in backticks. The user opens it themselves via the header search box (or `Cmd+P` palette) in the Rill GUI, which accepts a pasted path directly.

**Do not run `rill open` to force-navigate the GUI.** Forcible navigation disrupts the user while they are reading a different document. The header search box is the user-controlled entry point — keep the decision to switch views on their side.

This applies to:
1. Artifacts produced by `/distill`, `/focus`, `/solve`, etc. — list the resulting paths at the end of the run
2. Files the user asked "where is this?" about — reply with the path, not an open command
3. Related files you want to highlight — mention the path in prose

The `rill open` CLI still exists for manual / scripted use, but skills and ad-hoc assistant turns must not invoke it.

## Activity Log

When adding new skills, consider activity-log support. User-initiated activities that don't leave file traces should be recorded in `activity-log.md`:
- Add path detection patterns to the PostToolUse hook
- Or call `rill activity-log add` at the end of the skill (ADR-034)

## zsh Compatibility (when generating Bash commands)

Claude Code's shell environment is zsh, so be aware of:

### 1. Glob Zero-Match Error Prevention
- `ls dir/*.md 2>/dev/null`
- Or use the Glob tool (recommended)
- `for f in dir/*.md; do ...` errors on zero matches → replace with Glob tool

### 2. Reserved Variable Name Avoidance
- `status` (read-only) — cannot be used → use `file_status` etc.
- `aliases` (associative array) — cannot be used → use `alias_list` etc.

### 3. Prefer Glob Tool for File Collection
- Use Glob tool instead of Bash `for f in dir/*.md`
- Use Grep tool instead of running `rg` or `grep` directly

## Other Cross-Cutting Rules

### docs/ vs PKM Distinction
- `docs/` is **documentation about the Rill system itself**
- Distinct from PKM data (inbox/, knowledge/, workspace/, etc.)
- Technical decisions are recorded as ADRs in `docs/decisions/`
- Update `SPEC.md` on system design changes

### Binary Assets
- **PII-bearing source binaries** (business cards, meeting slides, scanned contracts containing real names / emails / phone numbers) — do not commit. Default `.gitignore` excludes `inbox/sources/*.{jpg,jpeg,png,heic,pdf}` per ADR-047 D47-2.
- **Non-PII asset binaries** (app icons, logos, documentation screenshots, generated figures) — commit when reasonably small (~2 MB soft cap) and the user has approved the asset. Prefer SVG / Markdown over raster when equivalent.
- The gate is PII-content, not file format. A 100 KB app icon is fine; a screenshot leaking real email addresses is not.

### `_distill/` Internal Templates
- `.claude/commands/_distill/` contains internal templates for /distill
- Underscore prefix means not user-invocable
- Agents Read and use them (ADR-048)
