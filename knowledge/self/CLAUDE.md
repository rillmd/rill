# knowledge/self/ — Persistent Knowledge Layer About Yourself

The entity layer that captures "you". Flat 9-file structure (no subdirectories). Each file is owned by a distinct velocity / skill group (see ADR-067; designed in workspace 2026-05-07 artifact 006).

## File List

### Static group (year-scale updates)
- `profile.md` — Core Identity, career summary, Skills
- `history.md` — Career and life milestones (for applications / interviews; aggregation target for past projects)

### Mid-velocity group (weekly to monthly)
- `constraints.md` — Family / financial / health / life events
- `interests.md` — Deep Interests / Curiosity / Obligations / Career (theme statements)
- `direction.md` — Cross-project meta-direction (current main axis / exclusions / Active Projects list)
- `decisions.md` — Curated decision digest (3-month window, updated by `/retrospective`)
- `observations.md` — Longitudinal self-observations
- `watches.md` — Watch targets (Competitors / Keywords / Key Facts; used by `/newsletter`)

### High-velocity group (daily to hourly)
- `current-state.md` — Pulse snapshot (updated by `/pulse`)

## Role Split

| File | What to write | What not to write |
|---|---|---|
| `profile.md` | Identification, career summary | Individual decisions |
| `history.md` | Chronology of career and life events | Active projects |
| `constraints.md` | Constraints (family / financial / health) | Per-task deadlines |
| `interests.md` | Theme statements (broad "what am I interested in") | Specific competitor names / keywords |
| `direction.md` | Current main theme, Active Projects | General-topic themes |
| `decisions.md` | Major decisions in past 3 months | Intra-session minor decisions |
| `observations.md` | Self-tendencies (recurring patterns) | One-off events |
| `watches.md` | Concrete watch targets (Competitors / Keywords / Key Facts) | Theme statements |
| `current-state.md` | Current-state snapshot (active WSs / tasks / decision gates) | Accumulated information |

## Boundary Between `interests.md` and `watches.md`

- `interests.md`: **What you are interested in** (broad statement)
  - Example: "Build a business with Claude Code"
- `watches.md`: **What concrete entities you watch** (specific entities)
  - Example: "Claude Code ecosystem" section → Dream System / KAIROS / ULTRAPLAN ...

Both are read by `/newsletter`. `interests.md` feeds Deep Dive / Discovery; `watches.md` feeds Alerts.

## Structure of `watches.md`

```markdown
# Watches

## {watch topic name}
**Why watch**: ...

### Competitors
- ...
### Keywords
- ...
### Key Facts (cap 20)
- ...
```

When adding a new watch target, append a `## {name}` section. A single file can handle 10–20 targets.

## Update Mechanism

Each file is owned by a distinct update velocity and a single writer: high-velocity `current-state.md` is overwritten only by `/pulse`; `decisions.md` / `observations.md` are appended only by `/retrospective`; `interests.md` / `direction.md` are updated conservatively by the `/distill` profile-agent; `profile.md` / `history.md` / `constraints.md` are manual. One writer per file means snapshot churn never rewrites slow identity files, and each skill has exactly one write target.
