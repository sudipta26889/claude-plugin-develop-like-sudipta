# develop-like-sudipta — Claude Code Plugin Marketplace

## Install

```bash
/plugin marketplace add sudipta26889/claude-plugin-develop-like-sudipta
/plugin install develop-like-sudipta
```

See [develop-like-sudipta/README.md](./develop-like-sudipta/README.md) for full documentation.

## What this plugin is

`develop-like-sudipta` is a Claude Code plugin for development discipline: slash commands, skills, agents, and hooks that check edits and completion. It installs per computer, not per Claude account. To see what a computer has installed, run `claude plugin list`.

The same install from a shell:

```bash
claude plugin marketplace add sudipta26889/claude-plugin-develop-like-sudipta
claude plugin install develop-like-sudipta@claude-plugin-develop-like-sudipta
```

## This plugin and sd-claude-mods

This plugin and [sd-claude-mods](https://github.com/sudipta26889/sd-claude-mods) are two separate things. You install each one on its own.

Installing or updating this plugin does not install any mods, including `secret-guard`. Installing the mods does not change this plugin. Neither depends on the other.

To install the mods, see the [sd-claude-mods README](https://github.com/sudipta26889/sd-claude-mods#readme).

## Updates

`main` is protected, so every change goes through a pull request. A merge alone does not reach installed computers:

- **The version must change.** A computer only gets a merged change once `version` in `develop-like-sudipta/.claude-plugin/plugin.json` changes. Until then, updating reports `already at the latest version`.
- **Auto-update is off by default for this marketplace.** You can turn it on under `/plugin` > Marketplaces. Or update by hand, then restart Claude Code:

  ```bash
  claude plugin marketplace update claude-plugin-develop-like-sudipta
  claude plugin update develop-like-sudipta@claude-plugin-develop-like-sudipta
  ```

With auto-update on, a version bump arrived in a test after a message was sent and about 11 minutes passed; a commit without a bump did not. The auto-update default comes from the Claude Code docs.
