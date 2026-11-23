# What trending READMEs look like

Measured 2026-11-24 from GitHub trending (weekly, all languages and Python). `scripts/readme_stats.py` prints the same columns for any README, so you can compare.

| Repo | Lines | `##` | Images | Badges | `<details>` | Notes |
|---|---|---|---|---|---|---|
| microsoft/PyRIT | 82 | 5 | 4 | 3 | 0 | logo, one line, links out to the docs site |
| we-promise/sure | 128 | 6 | 10 | 1 | 0 | centered hero, screenshot, getting started |
| ChromeDevTools/chrome-devtools-mcp | 198 | 12 | 1 | 1 | 0 | key features, getting started, rest linked |
| alibaba/open-code-review | 244 | 7 | 21 | 12 | 0 | centered hero, benchmark figure early |
| ag-ui-protocol/ag-ui | 252 | 10 | 22 | 5 | 2 | long lists folded in `<details>` |
| ZhuLinsen/daily_stock_analysis | 324 | 10 | 14 | 6 | 1 | preview image, features, quick start |
| mvanhorn/last30days-skill | 390 | 13 | 5 | 1 | 0 | |
| soxoj/maigret | 414 | 10 | 28 | 6 | 1 | "In one minute" section near the top |
| tradermonty/claude-trading-skills | 452 | 15 | 3 | 0 | 0 | |
| backnotprop/plannotator | 602 | 14 | 18 | 0 | 3 | |
| dream-num/univer | 914 | 10 | 54 | 21 | 8 | |
| jingyaogong/minimind | 2030 | 32 | 33 | 5 | 21 | outlier: tutorial-in-README |

Median ≈ 250–320 lines, but the ones that read best are 80–250: they say what it is, show it, let you run it, and link out.

## The common shape

1. **Centered hero** — `<div align="center">` with logo, `# Name`, one bold sentence (what it does, for whom), one plain line of context, a row of 2–6 badges, and a link row: *Demo · Docs · Install · 한국어/English · Sponsor*.
2. **Demo picture immediately** — a GIF or screenshot of the thing working, with a one-line caption.
3. **Quick start / "In one minute"** — 1–3 commands that work on a fresh clone. No credentials, no private data.
4. **Features** — 3–6 bullets or a two-column table; sometimes 2 screenshots side by side (`<img width="49%">` ×2 inside `<p align="center">`).
5. **Install / usage variants** — short, with links; long option lists go in `<details>` or docs.
6. **Docs table** — where the long material lives.
7. **Community** — contributing, issues, security, sponsor, license; a few lines.

## Anti-patterns seen in long READMEs

- Architecture diagrams and file trees on the front page.
- Every CLI flag, key binding or column described in the README.
- Operations runbooks, schedules, incident notes, dated "status" paragraphs.
- Comparison tables and research notes before the reader has run anything.
- Badges that 404 for anonymous visitors (private CI), or a wall of 20 badges.

## Skeleton

```markdown
<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/logo-dark.svg">
  <img alt="NAME" src="docs/brand/logo.svg" height="64">
</picture>

# NAME

**One sentence: what it does, for whom.**

One plain line of context (scope, honesty note).

[![Release](https://img.shields.io/github/v/release/OWNER/NAME)](https://github.com/OWNER/NAME/releases)
[![Python](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[Demo](URL) · [Docs](docs/guide.md) · [Install](docs/install.md) · [English](README.en.md) · [Sponsor](URL)

</div>

![What it looks like](docs/images/demo.gif)

<p align="center"><sub>One-line caption.</sub></p>

## Quick start

    one
    two
    three

What you will see, one sentence.

## What you get

| | |
|---|---|
| **Thing** | what it shows |

## Use your own data

| Path | What it does | Guide |
|---|---|---|

## Caveats

- …

## Docs

| Doc | What's inside |
|---|---|

## Contributing · Support

- Issues, contributing guide, security contact, sponsor line.

## License

MIT
```

Adapt the language of headings to the README's language; keep anchor-worthy headings stable once published.
