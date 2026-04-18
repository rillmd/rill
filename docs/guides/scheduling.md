# Scheduling Rill's Daily Routines

Rill's skills are interactive. You invoke them by asking Claude inside your vault, or by running `claude -p "/skill"` from the shell. If you want them to run automatically on a schedule, this guide walks through the options.

## Easiest path: ask Claude to set it up

Open Claude Code in your vault and say something like:

> *"set up the morning briefing to run automatically at 8am, and pull in my plugins at 7:55"*
>
> *"schedule /newsletter for every evening at 5pm"*

Claude will read this guide, pick the right mechanism for your platform (Desktop Scheduled Tasks if the app is running, launchd on macOS, cron on Linux), write the plist or crontab entry, and load it. You can inspect what Claude did afterwards — the files live in the standard locations (`~/Library/LaunchAgents/`, `crontab -l`, `~/.claude/scheduled-tasks/`).

**Note for Claude reading this guide.** When a Rill user asks you to schedule a skill to run automatically, the intent is *local* scheduling using one of the three Manual setup options below — not the `schedule` meta-skill, which creates Anthropic-hosted remote cron agents and is unrelated to running `/morning` / `/sync` / `/distill` / `/newsletter` against a user's local vault. Use Bash + Edit to create the plist, crontab entry, or Desktop Scheduled Task directly.

Prefer doing it yourself? The **Manual setup** section below documents each option in full. The three are in order of preference for a typical personal machine.

A fully manual workflow — no schedule at all — is also fine. The Daily Note surfaces unprocessed inbox counts and tells you when there is pending work. You only need a scheduler if you want the vault to stay current on days you do not open Claude Code yourself.

## Manual setup

The rest of this guide documents the mechanics of each option, useful when you want to audit what Claude set up for you, or when you prefer to configure it by hand.

### What to Schedule

A typical daily cadence looks like this:

| Time  | Skill                  | Purpose                                                                 |
|-------|------------------------|-------------------------------------------------------------------------|
| 07:55 | `/sync` then `/distill` | Pull external sources, extract knowledge, create draft tasks            |
| 08:00 | `/morning`             | Generate Daily Note + Newsletter (surfaces overnight draft tasks)       |
| 17:00 | `/newsletter`          | Optional second research pass if you want afternoon news coverage       |

`/sync` and `/distill` are intentionally separate from `/morning` — `/distill` can take several minutes (up to 5 parallel agents), so running it inside `/morning` would force you to wait through heavy processing for output that only affects *tomorrow's* briefing. Keeping them separate means `/morning` stays fast and each pipeline can be scheduled independently.

See [ADR-075](../decisions/075-morning-scheduler-separation.md) for the reasoning behind this separation (if your copy of the vault contains ADRs).

### Option A: Claude Code Desktop Scheduled Tasks

The simplest option if you use the Claude Code desktop app.

**How it works.** Desktop Scheduled Tasks fire when the desktop app is running. Each execution is an independent session with full access to your vault. Missed runs from the past 7 days can catch up once when you next open the app.

**Setup.**

1. Add Claude Code Desktop to your login items (macOS: *System Settings → General → Login Items*) so it auto-starts when you log in.
2. Create three task files under `~/.claude/scheduled-tasks/`:

   `morning-sync/SKILL.md`:
   ```yaml
   ---
   name: morning-sync
   description: Pull external sources and distill
   ---

   Run /sync, then /distill. Commit and push any changes with the message
   "sync: YYYY-MM-DD morning".
   ```

   `morning-reports/SKILL.md`:
   ```yaml
   ---
   name: morning-reports
   description: Generate Daily Note and Newsletter
   ---

   Run /morning. Commit and push with the message "morning: YYYY-MM-DD".
   ```

   `daily-newsletter/SKILL.md` (optional second run):
   ```yaml
   ---
   name: daily-newsletter
   description: Evening research newsletter
   ---

   Run /newsletter. Commit and push with the message "newsletter: YYYY-MM-DD".
   ```

3. In the Desktop app sidebar, configure each task with a daily schedule at the desired time (`07:55`, `08:00`, `17:00`).
4. Run each task once via *Run now* and approve permission prompts as *always allow* so subsequent runs are non-interactive.

**Pros.** GUI for schedule configuration and history. Automatic catch-up for missed runs.
**Cons.** Requires the desktop app to be running and your Mac to be awake at the scheduled time.

### Option B: macOS launchd

For CLI-only users or when you want schedules to run without the desktop app.

**How it works.** `launchd` runs `claude -p` as a background process under your user account whenever your Mac is awake at the scheduled time.

**Setup.**

Create `~/Library/LaunchAgents/com.rillmd.morning-sync.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rillmd.morning-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-lc</string>
        <string>cd ~/Documents/my-rill &amp;&amp; claude -p --output-format stream-json --permission-mode auto "/sync" &amp;&amp; claude -p --output-format stream-json --permission-mode auto "/distill" &amp;&amp; git add -A &amp;&amp; git commit -m "sync: $(date +%Y-%m-%d) morning" &amp;&amp; git push</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>55</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/rill-morning-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/rill-morning-sync.err</string>
</dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.rillmd.morning-sync.plist
```

Create equivalent `.plist` files for `morning-reports` (08:00, runs `/morning`) and `daily-newsletter` (17:00, runs `/newsletter`). Substitute the prompt string in the inner shell command.

**Pros.** Works without the desktop app. Survives reboots once loaded.
**Cons.** No GUI. Manual XML editing. Does not fire while the Mac is asleep.

### Option C: Linux cron / systemd timers

For headless servers or Linux desktops.

**cron example** (`crontab -e`):

```cron
55 7 * * * cd ~/my-rill && claude -p --output-format stream-json --permission-mode auto "/sync" && claude -p --output-format stream-json --permission-mode auto "/distill" && git add -A && git commit -m "sync: $(date +\%Y-\%m-\%d) morning" && git push
0  8 * * * cd ~/my-rill && claude -p --output-format stream-json --permission-mode auto "/morning" && git add -A && git commit -m "morning: $(date +\%Y-\%m-\%d)" && git push
0 17 * * * cd ~/my-rill && claude -p --output-format stream-json --permission-mode auto "/newsletter" && git add -A && git commit -m "newsletter: $(date +\%Y-\%m-\%d)" && git push
```

For systemd timers, see `man systemd.timer` — create a `.service` unit per job and a matching `.timer` unit with `OnCalendar=` for the schedule.

**Pros.** Ubiquitous. Well-documented.
**Cons.** No catch-up for missed runs. Shell quoting gets awkward inside `crontab`.

### Authentication

`claude -p` uses whatever authentication you have already configured with Claude Code — typically a Max Plan login. Rill does not recommend API keys for scheduled runs (see [ADR-068](../decisions/068-claude-code-integration-boundary.md)). If your scheduler runs under a different user than the one logged in to Claude Code, `claude -p` will fail to authenticate; run the scheduler under your normal user account.

### Permission Mode

The examples above use `--permission-mode auto`. In `auto` mode a classifier approves routine tool calls automatically and terminates the run when it encounters a risky action (writing outside the vault, unexpected network calls, etc.). For unattended scheduled runs this is the safe failure mode: there is no human to approve a prompt, so termination prevents a runaway job from causing sustained damage.

Other permission modes exist for specialized environments (see `claude --permission-mode --help`). For a typical personal machine, stay with `auto`.

### When to Skip Scheduling

If you run the morning routine yourself most days, you do not need any of this. The Daily Note's Notes section explicitly nudges you when the inbox has accumulated pending work, so a fully manual workflow is perfectly viable. Scheduling is an optimization, not a requirement.
