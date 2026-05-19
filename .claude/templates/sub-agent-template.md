<!--
Sub-agent prompt template — leaf agent variant.

When adding a new skill that spawns one or more **leaf** sub-agents via the
Agent tool (typically `subagent_type: general-purpose`, model: sonnet or
haiku), copy this file to the appropriate location and fill in the
placeholders:

    cp .claude/templates/sub-agent-template.md \
       .claude/commands/_{new-skill}/{agent-name}.md

A leaf agent returns structured output to the parent and does not write
files itself — the parent orchestrator performs every write. The canonical
in-repo example is `.claude/commands/_retrospective/theme-extraction-agent.md`.

Writer agents (sub-agents that create or update files as part of their job —
e.g. `_close/distillation-agent.md`, `_distill/journal-agent.md`,
`_task/create-agent.md`) need additional sections beyond this scaffold and
their output contracts vary per parent (YAML status fields, plain-text path
lines, etc.). For a writer agent, copy directly from one of those existing
files rather than starting here.

Placeholders to replace:

- `{Agent Name}`             — Title-cased agent name (e.g. "Theme Extraction Agent")
- `{one-line purpose}`       — One-sentence description of what the agent does
- `{required-input-N}`       — Inputs the parent orchestrator injects into the
                                rendered Agent-tool `prompt` string
- `{narrative-fields-list}`  — Names of free-text output fields (e.g. `summary`,
                                `conclusion`)
- `{internal-keys-list}`     — Names of structured fields that must stay
                                verbatim English (kebab-case keys, paths,
                                enum values)
- `{sentinels-list}`         — Any fixed enum / sentinel strings the
                                coordinator string-matches downstream (e.g.
                                `"(in progress)"`, confidence levels like
                                `"high"`/`"medium"`/`"low"`)
- `{output-schema-block}`    — Concrete YAML schema example
- `{constraint-N}`           — Skill-specific constraints

Optional sections (Read budget, What to extract, Failure handling) can be
dropped if not needed. The required sections — Target inputs, Language,
Output, Constraints — establish the contract every leaf sub-agent follows.

In-repo references:

- `.claude/commands/_retrospective/theme-extraction-agent.md` — canonical leaf
  example with the full Target inputs / Language / Read budget / Output /
  Failure handling / Constraints stack
- `.claude/commands/_retrospective/observation-agent.md` — leaf example with
  a simpler output schema
- `.claude/rules/rill-core.md` § Language Rules — distribution-default English
  with sharp boundary rules; the source of truth that `output_language` /
  `style_guide` injection extends per-vault
-->

# {Agent Name}

`/{parent-skill}` {phase-or-step} sub-agent. {one-line purpose}

## Target inputs

The parent orchestrator spawns this agent via the Agent tool
(typically `subagent_type: general-purpose`) and injects the following values
into the rendered `prompt` string. Each invocation receives:

- `{required-input-1}`: {one-line description, e.g. a list of paths to process}
- `{required-input-2}`: {one-line description}
- `output_language` (optional): ISO 639-1 language code for narrative output fields (e.g. `"ja"`, `"en"`); when omitted, default to English
- `style_guide` (optional): short vocabulary-boundary rules for narrative fields (see Language section); when omitted, write narrative fields in plain English

## Language

Use the language specified by `output_language` (ISO 639-1) for narrative output fields ({narrative-fields-list}). Internal keys ({internal-keys-list}), paths, fixed enum values, and the protocol sentinels emitted by this prompt — {sentinels-list} — stay verbatim English regardless of `output_language` because the coordinator string-matches them. Follow the inline `style_guide` block for vocabulary boundaries on the narrative fields.

## Read budget

{Optional. If the agent reads files from disk, document the per-invocation
cap so the parent can size the fanout safely. Otherwise delete this section.}

For each input path:

1. Full Read of `{primary-file-pattern}` (typically {expected-line-count} lines)
2. {Recency-weighted budget for secondary files, if applicable}

Avoid reading every file in full — keep per-agent tokens under ~30K to fit
the parent's fanout budget.

## What to extract

{Per-input enumeration of what the agent looks for. Bullet list, 3-7 items.}

1. **{Concept 1}** ({how many per input}): {short rule}
2. **{Concept 2}**: {short rule}
3. **{Concept 3}**: {short rule}

{Optional: skip rules / negative examples. Keep the agent's judgment surface
small so its output is predictable.}

## Output

Return a single YAML document on stdout. No prose before or after the YAML.

```yaml
{output-schema-block}
```

### Output schema requirements

- Every required field must be present; use `[]` for empty lists
- {Per-field requirements: required vs optional, value ranges, ordering}
- Narrative fields ({narrative-fields-list}) follow the Language section above
- Internal keys ({internal-keys-list}) and sentinel strings stay verbatim English regardless of `output_language`

## Failure handling

{Optional. If parts of the input may be unreadable / unparseable, document the
sentinel value to emit per failure mode so the parent can detect partial
results rather than guessing. Otherwise delete this section.}

| Condition | Emit |
|---|---|
| {Specific failure mode 1} | `"{sentinel-string-1}"` |
| {Specific failure mode 2} | `"{sentinel-string-2}"` |

Sentinels listed here are coordinator-string-matched and must stay verbatim
English regardless of `output_language`.

## Constraints

- Do not write any file. Return the structured output to the response body and let the parent orchestrator handle all file writes.
- Do not spawn further sub-agents. This is a leaf in the agent fanout DAG (parent → this agent → nothing).
- {constraint-3, skill-specific — e.g. "Do not invent {entity-type} IDs not present in `entity_mapping`"}
- {constraint-4, skill-specific — e.g. "Skip {category} items entirely; the parent handles them deterministically"}
