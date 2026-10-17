# dotfiles

My personal development environment configuration, managed with
[GNU Stow](https://www.gnu.org/software/stow/).

This is tailored and heavily opinionated entirely for my own workflow and needs,
and mostly exists as a personal reference that I will keep on iterating over
time. Most of this is shaped by the ideas, tools, and configs shared by the
community. Feel free to take inspiration, copy, or use the bootstrap scripts as
you wish for your own setup.

---

## Environments

### Laptop — Windows 11 + Fedora WSL2

Work runs on a Windows 11 laptop. All actual development happens inside a Fedora
Linux WSL2 (recently upgraded to WSL3) distro, with Windows serving as the host
for the terminal (WezTerm).

### PC — CachyOS

Personal machine is a dual-boot setup with a customised partition layout.
Currently on CachyOS & KDE, migrating to Hyprland. As such, bootstrapper
alongside a rice config is in progress.

---

## Tech Stack

| Layer        | Tool                                         |
| ------------ | -------------------------------------------- |
| Terminal     | WezTerm (nightly)                            |
| Shell        | Zsh + Zinit + Starship                       |
| Editor       | Neovim                                       |
| File manager | Yazi                                         |
| Node.js      | fnm + pnpm + Bun                             |
| JVM          | SDKMAN (Java, Maven, Gradle, Groovy, Kotlin) |
| Rust         | rustup                                       |
| Python       | pip + pipx                                   |
| Font         | JetBrainsMono Nerd Font                      |

---

## Repository Structure

```text
dotfiles/
  fedora-wsl/
    bootstrap.ps1          # Windows end-to-end bootstrap orchestrator
    bootstrap.sh           # Linux worker script (can run standalone)
    bootstrap.env.example  # Configuration template - copy and fill in
  zsh/                   # Zsh config (stow target)
  starship/              # Starship prompt config (stow target)
  nvim/                  # Neovim config (stow target)
  tealdeer/              # Tealdeer (tldr) config (stow target)
  wezterm/               # WezTerm config (stow target)
```

---

## Fedora WSL2 Bootstrap

The bootstrap is split into two scripts that work together. bootstrap.ps1 is the
Windows orchestrator — it handles Scoop, WezTerm, fonts, WSL setup, distro
installation, and cloning this repo into WSL. Once that's done it hands off to
bootstrap.sh, which runs as a single long-lived bash process inside the distro
and handles everything on the Linux side. At the end, bootstrap.ps1 takes back
control for one final step: creating the WezTerm config symlink, which requires
a UAC prompt. The whole thing is designed to be walked away from. The only
interaction is accepting UAC at the end.

The bootstrap is tested to be fully functional as of May 2026.

### Prerequisites

Two things must be done manually before running the bootstrap:

**1. WSL must be installed and the PC rebooted** (required on a fresh Windows
install)

```powershell
wsl --install
# Reboot the PC, then continue
```

**2. Git for Windows** (optional — only needed to bridge Windows Git Credential
Manager into WSL)

I use winget for Git:

```powershell
winget install Git.Git
```

If Git is not installed, the bootstrap will warn and skip the credential helper
setup. Everything else still works.

---

### Option A — Full End-to-End Bootstrap (Windows PS1)

A single PowerShell script handles everything: Scoop, WezTerm, fonts, WSL
configuration, Fedora installation, user creation, dotfiles clone, and the full
Linux setup. The only interaction required is one UAC prompt at the very end for
the WezTerm symlink.

**Step 1** — Clone this repo anywhere on Windows:

```powershell
git clone https://github.com/prodicty/dotfiles.git
cd dotfiles/fedora-wsl
```

Only the powershell script and .env file are required to start the bootstrap.
The full dotfiles repo will later be cloned automatically inside WSL.

**Step 2** — Copy the env template and fill in the values:

```powershell
copy bootstrap.env.example bootstrap.env
```

This .env file is required for a full installation from powershell.

> `bootstrap.env` is gitignored and never committed.

**Step 3** — Set execution policy (one-time, required on fresh Windows to
execute script):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Step 4** — Run the bootstrap:

```powershell
.\bootstrap.ps1
```

Doomscroll. The script will:

1. Install Scoop, WezTerm (nightly), and JetBrainsMono Nerd Font
2. Update WSL2 and write `.wslconfig`
3. Install FedoraLinux-44 and create the user account
4. Clone this dotfiles repo into the WSL distro
5. Hand off to `bootstrap.sh` for all Linux setup
6. Prompt once for UAC to create the WezTerm config symlink

Total runtime is roughly 30–60 minutes depending on network speed, including
first Neovim and zsh initializations.

---

### Option B — Linux Script Standalone

If WSL and the distro are already set up and you only need to run the Linux side
(re-provisioning, new machine with existing WSL, or a native Linux install), run
`bootstrap.sh` directly inside the distro:

```bash
cd ~/dotfiles
bash fedora-wsl/bootstrap.sh \
  --git-name "Your Name" \
  --git-email "your@email.com"
```

Optional flags:

| Flag                      | Description                                      |
| ------------------------- | ------------------------------------------------ |
| `--git-name`              | Sets `user.name` in git global config            |
| `--git-email`             | Sets `user.email` in git global config           |
| `--git-credential-helper` | Path to Windows GCM exe (e.g. `/mnt/c/...`)      |
| `--password`              | Sets the user account password non-interactively |

The script is fully idempotent — each phase checks whether its work is already
done before running, so it is safe to re-run after a failure. Delete
`.bootstrap_complete` in the root first if the sentinel is blocking a rerun.

---

### What the Linux Bootstrap Does

| Phase | Description                                                        |
| ----- | ------------------------------------------------------------------ |
| 5     | `dnf upgrade --refresh`                                            |
| 6     | Dev toolchain: gcc, make, rustup, luarocks, pipx, docker, etc.     |
| 7     | CLI tools: zsh, stow, ripgrep, fzf, fd, zoxide, yazi, neovim, etc. |
| 8     | Optional Git global config and Windows GCM bridge                  |
| 9     | Curl installers: Zinit, SDKMAN, Bun, Misc - pipx smassh            |
| 10    | Cargo builds: rustup-init, updater, starship, tree-sitter-cli, fnm |
| 11    | Node.js via fnm: LTS, npm, pnpm                                    |
| 12    | JVM via SDKMAN: Java, Maven, Gradle, Groovy, Kotlin                |
| 13    | Change default shell to Zsh via `usermod`                          |
| 14    | Stow all dotfile packages                                          |
| 15    | Set user password non-interactively via `chpasswd`                 |
| 16    | Remove NOPASSWD sudo rule (restored to default behaviour)          |

---

### Post-Bootstrap Manual Steps

Open Neovim. Plugins will install automatically on the first launch. As of May
2026, there will be 4 irrelevant errors for the unused snacks.image module in
the checkhealth result.

Setup Git for ssh with `ssh-keygen -t ed25519 -C "email"` and add the public
key. Optionally delete the original clone of the repository on Windows.

---

## Stow Package Reference

Each directory in the repo root is a stow package. To apply or re-apply a single
package manually:

```bash
cd ~/dotfiles
stow <package>      # apply
stow -D <package>   # remove
stow -R <package>   # re-apply (remove then apply)
```

---

## Package Manager Reference

| Manager | Purpose                    | Update or self-update commands        |
| ------- | -------------------------- | ------------------------------------- |
| `dnf`   | System packages (default)  | `sudo dnf upgrade --refresh`          |
| `cargo` | Rust tools (bleeding edge) | `cargo install-update --all --locked` |
| `sdk`   | JVM ecosystem              | `sdk update`                          |
| `fnm`   | Node.js versions           | `fnm install --lts`                   |
| `npm`   | Global Node packages       | `npm install -g npm@latest`           |
| `pnpm`  | Node package manager       | `pnpm add -g pnpm@latest`             |
| `bun`   | JS runtime + toolkit       | `bun upgrade`                         |
| `pipx`  | Currently only for Smassh  | `pipx upgrade-all`                    |
