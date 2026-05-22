# Contributing

## Getting Started

Install the plugin in Claude Code:

```bash
/plugin install harness@youngwhy
```

This registers all skills, agents, and hooks defined by the plugin. No npm install is needed — the plugin's CLI, **harness-cli** (`scripts/cli.sh`, pure bash + jq), ships bundled.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/youngwhy/harness.git
   cd harness
   git checkout develop
   ```

2. Verify the bundled CLI runs (requires `jq`):
   ```bash
   bash scripts/cli.sh --version
   ```

### Directory Structure

```
harness/
  .claude/
    skills/       # Skill definitions (SKILL.md per skill)
    agents/       # Agent definitions (.md files)
    scripts/      # Hook scripts (must be chmod +x)
    settings.json # Hook registrations and plugin config
  .claude-plugin/
    plugin.json       # Plugin metadata + version
    marketplace.json  # Marketplace listing + version
  scripts/
    cli.sh        # harness-cli — bundled bash CLI (pure bash + jq)
  docs/           # Documentation and learnings
  .playground/    # Experiments (git-ignored)
```

## Plugin Structure

- **Skills** live in `.claude/skills/<skill-name>/SKILL.md`. Each skill has YAML frontmatter (name, description, optional `validate_prompt`) and a markdown body defining its behavior.
- **Agents** live in `.claude/agents/<agent-name>.md` with the same frontmatter convention.
- **Hooks** are shell scripts in `.claude/scripts/`. A hook script must be both executable and registered in `.claude/settings.json` under `hooks.<EventType>.matchers[]` to fire. Creating the file alone is not enough.

## Git Workflow

| Branch | Purpose |
|--------|---------|
| `main` | Release only. Never commit directly. |
| `develop` | Integration branch. All feature branches merge here. |
| `feat/<name>` | Feature branches. Created from `develop`. |

### Rules

- Create feature branches from `develop`:
  ```bash
  git checkout develop && git checkout -b feat/my-feature
  ```
- Merge back to `develop` with `--no-ff`:
  ```bash
  git checkout develop && git merge feat/my-feature --no-ff
  ```
- Release merges go from `develop` into `main` (also `--no-ff`).

## Versioning

Two files must be bumped together in a single commit on `develop`:

1. `.claude-plugin/plugin.json`
2. `.claude-plugin/marketplace.json`

The CLI (`harness-cli` = `scripts/cli.sh`) ships inside the plugin, so there is no separate package version to sync.

## Testing

This project uses a 4-Tier Testing Model:

1. **Unit** -- individual function/module tests
2. **Integration** -- cross-module interaction tests
3. **E2E** -- full workflow tests
4. **Agent Sandbox** -- agent-level behavioral tests

See [VERIFICATION.md](VERIFICATION.md) for full details and conventions.

## Submitting Changes

1. Create a feature branch from `develop`:
   ```bash
   git checkout develop && git checkout -b feat/descriptive-name
   ```
2. Make your changes. Use `.playground/` for any experimentation.
3. Ensure hook scripts are executable (`chmod +x .claude/scripts/*.sh`).
4. If you added a new hook, register it in `.claude/settings.json`.
5. Open a pull request targeting `develop`.
6. In the PR description, summarize what changed and why.
