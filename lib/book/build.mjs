#!/usr/bin/env node
// lib/book/build.mjs — Rill standard book style builder.
//
// Renders a book directory (pages/{id}/ with a _book.md spine and NN-*.md
// chapters) into a fixed-style, self-contained HTML reading view under
// .view/ (a derived, non-committed sidecar — Markdown stays the source of
// truth; the AI never reads the generated HTML).
//
// Frame (identical for every book):
//   - single left sidebar: chapter list (parts supported, per-chapter
//     pending-proposal badges) with the current chapter's sections expanded
//     and a deterministic scroll-position highlight
//   - unified 720px content column (wide tables scroll inside their box)
//   - chapter pages get prev/next navigation and a status/reviewed header
//   - receptacle projection: proposals targeting an existing section are
//     rendered as cards in the right margin, vertically aligned with their
//     target (section headings get a marker chip, cross-linked); proposals
//     for new sections are grouped at the end of the chapter. Below 1440px
//     and in print everything falls back to the end-of-chapter list.
//
// The chapter Markdown is never rewritten — the only transforms are
// container concerns (link depth, anchors, table wrappers, callout classes).
//
// Invoked by `rill book build <id>`; direct use:
//   node build.mjs --src <book-dir> [--out <dir>]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

// markdown-it is vendored (see vendor/LICENSE-markdown-it for provenance) so
// the builder has no dependency on any vault- or machine-specific node_modules.
const require = createRequire(import.meta.url);
const MarkdownIt = require('./vendor/markdown-it.min.js');

const argv = process.argv.slice(2);
function argOf(name, dflt) { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : dflt; }
const BOOK = argOf('--src', '');
if (!BOOK || !fs.existsSync(path.join(BOOK, '_book.md'))) {
  console.error('book build: --src must point to a book directory containing _book.md');
  process.exit(1);
}
const SRC = path.resolve(BOOK);
const VIEW = path.resolve(argOf('--out', path.join(SRC, '.view')));
const BOOK_ID = path.basename(SRC);
fs.mkdirSync(VIEW, { recursive: true });
const GENERATOR_META = '<meta name="generator" content="rill book build">';
// Relative-URL prefix from the output dir back to the book dir ('..' for the
// default .view/ sidecar; computed for custom --out locations).
const REL_URL = path.relative(VIEW, SRC).split(path.sep).join('/');
const REL_PREFIX = REL_URL ? REL_URL + '/' : '';

const md = new MarkdownIt({ html: true, linkify: false, typographer: false });
// Receptacle items are auto-appended by pipelines, so their inline rendering
// keeps raw HTML disabled — only the human-owned chapter/spine prose may
// carry raw HTML (e.g. ownership comments).
const mdInline = new MarkdownIt({ html: false, linkify: false, typographer: false });
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const plural = n => (n === 1 ? '' : 's');

// ---------- source reading ----------

function stripFrontmatter(src) {
  const m = src.match(/^---\n([\s\S]*?)\n---\n/);
  if (!m) return { meta: {}, body: src };
  const meta = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([a-z]+):\s*(.+)$/);
    if (kv) meta[kv[1]] = kv[2];
  }
  return { meta, body: src.slice(m[0].length) };
}

// Receptacle heading — the ja vault content convention (v1). The builder
// splits chapters on this heading and re-renders it; the literal must match
// what /close and the recipes write into chapter files.
const INBOX_HEAD = '## 新着の学び (未統合)';
const INBOX_ID = INBOX_HEAD.slice(3);

function splitInbox(body) {
  // Line-anchored and fence-aware: only a real heading line splits — not an
  // inline mention, and not a line quoted inside a fenced code block.
  let fence = null, headPos = -1, pos = 0;
  for (const line of body.split('\n')) {
    const f = line.match(/^\s*(`{3,}|~{3,})/);
    if (f) {
      if (!fence) fence = f[1];
      else if (f[1][0] === fence[0] && f[1].length >= fence.length) fence = null;
    } else if (!fence && line.trimEnd() === INBOX_HEAD) headPos = pos;
    pos += line.length + 1;
  }
  if (headPos < 0) return { bodyMd: body, inboxMd: '' };
  const eol = body.indexOf('\n', headPos);
  return { bodyMd: body.slice(0, headPos), inboxMd: eol < 0 ? '' : body.slice(eol) };
}

// Receptacle item microformat (pull-request shaped): date + source + status
// mark + target + kind + summary. Tokens are the ja vault convention (v1),
// specified in the book's _recipe.md.
function parseInboxItems(inboxMd) {
  const items = [];
  for (const line of inboxMd.split('\n')) {
    const m = line.match(/^- \*\*([\d/-]+)\*\* \[([^\]]+)\]\(([^)]+)\) 〔AI 起草・未統合〕 宛先: (.+?) \/ 形: (.+?) — (.+)$/);
    if (m) items.push({ date: m[1], srcText: m[2], srcHref: m[3], dest: m[4], kind: m[5], summary: m[6] });
    else if (/^- /.test(line)) items.push({ raw: line.slice(2) });
  }
  return items;
}

// Spine: chapter order and part labels come from the first table in _book.md
// whose first column links to local .md chapter files (language-neutral —
// no heading text is assumed). A bold non-link first cell is a part label.
function parseSpine(bookBody) {
  // Group contiguous table rows into blocks; the first block whose first
  // column links to chapter files is the spine (rows of other tables never
  // bleed in).
  const blocks = [];
  let block = [];
  for (const line of bookBody.split('\n')) {
    if (/^\|/.test(line)) block.push(line);
    else if (block.length) { blocks.push(block); block = []; }
  }
  if (block.length) blocks.push(block);
  for (const tbl of blocks) {
    const items = [];
    for (const line of tbl) {
      if (/^\|[\s:-]*\|/.test(line)) continue;
      const cell = line.split('|')[1]?.trim() ?? '';
      const link = cell.match(/^\[([^\]]+)\]\(([^)]+\.md)\)/);
      if (link && !link[2].includes('/')) {
        const title = link[1];
        const file = link[2].replace(/\.md$/, '');
        const num = title.match(/^(\d+)\./)?.[1] ?? '';
        const short = title.replace(/^\d+\.\s*/, '').split(' — ')[0];
        items.push({ kind: 'chapter', title, file, num, short });
      } else {
        const part = cell.match(/^\*\*(.+)\*\*$/);
        if (part) items.push({ kind: 'part', label: part[1] });
      }
    }
    if (items.some(i => i.kind === 'chapter')) return items;
  }
  throw new Error('book build: no chapter table found in _book.md (a table whose first column links to chapter .md files)');
}

// ---------- HTML transforms (body content is preserved byte-for-byte;
// only container concerns are adjusted) ----------

// Rewrite links to sibling chapter files (as listed in the spine) to their
// generated .html counterparts (fragments preserved) — exact filenames,
// no naming pattern assumed.
function chapterLinks(html, spine) {
  for (const it of spine) {
    if (it.kind !== 'chapter') continue;
    html = html.replaceAll(`href="${it.file}.md"`, `href="${it.file}.html"`)
               .replaceAll(`href="${it.file}.md#`, `href="${it.file}.html#`);
  }
  return html;
}
// The view lives one directory deeper than the book Markdown, so every
// relative URL authored against the book dir gains one ../ — except links
// that stay inside .view (the generated chapter pages and index).
const hasScheme = (u) => /^[a-z][a-z0-9+.-]*:/i.test(u);
function relocateLinks(html, spine) {
  const inView = new Set(spine.filter(i => i.kind === 'chapter').map(i => `${i.file}.html`));
  inView.add('index.html');
  // Both quote styles are handled; protocol-relative (//host) and
  // root-relative (/path) URLs are left untouched.
  return html.replace(/(href|src)=("|')([^"'#]+)(#[^"']*)?\2/g, (whole, attr, q, url, frag) => {
    if (hasScheme(url) || url.startsWith('/')) return whole;
    if (attr === 'href' && inView.has(url)) return whole;
    return `${attr}=${q}${REL_PREFIX}${url}${frag || ''}${q}`;
  });
}
function addAnchors(html) {
  return html
    .replace(/<h3>(\d+)\.(\d+)/g, '<h3 id="s$1-$2">$1.$2')
    .replace(/<h2>(\d+)\./g, '<h2 id="ch$1">$1.');
}
// Private-application callout — the vault content convention for client-
// specific boxes that are dropped from any public export.
function markMti(html) {
  return html.replaceAll('<blockquote>\n<p><strong>【MTI 適用 — 非公開】</strong>',
    '<blockquote class="mti">\n<p><strong>【MTI 適用 — 非公開】</strong>');
}
function wrapTables(html) {
  return html.replaceAll('<table>', '<div class="table-wrap"><table>')
             .replaceAll('</table>', '</table></div>');
}
// Heading ids come from the decoded plain text (rendered inner HTML holds
// entities like &amp; — using it verbatim desyncs the DOM id from the
// sidebar's hash and breaks the jump + highlight).
function idOf(t) {
  return t.replace(/<[^>]+>/g, '')
          .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
          .replace(/&quot;/g, '').replace(/"/g, '');
}
function ensureH2Ids(html) {
  return html.replace(/<h2>(.+?)<\/h2>/g, (m, t) => `<h2 id="${idOf(t)}">${t}</h2>`);
}

// ---------- receptacle projection (data stays in the chapter Markdown;
// the view routes each proposal next to its target) ----------

function destAnchor(dest) {
  const m = dest.match(/^(\d+)\.(\d+)/);
  return m ? `s${m[1]}-${m[2]}` : null;
}

// Source links from auto-appended items: keep http(s)/mailto, neutralize any
// other scheme; relative paths are relocated with the whole page at write
// time (relocateLinks), together with links inside proposal summaries.
function safeSrc(href) {
  if (/^(https?:|mailto:)/i.test(href)) return href;
  if (hasScheme(href)) return '#';
  return href;
}

// Proposals with a section target → right-margin cards (Docs/Word pattern).
// Card ids are the future seat of the apply/dismiss actions.
function renderRail(anchored) {
  if (!anchored.length) return '';
  const cards = anchored.map(it => `<div class="prc" id="${it.id}" data-anchor="${it.anchor}">
<div class="prc-head"><span class="chip chip-status">Open</span><span class="chip chip-kind">${esc(it.kind)}</span><span class="prc-date">${esc(it.date)}</span></div>
<p class="prc-target">Target: <a href="#${it.anchor}">${esc(it.dest)}</a></p>
<p class="prc-body">${mdInline.renderInline(it.summary)}</p>
<div class="prc-foot">Source: <a href="${esc(safeSrc(it.srcHref))}">${esc(it.srcText)}</a><span class="prc-future">Apply / dismiss actions come later</span></div>
</div>`).join('\n');
  return `<aside class="rail" aria-label="Pending proposals">
<p class="rail-title">Proposals for this chapter (${anchored.length})</p>
${cards}
</aside>`;
}

// Marker chip on each targeted section heading, cross-linked to its first card.
function injectMarkers(html, anchored) {
  const bySec = new Map();
  for (const it of anchored) {
    if (!bySec.has(it.anchor)) bySec.set(it.anchor, []);
    bySec.get(it.anchor).push(it);
  }
  for (const [anchor, list] of bySec) {
    const re = new RegExp(`(<h3 id="${anchor}">.*?)</h3>`);
    html = html.replace(re, `$1 <a class="pmark" href="#${list[0].id}">${list.length} proposal${plural(list.length)}</a></h3>`);
  }
  return html;
}

// End of chapter: new-section proposal groups + the receptacle explainer
// (also the sidebar's jump target).
function renderChapterEnd(items, anchored, groups, raws) {
  const total = items.length;
  const note = '<p class="inbox-note">Pending proposals for this chapter — the book\'s pull requests. Each carries a target and an integration kind; they are merged only by you, while reading, and are always excluded from the public export.'
    + (anchored.length ? ` ${anchored.length} proposal${plural(anchored.length)} for existing sections sit in the right margin next to their targets (listed here on narrow screens and in print).` : '')
    + '</p>';
  let body = '';
  if (!total) {
    body = '<p class="empty">No pending proposals.</p>';
  } else if (groups.size) {
    body = '<h3>Proposed new sections</h3>\n' + [...groups.entries()].map(([name, list]) => `<div class="nsg">
<div class="nsg-head"><span class="chip chip-status">Open</span><span class="chip chip-kind">${esc(list[0].kind)}</span><span class="nsg-name">${esc(name)}</span><span class="nsg-count">${list.length} item${plural(list.length)}</span></div>
<ol class="nsg-items">
${list.map(it => `<li id="${it.id}">${mdInline.renderInline(it.summary)}<span class="nsg-meta">${esc(it.date)} · Source: <a href="${esc(safeSrc(it.srcHref))}">${esc(it.srcText)}</a></span></li>`).join('\n')}
</ol>
</div>`).join('\n');
  }
  if (raws && raws.length) {
    body += (body ? '\n' : '') + '<h3>Unparsed items</h3>\n<p class="inbox-note">These receptacle lines do not match the proposal format and are shown as-is:</p>\n'
      + raws.map(it => `<div class="prc" id="${it.id}"><p class="prc-body">${mdInline.renderInline(it.raw)}</p></div>`).join('\n');
  }
  return `<section class="inbox"><h2 id="${INBOX_ID}">${INBOX_ID}${total ? ` — ${total} pending proposal${plural(total)}` : ''}</h2>\n${note}\n${body}</section>`;
}

// Sidebar section list (chapters: numbered h3 sections; HUB: h2 sections).
// Labels are shortened at the em-dash.
function extractSections(html, isHub) {
  const re = isHub ? /<h2 id="([^"]+)">([^<]*)/g : /<h3 id="(s\d+-\d+)">([^<]*)/g;
  return [...html.matchAll(re)]
    .filter(m => !/^ch\d/.test(m[1]) && m[1] !== INBOX_ID)
    .map(m => ({ id: m[1], label: m[2].trim().split(' — ')[0] }));
}

// ---------- fixed theme ----------
// Palette: unbleached-paper ("kinari") background with a vermilion ("shu")
// accent; warm dark-brown ink. Hairline borders, no left-edge color bars,
// calm outline chips. Body 18px / 1.85 line height / 720px single column.

const CSS = `
  :root{
    --paper:#faf8f2; --card:#fffdf8; --ink:#2c2620; --sub:#6b6257;
    --line:#e4ddd0; --line-strong:#d3c9b8;
    --shu:#b5432a; --shu-soft:#f9efe9; --shu-line:#ecd9cf;
    --th-bg:#f4efe4; --ok:#4a6741; --side-w:288px;
  }
  *{box-sizing:border-box}
  html{scroll-behavior:smooth}
  @media (prefers-reduced-motion: reduce){ html{scroll-behavior:auto} }
  body{
    margin:0; background:var(--paper); color:var(--ink);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue","Hiragino Sans","Hiragino Kaku Gothic ProN","Noto Sans JP",Meiryo,sans-serif;
    font-size:18px; line-height:1.85; overflow-wrap:break-word;
  }
  a{color:var(--shu); text-decoration:none; border-bottom:1px solid var(--shu-line)}
  a:hover{border-bottom-color:var(--shu)}
  code{
    font-family:ui-monospace,"SF Mono",Menlo,monospace; font-size:.86em;
    background:#f1ece0; border:1px solid var(--line); border-radius:5px; padding:1px 6px;
  }

  /* frame: one left sidebar + centered content column */
  .layout{display:grid; grid-template-columns:var(--side-w) minmax(0,1fr)}
  aside.side{
    position:sticky; top:0; height:100vh; overflow-y:auto;
    background:var(--card); border-right:1px solid var(--line-strong);
    padding:20px 14px 28px; font-size:14.5px; line-height:1.6;
  }
  .side-title{margin:0 6px 14px}
  .side-title a{
    display:block; font-weight:700; font-size:15.5px; line-height:1.5;
    color:var(--ink); border-bottom:none;
  }
  .side-title .side-sub{display:block; font-size:12px; color:var(--sub); font-weight:400; margin-top:3px}
  nav.toc a{display:flex; align-items:baseline; gap:8px; padding:7px 10px; margin:1px 0;
    border-radius:8px; color:var(--ink); border-bottom:none}
  nav.toc a:hover{background:var(--th-bg)}
  nav.toc a.here{background:var(--shu-soft); color:var(--shu); font-weight:700}
  nav.toc a.hub{color:var(--sub); font-size:13.5px; margin-bottom:6px}
  nav.toc a.hub.here{color:var(--shu)}
  nav.toc .n{color:var(--sub); font-size:12.5px; min-width:1.1em; text-align:right}
  nav.toc a.here .n{color:var(--shu)}
  nav.toc .t{flex:1}
  nav.toc .lock{font-size:12px}
  nav.toc a.sec{font-size:13px; line-height:1.55; color:var(--sub); padding:4px 10px 4px 34px; margin:0}
  nav.toc a.sec:hover{color:var(--shu); background:var(--th-bg)}
  nav.toc a.sec.on{color:var(--shu); background:var(--shu-soft); font-weight:700}
  nav.toc a.sec .t{flex:1}
  .part{margin:16px 8px 4px; font-size:12px; letter-spacing:.07em; color:var(--sub); font-weight:700}
  .pill{
    font-size:11.5px; line-height:1; padding:3px 7px; border-radius:999px;
    border:1px solid var(--shu-line); color:var(--shu); background:var(--paper); white-space:nowrap;
  }
  .side-foot{margin:20px 8px 0; padding-top:12px; border-top:1px solid var(--line);
    font-size:12px; color:var(--sub); line-height:1.7}
  .side-close{display:none}

  /* content: every element shares one 720px measure; the right margin is
     reserved for proposal cards */
  .main-row{display:flex; flex-wrap:wrap; justify-content:center; gap:0 40px; padding:34px 44px 24px; min-width:0}
  main.content{max-width:720px; min-width:0; flex:0 1 720px}
  .foot-row{grid-column:2; display:flex; justify-content:center; padding:0 44px 70px}
  .foot-row footer.prov{max-width:720px; flex:0 1 720px; margin-top:0}
  h2[id], h3[id], .prc{scroll-margin-top:24px}
  a.pmark{font-size:12px; font-weight:400; white-space:nowrap; vertical-align:3px; margin-left:10px;
    padding:2px 9px; border:1px solid var(--shu-line); border-radius:999px;
    color:var(--shu); background:var(--shu-soft)}
  a.pmark:hover{border-color:var(--shu)}
  aside.rail{flex:1 1 100%; min-width:0; margin-top:26px}
  .rail .rail-title{font-size:13px; font-weight:700; color:var(--sub); letter-spacing:.06em; margin:0 0 10px}
  .rail .prc{font-size:13px; padding:10px 12px 8px}
  .rail .prc-body{font-size:13px; line-height:1.65; margin:0 0 7px}
  .rail .prc-foot{font-size:11.5px; padding-top:6px}
  .prc-target{font-size:12px; color:var(--sub); margin:0 0 6px}
  @media (min-width:1440px){
    aside.rail{flex:0 0 300px; margin-top:0; position:relative}
    .rail .rail-title{display:none}
    .rail.float .prc{position:absolute; width:300px; left:0; margin:0}
  }
  .ch-meta{
    font-size:13.5px; color:var(--sub); padding-bottom:12px; margin-bottom:26px;
    border-bottom:1px solid var(--line-strong); display:flex; flex-wrap:wrap; gap:6px 18px;
  }
  .ch-meta .priv{color:var(--shu); font-weight:700}
  article > h2:first-child{font-size:27px; line-height:1.5; margin:0 0 20px; border-bottom:none; padding-bottom:0}
  article h1{font-size:27px; line-height:1.5; margin:0 0 20px}
  h2{font-size:23px; line-height:1.55; font-weight:700; margin:44px 0 16px; padding-bottom:8px; border-bottom:1px solid var(--line-strong)}
  h3{font-size:19.5px; line-height:1.6; font-weight:700; margin:34px 0 12px}
  p{margin:0 0 15px}
  ul,ol{margin:0 0 15px; padding-left:1.5em}
  li{margin:5px 0}
  li p{margin:0 0 6px}
  blockquote{margin:18px 0; padding:14px 20px; background:var(--card);
    border:1px solid var(--line-strong); border-radius:10px}
  blockquote p{margin:0; font-weight:500}
  blockquote p + p{margin-top:10px}
  blockquote.mti{background:var(--shu-soft); border-color:var(--shu-line)}
  blockquote.mti p{font-weight:400}
  .table-wrap{overflow-x:auto; margin:16px 0}
  table{border-collapse:collapse; width:100%; min-width:560px; font-size:15.5px; line-height:1.7; background:var(--card)}
  th,td{border:1px solid var(--line); padding:9px 12px; text-align:left; vertical-align:top}
  th{background:var(--th-bg); font-weight:700}
  td:first-child{min-width:8.5em}
  pre{background:var(--card); border:1px solid var(--line); border-radius:10px;
    padding:14px 18px; overflow-x:auto; font-size:14.5px; line-height:1.7; margin:16px 0}
  pre code{background:none; border:none; padding:0; font-size:inherit}
  hr{border:none; border-top:1px solid var(--line-strong); margin:40px 0}

  /* receptacle: pull-request-shaped cards */
  section.inbox{margin-top:56px}
  section.inbox h2{color:var(--shu); font-size:20px}
  section.inbox .inbox-note{font-size:14px; color:var(--sub); margin:0 0 16px}
  section.inbox .empty{color:var(--sub); font-size:15.5px; margin:0}
  .prc{background:var(--card); border:1px solid var(--line-strong); border-radius:10px;
    padding:12px 16px 10px; margin:0 0 12px}
  .prc-head{display:flex; flex-wrap:wrap; gap:6px; align-items:center; margin:0 0 9px}
  .chip{font-size:11.5px; line-height:1.4; padding:3px 9px; border-radius:999px; border:1px solid; white-space:nowrap}
  .chip-status{color:var(--shu); border-color:var(--shu-line); background:var(--shu-soft)}
  .chip-dest{color:var(--ink); border-color:var(--line-strong); background:var(--th-bg)}
  .chip-kind{color:var(--sub); border-color:var(--line); background:var(--paper)}
  .prc-date{margin-left:auto; font-size:12px; color:var(--sub)}
  .prc-body{font-size:15px; line-height:1.75; margin:0 0 9px}
  .prc-foot{font-size:12.5px; color:var(--sub); display:flex; flex-wrap:wrap; gap:6px 14px;
    border-top:1px solid var(--line); padding-top:8px}
  .prc-future{margin-left:auto; color:var(--sub); opacity:.75}
  .prc:target{border-color:var(--shu); box-shadow:0 0 0 2px var(--shu-line)}
  .nsg{background:var(--card); border:1px solid var(--line-strong); border-radius:10px;
    padding:12px 16px; margin:0 0 14px}
  .nsg-head{display:flex; flex-wrap:wrap; gap:6px; align-items:center; margin:0 0 10px}
  .nsg-name{font-weight:700; font-size:15px}
  .nsg-count{margin-left:auto; font-size:12px; color:var(--sub)}
  ol.nsg-items{margin:0; padding-left:1.3em; font-size:14.5px; line-height:1.7}
  ol.nsg-items li{margin:0 0 12px}
  .nsg-meta{display:block; font-size:12px; color:var(--sub); margin-top:2px}

  nav.pager{display:flex; gap:14px; margin-top:54px}
  nav.pager a{
    flex:1; display:block; padding:14px 18px; background:var(--card);
    border:1px solid var(--line-strong); border-radius:12px; color:var(--ink);
  }
  nav.pager a:hover{border-color:var(--shu)}
  nav.pager .dir{display:block; font-size:12px; color:var(--sub); margin-bottom:4px}
  nav.pager .next{text-align:right}
  nav.pager .dest{font-weight:700; font-size:15.5px}

  footer.prov{margin-top:46px; padding-top:14px; border-top:1px solid var(--line);
    font-size:13px; color:var(--sub); line-height:1.8}

  header.topbar{display:none}
  #nav-toggle{display:none}
  @media (max-width:920px){
    body{font-size:16.5px}
    .layout{display:block}
    header.topbar{
      display:flex; align-items:center; gap:14px; position:sticky; top:0; z-index:30;
      background:var(--card); border-bottom:1px solid var(--line-strong); padding:10px 16px;
    }
    header.topbar label{
      font-size:14px; font-weight:700; color:var(--shu); padding:5px 12px;
      border:1px solid var(--shu-line); border-radius:999px; cursor:pointer;
    }
    header.topbar .tb-title{font-size:14px; font-weight:700; line-height:1.4}
    aside.side{
      position:fixed; z-index:40; top:0; bottom:0; left:0; width:min(84vw,320px);
      height:auto; transform:translateX(-105%); transition:transform .18s ease;
    }
    #nav-toggle:checked ~ .layout aside.side{transform:none; box-shadow:0 0 0 100vmax rgba(44,38,32,.28)}
    #nav-toggle:checked ~ .layout aside.side .side-close{display:block}
    .side-close{margin:0 6px 10px; font-size:13px; color:var(--sub); cursor:pointer}
    .main-row{padding:22px 16px 60px}
    .foot-row{padding:0 16px 60px}
    article > h2:first-child, article h1{font-size:22px}
    h2{font-size:20px}
    h3{font-size:17.5px}
    nav.pager{flex-direction:column}
    nav.pager .next{text-align:left}
    .prc-date, .prc-future{margin-left:0}
  }
  @media print{
    aside.side, header.topbar, nav.pager{display:none}
    .layout{display:block}
    body{background:#fff}
    aside.rail{position:static}
    .rail .prc{position:static !important; width:100% !important}
    .rail .rail-title{display:block}
  }
`;

// Scroll spy (deterministic: the active section is the last heading above
// the 25%-viewport line) + margin-card placement (cards align with their
// target's vertical position, stacking downward to avoid overlap).
const SPY = `<script>
(() => {
  const links = [...document.querySelectorAll('.side a.sec')];
  if (!links.length) return;
  const map = new Map(links.map(a => [decodeURIComponent(a.hash.slice(1)), a]));
  const hs = [...document.querySelectorAll('h2[id],h3[id]')].filter(h => map.has(h.id));
  if (!hs.length) return;
  let tick = false;
  function update() {
    tick = false;
    const y = window.scrollY + window.innerHeight * 0.25;
    let cur = hs[0];
    for (const h of hs) { if (h.offsetTop <= y) cur = h; else break; }
    const a = map.get(cur.id);
    links.forEach(x => x.classList.toggle('on', x === a));
  }
  addEventListener('scroll', () => { if (!tick) { tick = true; requestAnimationFrame(update); } }, { passive: true });
  update();
})();
</script>
<script>
(() => {
  const rail = document.querySelector('aside.rail');
  if (!rail) return;
  const mq = matchMedia('(min-width:1440px)');
  function place() {
    const wide = mq.matches;
    rail.classList.toggle('float', wide);
    const cards = [...rail.querySelectorAll('.prc')];
    if (!wide) { cards.forEach(c => { c.style.top = ''; }); rail.style.minHeight = ''; return; }
    const railTop = rail.getBoundingClientRect().top + window.scrollY;
    let cursor = 0;
    for (const c of cards) {
      const a = document.getElementById(c.dataset.anchor);
      const want = a ? a.getBoundingClientRect().top + window.scrollY - railTop : cursor;
      const top = Math.max(want, cursor);
      c.style.top = top + 'px';
      cursor = top + c.offsetHeight + 12;
    }
    rail.style.minHeight = cursor + 'px';
  }
  place();
  addEventListener('load', place);
  addEventListener('resize', () => requestAnimationFrame(place));
})();
</script>`;

// ---------- page template ----------

function sidebar(spine, chapters, book, currentFile, sections, inboxCount) {
  const rows = [];
  const secRows = () => {
    const r = sections.map(s =>
      `<a class="sec" href="#${encodeURIComponent(s.id)}"><span class="t">${esc(s.label)}</span></a>`);
    if (currentFile !== 'index') {
      const pill = inboxCount > 0 ? ` <span class="pill">${inboxCount}</span>` : '';
      r.push(`<a class="sec" href="#${encodeURIComponent(INBOX_ID)}"><span class="t">${esc(INBOX_ID)}</span>${pill}</a>`);
    }
    return r.join('\n');
  };
  rows.push(`<a class="hub${currentFile === 'index' ? ' here' : ''}" href="index.html">Contents &amp; status (HUB)</a>`);
  if (currentFile === 'index' && sections.length) rows.push(secRows());
  for (const it of spine) {
    if (it.kind === 'part') { rows.push(`<div class="part">${esc(it.label)}</div>`); continue; }
    const ch = chapters.get(it.file);
    const here = it.file === currentFile;
    const pill = !here && ch && ch.count > 0 ? ` <span class="pill">${ch.count}</span>` : '';
    const lock = ch && ch.priv ? ' <span class="lock">🔒</span>' : '';
    rows.push(`<a class="toc-ch${here ? ' here' : ''}" href="${it.file}.html"><span class="n">${it.num}</span><span class="t">${esc(it.short)}${lock}</span>${pill}</a>`);
    if (here) rows.push(secRows());
  }
  return `<aside class="side">
<div class="side-title"><a href="index.html">${esc(book.name)}<span class="side-sub">Rill book — reading view (derived)</span></a></div>
<label class="side-close" for="nav-toggle">× Close</label>
<nav class="toc">${rows.join('\n')}</nav>
<div class="side-foot">status: ${esc(book.status || 'living')}<br>updated: ${esc((book.updated || '').slice(0, 10))}</div>
</aside>`;
}

function pager(spine, currentFile) {
  const chs = spine.filter(i => i.kind === 'chapter');
  const idx = chs.findIndex(c => c.file === currentFile);
  if (idx < 0) return '';
  const prev = idx === 0
    ? `<a href="index.html"><span class="dir">← Back</span><span class="dest">Contents &amp; status (HUB)</span></a>`
    : `<a href="${chs[idx - 1].file}.html"><span class="dir">← Previous chapter</span><span class="dest">${esc(chs[idx - 1].title)}</span></a>`;
  const next = idx === chs.length - 1 ? ''
    : `<a class="next" href="${chs[idx + 1].file}.html"><span class="dir">Next chapter →</span><span class="dest">${esc(chs[idx + 1].title)}</span></a>`;
  return `<nav class="pager">${prev}${next}</nav>`;
}

function page({ book, spine, chapters, currentFile, title, metaHtml, bodyHtml, pagerHtml, sections, inboxCount, railHtml = '' }) {
  const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">\n<meta name="generator" content="rill book build">
<title>${esc(title)} — ${esc(book.name)}</title>
<style>${CSS}</style>
</head>
<body>
<input type="checkbox" id="nav-toggle">
<header class="topbar"><label for="nav-toggle">Contents</label><span class="tb-title">${esc(book.name)}</span></header>
<div class="layout">
${sidebar(spine, chapters, book, currentFile, sections, inboxCount)}
<div class="main-row">
<main class="content">
${metaHtml}
<article>
${bodyHtml}
</article>
${pagerHtml}
</main>
${railHtml}
</div>
<div class="foot-row">
<footer class="prov">
The source of truth is the Markdown under <code>pages/${esc(BOOK_ID)}/</code> — edit there; this view is derived and never committed.<br>
Regenerate: <code>rill book build ${esc(BOOK_ID)}</code> · generated ${stamp} UTC
</footer>
</div>
</div>
${SPY}
</body>
</html>`;
}

// ---------- build ----------

const bookRaw = stripFrontmatter(fs.readFileSync(path.join(SRC, '_book.md'), 'utf8'));
const book = { name: bookRaw.meta.name || BOOK_ID, status: bookRaw.meta.status, updated: bookRaw.meta.updated };
const spine = parseSpine(bookRaw.body);

const chapters = new Map();
for (const it of spine) {
  if (it.kind !== 'chapter') continue;
  const file = path.join(SRC, it.file + '.md');
  if (!fs.existsSync(file)) {
    console.error(`book build: chapter listed in _book.md not found: ${it.file}.md`);
    process.exit(1);
  }
  const { meta, body } = stripFrontmatter(fs.readFileSync(file, 'utf8'));
  const { bodyMd, inboxMd } = splitInbox(body);
  const items = parseInboxItems(inboxMd);
  chapters.set(it.file, { meta, bodyMd, items, count: items.length, priv: meta.public === 'false' });
}

// Inputs are valid — only now clear previously generated pages so renamed
// or removed chapters leave no orphans behind. Only files carrying this
// builder's generator marker are deleted (a custom --out directory may
// contain unrelated HTML), and a failed build never destroys the last
// good view.
for (const f of fs.readdirSync(VIEW)) {
  if (!f.endsWith('.html')) continue;
  const fp = path.join(VIEW, f);
  try {
    if (fs.readFileSync(fp, 'utf8').includes(GENERATOR_META)) fs.unlinkSync(fp);
  } catch { /* unreadable file: leave it alone */ }
}

const report = [];
for (const it of spine) {
  if (it.kind !== 'chapter') continue;
  const ch = chapters.get(it.file);
  let html = md.render(ch.bodyMd);
  html = chapterLinks(ensureH2Ids(wrapTables(markMti(addAnchors(html)))), spine);
  const withIds = ch.items.map((x, i) => ({ ...x, id: `prc-${it.file}-${i + 1}` }));
  const anchored = withIds
    .filter(x => !x.raw && destAnchor(x.dest) && html.includes(`id="${destAnchor(x.dest)}"`))
    .map(x => ({ ...x, anchor: destAnchor(x.dest) }))
    .sort((a, b) => html.indexOf(`id="${a.anchor}"`) - html.indexOf(`id="${b.anchor}"`));
  const groups = new Map();
  for (const x of withIds) {
    if (x.raw || anchored.some(a => a.id === x.id)) continue;
    const name = x.dest || 'other';
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push(x);
  }
  html = injectMarkers(html, anchored);
  const raws = withIds.filter(x => x.raw);
  html += '\n' + renderChapterEnd(ch.items, anchored, groups, raws);
  const meta = [
    `status: <code>${esc(ch.meta.status || '?')}</code>`,
    `reviewed: <code>${esc(ch.meta.reviewed || '?')}</code>`,
    `${ch.count} pending proposal${plural(ch.count)}`,
    ch.priv ? '<span class="priv">🔒 Private chapter (dropped from the public export)</span>' : '',
  ].filter(Boolean).map(s => `<span>${s}</span>`).join('');
  fs.writeFileSync(path.join(VIEW, it.file + '.html'), relocateLinks(page({
    book, spine, chapters, currentFile: it.file, title: it.title,
    metaHtml: `<div class="ch-meta">${meta}</div>`,
    bodyHtml: html,
    pagerHtml: pager(spine, it.file),
    sections: extractSections(html, false),
    inboxCount: ch.count,
    railHtml: renderRail(anchored),
  }), spine));
  report.push(`${it.file}.html(${ch.count})`);
}

{
  let html = md.render(bookRaw.body);
  html = chapterLinks(ensureH2Ids(wrapTables(markMti(html))), spine);
  const first = spine.find(i => i.kind === 'chapter');
  fs.writeFileSync(path.join(VIEW, 'index.html'), relocateLinks(page({
    book, spine, chapters, currentFile: 'index', title: 'Contents & status',
    metaHtml: '',
    bodyHtml: html,
    pagerHtml: `<nav class="pager"><a class="next" href="${first.file}.html"><span class="dir">Start reading →</span><span class="dest">${esc(first.title)}</span></a></nav>`,
    sections: extractSections(html, true),
    inboxCount: 0,
  }), spine));
  report.push('index.html');
}

console.log('book build: ' + report.join(', '));
