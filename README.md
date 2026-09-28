# myles-omarchy-plugins

The installer and auto-updater for the Omarchy plugin suite published by the
[Omarchy-plugin](https://github.com/Omarchy-plugin) organisation.

One command installs every plugin in the suite and sets up automatic updates, so
an improvement pushed to a plugin repo reaches every machine that installed it
without anyone running an update command.

## Install

```bash
git clone https://github.com/Omarchy-plugin/myles-omarchy-plugins.git
cd myles-omarchy-plugins
./install.sh
```

That installs the plugins, disables the stock Omarchy widgets they replace,
installs the updater to `~/.local/bin/`, and enables a systemd user timer.

Options:

| Flag | Effect |
| --- | --- |
| `--no-hooks` | Install the plugins but do not set up the updater or timer |
| `--only <id>` | Install a subset, e.g. `--only myles.clock,myles-network` |

Re-running is safe. A plugin already installed from this organisation is
**updated** rather than reinstalled, so its settings and history survive.

## The suite

| Plugin | Replaces | What it is |
| --- | --- | --- |
| [myles-clock](../myles-clock) | `omarchy.clock` | Calendar clock with merged world-clock places and holiday markers |
| [myles-network](../myles-network) | `omarchy.network` | Subnet warnings, IPv4 recovery, profile backups, Proton VPN |
| [myles-agents](../myles-agents) | `omarchy.agents` | Every coding agent ranked by token usage, with trends and launch |
| [myles-usage](../myles-usage) | — | Active/idle tracking, searchable reports, goals, timers |
| [myles-calculator](../myles-calculator) | — | Scientific, programmer, live FX, units, tip/VAT |
| [myles-appearance-picker](../myles-appearance-picker) | — | Grouped theme and wallpaper picker |
| [myles-workspaces](../myles-workspaces) | `omarchy.workspaces` | Workspace number indicators |
| [omarchy-myles-media](../omarchy-myles-media) | `omarchy.media` | Media hub: Spotify, YouTube, Radio Garden, PiP, casting |

## Updates

Three layers, so a fix lands whether or not the machine is awake:

1. **Timer** — a systemd user timer runs the updater every 30 minutes with
   jitter, and catches up after sleep via `Persistent=true`.
2. **Omarchy hooks** — `post-update.d` and `post-boot.d` run it after a system
   update and after boot.
3. **On demand** — `omarchy plugin update --yes`, or per plugin
   `omarchy plugin update myles.clock --yes`.

An update is a `git fetch` plus a fast-forward, so **local edits inside a plugin
folder will block its own update** ("cannot fast-forward; you have local
changes"). Commit and push your work, or move it aside, to resume updates.

`omarchy plugin update` re-validates the plugin folder after merging and rolls
back if validation fails, and the updater calls `rescanPlugins` on success, so
new code is picked up by the running shell without a logout. A bad push cannot
leave you with a broken shell.

## Scope

The updater only touches plugins whose id starts with `myles.`. Third-party
plugins you installed from elsewhere are never silently updated by it — use
`omarchy plugin update <id>` for those. Override the prefix with
`MYLES_PLUGIN_PREFIX` if you fork this suite under a different namespace.

## Verifying

```bash
omarchy plugin list                                   # what is installed and enabled
systemctl --user list-timers myles-plugin-update.timer # is the timer scheduled
systemctl --user status myles-plugin-update.service    # did the last run work
omarchy-myles-plugin-update                           # run it now, by hand
```

Log: `~/.local/state/omarchy/myles-plugin-update.log`

## Uninstalling the updater

```bash
systemctl --user disable --now myles-plugin-update.timer
rm ~/.config/systemd/user/myles-plugin-update.{timer,service}
rm ~/.config/omarchy/hooks/{post-update.d,post-boot.d}/10-myles-plugin-update
rm ~/.local/bin/omarchy-myles-plugin-update
```

The plugins themselves are independent; remove them with
`omarchy plugin remove <id> --yes`.

## Security

Omarchy plugins run **unsandboxed** inside the long-lived `omarchy-shell`
process with your user permissions. Every plugin in this suite can read your
files and run commands as you. Install only from repos you trust, and read the
source before enabling it.

Each plugin's README documents its external commands, network calls, and any
privilege boundary.

## Credits

- Omarchy — <https://omarchy.org> — MIT, © David Heinemeier Hansson
- Mylesoft — <https://github.com/Omarchy-plugin>
