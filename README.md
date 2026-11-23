<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/brand/wordmark-dark.svg">
  <img alt="dotfiles" src="docs/images/brand/wordmark-light.svg" height="52">
</picture>

**English** | [한국어](README.ko.md)

**Unified shell, Git, Vim, and Claude Code configuration across macOS, Linux, WSL, and Windows.**

![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20WSL%20%7C%20Windows-8B5CF6)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

### Key Features

- **One Repo, Every OS**: Symlinked on macOS, Linux, and WSL via `install.sh`, and copied on Windows via `install.ps1` — a single `git pull` (`pull-all`) updates every machine.
- **Profile Separation (`vanilla` / `personal`)**: Keeps public, reusable defaults separate from private `personal/` overlays (identity, host crontabs, SSH hosts, personal agents).
- **Global Git Hooks & Local CI**: `pre-commit` identity checks and `pre-push` `ci-local.py` run `.github/workflows/ci.yml` locally in an isolated worktree before pushing.
- **Claude Code HUD & Guard**: Includes a system-metrics status line (`statusline.sh`) and a `PreToolUse` guard (`guard.py`) that blocks secret leaks and destructive commands.

![One repo across every machine — macOS, Linux, and WSL symlink, Windows install.ps1 copies](docs/img/layout.svg)

### Quick Start

```bash
gh repo clone <owner>/dotfiles ~/git/dotfiles
~/git/dotfiles/install.sh --profile vanilla     # or personal
```

**Profiles**: `vanilla` installs only the general-purpose config; `personal` adds `personal/` (git identity allowlist, personal Claude agents, host crontabs). `personal/` is a separate private repository not included here — if missing, `install.sh` clones `<name>-personal` alongside `origin` (overridable via `DOTFILES_PERSONAL_REPO=<url>`). Your selection is saved in `~/.config/dotfiles/profile` so subsequent `install.sh` runs can omit `--profile`.
`vanilla` skips features that require private values (identity allowlist, blocked domains, peer sync) and prompts for your git name and email to write to `~/.gitconfig.local`.

Because everything symlinks back to this repo, running `git pull` (or `pull-all`) updates every machine in place.
When bootstrapping a fresh machine, run the OS-specific setup script first, then `install.sh`:

| OS | Script | Installs |
|---|---|---|
| macOS | `setup/macos.sh` | Xcode CLT, Homebrew, gh, uv, Oh My Zsh + p10k + plugins, Nerd Font, then `install.sh --brew` |
| Ubuntu | `setup/ubuntu.sh` | apt packages, gh, rclone, SSH server, uv, Node (nvm), docker group, JetPack + jtop on Jetson, Oh My Zsh + p10k + plugins; on desktop: MesloLGS NF + GNOME Terminal font + Korean input (ibus-hangul, Hangul/Eng key) + disable screen blank/sleep + Orca + Chrome + VS Code, then `install.sh --claude-md`, vim plugins, VS Code extensions |
| WSL | `setup/wsl.sh` | apt packages, uv, Oh My Zsh + p10k + plugins, fonts on Windows desktop, then `install.sh` |

Logins requiring a browser (GitHub, SSH keys, Google Drive, Claude Code) cannot be automated by scripts. For Ubuntu, those steps are documented in [`setup/MANUAL.md`](setup/MANUAL.md), and an agent can walk you through them one by one.

On a fresh machine without the repo yet, fetch the setup script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/dotfiles/main/setup/macos.sh -o setup.sh && bash setup.sh
```

## Layering

```
zsh/zshrc               All OSes
  └ zsh/os/<os>.zsh     darwin · linux · wsl (wsl sources linux first)
      └ ~/.zshrc.local  Machine-specific — secrets, single-host aliases (not committed)
```

The OS is detected at shell startup (`uname`, `/proc/version` for WSL), so the same `~/.zshrc` works everywhere.
Git follows the same pattern: `git/gitconfig` includes `~/.gitconfig.local` for credential helpers and machine-specific settings.

| In Repo | Link Target | OS |
|---|---|---|
| `bin/*` | `~/.local/bin/` | All |
| `zsh/zshrc`, `zsh/zshenv` | `~/.zshrc`, `~/.zshenv` | All |
| `zsh/os/*.zsh` | Sourced from `~/.zshrc` | Per-OS |
| `zsh/p10k.zsh` / `zsh/p10k.darwin.zsh` | `~/.p10k.zsh` | Linux·WSL / macOS (different Nerd Font generations) |
| `git/gitconfig` | `~/.gitconfig` | All |
| `git/hooks/` | `~/.config/git/hooks` | All |
| `personal/git/gitconfig`, `allowed-emails`, `blocked-domains` | `~/.config/git/profile.gitconfig`, `~/.config/git/` | `personal` only |

**Git Hooks** (applied globally via `core.hooksPath`) run across all repositories:

- `pre-commit` — checks commit identity (when `~/.config/git/allowed-emails` exists; `personal` rejects if missing). Repos with `.pre-commit-config.yaml` also run `uvx pre-commit run`.
- `commit-msg` — rejects commit messages containing Hangul, kana or CJK ideographs (commit messages are English). One-off override: `COMMIT_MSG_ALLOW_NON_ENGLISH=1`.
- `pre-push` — after identity checks, runs `ci-local.py`: reads the repo's `.github/workflows/ci.yml` and executes its steps against the **commits being pushed** (in a separate worktree + venv under `.git/ci-local/`). Skips `services:` jobs and `uses:` actions, and respects `continue-on-error`. Bypass with `git push --no-verify` or `SKIP_CI_LOCAL=1`.

**Cross-Host Repos & Cron** (peer hosts configured via `sync.peers` in `~/.gitconfig.local`; failure alert script via `sync.alert`):

- `bin/pull-all` — fast-forwards all repos under `~/git`. `--ci-gate` only pulls commits with green GitHub checks (leaves red or pending repos untouched and reports `⏸`); `--check` only reports behind repos.
- `bin/cron-install` — installs `~/git/*/deploy/crontab.<host>` (and `*/personal/deploy/`) as fenced per-repo blocks into the user crontab. Leaves lines outside fences untouched, preserves old blocks if a file is missing, aborts on invalid lines, and backs up previous crontabs to `~/.local/state/cron-install/`.
- `bin/ssh-keys-sync` — syncs `~/.ssh/authorized_keys` across all machines using your GitHub account's public keys + `personal/ssh/authorized_keys` (`install.ps1` on Windows). Adding a key to GitHub propagates it to all machines on the next sync. Leaves `authorized_keys` untouched if GitHub is unreachable or returns 0 keys. `--check` reports only.
- `bin/repos-doctor` — read-only check for silently broken git, hook, or environment setups (`core.hooksPath` pointing to stale paths, broken `.venv` shebangs, dangling global links, etc.). Exits 1 if issues are found.
- `bin/gh-protect` — applies a "main via PR" ruleset (default branch via PR only, 0 required approvals, block force-push and deletion) to each of your public repos. `--check` reports missing repos only. Run daily via cron so new public repos are never missed.
- Cron jobs are updated by editing `deploy/crontab.<host>` in the repo, not `crontab -e`.

Other links:

| In Repo | Link Target | OS |
|---|---|---|
| `vim/vimrc` | `~/.vimrc` — installs Vundle and plugins on first launch | All |
| `npm/npmrc` | `~/.npmrc` | All |
| `linux/systemd/rclone-gdrive.service` | `~/.config/systemd/user/` — mounts Google Drive at `~/gdrive` when `gdrive` remote exists | Linux |
| `claude/hud/statusline.sh` | `~/.claude/hud/` + `statusLine` in `settings.json` | All |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` — **only with `--claude-md`**. Imports `~/.claude/CLAUDE.personal.md` at the end | All |
| `claude/hooks/guard.py` | `~/.claude/hooks/` + `PreToolUse` guard entry and `permissions.deny` in `settings.json` | All |
| `personal/ssh/config` | `~/.ssh/config.d/dotfiles-personal.conf` + `Include config.d/*.conf` at top of `~/.ssh/config` — shared host list across all machines; keys are not synced | `personal` only |
| `personal/claude/agents/*.md`, `personal/claude/CLAUDE.md` | `~/.claude/agents/`, `~/.claude/CLAUDE.personal.md` | `personal` only |
| Orca skills `orca-cli`, `orchestration`, `computer-use` | Installed via `orca skills install` to `~/.agents/skills/` + `~/.claude/skills/` when Orca CLI is present (`orca-ide` on Linux) | All |
| `macos/karabiner.json` | `~/.config/karabiner/` | macOS |
| `macos/vscode/settings.json` | VS Code user settings | macOS · Linux desktop |
| `macos/Brewfile` | `brew bundle` — **only with `--brew`** | macOS |
| `macos/vscode/extensions.txt` | Installed by `setup/ubuntu.sh`; import manually on macOS | macOS · Linux desktop |
| `macos/brew_*.txt` | Reference / manual import | macOS |

## Secrets

No secrets live in this repository. API keys, passwords, and tokens go into `*.local` files:

| File | Purpose |
|---|---|
| `~/.zshenv.local` | Environment variables needed by non-interactive commands (`ssh host cmd`, cron) |
| `~/.zshrc.local` | Interactive-only aliases and functions |
| `~/.gitconfig.local` | Credential helper and host-specific git config |

## Commit Identity Guard

`git/hooks` run in every repo (repo-local hooks run first):
`pre-commit` rejects authors/committers not listed in `~/.config/git/allowed-emails`, and `pre-push` also rejects commit messages containing domains from `~/.config/git/blocked-domains`.
Both files are linked by the `personal` profile. In `vanilla`, if the files are absent, those checks are skipped.
The allowlist matches the repo CI's Commit Identity Guard — agent attribution belongs in `Co-Authored-By`, never as the commit author.

## `pull-all`

Fast-forwards all git repositories in a directory tree.

```bash
pull-all                    # Repos under $PULL_ALL_ROOT or ~/git
pull-all ~/src ~/work       # Repos under these directories
pull-all -j 8               # Fetch 8 repos in parallel (default: 4)
ssh other-host pull-all     # Same on another machine
```

Only fast-forwards. Anything requiring judgment is reported and left untouched:

| | |
|---|---|
| `✓` | Already up to date (`↑` if unpushed commits exist) |
| `↓` | Fast-forwarded |
| `●` | Skipped — uncommitted changes or detached HEAD |
| `–` | No upstream branch |
| `✗` | Fetch failed or diverged history |

Disables SSH host-key and credential prompts so it never hangs. Disables color when stdout is not a TTY or `NO_COLOR` is set. Exits non-zero if any repo fails.

## `update`

Run whenever you want to bring a machine up to date. Prints `==> [n/N]` per step; if one step fails, it continues through the rest and summarizes failures at the end.

| | Linux · WSL (`zsh/os/linux.zsh`) | Windows (`windows/bin/update.cmd`) |
|---|---|---|
| Packages | `apt update` → `full-upgrade` → `autoremove`, `snap` | `winget` (single UAC prompt) |
| Tools | `uv tools`, global `npm` | `uv tools`, global `npm` |
| OS | Lists firmware updates only (`fwupdmgr update` to install), notifies if reboot needed | Windows Update (lists drivers/firmware only), `wsl --update` |

Passing arguments like `update install foo` forwards directly to `apt` (`winget` on Windows).

## Windows (PowerShell)

`windows/bin/*` are the Windows counterparts to zsh aliases. `install.ps1` copies them to `~\.local\bin`:

```powershell
pwsh -File C:\dev\git\dotfiles\windows\install.ps1
```

| Command | What It Does |
|---|---|
| `update` | Prints `==> [n/5]` per step: `uv tool upgrade --all`, global `npm update -g`, elevated `winget upgrade --all` after one UAC prompt (+ lists remaining outdated packages), Windows Update software updates (drivers/firmware listed only; no auto-reboot), `wsl --update`. For Linux/WSL see [`update`](#update) above |
| `update --check` | List available `winget` upgrades only |
| `update install foo` | Forward any other arguments directly to `winget` |
| `cla` | `claude --dangerously-skip-permissions` |
| `doctor` | Read-only check for recurring issues: whether `WSLService` is stopped, whether common apps are missing from startup; prints fix instructions |

Fresh machine: `pwsh -File windows\setup.ps1` runs `winget import` from `windows/winget-packages.json` (the Windows Brewfile equivalent), then runs `install.ps1`. Refresh the list with `winget export -o windows\winget-packages.json` and strip runtimes/frameworks (they pull in automatically as dependencies).

`windows/bin` uses `.cmd` shims instead of PowerShell profile functions by design: they work in `cmd`, Windows PowerShell 5.1, and `pwsh` 7 alike without relying on `Documents` (which Defender Controlled Folder Access may lock) or execution policies (5.1 ships with scripts disabled).

### Terminal Appearance

![Windows Terminal — Shades of Purple theme, JetBrains Mono, pill-shaped Starship prompt](docs/img/windows-terminal.svg)

`install.ps1` brings the Linux zsh + p10k look to Windows:

| In Repo | What It Does |
|---|---|
| `windows/terminal/shades-of-purple.json` | Merges the Shades of Purple color scheme + `JetBrainsMono NFM` font into Windows Terminal, leaving only PowerShell 7 in the menu (hides cmd and Windows PowerShell without deleting them) |
| `windows/starship.toml` | `~\.config\starship.toml` — pill-shaped [Starship](https://starship.rs) prompt modeled after p10k rainbow |
| `windows/powershell/profile.ps1` | `~\.config\powershell\profile.ps1` — initializes Starship & zoxide and defines Linux-style commands (`ls`/`ll` via `eza`, `cat` via `bat`, `grep` via `rg`, `which`, `touch`, `head`, `tail`, `wc`, `sudo`, `gs`/`gl`/`gd`) |
| `windows/orca/shades-of-purple.json` | Applies the same theme to the Orca terminal (only when Orca is not running) |

The profile lives outside `Documents` (`~\.config\powershell\profile.ps1`) because Controlled Folder Access blocks creating `Documents\PowerShell`. Instead, the all-users profile in the PowerShell install folder (`C:\Program Files\PowerShell\7\profile.ps1`, written once when running `install.ps1` as Administrator) sources it so Windows Terminal, Orca, VS Code, and standalone `pwsh` all share the same prompt and commands. Fonts and tools (`starship`, `eza`, `bat`, `ripgrep`, `zoxide`, `fzf`, `delta`, `lazygit`) are listed in `winget-packages.json`.

## Claude Code Status Line

`claude/hud/statusline.sh` — displays model, directory & git branch, context/usage limits, CPU / memory / temperature / GPU, weather, host, and session name. Omits segments unavailable on the machine (no GPU, no sensors, no `node`). Requires `jq`.

Also works in Git Bash on native Windows: converts backslashes in `cwd` and fetches CPU/memory from PowerShell (cached, refreshed in the background). Because `install.sh` is bash-only, configure `statusLine.command` manually in `~/.claude/settings.json` pointing to Git's bash by full path — plain `bash` resolves to WSL's `bash.exe` on Windows hosts and fails to find the script:

```json
"statusLine": {"type": "command", "command": "\"C:/Program Files/Git/bin/bash.exe\" \"C:/Users/<you>/.claude/hud/statusline.sh\""}
```

Install `jq` first (`winget install jqlang.jq`).

Only the `statusLine` key is modified in `~/.claude/settings.json`; other hooks, `env`, and plugins remain per-machine.

## Claude Code Guard

`claude/hooks/guard.py` is a `PreToolUse` hook (Bash, Read, Edit, Write, Grep) that enforces guardrails even under `--dangerously-skip-permissions`:

- **Secret Leak Prevention**: Blocks reading, printing, copying, or sending `.env` and variants (templates like `.env.example` are allowed), `~/.claude/.credentials.json`, SSH private keys, `~/.zshenv.local`, and `~/.pgpass`, as well as dumping the environment after sourcing (`env`, `printenv NAME`, `echo $..._DB/KEY/TOKEN`, `set -x`). Allowed: sourcing for execution (`set -a; . ./.env; set +a`, `export $(grep -v '^#' .env | xargs)`, `source <(grep ...)`), listing key names only (`cut -d= -f1`, `sed 's/=.*//'`, `grep -o '^NAME'`), existence checks (`grep -q`, `[ -n "$VAR" ]`), and non-secret keys selected by name (`grep '^TIMESCALE_HOST=' .env`).
- **Irreversible Actions**: Blocks force-push (`--force-with-lease` is allowed), dropping/truncating shared DB tables (including via psql/sqlite heredocs), wiping or overwriting crontab (repos own `deploy/crontab.<host>`; use `cron-install`), deleting Docker volumes (single copy of DB), rebooting/powering off, recursive deletion of `/`, `~`, `~/git`, `.`, or `.git`, and un-messaged `git stash` / `pop` / `clear` / bare `drop` (the stash stack is shared across all worktrees).
- **Production Checkouts**: Blocks switching or creating non-`main` branches in `~/git/<repo>` checkouts used by cron (use a worktree instead).

Commands are parsed with quotes, `$( )`, and heredocs in mind: text written to files via heredocs and python heredoc bodies are not parsed as shell commands. Hook entries fail open (missing file → allow). Tests: `python3 claude/hooks/test_guard.py` and `claude/hooks/test_guard_extra.py` (also replayed against ~15,000 historical tool calls). `install.sh` also merges `permissions.deny` rules for home-directory secret files.

## Checks

Steps in `.github/workflows/ci.yml` run in both GitHub Actions and the `pre-push` hook (`ci-local.py`). `main` accepts changes via PR only.

| Category | Scripts |
|---|---|
| Static Analysis | `tests/test_shellcheck.sh` (style, `-x`), `tests/test_ruff.sh`, `tests/test_psscriptanalyzer.sh`, `tests/test_actionlint.sh`, `tests/test_typos.sh` |
| Public Repo | `tests/check_no_personal.py` (also runs on commit) and its self-test `tests/test_check_no_personal.sh` |
| Windows Files | `tests/test_powershell.sh` (parse), `tests/test_ps1_ascii.sh`, `tests/test_eol.sh` (`.cmd` must be CRLF) |
| Behavior | `install`, `cron-install`, `pull-all`, `repos-doctor`, `ssh-keys-sync`, `gh-protect`, `update`, identity hooks, Claude guard — `tests/test_*.sh`, `claude/hooks/test_guard*.py` |

## License

MIT — see [LICENSE](LICENSE).
