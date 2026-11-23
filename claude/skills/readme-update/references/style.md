# The nature of a trending README — voice, typography, layout

Measured 2026-11-24 on 28 READMEs from GitHub trending (weekly + monthly; all, Python, TypeScript, Rust). 26 are English, 2 Chinese.
Ratios and medians below are for the English ones. Re-measure any time with:

```bash
python3 <skill>/scripts/readme_nature.py <folder of README .md files>
```

GitHub renders READMEs with its own fonts — you cannot choose a typeface. "Typography" here means what markdown and a few
HTML attributes control: heading levels, bold, inline code, small text (`<sub>`), alignment and image widths.

## Voice

| Trait | Measure | What it means for writing |
|---|---|---|
| Talks to the reader | "you/your" median **14** per README; "we/our" **2.5** | Address the reader. Say what *they* get or do. Keep the team's story short. |
| Calm, not hype | exclamation marks median **0**; hype words (blazing, powerful, seamless, revolutionary…) median **0** | Confidence comes from specifics. No exclamation marks, no superlatives. |
| Short sentences | median **16** words per sentence | One idea per sentence. Split anything over ~25 words. |
| One-sentence pitch | first paragraph median **17** words | The opening says what it is in one sentence, then stops. |
| Numbers only when real | 5/26 make a numeric claim (benchmarks, speed) | Use a number when it is measured and checkable; otherwise describe. |

**Tagline shape** — a noun phrase: *[qualities] + [what it is] + [the difference]*.
- "An extremely fast Python linter and code formatter, written in Rust." (ruff)
- "A free, open source, and extensible speech-to-text application that works completely offline." (Handy)
- "Browser automation for AI agents: open pages, read them as an accessibility tree, and act on elements from the shell." (agent-browser)

Often in bold, directly under the name. A second plain line may add scope or an honest limit.

**"Why X?"** — a short section of bold-led bullets (`- **Private**: your voice stays on your computer`) is the common way to state values. Question headings are otherwise rare (6 of ~230 `##`).

**Korean READMEs** — keep the same traits: speak to the reader (합니다체 or the repo's existing register if it has a rule), short sentences, the
benefit first, no hype words or exclamation marks. A noun-phrase tagline works in Korean too ("…을 한 장의 지도로 보는 도구").
If the repo has a wording rule (banned words, "no advice", required notices), it wins over all of this.

## Typography

| Element | Measure | Rule of thumb |
|---|---|---|
| Emoji in `##` headings | median **0** (16 of ~230 in English READMEs; the Chinese ones use them on most headings) | No emoji headings for English/Korean dev tools; follow the audience's convention otherwise. |
| Emoji bullets | median **0** | Avoid. |
| Bold-led bullets | median **6** of **13.5** bullets | Lead each feature bullet with its name in bold, then a plain clause. |
| Bold density | median **1.3** per 100 words | Bold the one phrase a skimmer needs per paragraph, not sentences. |
| Inline code | median **3.3** per 100 words | Put commands, flags, file names and identifiers in backticks — readers copy them. |
| Code blocks | median **7.5**, almost all language-tagged | Tag every fence (` ```bash `). Keep each block runnable. |
| Heading case | Title Case slightly ahead of Sentence case | Pick one and keep it. Short headings: "Quick start", "Install", "Why X?". |
| Em dashes | median 0, a few READMEs use many | Fine in moderation; don't chain them. |
| Small text | captions under images | `<sub>` or italics for captions and fine print. |

## Layout

| Element | Measure | Rule of thumb |
|---|---|---|
| A picture in the first screen | **25/26** | Show the thing working (GIF, screenshot, chart) above the fold. |
| Centered hero | **17/26** | `<div align="center">` around logo, name, tagline, badges, link row. |
| Dark-mode aware logo | 8/26 | Use `<picture><source media="(prefers-color-scheme: dark)" …>` when the repo has both logos. |
| Link row | 8/26 | `Docs · Demo · Install · Languages · Sponsor` with ` · ` or ` | `. |
| Badges | median **3.5**, nearly all in the hero | 2–4 badges that work for anonymous visitors. |
| `##` sections | median **9** | 6–10. More means material that belongs in docs. |
| Tables | median **1** | One comparison or "what you get" table; not more. |
| `<details>` | median 0 (a few use many) | Fold long lists (integrations, all options) instead of deleting or showing them. |
| Side-by-side images | 7/26 | Two `<img width="49%">` in one centered `<p>` for before/after or two surfaces. |
| GitHub alerts (`> [!NOTE]`) | rare | Use at most one, for the one thing that must not be missed. |
| Horizontal rules | rare | Headings already separate sections. |
| Length | median **257** lines (48–1002) | Target 80–150, up to 250 with pictures or install variants (same target as SKILL.md). |

## Order of a first screen that works

1. Logo (dark-mode aware) and name.
2. Bold noun-phrase tagline; one plain line of scope.
3. 2–4 badges; link row.
4. The demo picture with a one-line caption in small text.
5. "Quick start" with one tagged code block.

Everything else follows, in short sections with bold-led bullets, then a docs table and a community/license footer.

## Images — where they live and how they are written

Measured on the same 28 READMEs (`scripts/readme_assets.py <folder>` re-measures).

| Trait | Measure | Rule of thumb |
|---|---|---|
| Where images live | repo-relative **183** · other sites **52** · `raw.githubusercontent` **17** · GitHub drag-and-drop uploads (`user-attachments`) **11** (badges excluded) | Commit images to the repo (`docs/images/`, `.github/assets/`, `assets/`) and link them relatively. Use an absolute `raw.githubusercontent.com/OWNER/REPO/main/…` URL only when the README is also shown off GitHub (PyPI, npm, a docs site). Drag-and-drop uploads are for one-off screenshots and videos — they are not versioned with the code. |
| Formats | png **99** · svg **84** · webp **38** · jpg **25** · gif **6** | SVG for logos, diagrams and charts (crisp, small, can have a dark variant). PNG/WebP for screenshots — WebP when size matters. GIFs are rare; prefer a short MP4 uploaded to GitHub or an animated WebP, and keep any GIF small. |
| Alt text | **224/243** images have it | Always write alt text that says what the picture shows, not "screenshot". |
| Size | `width` set on **142** `<img>` | Set `width` (or `height` for logos) so a large asset does not take over the page; use `width="49%"` pairs for side by side. |
| Dark mode | **12/28** use `<picture>` with `prefers-color-scheme` | Give logos and diagrams a dark variant when the repo has one; screenshots can stay single. |
| Linked images | common (badges, deploy buttons, the logo) | Wrap a badge or button in the link it describes; don't link screenshots to themselves. |

## Branding

| Trait | Measure | Rule of thumb |
|---|---|---|
| Logo or banner at the top | **21/28** | Use the repo's logo if it has one; do not invent one. |
| Name as real heading text | **23/28** have `# Name` or `<h1>` | Keep the name as text even when there is a logo or banner — it is searchable, copyable and read by screen readers. |
| Full-width banner image | **4/28** | Rare; a logo plus text heading is the norm. |
| Bold tagline near the top | **11/28** | One bold sentence under the name (see Voice). |
| Social / community links in the hero | **12/28** | Add only channels that exist (Discord, X, site). |
| Language switcher in the hero | **9/28** | One line: `English · 한국어 · 日本語` linking to `README.<lang>.md`. |
| Brand-asset note | Handy, Sure: "the name and logo are not open source" / trademark lines | If the owner wants the name and logo protected while the code is open, say so in one line near the license. Ask the owner — don't add it on your own. |

Keep name, tagline, logo and colors identical across README, docs site, social preview and package metadata; if the repo has a brand guide, it is the source.

## Footer — how READMEs end

| Trait | Measure | Rule of thumb |
|---|---|---|
| License is the last section | **18/28** have it among the last three `##`; **16/28** end on a license line | End with `## License` — one line: the license name and a link to `LICENSE`. |
| Acknowledgments | **13/28** | A short bullet list of the projects and people you build on, when there are some. |
| Community links in the tail | **13/28** | Issues, discussions or chat, one line each. |
| Trademark / security notes | **8/28** | One line each, linking `SECURITY.md` or the trademark policy. |
| Star-history chart | **8/28** | Only for repos with an audience; skip for new or private ones. |
| Contributors image (contrib.rocks, all-contributors) | **4/28** | Use when outside contributors exist. |
| Sponsors in the tail | **5/28** | One line with the Sponsors link; perks, if any, stated plainly. |
| "Made by / Built with" line | **4/28** | Optional, small, last. |
| Back-to-top link, citation block | 1/28 each | Rare; add a citation only for research software. |

A typical ending: **Docs → Contributing / Community → Acknowledgments → License** — a few lines each, nothing after the license except an optional small "made by" line.
