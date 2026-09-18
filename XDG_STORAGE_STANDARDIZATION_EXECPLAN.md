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

The completed result must use OpenCode's native credential store populated through `/connect`, preserve OpenCode and
Neovim configuration and features, and preserve the container's other explicit storage locations such as
`/root/.codex`, `/root/.m2`, `GOMODCACHE`, `GRADLE_USER_HOME`, and the npm cache. The xAI key is deliberately created
with a server-side expiration date and is not injected through the process environment.

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
   Derive `GOMODCACHE` and `NPM_CONFIG_CACHE` from `XDG_CACHE_HOME`; npm does not consume the XDG variable
   automatically, so the pre-created directory alone does not change npm's effective cache path.
4. Do not inject the xAI key into the process environment. Populate OpenCode's native credential store through
   `/connect`; the resulting `/data/share/opencode/auth.json` persists with the other OpenCode data.

Validation and expected results:

- A new interactive container reports the three intended XDG home variables and no user config or runtime override.
- `nvim --headless` reports `/root/.config/nvim`, `/data/share/nvim`, `/data/state/nvim`, and `/data/cache/nvim` for its
  config, data, state, and cache paths respectively; its runtime directory remains temporary.
- OpenCode reports `/root/.config/opencode`, `/data/share/opencode`, `/data/state/opencode`, and
  `/data/cache/opencode` for its config, data, state, and cache paths respectively; its temporary path remains under
  `/tmp`.
- `npm config get cache` reports `/data/cache/npm` in a new interactive container.
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
- Native `/connect` credentials exist only in `/data/share/opencode/auth.json`, written as mode `0600`, and remain
  absent from tracked configuration, the image, shell history, command arguments, logs, state, cache, and the process
  environment. OpenCode core, unrestricted commands, and plugins running as the same user can still read the file.

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
2. Build `ddadon/dev:current` on the Docker-capable host with
   `docker build --file docker/Dockerfile --tag ddadon/dev:current .`, then start a fresh `dev` container. A clean
   `dev-data` volume is acceptable; no old OpenCode data must be retained. Do not use `build.sh` for this focused check
   because it also pushes images and rebuilds the unrelated Git and Azure clients.
3. Validate all resolved OpenCode and Neovim paths, the absence of config/runtime redirection, and the presence of
   system-installed Neovim plugins and parsers.
4. Launch Neovim normally and exercise colorscheme loading, Tree-sitter highlighting, and one configured plugin-backed
   command. Confirm startup does not populate the persistent user data directory with image-managed packages.
5. Launch plain `opencode`, use `/connect` to store a deliberately expiring xAI key, complete a harmless Grok request,
   toggle a TUI preference such as sidebar visibility, and exit cleanly.
6. Recreate the `--rm` container and verify that the OpenCode session and TUI preference survive under `/data`, while
   `opencode auth list` still reports xAI without another key prompt and runtime files do not survive.
7. Confirm the Codex and Maven volumes, project bind mount, Go module cache, Gradle home, and repository-managed
   configuration still resolve as before. Confirm npm now resolves its previously pre-created cache directory at
   `/data/cache/npm`.

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
- [x] Milestone 2: define `XDG_DATA_HOME` and `XDG_STATE_HOME` while retaining the existing cache home.
- [x] Milestone 3: remove the dedicated OpenCode mount and update the superseded checklist decision.
- [ ] Milestone 4 (in progress): rebuild and validate paths, application behavior, key handling, and cross-container
      persistence.
- [ ] Milestone 5: manually remove only the obsolete `dev-opencode-home` volume after successful validation.
- [ ] Milestone 6: record final evidence and commit the completed implementation.

Exact next action: launch `opencode` once in the recreated container, confirm that the sidebar has the same visibility
state it had when the previous container exited, then exit OpenCode and report the visual result.

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
- Milestone 2 added only `XDG_DATA_HOME=/data/share` and `XDG_STATE_HOME=/data/state` beside the existing cache home.
  Shell syntax passed, and no config, runtime, config-dirs, or data-dirs override was added.
- With the intended environment, Neovim resolved config, data, state, cache, and run beneath `/root/.config/nvim`,
  `/data/share/nvim`, `/data/state/nvim`, `/data/cache/nvim`, and `/tmp`. OpenCode resolved the equivalent paths beneath
  `/root/.config/opencode`, `/data/share/opencode`, `/data/state/opencode`, `/data/cache/opencode`, and `/tmp/opencode`.
- The user explicitly chose a clean cutover: no OpenCode data migration, backward-compatibility path, or transition
  logic is required.
- The existing `dev-opencode-home` volume becomes unused after implementation. Repository code will neither migrate nor
  delete it; after the new layout is validated, the user will remove it manually on the Docker-capable host.
- `dev-data` must not be deleted during cleanup because it becomes the durable home for all XDG data and state in
  addition to caches. `dev-codex-home` and `dev-maven` also remain active and must be retained.
- Milestone 3 removed the only `dev-opencode-home` mount from `.zshrc`. The remaining development-container volumes are
  `dev-codex-home`, `dev-data`, and `dev-maven`; the project remains a bind mount at `/workspace`.
- `OPENCODE_GROK_TODOLIST.md` now distinguishes the historically validated dedicated volume from the final shared-XDG
  layout, documents all three concrete OpenCode paths, and warns that `/data` itself is not a disposable cache root.
- Milestone 4's container-local checks passed on 2026-09-18: both shell files and both OpenCode JSON files parsed; the
  three intended XDG exports and the remaining mounts matched exactly; OpenCode diagnostics resolved every target
  path; the exact Neovim config loaded system-provisioned plugins and a Lua parser without creating a user package
  tree; and `git diff --check` passed across all implementation commits.
- Docker is unavailable inside this development container, so the rebuilt image contents, real mount table, TUI/model
  behavior, and cross-container persistence remain host validation rather than inferred results.
- The host rebuilt `ddadon/dev:current` on 2026-09-18. The new image exposes exactly the three intended XDG variables;
  resolves all Neovim and OpenCode paths correctly; contains all 11 plugins and 33 parsers under
  `/usr/local/share/nvim/site`; loads Gruvbox, nvim-tree, nvim-treesitter, and a Lua parser; and creates no user package
  tree under `/data/share/nvim`.
- The first rebuilt container still mounted `dev-opencode-home` at `/root/.local/share/opencode` even though tracked
  `.zshrc` no longer requests it. The host shell retained the old `dev()` function in memory. OpenCode ignores this
  obsolete mount because its data path resolves to `/data/share/opencode`; the host shell must reload `.zshrc` before
  the persistence-test container is created.
- Rebuilt-image validation found that npm resolved its cache to `/root/.npm`: npm does not consume `XDG_CACHE_HOME`,
  `.npmrc` had no cache setting, and the Dockerfile merely pre-created `/data/cache/npm`. The selected correction is a
  container-only `NPM_CONFIG_CACHE="${XDG_CACHE_HOME}/npm"` export in `docker/.bashrc`; placing the absolute container
  path in the repository `.npmrc` would incorrectly affect host-side npm usage in this checkout. `GOMODCACHE` likewise
  derives its existing child path from `XDG_CACHE_HOME` so both explicit cache bridges share one authoritative root.
- The final rebuilt-container pre-credential checks passed on 2026-09-18. `/data`, `/workspace`, `/root/.codex`, and
  `/root/.m2` had the intended mounts, with no mount at `/root/.local/share/opencode`. The environment contained only
  the three intended XDG variables; npm and Go resolved `/data/cache/npm` and `/data/cache/gomod`; OpenCode resolved
  config, data, state, cache, and temporary paths correctly and reported zero credentials before `/connect`; and
  Neovim loaded all 11 image plugins, all 33 parsers, and a Lua parser without creating a user plugin tree.
- The interactive OpenCode checkpoint passed on 2026-09-18. `/connect` stored one xAI API credential in
  `/data/share/opencode/auth.json` as root-owned mode `0600`, while `XAI_API_KEY` remained unset. A successful Grok
  interaction created session `ses_f4c4100f2ffeH3148Kjzh1s11P` with title `Greeting`; OpenCode's database and log were
  written beneath `/data/share/opencode`, and prompt/model state was written beneath `/data/state/opencode`. No secret
  content was inspected during validation.
- Cross-container persistence checks passed on 2026-09-18 for all nonvisual OpenCode state. In the recreated container,
  OpenCode still reported the xAI credential from the root-owned mode-`0600` file, the original `Greeting` session,
  model state, and prompt history; `XAI_API_KEY` remained unset. `/data` was the only relevant mount and OpenCode still
  resolved its data and state beneath it. Manual confirmation of sidebar visibility remains pending.
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
- 2026-09-18: Completed Milestone 2. Added the persistent data and state homes beside the existing cache home, created
  their image-level mountpoint directories, and verified exact Neovim and OpenCode path resolution while leaving
  configuration and runtime paths at their defaults. The OpenCode mount remained unchanged pending Milestone 3.
- 2026-09-18: Completed Milestone 3. Removed the dedicated OpenCode mount, retained the shared data, Codex, and Maven
  volumes, and updated the OpenCode checklist to supersede the old persistence decision with the concrete shared-XDG
  paths and safe cleanup guidance. No data migration, compatibility logic, or secret-handling change was added.
- 2026-09-18: Completed the container-local portion of Milestone 4. Validated syntax, configuration parsing, exports,
  mounts, application paths, system-loaded Neovim plugins and parser execution, absence of a user plugin tree, and the
  aggregate diff. Recorded the focused host build command; Docker-host and recreation checks remain pending.
- 2026-09-18: Updated the plan for the later credential decision: plain OpenCode now uses `/connect` with an expiring
  xAI key rather than a launch wrapper or environment injection. Recorded successful rebuilt-image validation and the
  stale host-shell `dev()` function that temporarily retained the obsolete mount. Interactive and recreation checks
  remain pending.
- 2026-09-18: Added the missing container-specific npm cache export after rebuilt-image validation proved that the
  pre-created `/data/cache/npm` directory alone did not configure npm. Updated the remaining validation and rebuild
  step without changing the repository `.npmrc` or host-side npm behavior.
- 2026-09-18: Reorganized `docker/.bashrc` into application-focused sections, retained the ShellCheck-friendly
  `dpkg_arch` assignment for `JAVA_HOME`, and derived the explicit Go and npm cache paths from `XDG_CACHE_HOME` to keep
  one authoritative cache root. No effective storage destination changed.
- 2026-09-18: Changed the literal `MANPAGER` value to single quotes for semantic consistency with the alias and other
  non-expanding shell strings. This cosmetic cleanup does not change its effective value.
- 2026-09-18: Validated the final rebuilt container before credential entry. Confirmed the corrected mounts and cache
  paths, exact OpenCode and Neovim XDG paths, system-provisioned Neovim assets, and absence of both the obsolete
  OpenCode mount and pre-existing native credentials. Advanced the exact next action to the interactive `/connect`
  and session-state test.
- 2026-09-18: Recorded the successful interactive OpenCode checkpoint: native xAI credential discovery, restrictive
  credential-file metadata, absence of environment injection, and the persisted session, database, prompt history,
  and model-state locations. Advanced the exact next action to cross-container persistence validation.
- 2026-09-18: Verified native credentials, the original session, model state, and prompt history after recreating the
  container, with no obsolete OpenCode mount or environment key. Advanced the exact next action to the remaining
  manual sidebar-visibility check before completing Milestone 4.
