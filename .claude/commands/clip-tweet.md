# /clip-tweet — Tweet Ingestion

Ingests a Twitter/X tweet URL into `inbox/tweets/`, fetches the content via `fetch-tweet.sh`, and generates an organized version in `_organized/`. A skill that runs `rill clip` + `/distill` Phase 2 (tweet) in one shot.

## Arguments

$ARGUMENTS — Tweet URL (e.g. `https://x.com/user/status/12345`)

## Steps

### Step 1: URL Validation and Normalization

1. If the argument is empty, display "Please specify a tweet URL" and exit
2. Confirm the URL matches the pattern `https://(x.com|twitter.com)/*/status/*`
3. Strip tracking parameters (`?s=`, `&t=`, `&ref_src=`, etc.)
4. Extract `screen_name` and `tweet_id` from the URL

### Step 2: Create File in inbox/tweets/

1. If a file with the same `tweet-id` already exists in `inbox/tweets/`, report the duplicate and skip
2. Create the file with `rill mkfile` (to guarantee timestamp accuracy):

```bash
rill mkfile inbox/tweets --slug {screen_name} --field "source-type=tweet" --field 'url="{normalized URL}"' --field 'tweet-id="{tweet_id}"'
```

3. Use the output path in subsequent steps

### Step 3: Fetch Tweet Data (Script Execution)

Run the following with the Bash tool:

```
bash plugins/twitter/fetch-tweet.sh "{normalized URL}"
```

The script outputs structured YAML to stdout. Use this output in subsequent steps.

If the script fails (exit code ≠ 0), report the error message from stderr and leave the file created in Step 2 (it can be reprocessed by /distill).

### Step 3.5: URL Enrichment (only if urls is non-empty)

Only run this if the Step 3 output has `urls:` and it is not an empty array `[]`.

1. For each URL in the urls list, run the following with the Bash tool:
   ```
   bash plugins/twitter/fetch-url-meta.sh "{url}"
   ```
2. The script returns `title` and `description` as YAML
3. If the description makes sense as a summary (non-empty, not generic) → use it as-is
4. If the description is empty or insufficient → use WebFetch to retrieve the linked page body and create a 3-5 line summary. If WebFetch also fails, record only the title
5. Save the result and use it in Step 4 under "## Linked Content"

### Step 3.7: Language and Relevance Detection

#### Language Rules
- `tweet-lang: ja` → Both the body and AI-generated text (summary, linked content) are in Japanese
- `tweet-lang: en` → Record the tweet body in English. AI-generated text (summary, linked content) follows the system output language
- Other / mixed → Preserve the original language; AI-generated text follows the system output language

#### Engagement Signal
Interpret `engagement-save-ratio` and `engagement-rate` from the script output and add `engagement-signal` to the frontmatter:
- `engagement-save-ratio` ≥ 1.0 → `high-save` (bookmarks ≥ likes; practical tools / reference content)
- `engagement-rate` ≥ 5.0 → `viral` (engagement rate over 5%; viral content)
- Neither applies → omit `engagement-signal`

#### Related Projects
Match the tweet content against projects in `knowledge/projects/`, and if related project IDs exist, add `relevance-to: [id1, id2]` to the frontmatter (max 2). Use the file names (= IDs) in knowledge/projects/ and the name in _workspace.md as references. Omit if none apply.

### Step 4: Generate Organized Version in _organized/

1. Read `taxonomy.md` to check existing tags
2. Write to `inbox/tweets/_organized/{same filename}`

#### frontmatter

```yaml
---
created: {same as Step 2}
source-type: tweet
original-file: inbox/tweets/{filename}
url: "{normalized URL}"
tweet-id: "{tweet_id}"
tweet-author: {tweet-author from script output}
tweet-author-name: {tweet-author-name from script output}
tweet-date: {tweet-date from script output}
tweet-likes: {number}
tweet-retweets: {number}
tweet-bookmarks: {number}
tweet-views: {number}
tweet-type: {article | tweet}
tags: [{up to 3, selected from taxonomy.md}]
engagement-signal: {high-save | viral — only if applicable}
relevance-to: [{project ID — only if applicable}]
---
```

#### Body (for normal tweets)

```markdown
{the text content as-is}

---

**{tweet-author-name} ({tweet-author})** · {tweet-date}

👍 {tweet-likes} · 🔁 {tweet-retweets} · 🔖 {tweet-bookmarks} · 👁 {tweet-views}
```

If urls exist, append:

```markdown
## Links
- [{display}]({url})
```

If urls exist and Step 3.5 enrichment was retrieved, append after "## Links":

```markdown
## Linked Content

### [{title}]({url})
{description or WebFetch-based summary}
```

If media exist, append:

```markdown
## Media
- 📷 Image ({width}×{height})
- 🎥 Video ({duration}s, {width}×{height})
```

If a quote exists, append:

```markdown
## Quoted Tweet
> {quote.text}
>
> — {quote.author-name} ({quote.author}) [original]({quote.url})
```

#### Body (for Articles)

```markdown
# {article.title}

by {tweet-author-name} ({tweet-author}) — {tweet-date}

## Summary

{AI-generated summary: 3-5 key points}

## Body

{full text converted from article.blocks to Markdown}
```

**Article block conversion rules**:
- `type: "header-two"` → `## {text}`
- `type: "unstyled"` → paragraph (separated by blank lines)
- `type: "ordered-list-item"` → `1. {text}`
- `type: "unordered-list-item"` → `- {text}`
- `type: "blockquote"` → `> {text}`
- `type: "atomic"` → `---` (horizontal rule)
- `styles` `Bold` → `**{text}**`, `Italic` → `*{text}*` (applied to the range specified by offset/length)
- `entity-map` `LINK` type → convert to `[text](url)`
- `entity-map` `TWEET` type → record as `> [Embedded tweet](https://x.com/i/status/{tweet-id})`

### Step 5: Update .processed

1. Append `{filename}:organized` to `inbox/tweets/.processed`
2. Report the result:
   - Path of the created file
   - Tweet type (normal / Article)
   - Number of links and media
   - Body summary (first 1-2 sentences)

## Rules

- **Do not modify the original file in inbox/tweets/** (create a thin file with frontmatter only, and expand the full text in _organized/)
- Reference `taxonomy.md` when assigning tags
- Division of responsibility with `/distill`: `/distill` batch-processes unprocessed files; `/clip-tweet` immediately processes a single tweet
