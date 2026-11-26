<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/brand/wordmark-dark.svg">
  <img alt="dotfiles" src="docs/images/brand/wordmark-light.svg" height="52">
</picture>

# dotfiles

**Unified shell, Git, Vim, and Claude Code configuration across macOS, Linux, WSL, and Windows.**

Symlinked on Unix and copied on Windows, with public defaults separated from private overlays.

![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20WSL%20%7C%20Windows-8B5CF6)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Quick start](#quick-start) · [Claude Code only](#take-only-the-claude-code-config) · [Guide](docs/guide.md) · [Ubuntu manual](setup/MANUAL.md) · [한국어](README.ko.md)

</div>

<p align="center"><img alt="One repo across every machine — macOS, Linux, and WSL symlink; Windows install.ps1 copies" src="docs/img/layout.svg" width="760"></p>

<p align="center"><sub>One repo across every machine: macOS, Linux, and WSL symlink via <code>install.sh</code>; Windows copies via <code>install.ps1</code>.</sub></p>

## Quick start

```bash
gh repo clone <owner>/dotfiles ~/git/dotfiles
~/git/dotfiles/install.sh --profile vanilla     # or personal
```

`install.sh` symlinks shell, Git, Vim, and Claude Code configs into `~` and saves your profile to `~/.config/dotfiles/profile`. `vanilla` installs general-purpose defaults and carries over the git identity from your existing `~/.gitconfig` into `~/.gitconfig.local` (or prompts; pass `--git-name`/`--git-email` for unattended installs); add `--shell` to install zsh, Oh My Zsh and powerlevel10k on a bare server; `personal` clones `personal/` alongside `origin` (overridable via `DOTFILES_PERSONAL_REPO`).

On a fresh machine, run the OS setup script first:

| OS | Bootstrap command | What it sets up |
|---|---|---|
| macOS | `curl -fsSL https://raw.githubusercontent.com/<owner>/dotfiles/main/setup/macos.sh -o setup.sh && bash setup.sh` | Xcode CLT, Homebrew, gh, uv, Oh My Zsh + p10k, Nerd Font, `install.sh --brew` |
| Ubuntu | `bash setup/ubuntu.sh` | apt packages, gh, uv, Node (nvm), Oh My Zsh + p10k, desktop apps, `install.sh --claude-md` |
| WSL | `bash setup/wsl.sh` | apt packages, uv, Oh My Zsh + p10k, Windows desktop fonts, `install.sh` |
| Windows | `pwsh -File windows\setup.ps1` | `winget import` from `windows/winget-packages.json`, `windows/install.ps1` |

Browser logins (GitHub, SSH keys, Google Drive, Claude Code) are documented in [setup/MANUAL.md](setup/MANUAL.md).

## Take only the Claude Code config

You do not need the shell, Git, or Vim parts. The Claude Code pieces are self-contained:

| Piece | File | What it does |
|---|---|---|
| Guard hook | [`claude/hooks/guard.py`](claude/hooks/guard.py) | `PreToolUse` hook that denies secret reads (`.env`, SSH keys, credentials), force-push, destructive deletes and similar, even under `--dangerously-skip-permissions`. It tells Claude the safe alternative, so it routes around the block instead of stalling. Tests: `claude/hooks/test_guard.py` |
| Status line | [`claude/hud/statusline.sh`](claude/hud/statusline.sh) | CPU/memory HUD for the Claude Code status line (needs `jq`) |
| Skills | [`claude/skills/`](claude/skills) | Skills in the standard `SKILL.md` layout (currently `readme-update`) |

```bash
git clone --depth 1 https://github.com/younghwan91/dotfiles /tmp/dotfiles
mkdir -p ~/.claude/hooks ~/.claude/skills
cp /tmp/dotfiles/claude/hooks/guard.py ~/.claude/hooks/
cp -r /tmp/dotfiles/claude/skills/readme-update ~/.claude/skills/      # optional
```

Then register the hook by merging this into `~/.claude/settings.json` (keep your other keys). The `[ -f ... ]` check makes it fail open if the file is ever missing:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Grep",
      "hooks": [{
        "type": "command",
        "timeout": 10,
        "command": "[ -f \"$HOME/.claude/hooks/guard.py\" ] && python3 \"$HOME/.claude/hooks/guard.py\"; exit 0"
      }]
    }]
  }
}
```

Copy rather than symlink if you do not want to keep the clone. The guard is tuned to the author's workflow (for example, it blocks switching branches in `~/git/<repo>` checkouts that cron runs), so read `guard.py` and trim what does not fit. Details are in [docs/guide.md](docs/guide.md#claude-code-guard).

### Try it in a throwaway container

`install.sh` has no dry-run flag, and it rewrites `~`. Run it in a container instead, with `INSTALL_SKIP_SERVICES=1` to skip service and network steps. Nothing touches your host:

```bash
docker run --rm ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -y -qq git python3 ca-certificates >/dev/null
  git clone -q --depth 1 https://github.com/younghwan91/dotfiles /dotfiles
  INSTALL_SKIP_SERVICES=1 /dotfiles/install.sh --profile vanilla </dev/null
  cat ~/.claude/settings.json'
echo '{"tool_name":"Bash","tool_input":{"command":"cat .env"},"cwd":"/tmp"}' | python3 claude/hooks/guard.py   # prints a deny with the safe alternative
```

The `vanilla` profile installs public defaults only. `personal/` is a separate private repo and is never part of this one.

## What's inside

- **One repo, every OS**: Symlinked on macOS, Linux, and WSL (`install.sh`) and copied on Windows (`install.ps1`), so `git pull` or `pull-all` updates every machine in place.
- **Profile separation (`vanilla` / `personal`)**: Keeps reusable public defaults separate from private `personal/` overlays (git identity allowlist, SSH hosts, host crontabs, personal Claude agents).
- **Global Git hooks & local CI**: `pre-commit` identity checks, `commit-msg` English-only guard, and `pre-push` `ci-local.py` running `.github/workflows/ci.yml` in an isolated worktree before push.
- **Cross-host tools**: `bin/pull-all`, `bin/cron-install`, `bin/ssh-keys-sync`, `bin/ssh-fallback`, `bin/repos-doctor`, and `bin/gh-protect` keep repositories, crontabs, and SSH keys in sync.
- **Claude Code HUD & guard**: System-metrics status line (`claude/hud/statusline.sh`) and `PreToolUse` guard (`claude/hooks/guard.py`) blocking secret leaks, destructive commands, and non-`main` branches in cron checkouts.

## Layering and profiles

```text
zsh/zshrc               All OSes
  └ zsh/os/<os>.zsh     darwin · linux · wsl (wsl sources linux first)
      └ ~/.zshrc.local  Machine-specific — secrets, single-host aliases (not committed)
```

No secrets live in this repository. Put API keys, tokens, and host-specific settings in `~/.zshenv.local`, `~/.zshrc.local`, and `~/.gitconfig.local`. See [docs/guide.md](docs/guide.md) for the full symlink map and per-tool reference.

## Docs

| Doc | What's inside |
|---|---|
| [Guide](docs/guide.md) | Layering & symlink map, Secrets, Commit Identity Guard, `pull-all`, `update`, Windows PowerShell & Terminal, Claude Code Status Line & Guard, Checks |
| [Ubuntu manual](setup/MANUAL.md) | Browser-based setup steps for GitHub, SSH keys, Google Drive, and Claude Code |
| [한국어 README](README.ko.md) | Korean overview ([가이드](docs/guide.ko.md)) |

## Contributing

- **PR workflow**: Open a branch and submit a PR (`main` accepts changes via PR only).
- **Commit messages**: Use English Conventional Commits (`feat(install): ...`, `docs(readme): ...`).
- **Checks**: Run `python3 tests/check_no_personal.py` before committing; `pre-push` runs `.github/workflows/ci.yml` locally via `ci-local.py`.

## Tools by the same author

- [kiwoom-client](https://github.com/younghwan91/kiwoom-client): unofficial Kiwoom REST API client for Python and AI agents (182 endpoints, real-time WebSocket, MCP server).
- [fin-checkup](https://github.com/younghwan91/fin-checkup): reads Korean listed companies' financial statements as traffic lights, with formulas and thresholds. Measurements only, no investment advice.
- [kiwoom-order-guard](https://github.com/younghwan91/kiwoom-order-guard): a Claude Code hook that inspects orders an AI agent sends through Kiwoom's official MCP/plugin before they go out.

## License

MIT — see [LICENSE](LICENSE).
