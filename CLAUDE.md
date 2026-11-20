# dotfiles

- **Changes go through a PR**: branch → push → `gh pr create` → `gh pr merge --merge --delete-branch` (self-merge is fine). Never push straight to `main`. Keep `Co-Authored-By` trailers in the commits — merged PRs with co-authored commits are what count.
- **Public repo**: personal values live in the separate private repo cloned at `personal/` (gitignored). Before committing, `python3 tests/check_no_personal.py` must report 0 hits; the pre-push hook runs the full CI (`.github/workflows/ci.yml`) locally.
- **Tests**: every step in `.github/workflows/ci.yml`; add new tests there so both CI and the pre-push hook run them.
