# Docker workspace migration checklist

Move repositories into Docker volumes and separate active Mac configs from agent-writable files.

## Implementation workflow

Before implementing each change, suggest three viable, materially different approaches. Put the simplest approach that
meets the requirements first and label it `(Recommended)`. Wait for the user's choice before implementation.
If fewer than three viable approaches exist, present those without inventing filler. This applies especially to the
skippable folder picker.

## Checklist

- [x] Create a Docker volume named `workspace`, separate from `dev-data`.
- [x] Copy existing repositories into `workspace`, preserving Git metadata, branches, uncommitted changes, and untracked files.
- [ ] Verify migrated repositories before deleting the original host copies.
- [x] Restart Docker without the host code-folder bind mount.
- [x] Replace the `${PWD}` bind mounts in `.zshrc` with the `workspace` volume, mounted at `/workspace`.
- [x] Make `dev` open a development shell and `g` open an interactive Git client in that shared workspace.
- [x] Remove the host `git()` blocker and the `gclone`, `gfetch`, `glsremote`, `gpull`, and `gpush` aliases.
- [ ] Remove `DEV_PROJECT_ROOT` from `.zshrc` and Neovim; derive Java LSP state from the startup repository directory,
      using one Neovim session per repository.
- [ ] Create a fresh host-only config clone at `~/config`, outside container mounts.
- [ ] Pull changes into that clone, review them, and manually copy approved configs into their active Mac locations.
- [ ] Update active config loading paths and dependencies so they no longer load agent-writable files.
- [ ] Add `dcp <file-or-folder>` to import directly into `/data/shared` in `dev-data`, retaining the source name.
- [ ] Add `dget <source> <destination-folder>` to export from `/data/shared` into an existing host folder,
      retaining the source name.
- [ ] Implement transfers with a temporary lightweight container and normal copy behavior, independent of running dev
      containers. Refuse overwrites unless `--force` is supplied; forced folder overwrites replace the whole target item.
- [ ] Clean `.DS_Store` from migrated development folders using `fd` inside the container.
- [ ] Include `project` in `.codex/config.toml`'s `terminal_title`.
- [ ] Remove `.config/lazygit.yml`'s `notARepository: quit` override.
- [ ] Limit Neovim's `<Space>r` file history picker to the current directory with `fzf.history({ cwd_only = true })`.
- [ ] Review the migration's security model against the code, focusing on volume mounts and host config separation.
- [ ] Verify persistence after container removal, access from both clients, and separation from active host configs.
- [ ] Delete the original host code folder at the end of the migration, after verification.

## Deferred

- Skippable startup directory picker for `dev` and `g`; use `cd` to navigate for now.
- Long-term backups.
