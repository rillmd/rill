<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/rill-logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/rill-logo-light.svg">
    <img alt="Rill" src="assets/rill-logo-light.svg" height="60">
  </picture>
</p>

<p align="center"><strong>AI remembers. Rill thinks.</strong></p>

Rill is a personal knowledge management system powered by [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It distills fragmented thoughts — entered via voice, text, or external sources — into structured, searchable knowledge.

All data is plain Markdown. Git is the single source of truth. Claude Code is the processor.

## How It Works

```
Voice / Text / Files / URLs
        │
        ▼
    inbox/          ← Immutable input layer
        │
        ▼ /distill
    knowledge/      ← Evergreen atomic knowledge
        │
        ▼ /focus + /close
    workspace/      ← Deep thinking sessions
        │
        ▼ /briefing, /newsletter
    reports/        ← Daily notes & research reports
```

**Core skills:**

| Skill | What it does |
|-------|-------------|
| `/distill` | Distill inbox entries into structured knowledge, tasks, and entities |
| `/briefing` | Generate a daily note with today's focus and yesterday's activity |
| `/newsletter` | Generate a daily research report based on your interests |
| `/focus` | Start or resume a deep thinking workspace |
| `/close` | Complete a workspace and distill insights to knowledge |
| `/page` | Create and update human-facing aggregated views |
| `/morning` | Run the full morning routine: sync → distill → briefing → newsletter |

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (with Max Plan)
- Git
- `jq` (for `rill init`)

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/rillmd/rill/main/install.sh | bash
```

### Start using Rill

The installer creates a vault at `~/Documents/my-rill`. Open it with Claude Code:

```bash
cd ~/Documents/my-rill
claude
```

Then type `/onboarding` to start your first session.

### Daily Usage

```bash
# Capture thoughts
rill log "Ideas about project architecture"

# Run morning routine
claude "/morning"

# Deep dive into a topic
claude "/focus API redesign"

# Import a web article
rill clip https://example.com/interesting-article
```

## Vault Structure

After `rill init`, your knowledge repository looks like:

```
my-rill/
├── inbox/
│   ├── journal/        # Your thoughts (rill log)
│   ├── meetings/       # Meeting notes
│   ├── tweets/         # Saved tweets
│   ├── web-clips/      # Web articles
│   └── sources/        # Other external input
├── knowledge/
│   ├── me.md           # Your interest profile
│   ├── notes/          # Atomic knowledge (distilled)
│   ├── people/         # Person entities
│   ├── orgs/           # Organization entities
│   └── projects/       # Project profiles
├── workspace/          # Deep thinking sessions
├── tasks/              # Task tickets
├── reports/
│   ├── daily/          # Daily notes (/briefing)
│   └── newsletter/     # Research reports (/newsletter)
├── pages/              # Aggregated views
├── taxonomy.md         # Tag vocabulary
└── CLAUDE.md           # Claude Code instructions
```

## Updating

```bash
cd ~/src/rillmd/rill && git pull
rill update
```

`rill update` syncs the latest skills and rules to your vault. Your personal data and custom skills are never touched.

## Plugins

Rill supports plugins for importing data from external services. See [plugins/README.md](plugins/README.md) for the plugin development guide.

## Documentation

- [SPEC.md](SPEC.md) — Full system specification (state machine, schemas, pipelines)
- [plugins/README.md](plugins/README.md) — Plugin development guide

## License

[MIT](LICENSE)
