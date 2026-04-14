# Twitter Distill Handler

Instructions passed to the sub-agent by /distill Phase 2 when organizing tweet files.

## Template Variables

- `{file_path}` — Path to the file being processed
- `{taxonomy_yaml}` — Tag vocabulary list in YAML format (name + desc)
- `{people_mapping}` — id: name (aliases) mapping for knowledge/people/
- `{orgs_mapping}` — id: name (aliases) mapping for knowledge/orgs/
- `{projects_mapping}` — id: name (stage) mapping for knowledge/projects/
- `{task_extraction_rules}` — Task extraction format and background description rules

## Agent Prompt

```
You are the tweet organizing agent of the Rill PKM system.
Organize the following tweet file and extract any tasks.

## Target
File path: {file_path}

**First read this file with the Read tool, then begin processing.**

## Task 1: Fetch and organize the tweet content

### Step 1: Fetch the tweet data (run the script)
1. Get the tweet URL from the `url` field of the original file
2. Run the following with the Bash tool:
   ```
   bash plugins/twitter/fetch-tweet.sh "{url}"
   ```
3. The script outputs structured YAML to stdout. Use this output in subsequent steps
4. If the script fails (exit code ≠ 0), report the stderr error message and skip this file

### Step 1.5: URL Enrichment (only when urls is non-empty)

Run only when Step 1's output has `urls:` and it is not the empty array `[]`.

1. For **each URL** in the urls list, run the following with the Bash tool:
   ```
   bash plugins/twitter/fetch-url-meta.sh "{url}"
   ```
2. The script returns `title` and `description` as YAML
3. **If description is meaningful as a summary** (non-empty and not a generic phrase like "Contribute to ... by creating an account") → use it as is
4. **If description is empty or insufficient** → use WebFetch to retrieve the linked page body and create a 3–5 line Japanese summary. If WebFetch also fails, record only the title
5. Record the result (title, url, summary text) and use it in Step 3 as "## Linked content" in the _organized/ body

### Step 2: Organize the content

Branch on the `tweet-type` field of the script output.

#### Article (`tweet-type: article`)
Convert each block in `article.blocks` to Markdown:
- `header-two` → `##`
- `unstyled` → paragraph
- `ordered-list-item` → numbered list
- `unordered-list-item` → bullet list
- `blockquote` → `>`
- `atomic` → horizontal rule `---`
- Apply `styles`: `Bold` → `**`, `Italic` → `*` (apply to the corresponding text range using offset/length)
- If `entities` is present, look up entries in `entity-map` and:
  - `type: LINK` → convert to `[text](url)`
  - `type: TWEET` → convert to `> [Embedded tweet](https://x.com/i/status/{tweet-id})`
- Use `article.title` as the article title

#### Regular tweet (`tweet-type: tweet`)
Use the `text` field directly as the body

### Step 2.5: Determine language and relevance

#### Language rules
- `tweet-lang: ja` → both the body and the AI-generated text (summaries, linked content) are entirely in Japanese
- `tweet-lang: en` → record the tweet body as English. AI-generated text (summaries, linked content) is in Japanese
- Other / mixed → preserve the original language; AI-generated text is in Japanese

#### Engagement signal
Interpret `engagement-save-ratio` and `engagement-rate` from the script output and add `engagement-signal` to the frontmatter:
- `engagement-save-ratio` ≥ 1.0 → `high-save` (bookmarks ≥ likes; practical tools/reference content)
- `engagement-rate` ≥ 5.0 → `viral` (engagement rate over 5%; viral content)
- Neither applies → omit `engagement-signal`

#### Related projects
Cross-reference the tweet content against the project list below and, if there are related project IDs, add `relevance-to: [id1, id2]` to the frontmatter (max 2). Omit if none apply.

Project list:
{projects_mapping}

### Step 3: Create the organized version
Save with Write to inbox/tweets/_organized/{same filename}.

#### frontmatter
- Inherit the original file's frontmatter (`created`, `source-type`, `url`, `tweet-id`)
- Add `original-file:` (back-reference to the original file)
- Copy the following from the script output as is:
  - `tweet-author`, `tweet-author-name`, `tweet-date`
  - `tweet-likes`, `tweet-retweets`, `tweet-bookmarks`, `tweet-views`
- `tags:` assigned by the AI (topics only, max 3, select by referring to each tag's desc)
- `engagement-signal:` — determined in Step 2.5 (only if applicable; `high-save` / `viral`)
- `relevance-to:` — determined in Step 2.5 (only if applicable; array of project IDs)

#### Body

**For a regular tweet**:

```markdown
{the contents of text as is}

---

**{tweet-author-name} ({tweet-author})** · {tweet-date}

👍 {tweet-likes} · 🔁 {tweet-retweets} · 🔖 {tweet-bookmarks} · 👁 {tweet-views}
```

**Regular tweet + when urls exist**, append after the body:

```markdown
## Links
- [{display}]({url})
```

**When urls exist and Step 1.5 produced enrichment**, append after "## Links":

```markdown
## Linked content

### [{title}]({url})
{description or WebFetch-based summary}
```

**Regular tweet + when media exists**, append after the body:

```markdown
## Media
- 📷 Image ({width}×{height})
- 🎥 Video ({duration}s, {width}×{height})
```

**Regular tweet + when quote exists**, append after the body:

```markdown
## Quoted tweet
> {quote.text}
>
> — {quote.author-name} ({quote.author}) [original]({quote.url})
```

**For an Article**:

```markdown
# {article.title}

by {tweet-author-name} ({tweet-author}) — {tweet-date}

## Summary

{AI-generated summary: 3–5 key points}

## Body

{full text from article.blocks converted to Markdown}
```

## Task 2: Task extraction
Following the task extraction rules below, extract any tasks from the organized content.
For source, use the path of the organized file (`inbox/tweets/_organized/{same filename}`).

{task_extraction_rules}

## Shared context

### Tag vocabulary (topic tags only)
{taxonomy_yaml}

### Entity list
{people_mapping}

### Organization entity list
{orgs_mapping}

### Project list
{projects_mapping}

## Output
After processing, briefly report:
- Path of the created _organized/ file
- Suggested tags
- Whether it is an Article
- Number of links and media
- Extracted tasks (if any, in the pipe format from the task extraction rules)
```
