---
gui:
  label: "/onboarding"
  hint: "First-time setup and tutorial"
  arg: none
  order: 1
  mode: live
---

# /onboarding — First-Time Setup & Tutorial

Guides a new user through their first Rill experience. Interactive session (~5-8 minutes).

Completion conditions:
1. First journal entry created
2. /focus and /distill understood
3. "Ask Claude" experienced firsthand
4. /morning reminder set (optional)
5. Rill app offered (macOS, if not already installed)

## Arguments

$ARGUMENTS — one of the following:
- Omitted → Full onboarding
- `--refresh` → Skip Phase 0 checks and Phase 2 (journal), give overview + Q&A for returning users

## Procedure

### Phase 0: State Check & Language Detection

**Run these checks silently before saying anything to the user:**

#### 0-1: Language Detection

Detect the user's preferred language using the following priority order:

**Priority 1 — Vault-level setting:**
Check if `.claude/rules/personal-language.md` exists:
- If yes → Read it, extract the language → set as `DETECTED_LANG` → skip to 0-3

**Priority 2 — System locale:**
```bash
echo $LANG
```
Map the result to a language:
- `ja_*` → Japanese
- `zh_CN*` or `zh_Hans*` → Simplified Chinese
- `zh_TW*` or `zh_Hant*` → Traditional Chinese
- `ko_*` → Korean
- `fr_*` → French
- `de_*` → German
- `es_*` → Spanish
- `pt_*` → Portuguese
- `it_*` → Italian
- Anything else or empty → English

Set the result as `DETECTED_LANG`.

**From this point on, conduct ALL conversation in `DETECTED_LANG`.** The only exceptions are: code blocks, slash commands (e.g., `/distill`), and technical terms (e.g., Markdown, frontmatter) — keep those in English.

#### 0-2: Create personal-language.md

**Do not ask the user whether to create this file. Create it automatically.** This is an internal system file — the user neither authored it nor needs to approve it. A confirmation prompt here is the single biggest reported source of first-run confusion; one confirmation means onboarding has failed before it started.

If `.claude/rules/personal-language.md` already exists, skip this step.

Otherwise, create it now. This is the only place the preference is stored — do not write to any global file outside the vault.

```bash
mkdir -p .claude/rules
```

Write `.claude/rules/personal-language.md` in `DETECTED_LANG`. Generate the content yourself in the appropriate language. Examples:

**Japanese:**
```
# Language Preference

- 本文: 日本語ベース
- 技術用語: 英語のまま（Markdown, API, frontmatter 等）
- ファイル名・ディレクトリ名: 英語 kebab-case
- frontmatter のキー: 英語
- コミットメッセージ: 英語
```

**English (and fallback):**
```
# Language Preference

- Body text: English
- Technical terms: English as-is (Markdown, API, frontmatter, etc.)
- File/directory names: English kebab-case
- Frontmatter keys: English
- Commit messages: English
```

For other languages: generate equivalent content in that language. The body text line must name the language in its own native script. Technical terms that must stay English (Markdown, API, frontmatter, kebab-case) remain as English literals even within non-English lines.

**Notify, do not confirm.** The outcome is surfaced as the *first sentence* of the Phase 1 greeting — one line in `DETECTED_LANG` acknowledging which language will be used going forward. Never as a standalone question, yes/no prompt, or step-by-step file-creation walkthrough.

#### 0-3: Vault & Prior State Check

```bash
# Check vault marker
ls .rill/ 2>/dev/null && echo "vault_ok" || echo "vault_missing"

# Check for existing me.md
ls knowledge/me.md 2>/dev/null

# Check for Rill app (used in Phase 6)
ls /Applications/Rill.app ~/Applications/Rill.app 2>/dev/null | head -1

# Check platform (Phase 6 is macOS-only)
uname
```

Interpret results:
- **`vault_missing`**: Warn the user that `rill init` hasn't been run. Guide them to run it before proceeding. Do not continue.
- **`--refresh` set**: Skip Phase 2 (journal creation). Default mode always runs Phase 2 — writing one's own journal is the core onboarding experience, and file presence (sample preload or earlier captures) is not a signal that the user has onboarded.
- **`knowledge/me.md` exists**: Skip the name question in Phase 1.
- **Rill.app found OR not macOS**: Skip Phase 6.
- **Rill.app not found AND macOS**: Run Phase 6 after Phase 5.

---

### Phase 1: Introduction

Greet the user warmly in `DETECTED_LANG`. Keep the tone conversational — this is "hello," not a setup wizard.

**Opening sentence (always first):** Open the greeting with one short sentence — in `DETECTED_LANG` — telling the user which language you'll use from here on (e.g., 日本語の場合「ここからは日本語で進めます。」/ English の場合 "I'll continue in English from here."). Keep it to a single sentence; do not justify the choice or show any file path or reference `personal-language.md`. Then proceed to the framing below.

If `--refresh` is set (returning user):
> Acknowledge they've already onboarded, skip the "first time" framing, and offer a quick overview.

Otherwise (default mode):
> Open with a 3-part framing (aim for ~30 seconds spoken, ~3 short paragraphs). Run this even if sample or earlier journal entries already exist in the vault — file presence is not a signal that the user has been through onboarding.
>
> 1. **What Rill is.** A *thinking partner* — not a notes app, and not a knowledge base. Position it against the user's likely prior (memory / second-brain apps) and redirect: Rill exists to *dig into* what they're thinking with them, not just store it.
> 2. **What they'll have by the end.** Their thoughts start feeding back into their morning briefing and a personalized news stream. The feeling to aim for: "if I get stuck, I just ask Claude."
> 3. **What the next 5–8 minutes look like.** A small intro question, capturing their first entry together, and a quick setup for tomorrow morning.
>
> Do **not** use the words `distill`, `workspace`, `session`, or `vault` in this framing. Land on everyday language. After the framing, hand off to the next step (name question below).

If `knowledge/me.md` does not exist, ask for the user's name at the end of the greeting. After they respond:
1. Get the current timestamp:
   ```bash
   date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
   ```
2. Create `knowledge/me.md` with that timestamp and the user's name. Use the Write tool with this structure:
   ```markdown
   ---
   created: {timestamp from date command}
   type: interest-profile
   ---

   # {name}

   ## Deep Interests
   (to be filled by /distill)

   ## Curiosity
   (to be filled by /distill)

   ## Obligations
   (to be filled by /distill)

   ## Career
   (to be filled by /distill)

   ## Active Projects
   (to be filled by /distill)
   ```

---

### Phase 2: First Journal Entry

(Skip this phase only if `--refresh` is set. Default mode always runs Phase 2, even if sample or earlier journal entries are already present — writing one's own journal is the core onboarding experience.)

Ask the user what's on their mind right now. Use conversational language. Examples (adapt to `DETECTED_LANG`):

> "Rill starts with one of your thoughts. Whatever you drop in here becomes the seed Claude works with — it'll show up in tomorrow's briefing and shape the news it pulls for you."
>
> "So: what's on your mind right now? Anything works — a task you've been putting off, something you're curious about, or just how today's going."
>
> "If it helps, it can be as casual as: *'I've been stuck on the pricing deck all week and I can feel it bleeding into the weekend.'* One line like that is enough."

After the user responds, capture it using the Write tool (do **not** use `rill log` — it would expose the CLI to the user):

1. Get the filename timestamp:
   ```bash
   date +%Y-%m-%d-%H%M%S
   ```
2. Get the ISO timestamp for frontmatter:
   ```bash
   date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
   ```
3. Write the journal file using the Write tool:
   - Path: `inbox/journal/{TIMESTAMP_FROM_STEP_1}.md`
   - Content:
     ```
     ---
     created: {ISO_TIMESTAMP_FROM_STEP_2}
     ---

     {user's text verbatim}
     ```

Show the output path to confirm capture, then say something brief like (in `DETECTED_LANG`):
> "That's your first Rill entry. Every thought you capture here becomes material Claude can work with."

Then add:
> "For future entries: click 'New Entry' in the Rill app, or just tell me what's on your mind here — I'll capture it for you."

---

### Phase 3: Core Concepts

Explain the two core moves in `DETECTED_LANG`: **thinking through something with Claude** and **letting Claude make sense of what you've captured**. Use a two-item list. Aim for 2-3 sentences per item — no more. Do **not** present bare slash commands as the call-to-action — frame both moves as things the user asks Claude to do.

Template (adapt wording to language and tone):

> **Think something through** — when you want to go deep on a topic, just tell me. Something like *"help me think through whether I should refactor this module"* is enough. I'll gather the relevant context from your vault and work through it with you (internally this runs `/focus`).
>
> **Make sense of what you've captured** — once you have a handful of journals and notes, ask me to *"go through my inbox and pull out the useful bits"*. I'll extract insights, connect the dots, and draft any tasks that come up (internally this runs `/distill`).
>
> You don't need to organize anything or remember command names. Just keep capturing, and ask me when you want to do something with it.

---

### Phase 4: "Ask Claude" Experience

This phase establishes the habit of asking Claude when stuck. **Do not skip it.**

Transition from Phase 3 naturally. In `DETECTED_LANG`:

> "One more thing before we wrap up. Rill doesn't have a support page or FAQ — because you don't need one. Whenever you're curious or stuck, just open Claude Code in your vault and ask me."

Then invite a specific question to make it concrete. Suggest this example (adapt phrasing to `DETECTED_LANG`):

> "For example, try asking: 'How do I get a personalized newsletter?'"

**Expected exchange:**

User asks (verbatim or paraphrased): "How do I get a personalized newsletter?"

Respond with something like (in `DETECTED_LANG`):

> Rill can generate a daily research briefing tailored to your interests.
>
> It pulls from what you've been capturing — journals, meetings, and notes — and adds relevant news and insights from outside.
>
> Once you've built up a few more entries, just ask me *"give me today's newsletter"* or *"what's worth reading today based on my interests?"*. The more you capture, the more personalized it gets. (Internally this runs `/newsletter`.)

After answering, add:
> "You can always come back here with questions like that — you don't need to remember command names."

**If the user asks a different question instead:** Answer it genuinely. The newsletter prompt is a suggestion, not a script. After answering, say: "You can always ask me things like that — that's what I'm here for."

**If the user says "no questions" or skips:** That's fine. Say: "No problem — keep it in mind. Anytime you want to explore what Rill can do, just ask."

---

### Phase 5: Morning Reminder

Transition into the closing. In `DETECTED_LANG`:

> "You're all set. You have your first entry, and Rill can start working for you."
>
> "Tomorrow morning, ask me for *'today's briefing'* — I'll look at what you've captured and help you plan your day (internally this runs `/morning`, but you don't need to remember that)."
>
> "And remember: if you ever get stuck or want to try something new, just open Claude Code here and ask."
>
> "Want me to set a reminder for tomorrow morning?"

**If yes:**

Ask for their preferred time:
> "What time do you usually start your day? (e.g., '7am', '8:30')"

After receiving the time:
1. Get tomorrow's date and calculate the cron expression:
   ```bash
   # Get tomorrow's date components
   TOMORROW=$(date -v+1d +"%d %m" 2>/dev/null || date -d "tomorrow" +"%d %m")
   # TOMORROW format: "DD MM" (e.g., "14 04")
   ```
2. Parse the user's time into hour/minute (e.g., "7am" → hour=7, min=0; "8:30" → hour=8, min=30).
3. Build cron expression: `{min} {hour} {DD} {MM} *`
4. Use the `schedule` skill or CronCreate to schedule `/morning` for that time with the cron expression. **This is an internal tool call — do not surface the skill name to the user.**
5. Confirm to the user:

   > "Done — you'll get your briefing at {time} tomorrow morning."

**If no:**

> "No problem. Whenever you want a briefing, just ask me for it."

Then proceed to Phase 6.

---

### Phase 6: Rill App (conditional)

**Skip this phase entirely if the Rill app is already installed.**

Check at the start of this phase:
```bash
ls /Applications/Rill.app ~/Applications/Rill.app 2>/dev/null | head -1
```

**If already installed:** Skip Phase 6. Go directly to the closing message.

**If not installed**, offer in `DETECTED_LANG`:

> "There's also a Rill app — a visual timeline for browsing your journals and knowledge. Want me to install it?"

**If yes:**

Run the following commands:
```bash
curl -fsSL https://github.com/rillmd/rill/releases/latest/download/Rill.dmg -o ~/Downloads/Rill.dmg
hdiutil attach -nobrowse ~/Downloads/Rill.dmg -mountpoint /tmp/rill-dmg
cp -R /tmp/rill-dmg/Rill.app ~/Applications/
hdiutil detach /tmp/rill-dmg
open ~/Applications/Rill.app
```

After successful install:
> "Done — Rill is running. You'll see your entries building up there over time."

If the download or install fails, don't block — just provide the fallback:
> "The install didn't work automatically. You can download it manually from https://github.com/rillmd/rill/releases"

**If no:**

> "No problem. You can download it anytime from https://github.com/rillmd/rill/releases"

---

### Step: Hand off to the GUI (conditional)

Before the closing, hand the session off to the Rill app visually. **Skip this step entirely on Linux or if the Rill app is not installed.**

Check for the app:
```bash
ls /Applications/Rill.app ~/Applications/Rill.app 2>/dev/null | head -1
```

If no app is found, skip to Closing.

If the app is present:

1. Determine a repo-relative path to name for the user, in priority order. Use the first that exists; if none do, skip to Closing.
   - `reports/daily/{today}.md` — today's briefing, if it exists
   - Most recent `inbox/journal/*.md` — typically the entry the user just wrote in Phase 2
   - `knowledge/me.md` — fallback

2. Bring the app to the foreground. **Do not** run `rill open` — this would force-navigate the GUI, which is prohibited for skills (see `.claude/rules/rill-claude-code-integration.md`). Use the plain shell `open` command to launch / front the app only:
   ```bash
   open -a Rill 2>/dev/null || open ~/Applications/Rill.app 2>/dev/null || open /Applications/Rill.app
   ```

3. Tell the user in `DETECTED_LANG`. Name the file in prose (backticks or Markdown link) and point them at `Cmd+P`:

   > "Your latest entry is saved at `{repo-relative path}`. The app is now open — you can find it in the timeline, or hit `Cmd+P` (the header search box) and start typing the filename to jump straight to it. Any file in your vault opens the same way."

---

### Closing

End with a warm closing in `DETECTED_LANG`. Wording depends on whether the GUI hand-off step ran:

**If the app was handed off to:**

> "The app is your visual home — come back here whenever you want to browse what you've been capturing. And if you ever get stuck or want to explore something new, just open Claude Code in your vault and ask."
>
> "See you around. ✦"

**Fallback (no app / Linux / declined install):**

> "And remember: if you ever get stuck or want to explore something new, just open Claude Code in your vault and ask."
>
> "See you around. ✦"

---

## Edge Cases

| Situation | Handling |
|---|---|
| vault marker missing | Warn before Phase 1. Tell the user the vault hasn't been initialized yet — they can either ask Claude to *"initialize the vault here"* (Claude will run `rill init`) or run `rill init` themselves from the terminal. Do not lead with the CLI command |
| User runs `/onboarding --refresh` | Skip Phase 2 regardless of journal count. Use the returning-user greeting in Phase 1 |
| Sample or earlier journal entries already exist in default mode | Do NOT skip Phase 2. File presence is not a signal the user has onboarded |
| User says "nothing on my mind" in Phase 2 | Offer a more concrete prompt: *"What took up most of your attention today? Even something like 'spent 2 hours debugging a flaky test' works — it'll still give Claude something to respond to tomorrow."* Accept any one-line answer |
| Language not detected (empty $LANG) | Default to English |
| personal-language.md already exists | Skip creation. Respect existing setting. Still open the greeting with the language-continuation line, reading the language from the existing file |
| personal-language.md newly created | Create silently without asking. Notify via the Phase 1 opener only — never as a yes/no prompt |
| User explicitly requests a different language mid-onboarding | Rewrite `.claude/rules/personal-language.md` to the requested language inline and continue in the new language. No yes/no prompt |
| knowledge/me.md already exists | Skip name question. Use existing name in greeting if readable |
| Time parsing fails in Phase 5 | Ask: "Could you give me a time like '7am' or '8:30'?" |
| `rill log` fails | Read the error. If vault not initialized, apply the vault-marker-missing guidance above. Otherwise show the error and offer to retry |
| Rill app already installed | Skip Phase 6 entirely. Still run the GUI hand-off step before Closing |
| DMG download fails (offline, 404) | Show fallback URL, don't block onboarding |
| Linux user (no .app support) | Skip Phase 6 entirely (detect with `uname`). Also skip the GUI hand-off step; use the fallback closing |
| GUI hand-off: `.app` not present (Linux, declined install) | Skip the hand-off step. Use the fallback closing |
| GUI hand-off: no briefing / journal / me.md exists | Skip the hand-off step. Use the fallback closing |

---

## Rules

- Conduct **all conversation** in `DETECTED_LANG` — detected in Phase 0 before the first message
- Never ask the user whether to create `.claude/rules/personal-language.md`. It is a system-managed file — create it automatically in Phase 0-2 and notify via the Phase 1 opener only
- The journal entry in Phase 2 is mandatory in default mode — it runs even when sample or earlier journal entries already exist. Skip only when `--refresh` is set
- Phase 4 is mandatory — the user must experience asking at least once
- "Ask Claude anytime" must appear in both Phase 4 and Phase 5 closing
- Total session time should stay under 8 minutes — if any phase runs long, trim explanations
- Never explain more than 2 features in Phase 3 (/focus + /distill only)
- Use `CronCreate` (via the `schedule` skill) only after explicit user confirmation
- Always end with a warm closing in `DETECTED_LANG`
- When writing `knowledge/me.md`, always get the timestamp from `date` — never hardcode it
- In the GUI hand-off step, bring the app forward with the shell `open` command only. **Do not** run `rill open` — skills and assistant turns must not force-navigate the GUI (see `rill-claude-code-integration.md`). Display the target path in prose and let the user open it themselves via the `Cmd+P` palette
