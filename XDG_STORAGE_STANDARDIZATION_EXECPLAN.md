# XDG Storage Standardization ExecPlan

## Purpose and Context

Standardize persistent XDG storage for the development container while keeping repository-owned configuration and
image-provisioned application assets outside mutable Docker volumes. After implementation, XDG-aware applications will
write durable user data to `/data/share`, durable user state to `/data/state`, and disposable cache data to
`/data/cache`. The existing `dev-data` named volume mounted at `/data` will persist all three categories.

The observable target environment is:

```bash
XDG_DATA_HOME=/data/share
XDG_STATE_HOME=/data/state
XDG_CACHE_HOME=/data/cache
```

`XDG_CONFIG_HOME` will remain unset, so repository-managed configuration copied into `/root/.config` stays part of the
image. `XDG_RUNTIME_DIR` will remain unset, so sockets, locks, and other runtime-only files remain under an ephemeral
temporary directory. `XDG_CONFIG_DIRS` and `XDG_DATA_DIRS` will retain their system defaults.

The current repository exports only `XDG_CACHE_HOME=/data/cache` in `docker/.bashrc`. `.zshrc` mounts `dev-data` at
`/data`, but it also mounts `dev-opencode-home` directly at `/root/.local/share/opencode`. OpenCode therefore currently
uses `/root/.local/share/opencode` for data, `/root/.local/state/opencode` for state, and `/data/cache/opencode` for
cache. The dedicated OpenCode mount will be removed after the global data and state homes are defined.

Neovim is the material exception that must be handled before changing `XDG_DATA_HOME`. Its configuration is copied to
`/root/.config/nvim`, but the Docker build currently runs Neovim with its default data home. `vim.pack` installs plugins
and nvim-treesitter installs compiled parsers under `/root/.local/share/nvim/site`; the current image contains about
97 MB there. Merely redirecting `XDG_DATA_HOME` would make those image-provisioned assets unavailable and cause runtime
installation attempts. The implementation will instead provision plugins and parsers into the system data location
`/usr/local/share/nvim/site` and load them from Neovim's normal system `packpath` at runtime.

This is a clean cutover. Do not migrate data from `/root/.local/share/opencode`, preserve compatibility with the old
layout, seed the new layout from the old named volume, or add transitional detection. After the new layout passes
cross-container persistence validation, the obsolete `dev-opencode-home` volume will be removed manually on the
Docker-capable host. No other named volume will be removed.

The completed result must preserve the existing OpenCode key-injection policy, OpenCode and Neovim configuration,
Neovim features, and the container's other explicit storage locations such as `/root/.codex`, `/root/.m2`,
`GOMODCACHE`, and `GRADLE_USER_HOME`.

## Plan of Work

### Milestone 1: Separate Neovim image assets from user data

Affected files and interfaces:

- `.config/nvim/init.lua`: plugin provisioning/loading and Tree-sitter parser installation.
- `docker/Dockerfile`: the image-build Neovim invocation and system data destination.
- Neovim interfaces: `vim.pack`, `packpath`, `stdpath()`, and nvim-treesitter's parser runtime paths.

Steps:

1. Keep the existing plugin specification in one authoritative list in `init.lua`, but distinguish image provisioning
   from normal runtime startup with a build-only environment flag supplied by the Dockerfile.
2. During image provisioning, run Neovim with `XDG_DATA_HOME=/usr/local/share` so `vim.pack` installs its managed
   optional packages beneath `/usr/local/share/nvim/site/pack/core/opt`.
3. Run the existing nvim-treesitter parser installation only during image provisioning so compiled parsers and parser
   metadata land beneath `/usr/local/share/nvim/site`.
4. During normal startup, load the named optional packages from the system `packpath` without invoking `vim.pack.add`
   or nvim-treesitter installation. Image rebuilds, rather than the persistent data volume, remain the update mechanism
   for plugins and parsers.
5. Do not redirect Neovim configuration, add a Neovim-specific volume, or copy image assets into `/data`.

Validation and expected results:

- The image build contains every configured plugin under `/usr/local/share/nvim/site/pack/core/opt` and every selected
  parser under `/usr/local/share/nvim/site/parser`.
- With `XDG_DATA_HOME=/data/share`, Neovim's `packpath` still includes `/usr/local/share/nvim/site`.
- A headless runtime launch loads representative plugins such as `gruvbox.nvim` and `nvim-treesitter` without network
  access or a runtime installation beneath `/data/share/nvim/site/pack/core/opt`.
- A representative configured parser starts successfully, and normal headless startup exits successfully.

Recovery:

- If runtime loading fails, inspect `:set packpath?`, confirm the package names derived from the plugin specifications,
  and confirm the system package and parser directories exist in the image.
- Reverting the `init.lua` and Dockerfile changes restores the current user-data installation behavior after rebuilding
  the image; no volume deletion is required.

### Milestone 2: Define the persistent XDG homes

Affected files and interfaces:

- `docker/.bashrc`: interactive container environment inherited by OpenCode, Neovim, and their child processes.
- `docker/Dockerfile`: creation of the target directory structure where useful for deterministic image validation.
- XDG interfaces: `XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME`.

Steps:

1. Add `XDG_DATA_HOME=/data/share` and `XDG_STATE_HOME=/data/state` alongside the existing
   `XDG_CACHE_HOME=/data/cache` export in `docker/.bashrc`.
2. Keep `XDG_CONFIG_HOME`, `XDG_RUNTIME_DIR`, `XDG_CONFIG_DIRS`, and `XDG_DATA_DIRS` unset.
3. Ensure `/data/share`, `/data/state`, and `/data/cache` are valid root-owned directories. Preserve the existing
   `/data/cache/gomod`, `/data/cache/npm`, and `/data/gradle` initialization and the explicit Go and Gradle variables.
4. Do not change the `ocgrok` function or persist `XAI_API_KEY`; the key must remain scoped to the OpenCode child
   process exactly as it is now.

Validation and expected results:

- A new interactive container reports the three intended XDG home variables and no user config or runtime override.
- `nvim --headless` reports `/root/.config/nvim`, `/data/share/nvim`, `/data/state/nvim`, and `/data/cache/nvim` for its
  config, data, state, and cache paths respectively; its runtime directory remains temporary.
- OpenCode reports `/root/.config/opencode`, `/data/share/opencode`, `/data/state/opencode`, and
  `/data/cache/opencode` for its config, data, state, and cache paths respectively; its temporary path remains under
  `/tmp`.
- Repository-managed Neovim and OpenCode configuration continues to resolve from the image rather than the volume.

Recovery:

- Remove only the new data and state exports to restore their default `/root/.local` locations. The existing cache
  behavior remains independent.
- Do not delete `/data` while diagnosing an environment problem because it will contain durable application data and
  state after this change.

### Milestone 3: Consolidate OpenCode onto the shared XDG layout

Affected files and interfaces:

- `.zshrc`: Docker named-volume mounts used by `dev()`.
- `OPENCODE_GROK_TODOLIST.md`: superseded OpenCode persistence decision and final documented paths.
- OpenCode paths: data, logs, repositories, session database, state, cache, and optional native credentials.

Steps:

1. Remove the `dev-opencode-home` mount from `dev()`; retain the single `dev-data` mount at `/data`.
2. Do not copy or inspect the old OpenCode data, add a migration command, retain an old-path fallback, or conditionally
   mount the dedicated volume.
3. Update the OpenCode contingency checklist to record that the earlier dedicated-volume decision is superseded by the
   global XDG layout. Document the resulting paths and that `/data` now contains both durable data/state and disposable
   caches.
4. Leave the dedicated Codex and Maven mounts and the `/workspace` bind mount unchanged.

Validation and expected results:

- `/proc/self/mountinfo` shows `dev-data` mounted at `/data` and no mount at `/root/.local/share/opencode`.
- A fresh OpenCode launch creates its database, sessions, logs, and related data under `/data/share/opencode` and its
  TUI/model/prompt state under `/data/state/opencode`.
- OpenCode does not create a replacement data or state tree under `/root/.local` during normal operation.
- The hidden API-key prompt still leaves no key in configuration, data, state, cache, logs, shell history, or command
  arguments; exposure remains limited to the OpenCode process and unrestricted children it launches.

Recovery:

- Re-add the exact `dev-opencode-home` mount and remove the global data/state exports to restore the previous path
  model, then rebuild the image and recreate the container.
- Retain the old named volume until the new layout has passed validation if a convenient rollback source is desired,
  but do not add migration or compatibility logic to the repository.

### Milestone 4: Rebuild and validate the complete storage contract

Affected interfaces:

- Host-side image build and `dev()` container recreation.
- OpenCode diagnostics and session/TUI persistence.
- Neovim configuration, plugins, parsers, data, state, cache, and runtime behavior.

Steps:

1. Run focused static checks inside the current container after editing: inspect the shell exports and mounts, parse the
   changed Lua through a headless Neovim invocation where possible, and inspect the task diff.
2. Build `ddadon/dev:current` on the Docker-capable host and start a fresh `dev` container. A clean `dev-data` volume is
   acceptable; no old OpenCode data must be retained.
3. Validate all resolved OpenCode and Neovim paths, the absence of config/runtime redirection, and the presence of
   system-installed Neovim plugins and parsers.
4. Launch Neovim normally and exercise colorscheme loading, Tree-sitter highlighting, and one configured plugin-backed
   command. Confirm startup does not populate the persistent user data directory with image-managed packages.
5. Launch OpenCode through `ocgrok`, complete a harmless Grok request, toggle a TUI preference such as sidebar
   visibility, and exit cleanly.
6. Recreate the `--rm` container and verify that the OpenCode session and TUI preference survive under `/data`, while
   the xAI key must be supplied again and runtime files do not survive.
7. Confirm the Codex and Maven volumes, project bind mount, Go module cache, Gradle home, npm cache, and existing
   repository-managed configuration still resolve as before.

Validation commands and expected evidence include:

```bash
env | sort | rg '^XDG_'
opencode debug paths
nvim --headless '+lua for _, k in ipairs({"config", "data", "state", "cache", "run"}) do print(k, vim.inspect(vim.fn.stdpath(k))) end' +qa
nvim --headless '+lua assert(pcall(require, "gruvbox")); assert(pcall(require, "nvim-treesitter"))' +qa
```

The expected XDG output contains only the three home variables. OpenCode and Neovim must resolve the paths specified in
Milestone 2. Neovim must find its configured plugins and parsers in `/usr/local/share/nvim/site`, while OpenCode data
and state must survive one full container recreation through the `dev-data` volume.

Recovery:

- If the rebuilt container is unusable, revert the implementation commit, rebuild the previous image, and recreate the
  container. Do not remove any named volume as part of rollback.
- If only cache contents are corrupt, stop relevant processes and clear the affected child directory beneath
  `/data/cache`; never treat all of `/data` as disposable after this change.
- If a persistent application state causes a startup problem, move only that application's directory beneath
  `/data/state` aside and retry, preserving it for inspection.

### Milestone 5: Remove the obsolete OpenCode volume manually

Affected interfaces:

- Host-side Docker containers and the `dev-opencode-home` named volume.
- Persistent OpenCode data already validated beneath `/data/share/opencode` and `/data/state/opencode`.

Precondition:

- Complete Milestone 4 successfully, including recreating the container and verifying that OpenCode data and state
  survive through `dev-data`. Do not remove the old volume before this validation provides the rollback checkpoint.

Steps:

1. Exit the development container so the `--rm` container is removed, then confirm that no remaining container
   references `dev-opencode-home`:

   ```bash
   docker ps -a --filter volume=dev-opencode-home --format '{{.ID}} {{.Names}}'
   ```

   The command must produce no output. If it lists a container, inspect and remove that container only after confirming
   it is the obsolete development container; do not force-remove the volume from an unknown container.
2. Confirm the exact named volume exists with `docker volume inspect dev-opencode-home`, then remove only that volume:

   ```bash
   docker volume rm dev-opencode-home
   ```

3. Confirm `docker volume inspect dev-opencode-home` now reports that the volume does not exist. Retain `dev-data`,
   `dev-codex-home`, and `dev-maven`; none is obsolete under the new layout.

Validation and expected results:

- `dev-opencode-home` no longer exists and is no longer referenced by `.zshrc` or any container.
- Starting `dev` does not recreate `dev-opencode-home`; OpenCode continues using the shared `dev-data` mount.
- OpenCode sessions and TUI state validated in Milestone 4 remain available.

Recovery:

- Volume deletion is irreversible within this repository. If old OpenCode data might still be needed, stop before
  `docker volume rm` and retain the volume until it has been backed up or is no longer required.
- If the removed volume is unexpectedly recreated, recheck the active `.zshrc` definition and any other host scripts
  for a stale `dev-opencode-home` mount before deleting the newly created empty volume.

### Milestone 6: Record the completed outcome

Affected files and interfaces:

- `XDG_STORAGE_STANDARDIZATION_EXECPLAN.md`: progress, findings, validation evidence, and audit history.
- All task-related implementation files covered by the final audit entry.

Steps:

1. Update Progress after each stopping point, keeping exactly one next action explicit.
2. Record deviations, resolved implementation details, and command results in Findings and Decisions.
3. Add an Audit Log entry whenever the ExecPlan or implementation is materially updated.
4. Each Audit Log update must be committed locally with the ExecPlan and only the task-related files it covers. Never
   stage unrelated user changes and never push.
5. Mark the plan complete only after the host rebuild and cross-container persistence validation succeed.

## Progress

- [x] Inspected the current XDG environment, Docker mounts, OpenCode paths, Neovim standard paths, and image-provisioned
      Neovim data.
- [x] Resolved the target XDG layout, configuration/runtime exclusions, Neovim system-data design, and clean-cutover
      policy.
- [x] Wrote and committed this implementation plan without changing runtime configuration.
- [x] Milestone 1: relocate image-provisioned Neovim plugins and parsers to `/usr/local/share/nvim/site`.
- [ ] Milestone 2: define `XDG_DATA_HOME` and `XDG_STATE_HOME` while retaining the existing cache home.
- [ ] Milestone 3: remove the dedicated OpenCode mount and update the superseded checklist decision.
- [ ] Milestone 4: rebuild and validate paths, application behavior, key handling, and cross-container persistence.
- [ ] Milestone 5: manually remove only the obsolete `dev-opencode-home` volume after successful validation.
- [ ] Milestone 6: record final evidence and commit the completed implementation.

Exact next action: add `XDG_DATA_HOME=/data/share` and `XDG_STATE_HOME=/data/state` to `docker/.bashrc`, and ensure the
Dockerfile creates the three persistent XDG home directories beneath `/data`.

## Findings and Decisions

- On 2026-09-18, `docker/.bashrc` exported only `XDG_CACHE_HOME=/data/cache`; data and state used their default paths.
- On 2026-09-18, `opencode debug paths` resolved config to `/root/.config/opencode`, data to
  `/root/.local/share/opencode`, state to `/root/.local/state/opencode`, and cache to `/data/cache/opencode`.
- On 2026-09-18, Neovim resolved config to `/root/.config/nvim`, data to `/root/.local/share/nvim`, state to
  `/root/.local/state/nvim`, cache to `/data/cache/nvim`, and runtime files to `/tmp/nvim.root/...`.
- The current Neovim data directory was approximately 97 MB and contained `vim.pack` optional packages, 33 compiled
  Tree-sitter parsers, and corresponding parser metadata. These files are created by the Dockerfile's headless Neovim
  run and are image assets, not user state.
- Neovim's `vim.pack` manages only `stdpath("data")/site/pack/core/opt`. Therefore, installing packages into a system
  data directory is insufficient by itself: normal runtime startup must load the system packages without calling
  `vim.pack.add`, or it will attempt to install another copy beneath `/data/share`.
- `/usr/local/share/nvim/site` is already present in Neovim's default `packpath`, so it is the selected immutable
  destination for image-provisioned packages and parsers.
- Milestone 1 uses one plugin table with explicit package names. `DEV_IMAGE_BUILD=1` enables `vim.pack.add` and parser
  installation only for the Docker build; normal startup uses `packadd` for each system-installed optional package.
- The exact edited Neovim configuration was validated with disposable system and user XDG trees on 2026-09-18. It
  provisioned all 11 plugins and 33 parsers, loaded Gruvbox and nvim-treesitter, parsed Lua successfully at runtime,
  and did not create a package tree beneath the simulated user data home.
- The selected persistent layout is `/data/share`, `/data/state`, and `/data/cache`, all backed by `dev-data`. This makes
  resetting the entire `dev-data` volume destructive to sessions, credentials deliberately stored by applications,
  editor state, and caches; cleanup guidance must target child directories.
- Configuration remains at the default `/root/.config` and is copied from the repository during image construction.
  No configuration directory will be placed in a volume.
- Runtime files remain ephemeral. `XDG_RUNTIME_DIR`, `XDG_CONFIG_DIRS`, and `XDG_DATA_DIRS` will not be overridden.
- The user explicitly chose a clean cutover: no OpenCode data migration, backward-compatibility path, or transition
  logic is required.
- The existing `dev-opencode-home` volume becomes unused after implementation. Repository code will neither migrate nor
  delete it; after the new layout is validated, the user will remove it manually on the Docker-capable host.
- `dev-data` must not be deleted during cleanup because it becomes the durable home for all XDG data and state in
  addition to caches. `dev-codex-home` and `dev-maven` also remain active and must be retained.
- Official references used to resolve the design are the
  [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/0.8/) and
  [Neovim standard-path documentation](https://neovim.io/doc/user/starting/#standard-path).

## Audit Log

- 2026-09-18: Created this ExecPlan from the verified repository and running-container state. Recorded the clean-cutover
  requirement, resolved the persistent XDG layout, specified the Neovim system-data prerequisite, and defined focused
  validation and recovery procedures. No runtime or application configuration was changed.
- 2026-09-18: Added a post-validation manual cleanup milestone for the obsolete `dev-opencode-home` Docker volume.
  Specified the safety check for container references, the exact removal and verification commands, and the active
  volumes that must be retained. No implementation or volume operation was performed.
- 2026-09-18: Completed Milestone 1. Split Neovim image provisioning from runtime loading, installed image assets under
  the system data path in the Dockerfile, and validated the exact configuration with all 11 plugins and 33 parsers in
  disposable XDG trees. No persistent XDG environment or container mount was changed yet.
