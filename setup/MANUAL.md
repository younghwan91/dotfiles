# Manual steps after `setup/ubuntu.sh`

These steps need a person at a browser or a login screen, so no script can finish them.
An agent can run each command and give the person the code or link. The person only signs in.
Sign in with the accounts this machine's profile is for (`~/.config/dotfiles/profile`; personal accounts: `personal/README.md` in the private personal repo).

## 1. GitHub CLI

```bash
gh auth login -h github.com -p https -w          # prints a one-time code
```
The person enters the code at https://github.com/login/device.
An agent can run this in the background with `< /dev/null` and read the code from its output.

## 2. This machine's SSH key on GitHub

The default login can't manage keys, so request that scope first. This prints another device code:
```bash
gh auth refresh -h github.com -s admin:public_key
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
ssh -T git@github.com                             # expect "Hi <your GitHub user>!"
gh config set git_protocol ssh
git -C ~/git/dotfiles remote set-url origin "git@github.com:$(gh repo view --json nameWithOwner -q .nameWithOwner).git"
```
Without this step, pushes fail: `~/.gitconfig` is the repo's file and has no HTTPS credential helper.

## 3. Google Drive (rclone)

The person runs this from a terminal on the machine's desktop. In Claude Code, type it with the `!` prefix:
```bash
rclone config create gdrive drive scope=drive     # opens the browser on this machine
rclone about gdrive:                              # check
~/git/dotfiles/install.sh                         # enables the ~/gdrive mount (rclone-gdrive.service)
```
On a machine without a desktop, run `rclone authorize "drive"` on a machine that has a browser and paste the token it prints.
rclone's shared Google client_id is being retired in 2026. If logins start failing, create your own client_id (https://rclone.org/drive/#making-your-own-client-id) and add `client_id=… client_secret=…` to the command.

## 4. Claude Code

Sign in with the personal account: `/logout`, then `/login`.

## 5. Desktop only

- Reopen the terminal so the MesloLGS NF font takes effect.
- Log out and back in once so ibus loads the Hangul input source. The Han/Eng key (Right Alt) or Shift+Space toggles between English and Korean.
