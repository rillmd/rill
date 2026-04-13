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

If `.claude/rules/personal-language.md` does not exist, create it now and save the detected language. This is the only place the preference is stored — do not write to any global file outside the vault.

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

#### 0-3: Vault & Prior State Check

```bash
# Check vault marker
ls .rill/ 2>/dev/null && echo "vault_ok" || echo "vault_missing"

# Check for existing journal entries
ls inbox/journal/*.md 2>/dev/null | head -1

# Check for existing me.md
ls knowledge/me.md 2>/dev/null
```

Interpret results:
- **`vault_missing`**: Warn the user that `rill init` hasn't been run. Guide them to run it before proceeding. Do not continue.
- **journal entries exist AND `--refresh` not set**: Skip Phase 2 (journal creation). Note this for Phase 1 greeting.
- **`knowledge/me.md` exists**: Skip the name question in Phase 1.

---

### Phase 1: Introduction

Greet the user warmly in `DETECTED_LANG`. Keep it brief — 3-4 sentences max.

If this is a fresh vault (no prior journals):
> Introduce Rill as a thinking tool, mention the session takes ~5 minutes, and say you'll help them capture their first thought.

If prior journals exist (returning user or `--refresh`):
> Acknowledge they've already started, skip the "first time" framing, and offer a quick overview.

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

(Skip this phase if journal entries already exist and `--refresh` is not set.)

Ask the user what's on their mind right now. Use conversational language. Examples (adapt to `DETECTED_LANG`):

> "Rill starts with your thoughts. What's on your mind right now? It can be anything — a task you've been putting off, something you're curious about, or just how you're feeling today."

After the user responds, run:
```bash
rill log "{user's text verbatim}"
```

Show the output path to confirm capture, then say something brief like:
> "That's your first Rill entry. Every thought you capture here becomes material Claude can work with."

---

### Phase 3: Core Concepts

Explain `/focus` and `/distill` concisely in `DETECTED_LANG`. Use a two-item list. Aim for 2-3 sentences per item — no more.

Template (adapt wording to language and tone):

> **`/focus`** — for thinking through something. Type `/focus your topic` when you want to go deep. I'll gather context and help you think it through.
>
> **`/distill`** — for making sense of everything. After you've accumulated some journals and notes, type `/distill`. I'll extract insights and connect the dots automatically.
>
> You don't need to organize anything. Just keep capturing.

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

> Rill has a `/newsletter` skill that generates a daily research briefing tailored to your interests.
>
> It pulls from what you've been capturing — journals, meetings, and notes — and adds relevant news and insights from outside.
>
> Once you've built up a few more entries, just type `/newsletter`. The more you capture, the more personalized it gets.

After answering, add:
> "You can always come back here with questions like that."

**If the user asks a different question instead:** Answer it genuinely. The newsletter prompt is a suggestion, not a script. After answering, say: "You can always ask me things like that — that's what I'm here for."

**If the user says "no questions" or skips:** That's fine. Say: "No problem — keep it in mind. Anytime you want to explore what Rill can do, just ask."

---

### Phase 5: Morning Reminder

Transition into the closing. In `DETECTED_LANG`:

> "You're all set. You have your first entry, and Rill can start working for you."
>
> "Tomorrow morning, try `/morning` — it'll give you a briefing based on what you've captured and help you plan your day."
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
4. Use the `schedule` skill or CronCreate to schedule `/morning` for that time with the cron expression.
5. Confirm to the user:

   > "Done — I'll run `/morning` for you at {time} tomorrow. If anything comes up before then, you know where to find me. See you then. ✦"

**If no:**

> "No problem. When you're ready, just type `/morning` anytime. You can always come back here with questions too. See you around. ✦"

---

## Edge Cases

| Situation | Handling |
|---|---|
| vault marker missing | Warn before Phase 1. Guide to run `rill init` |
| User has prior journal entries | Skip Phase 2. Acknowledge in Phase 1 greeting |
| User says "nothing on my mind" in Phase 2 | Ask: "What did you do today?" or "What are you working on this week?" |
| Language not detected (empty $LANG) | Default to English |
| personal-language.md already exists | Skip creation. Respect existing setting |
| knowledge/me.md already exists | Skip name question. Use existing name in greeting if readable |
| Time parsing fails in Phase 5 | Ask: "Could you give me a time like '7am' or '8:30'?" |
| `rill log` fails | Read the error. If vault not initialized, guide to `rill init`. Otherwise show the error and offer to retry |

---

## Rules

- Conduct **all conversation** in `DETECTED_LANG` — detected in Phase 0 before the first message
- The journal entry in Phase 2 is mandatory (unless prior entries exist)
- Phase 4 is mandatory — the user must experience asking at least once
- "Ask Claude anytime" must appear in both Phase 4 and Phase 5 closing
- Total session time should stay under 8 minutes — if any phase runs long, trim explanations
- Never explain more than 2 features in Phase 3 (/focus + /distill only)
- Use `CronCreate` (via the `schedule` skill) only after explicit user confirmation
- Always end with a warm closing in `DETECTED_LANG`
- When writing `knowledge/me.md`, always get the timestamp from `date` — never hardcode it
