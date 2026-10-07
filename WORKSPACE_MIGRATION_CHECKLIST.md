# Docker workspace migration checklist

Move repositories into Docker volumes and separate active Mac configs from agent-writable files.

## Implementation workflow

Before implementing each change, show the user the concrete changes you intend to make and wait for approval.
Present one proposed approach; do not generate alternatives unless requested.

## Checklist

- [x] Create a Docker volume named `workspace`, separate from `dev-data`.
- [x] Copy existing repositories into `workspace`, preserving Git metadata, branches, uncommitted changes, and untracked files.
- [ ] Verify migrated repositories before deleting the original host copies.
- [x] Restart Docker without the host code-folder bind mount.
- [x] Replace the `${PWD}` bind mounts in `.zshrc` with the `workspace` volume, mounted at `/workspace`.
- [x] Make `dev` open a development shell and `g` open an interactive Git client in that shared workspace.
- [x] Restore the Git client's orange Git prompt and Azure-style terminal exports.
- [x] Remove the host `git()` blocker and the `gclone`, `gfetch`, `glsremote`, `gpull`, and `gpush` aliases.
- [x] Remove `DEV_PROJECT_ROOT` from `.zshrc` and Neovim; derive Java LSP state from the startup repository directory,
      using one Neovim session per repository.
- [x] Create a fresh host-only config clone at `~/config`, outside container mounts.
- [x] Bring changes into the host-only clone, review them, and manually copy approved Zsh and Ghostty configs into place.
- [x] Replace Ghostty's old code-folder include with a manually copied active config.
- [x] Add `dcp <file-or-folder>` to import directly into `/data/shared` in `dev-data`, retaining the source name.
      Uses normal `docker cp` behavior (overwrites files and merges folders) with a temporary stopped development
      container, removed afterward. The development image creates `/data/shared` at build time; the existing volume was initialized
      once manually. User tested successfully on macOS; confirmed `README.md` arrived in `/data/shared`.
- [x] Add `dget <source> <destination-folder>` to export from `/data/shared` into an existing host folder,
      retaining the source name. Implemented with the same stopped dev container, `docker cp --quiet`, and cleanup
      as `dcp`; user successfully exported `dget-test.txt` on macOS.
- [x] Implement transfers with a temporary stopped development container and normal `docker cp` behavior, independent of running
      dev containers. No `--force` option or custom overwrite checks.
- [x] Clean `.DS_Store` from migrated development folders using `fd` inside the container; verified none remain under `/workspace`.
- [x] Include `project` in `.codex/config.toml`'s `terminal_title`.
- [x] Limit Neovim's `<Space>r` file history picker to the current directory with `fzf.history({ cwd_only = true })`.
- [x] Review the migration's security model against the code: `dev` mounts named volumes without host directories;
      transfer helpers mount only `dev-data` and copy explicitly selected paths. Host active configs are manually copied
      from the separate host clone. Review changes before activating host configs or building images on the host;
      verification of actual host paths and running-container mounts remains below.
- [x] Verify persistence after container removal and repository access from both `dev` and `g`.
- [ ] Verify active host configs have no references or symlinks into the old host code folder.
- [ ] Delete the original host code folder at the end of the migration, after verification.

## Deferred

- Changing lazygit's behavior outside a repository.
- Skippable startup directory picker for `dev` and `g`; use `cd` to navigate for now.
- Long-term backups.
