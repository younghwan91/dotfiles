---
name: readme-update
description: Rewrite a repository README into the shape, voice and layout today's trending GitHub repos use — centered hero (logo, one-line pitch, badges, link row), demo picture, a Quick start that runs, a few lines of what it does, and a docs table — and move the long material, word for word, into docs/ so nothing is lost. Use this whenever someone says the README is too long, messy, outdated or hard to read, or asks to clean up, tidy, refresh, restructure, rewrite or "make it like popular repos" — including short Korean asks like "리드미 정리", "리드미 업데이트", "README 너무 길다", "리드미 다듬어", "트렌딩 레포처럼". Also use it after big features land and the README no longer matches the project. It does the whole job by itself: measure, plan, move, relink, fix references and tests, verify.
---

# README update

A README is the front door. People decide in the first screen whether to keep reading, so the first screen has to say what this is, show it, and let them run it. Everything else — architecture, operations, every flag, the theory — belongs one click away in `docs/`, not deleted.

Do the whole job without asking for each step. Ask only when a choice genuinely belongs to the owner (for example, two conflicting taglines). Treat the repo's own rules (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, a brand guide, a wording/banned-words list, legal or data notices) as overriding the patterns here.

## 1. Measure and read

```bash
python3 <skill>/scripts/readme_stats.py README.md [README.*.md]
```

It prints lines, `##` count, images, badges and code blocks. Compare against `references/patterns.md` (structure and length of trending READMEs) and `references/style.md` (their voice, typography and layout, measured). To re-measure the trend on fresh samples, put README files in a folder and run `scripts/readme_nature.py <folder>` (voice, typography, layout) and `scripts/readme_assets.py <folder>` (images, branding, footer). Length target (one number everywhere): **aim for 80–150 lines; up to 250 is fine when the extra lines are pictures, a features table or install variants; above 250 move more out.** 6–10 `##` sections.

Then read the README top to bottom as a first-time visitor and note, per section: *does a first-time reader need this on the front page?* Typical answers:
- Keep (shortened): what it is, demo, quick start, what you get, how to use your own data / install, the one or two caveats that change how results are read, license, how to contribute or support.
- Move to `docs/`: architecture and file trees, operations and schedules, every key and column explained, formulas and definitions, validation details, development and testing commands, comparison tables, long FAQs.
- Delete only true duplication and dated status logs ("as of last Tuesday we…"). When in doubt, move instead of delete.

**Keep what the brand already is.** If the README has a banner image, a custom `<p align="center">` block, a logo layout or an established register (e.g. Korean "~다" or "~합니다"), keep it and apply the patterns inside it — do not swap a working hero for the skeleton.

Also read the project rules files and any brand guide now — they may fix the tagline, required notices, words that must not appear, or which pictures may be public.

## 2. Find everything that points at the README

```bash
bash <skill>/scripts/find_readme_refs.sh .
```

It lists links with README anchors (`README.md#…`), prose pointers like "README §4" or "see the README section", and tests or scripts that read README text or slice it by headings. Each of these must point at the new home after the move, or still find what it checks in the README. Plan the changes before editing.

## 3. Move the long sections word for word

```bash
python3 <skill>/scripts/move_sections.py --readme README.md --out docs/guide.md \
  --start "## 1. What it does" --end "## License" --title "Project guide"
```

- Moves the block from the `--start` heading up to (not including) the `--end` heading into the new file, unchanged, and rewrites relative links and images for the new folder (`docs/x.md` → `x.md`, `scripts/a.py` → `../scripts/a.py`). Anchors (`#...`) stay valid because headings keep their text.
- Add a short table of contents at the top of the new file and a line pointing back to the README.
- If the repo already has a docs folder with a natural home for a section (e.g. an existing `architecture.md`), put it there instead; one `guide.md` is the default.
- Run it with `--dry-run` first if the start/end headings are ambiguous.
- **Part of a section:** headings match by prefix at any level, so `--start "### Updating" --end "## How it works"` moves the tail of a section and leaves its first part (e.g. the install command) in the README.
- **Don't duplicate.** Something a first-time reader needs (install command, the main table) lives in the README; the guide links back to it (`[Install](../README.md#install)`) instead of keeping a second copy that will drift.
- The script writes a heading, a back-link and a table of contents in the README's language when it creates the file, and drops trailing `---` rules from the moved block.

## 4. Write the new README

Use the skeleton in `references/patterns.md` and write in the manner of `references/style.md` — talk to the reader, short sentences, a bold noun-phrase tagline, bold-led bullets, code in backticks, no hype words or exclamation marks, a picture in the first screen. For pictures, branding and the ending follow the Images, Branding and Footer sections of `references/style.md`: images committed to the repo and linked relatively, SVG for logos and charts, alt text and a `width` on every image, the name kept as heading text next to the logo, and a footer that ends on a one-line `## License`. Fill it from what the project already says — do not invent claims, numbers, features or badges. In short:

1. **Hero** (centered `<div align="center">`, or the repo's existing hero block): logo if the repo has one, `# name`, one bold sentence that says what it does for whom, one plain line of context, 0–4 badges that are true and work for anonymous visitors — a release badge only if a release exists, license only if a LICENSE file exists, no CI badge for private repos; zero badges is fine — and a link row (demo · docs · install/own data · other languages · sponsor).
2. **Demo picture** right under the hero — the best existing GIF/screenshot; caption in small text. Respect rules about synthetic/demo-only images.
3. **Quick start**: ≤3 commands that run on a fresh clone without credentials or private data; one sentence about what you will see.
4. **What it does / What you get**: a small table or 3–6 bullets, optionally two screenshots side by side.
5. **Use with your own data / Install** (if different from Quick start): a short table of paths with links to the detailed docs.
6. **Caveats** only if they change how output is read (limits, not advice, data licensing) — 3–5 bullets linking to the long version.
7. **Docs** table linking the moved material and other docs.
8. **Contributing · Support · License** in a few lines.

Keep the tagline identical to wherever the repo treats it as canonical (brand guide, repo description). Mirror the same structure in other-language READMEs (`README.en.md`, `README.ko.md`, …) and keep their Quick start commands identical to the main one.

### Korean prose: polish with humanize-korean

If the README (or `README.ko.md`) is Korean and the `humanize-korean` skill is installed (`~/.claude/skills/humanize-korean`, from epoko77-ai/im-not-ai), run it on the Korean prose you wrote — the hero line, captions, bullets and short paragraphs. It removes translationese, stiff nominalisation, mechanical parallelism and other AI tells without changing content. Keep these out of its reach or restore them afterwards: code blocks and commands, links and paths, headings that other files link to, the tagline when a brand guide fixes it, and any wording the repo requires (notices, banned-word rules). Then diff the result against your draft and keep only changes that read better and say the same thing. If the skill is not installed, apply the same ideas yourself: short sentences, plain verbs, no "~하는 것이 가능하다"-style nominalisation, no "다양한·혁신적인" filler.

## 5. Repoint references and tests

Using the list from step 2:
- Links/anchors → the new file and anchor.
- Prose like "README §4.3" in code, help text, issue templates and docs → the new location ("docs/guide.md §4.3").
- Tests that read README sections → read the new file for moved content; keep tests that check the README front page pointing at the README with the new section names. Do not weaken a test's intent; move it.
- If the repo uses mutation tests, golden files, screenshot ledgers or doc-reference checkers, update their anchors the same way and re-shoot images if a watched file changed.
- Consider adding a small guard (e.g. "README stays under 150 lines and links to the guide") so it does not grow back — only if the repo already has a docs test suite to put it in.

## 6. Verify and ship

```bash
python3 <skill>/scripts/check_links.py README.md README.*.md docs/guide.md
```

It checks that every relative link and image target exists and that `#anchors` resolve to headings. Add `--baseline HEAD` (or the commit before your change) to report only links you broke — targets that were already missing are listed separately.

```bash
python3 <skill>/scripts/verify_moved.py --before <(git show HEAD:README.md) --after README.md docs/
```

It confirms every non-empty line of the old README still exists somewhere (README or the docs you moved to) and lists the ones that don't, so intended rewrites are visible and accidental losses are caught. Then run the repo's own tests and linters. Report before/after line counts, where each moved section went, and anything the owner must do by hand (e.g. upload a social preview). Ship through the repo's normal flow (branch → PR, or whatever its rules say).
