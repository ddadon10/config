# OpenCode + Grok Contingency Setup

## Goal

Prepare OpenCode with the xAI API as a dependable fallback when Codex or OpenAI is unavailable. Use Grok 4.6 as the
primary model and evaluate `grok-build-0.1` as the small/fast model. Preserve the current container-based workflow,
avoid committing credentials, and make security, privacy, tool access, persistence, web search, fast mode, and prompt
caching explicit decisions.

Work through this list in order. Stop at each decision gate and interview the user one question at a time, always
including a recommended answer. Do not implement a later phase before its decisions and validation are complete.

## Todo List

### 1. Remove OpenRouter and install OpenCode

- [x] Inventory every tracked OpenRouter reference and confirm the removal scope before editing.
  - Known starting points: `.codex/openrouter.config.toml`, `docker/Dockerfile`, and `docker/.bashrc`.
  - Check history or other files only when needed to understand the current alias and credential-injection behavior.
- [x] Remove all OpenRouter configuration, startup copying, aliases/functions, and obsolete documentation from this
      repository without changing the normal Codex configuration.
- [x] Present viable OpenCode installation approaches, with the simplest fully suitable option first and marked
      `(Recommended)`.
  - Compare an official binary/install script, the `opencode-ai` npm package, and any suitable container-oriented
    installation method.
  - Evaluate reproducibility, version pinning, image size, update policy, supported architectures, and supply-chain
    verification for this Debian development image.
- [x] Interview the user about version pinning versus automatic updates and select one installation method.
  - Decision: use the official install script so image rebuilds track the latest OpenCode release.
  - Decision: pass `--no-modify-path` and manage `PATH` in the repository-owned `docker/.bashrc`.
- [x] Add OpenCode to `docker/Dockerfile` using the selected method.
- [x] Build or otherwise validate the installation as far as this environment allows; record any Docker-only command
      the user must run externally.
  - Live installer validation succeeded in the current container with `--no-modify-path`; Docker itself is unavailable.
  - Host validation command: `docker build --file docker/Dockerfile --tag ddadon/dev:current .`.
  - The latest release is resolved when the install layer executes; use `--no-cache` when explicitly checking for an
    OpenCode update without another Dockerfile change invalidating that layer.
- [x] Confirm `opencode --version` and basic startup work before continuing.
  - `/root/.opencode/bin/opencode --version` reported `1.18.31` on 2026-09-17.
- [x] Commit the completed OpenRouter removal and OpenCode installation as one focused milestone.

### 2. Explore and design the general OpenCode configuration

- [x] Create an exploration workspace and concise journal following the repository's Explore instructions; report the
      journal path.
- [x] Research current official OpenCode documentation and its original upstream repository for:
  - Configuration locations, precedence, schemas, environment interpolation, provider definitions, model definitions,
    agents, instructions, permissions, tools, commands, plugins, MCP servers, sharing, updates, snapshots, logging, and
    session storage.
  - The native xAI provider and whether custom provider configuration is necessary or less desirable.
- [x] Research current official xAI documentation for Grok 4.6 and `grok-build-0.1`:
  - Exact model IDs, availability, API compatibility, context/output limits, reasoning controls, tool calling,
    streaming, pricing-relevant settings, rate limits, and supported server-side tools.
- [x] Verify every model ID and option against the live xAI API or OpenCode model listing instead of relying solely on
      documentation examples.
- [x] Interview the user, one question at a time, and record each answer before writing configuration. Cover at least:
  - Default model and small model responsibilities.
  - Reasoning effort, output verbosity, context limits, compaction, and cost/latency preferences.
  - Whether OpenCode may edit files and run shell commands automatically, must ask, or must deny by default.
  - Command-specific rules for destructive commands, Git operations, network access, external directories, and reads
    of sensitive files.
  - Whether project instructions, agents/subagents, skills, MCP servers, plugins, LSP integration, snapshots, and
    automatic updates should be enabled.
  - Whether conversation sharing must be disabled and what local session/log retention is acceptable.
  - Whether OpenCode may send repository contents, environment data, or diagnostics anywhere other than xAI.
  - Decisions recorded on 2026-09-17:
    - Use the native global xAI endpoint with `xai/grok-4.6` as the main model and `xai/grok-build-0.1` as the small
      model; explicitly pin `high` reasoning for build and `xhigh` for plan. Keep trivial single-property configuration
      objects on one line.
    - Enable full autonomy, including secret-like files, external directories, arbitrary shell commands, and no
      approval prompts. Apply this literally to every built-in agent, so global permissions also override Plan's edit
      denial and Explore's read-only restrictions. Explicitly accept and document the resulting local
      secret-exfiltration risk.
    - Disable OpenCode sharing, disable filesystem snapshots, and disable OpenCode self-updates.
    - Persist local sessions/logs; decide the volume and cleanup mechanics in item 3.
    - Reuse the global `AGENTS.md`, honor project instructions/configuration for trusted projects, and restrict model
      providers to xAI.
    - Keep OpenCode's default plugin behavior and configure no MCP servers initially. Trusted projects may supply
      plugins, standalone custom tools, skills, agents, commands, LSP, formatters, or configuration overrides.
    - Keep the default one-level subagent delegation: primary agents may launch subagents, but subagents may not launch
      more agents. Omit the default-valued `subagent_depth` key and validate its effective behavior.
    - Allow every agent to discover and load trusted global/project skills without prompts. Rely on the broad global
      allow rule rather than adding a redundant skill-specific setting.
    - Allow trusted projects to load executable `.opencode/tools` modules automatically. Accept that initialization is
      not sandboxed and that a custom tool can replace a built-in tool with the same name.
    - Enable local-only LSP integration and set `OPENCODE_DISABLE_LSP_DOWNLOAD=true`; use only language servers already
      installed in the image/project. Keep the experimental model-callable LSP tool disabled.
    - Keep automatic formatters disabled by omitting `formatter`; use each repository's explicit formatting and
      validation commands instead of background post-edit mutations.
    - Set `OPENCODE_DISABLE_CLAUDE_CODE=1`; ignore Claude prompt files and `.claude` skills while retaining `AGENTS.md`,
      native OpenCode extensions, and `.agents` skills.
    - Keep automatic compaction enabled and tool-output pruning disabled by relying on the defaults; omit a redundant
      `compaction` block and validate the effective 20k-token safety reserve.
    - Keep OpenCode's stable 32k output-token default and do not set the experimental output override. Control response
      verbosity through `AGENTS.md` and prompts because xAI exposes no documented Grok 4.6 verbosity parameter.
    - Leave experimental OpenTelemetry disabled and export no diagnostic spans; retain only local logs/sessions and
      required xAI traffic.
    - Persist local logs at the default INFO level for contingency troubleshooting; accept that logs may contain paths,
      commands, tool metadata, and error details, and omit a redundant log-level setting.
    - Allow the default models.dev catalog refresh for current public model metadata; it sends no prompt or repository
      content. Do not set `OPENCODE_DISABLE_MODELS_FETCH`.
    - Keep literal full autonomy with no tool-specific exceptions; trusted repositories remain the security boundary.
- [x] Produce a least-privilege threat model covering prompt injection, secret exfiltration, malicious repository
      instructions, shell execution, filesystem escape, untrusted plugins/MCP servers, telemetry, sharing, and local
      credential/session exposure.
  - Outcome: the selected policy deliberately matches the current Codex full-access posture and is not least privilege.
    Trusting the repository and container boundary—not an OpenCode sandbox—is the primary control.
  - Prompt injection and malicious repository instructions can drive unrestricted reads, writes, shell/network calls,
    Git operations, and data exfiltration. Use this profile only in repositories whose contents and extensions are
    trusted; `AGENTS.md` guidance is behavioral rather than an enforceable sandbox.
  - The xAI key, `.env` files, mounted host paths, other credentials, and external directories are reachable whenever
    exposed to the OpenCode process or container. ZDR governs xAI retention but cannot protect secrets read or sent by
    local tools, plugins, MCP servers, or malicious commands.
  - Project/global plugins and `.opencode/tools` execute local code during loading and can intercept tools or replace
    built-ins. Project configuration may also add MCP servers despite the empty global MCP policy; each trusted project
    therefore expands the executable-code and external-recipient boundary.
  - Sharing and OpenTelemetry are disabled. Expected non-project-content recipients are xAI for model requests and
    models.dev for public catalog refreshes; future web search, plugins, and MCP integrations require separate review.
  - Sessions and INFO logs are local but intentionally persistent and may contain prompts, code, paths, commands, tool
    metadata, and errors. Phase 3 must protect their volume and credentials with appropriate ownership, permissions,
    retention, and deletion procedures.
  - Snapshots are disabled, so Git and backups are the recovery controls for destructive edits. Full shell/network
    authority remains comparable to this repository's current Codex configuration, while OpenCode additionally removes
    the built-in Plan/Explore tool boundaries.
- [x] Propose the minimal global `opencode.json`/`opencode.jsonc` configuration and clearly separate user-wide settings
      from any project-specific settings that should be committed here.
  - Approved global configuration:

    ```json
    {
      "$schema": "https://opencode.ai/config.json",
      "model": "xai/grok-4.6",
      "small_model": "xai/grok-build-0.1",
      "enabled_providers": ["xai"],
      "share": "disabled",
      "snapshot": false,
      "autoupdate": false,
      "lsp": true,
      "permission": {"*": "allow"},
      "agent": {"build": {"variant": "high"}, "plan": {"variant": "xhigh"}}
    }
    ```

  - Set `OPENCODE_DISABLE_LSP_DOWNLOAD=true` and `OPENCODE_DISABLE_CLAUDE_CODE=1` outside the JSON configuration.
  - Do not set `OPENCODE_PURE`; keep default plugin behavior.
- [x] Validate the proposed configuration against the current OpenCode schema and with OpenCode's own diagnostics.
  - `opencode debug config` on OpenCode 1.18.31 resolved every proposed field and both agent variants exactly.
- [x] Run a harmless Grok 4.6 smoke test and a small-model task; confirm which configuration and model are actually in
      use.
  - `xai/grok-4.6` with the Build agent and `high` variant returned the requested sentinel.
  - `xai/grok-build-0.1` with the Build agent returned the requested sentinel; the pinned Build variant caused no error.
  - The environment-injected key had zero matches in OpenCode config, logs, sessions, state, cache, or exploration files.
    The temporary source file itself is mode `0644` and must not become the approved credential-storage design.
- [x] Commit the approved configuration milestone after the repository-managed source and runtime placement are settled
      in item 3, per the user's instruction to make one commit at the end rather than interim commits.

### 3. Decide API-key injection and configuration persistence

- [x] Document exactly where OpenCode reads credentials and where `/connect` stores them, including file permissions,
      plaintext/encryption behavior, precedence, and whether credentials enter logs, shell history, or process
      environments.
  - The initially implemented launch-time environment workflow was inherited by OpenCode shell tools. It has been
    superseded by native credential storage so the key is no longer added to the process environment.
  - `/connect` and `opencode auth login` offer xAI's `Manually enter API Key` method and store the key as unencrypted
    JSON in `${XDG_DATA_HOME:-~/.local/share}/opencode/auth.json`, written with mode `0600`. Under the standardized XDG
    environment, the concrete path is `/data/share/opencode/auth.json`.
  - In the current provider loader, stored API credentials are merged after environment credentials and therefore take
    precedence when both exist. Stored credentials are not copied into the process environment, although this profile's
    unrestricted filesystem tools can still read the credential file.
  - Native credential storage does not intentionally log the key. Plugins, arbitrary shell commands, and unrestricted
    file access can still read the credential file under the approved full-autonomy policy.
- [x] Present three materially different credential approaches where viable:
  1. A prompt-on-launch shell function that injects the key only into the OpenCode child process.
  2. OpenCode's native credential store populated via `/connect`.
  3. Host secret-manager or Docker-secret integration, if it fits this local development workflow.
- [x] Interview the user to choose between entering the key for every launch and persisting it across containers.
  - Superseded decision on 2026-09-18: prompt for an ephemeral key on every launch through a shell function.
  - Final decision on 2026-09-18: create an xAI API key with a deliberate server-side expiration date when contingency
    access is needed, store it through `/connect`, and launch OpenCode normally. The key must not be tracked, baked into
    the image, placed in shell history or command arguments, or injected into child-process environments.
- [x] Remove the superseded prompt-on-launch function after selecting OpenCode's native credential store.
- [x] Map all OpenCode state that may need persistence: general/TUI config, credentials, sessions, logs, caches,
      plugins, downloaded packages, and other XDG data/state/cache paths.
  - `${XDG_CONFIG_HOME:-~/.config}/opencode`: global `opencode.json`, `tui.json`, and global agents, commands, modes,
    plugins, skills, themes, tools, dependency manifests, and installed plugin packages. Repository-managed defaults can
    be baked into `/root/.config/opencode`; project `.opencode` content remains in the `/workspace` bind mount.
  - `${XDG_DATA_HOME:-~/.local/share}/opencode`: `opencode.db` sessions/messages plus logs, plans, truncated tool output,
    managed worktrees/repository data, and any `auth.json` or `mcp-auth.json`. This is the sensitive durable-data tier.
  - `${XDG_STATE_HOME:-~/.local/state}/opencode`: recent-model/variant selection, plugin metadata, and process locks. It
    is convenient rather than essential, but now persists beneath `/data/state/opencode` with other XDG state.
  - `${XDG_CACHE_HOME:-~/.cache}/opencode`: refreshable models.dev metadata, skill cache, and downloaded helper binaries.
    This repository already sets `XDG_CACHE_HOME=/data/cache`, so it already lands in the persistent `dev-data` volume.
  - `${TMPDIR:-/tmp}/opencode`: disposable runtime files. `/root/.opencode/bin/opencode` is the image-installed executable,
    not the configuration directory, and is restored by rebuilding the image.
- [x] Present and compare persistence layouts:
  - Reuse the existing `dev-data` volume for OpenCode data and cache while baking non-secret configuration into the
    image.
  - Add a dedicated `dev-opencode-home` named volume while continuing to bake non-secret configuration into the image.
  - Bind-mount a host directory for directly inspectable and independently backed-up OpenCode data.
- [x] Interview the user about which state should survive container recreation and which state must remain ephemeral.
  - Superseded decision on 2026-09-18: reusing `dev-data` through child-scoped `XDG_DATA_HOME=/data` would also redirect
    XDG-aware tools launched by OpenCode, including Neovim. That direct `/data` layout was not used.
  - Superseded decision on 2026-09-18: mount a dedicated `dev-opencode-home` volume at OpenCode's default data directory,
    `/root/.local/share/opencode`. This persists its database, sessions, logs, plans, tool output, and any credentials
    deliberately added later without changing `XDG_DATA_HOME` for OpenCode or its child tools. Continue using the
    existing `/data/cache/opencode` cache; keep recent-model/plugin state and locks ephemeral. The volume name follows
    `dev-codex-home`, although its exact scope is OpenCode's data directory rather than configuration, cache, or state.
  - Final decision on 2026-09-18: standardize the container on `XDG_DATA_HOME=/data/share`,
    `XDG_STATE_HOME=/data/state`, and `XDG_CACHE_HOME=/data/cache`, all backed by `dev-data`. OpenCode therefore stores
    durable application data under `/data/share/opencode`, durable TUI/model/plugin state under `/data/state/opencode`,
    and disposable caches under `/data/cache/opencode`. Neovim image assets move to `/usr/local/share/nvim/site`, so
    redirecting its user data no longer hides or duplicates image-installed plugins and parsers.
  - Decision on 2026-09-18: keep the repository source of truth at `.config/opencode/opencode.json` and copy it to
    `/root/.config/opencode/opencode.json` in the image. This mirrors the existing Neovim layout, uses OpenCode's normal
    global configuration path, and preserves the ability for trusted project configuration to override global values.
  - Decision on 2026-09-18: retain sessions and the append-only INFO log until manual cleanup. Use
    `opencode session delete <sessionID>` for targeted session removal; document a deliberate full
    `/root/.local/share/opencode` reset procedure after OpenCode is stopped. Do not add automatic age-based deletion or
    `logrotate`.
- [x] Update `docker/.bashrc`, `docker/Dockerfile`, and `.zshrc` only as required by the approved credential and
      persistence design.
  - The initial implementation added a hidden-input launch function to `docker/.bashrc`, the repository-managed global
    configuration copy to `docker/Dockerfile`, and the `dev-opencode-home` mount to `.zshrc`.
  - The later XDG standardization supersedes that mount: `.zshrc` now retains only `dev-data` at `/data`, while
    `docker/.bashrc` exports the data, state, and cache homes. The later credential decision removes the key-prompt
    function; plain `opencode` now uses the native store populated through `/connect`.
- [x] Verify the earlier key workflow was absent from Git, image layers, shell history, process arguments, OpenCode
      logs, and diagnostic output; document the replacement storage boundary.
  - Earlier exact-value scans found no key in the repository, configuration, data/logs, state, or cache. Under the final
    design, the key is intentionally present only in `/data/share/opencode/auth.json`, which OpenCode writes as mode
    `0600`; it must remain absent from tracked files, the image, shell history, command arguments, logs, and state.
  - Unavoidable exposure: OpenCode core, unrestricted shell commands, and plugins run as the same user and can read the
    credential file. The xAI expiration date limits server-side validity even if the local expired value remains.
- [x] Recreate the container and confirm the selected configuration/state persists while secrets follow the approved
      policy.
  - Docker is unavailable in this container. Current-process validation proved that the tracked configuration resolves,
    a live Grok request succeeds. Host check after rebuilding: launch with `dev`, use `/connect` once for xAI, create a
    session with `opencode`, exit, launch `dev` again, then confirm both `opencode auth list` and
    `opencode session list` retain their entries without another credential prompt.
  - Manual cleanup: stop OpenCode before changing its files. Delete one session with
    `opencode session delete <sessionID>`. Rotate the log recoverably by moving
    `/data/share/opencode/log/opencode.log` aside. Reset durable OpenCode data recoverably by moving only
    `/data/share/opencode` to a backup name; move `/data/state/opencode` separately only when state also needs resetting.
    Never treat all of `/data` as disposable because it is shared with other applications.
  - First host half completed on 2026-09-18: `/proc/self/mountinfo` confirmed `dev-opencode-home` at
    `/root/.local/share/opencode`; the rebuilt image resolved the approved configuration, completed a default
    `xai/grok-4.6` request, and created a session in the mounted data directory. The exact test key was absent
    from repository, configuration, data/log, state, and cache files. Recreate once more and confirm the session remains.
  - Final host validation on 2026-09-18: after another `--rm` container recreation, the same
    `ses_f4cb47fadffenBpL6bHFo6z6r8` session remained in `opencode session list` and the named volume was mounted at the
    expected path. The host supplied the key again through the earlier child-process environment, but no native
    `auth.json` existed and an
    exact-value scan found no key in persistent data/logs, configuration, state, cache, or the repository.
  - The two preceding host checks validate the now-superseded dedicated-volume layout. The standardized XDG layout
    requires a new rebuild and two-container persistence check before `dev-opencode-home` can be deleted manually.
  - Final shared-XDG validation on 2026-09-18 confirmed that the native xAI credential, sessions, model state, prompt
    history, and hidden-sidebar state survived container recreation through `dev-data`. The credential remained
    root-owned mode `0600`, `XAI_API_KEY` remained unset, and deleting `dev-opencode-home` did not affect active data.
- [x] Commit the credential and persistence milestone in the same end-of-phase commit as the approved configuration.
  - The later dedicated-volume correction is a separate focused commit so the user's intervening
    `Remove lsp support in opencode` commit remains intact.

### 4. Match the OpenCode TUI to the current environment

- [x] Compare current Codex, Ghostty, shell, Vim/Neovim, and VS Code preferences with supported OpenCode TUI settings.
  - Gruvbox is consistent across Ghostty, Codex, Neovim, and BAT. Ghostty and VS Code disable cursor blinking; Ghostty
    uses a block cursor. Neovim enables mouse support and uses one-line vertical mouse scrolling; VS Code uses stacked
    diffs. Codex enables OSC 9 notifications and a dynamic terminal title.
- [x] Research the current dedicated `tui.json` schema and avoid deprecated TUI keys in `opencode.json`.
  - OpenCode 1.18.31 loads global TUI settings from `/root/.config/opencode/tui.json`, then merges explicit and project
    overrides. The existing Dockerfile copies the entire repository-managed `.config/opencode` directory there.
  - The supported user-facing fields are `theme`, `keybinds`, `leader_timeout`, `attention`, `prompt`, `scroll_speed`,
    `scroll_acceleration`, `diff_style`, `cursor`, and `mouse`; TUI plugins also have dedicated fields.
  - Legacy `theme`, `keybinds`, and `tui` keys in `opencode.json` are migration inputs, not the target design.
- [x] Propose a minimal TUI configuration using the built-in Gruvbox theme when it matches the current palette.
  - Fixed portion: use built-in `gruvbox`, which includes light and dark palettes and follows the terminal mode unless
    manually locked.
- [x] Configure a non-blinking block cursor if OpenCode can control it reliably; otherwise document the terminal-level
      fallback and avoid conflicting cursor controls.
  - Verified that OpenCode supports `"cursor": {"style": "block", "blinking": false}`. It agrees with Ghostty's
    existing block/non-blinking settings and is therefore the proposed explicit configuration.
- [x] Interview the user about notifications, sounds, mouse support, scrolling/acceleration, diff display, status
      information, keybindings, and terminal-title behavior.
  - Status gap: OpenCode has no configurable Codex-style status line. It always shows model/provider/variant and
    context/cost near the prompt; `/status` reports MCP, LSP, formatter, and plugin state.
  - Decision: accept the built-in status information and do not add executable TUI-plugin code to emulate Codex's
    five-hour/weekly limits or token-total fields.
  - Decision: enable terminal-mediated desktop notifications but disable sounds. Notifications occur only when Ghostty
    is blurred and may expose the generated session title plus a generic status message. Configure
    `"attention": {"enabled": true, "sound": false}` and omit the default-valued `notifications` field.
  - Decision: retain the default enabled mouse capture, matching Neovim and allowing clickable controls and TUI wheel
    scrolling. Omit the redundant `mouse` field.
  - Decision: set `"scroll_speed": 1` to match Neovim's precise one-line vertical scrolling. Do not configure scroll
    acceleration because enabling it would override the fixed speed.
  - Decision: set `"diff_style": "stacked"` to match VS Code's non-side-by-side diff preference at every terminal
    width instead of letting OpenCode switch layouts automatically.
  - Decision: keep OpenCode's default keybindings and `ctrl+x` leader. Do not remap Ghostty's Command-derived Control
    bytes or add a modal plugin; validate the defaults interactively before considering targeted overrides later.
  - Decision: retain OpenCode's default dynamic terminal title. It displays `OpenCode` or a generated session title,
    which can reveal task context in Ghostty's tab/window title; add no title environment flag or launcher override.
  - Decision order: attention/notifications/sounds; mouse capture; scrolling; diff layout; status information;
    keybindings; terminal title.
  - Approved global TUI configuration:

    ```json
    {
      "$schema": "https://opencode.ai/tui.json",
      "theme": "gruvbox",
      "scroll_speed": 1,
      "diff_style": "stacked",
      "cursor": {"style": "block", "blinking": false},
      "attention": {"enabled": true, "sound": false}
    }
    ```
- [x] Check for conflicts with Ghostty's existing cursor and shell-integration settings.
  - OpenCode and Ghostty both request a non-blinking block cursor. Ghostty's `shell-integration-features = no-cursor`
    prevents its shell integration from changing the cursor; it does not block a full-screen application from setting
    the same cursor behavior. No conflicting repository setting was found.
- [x] Validate the TUI interactively for color, cursor behavior, diffs, scrolling, notifications, and keybindings.
  - OpenCode 1.18.31 loaded and applied the tracked file without a TUI-config warning. Its terminal output used Gruvbox's
    `#282828` background, requested a steady block cursor, enabled mouse tracking, and set the `OpenCode` title.
  - Default `ctrl+x s` opened the status dialog and `ctrl+x q` exited. A harmless Grok 4.6 request returned `TUI_OK`,
    and the prompt displayed model/provider plus context use and cost. The user confirmed the TUI loads and looks good.
  - The stacked diff and fixed scroll speed feed the built-in diff viewer directly. Desktop notification delivery could
    not be simulated from the automation pseudo-terminal because it cannot blur a real Ghostty window; sound is
    disabled by configuration. The disposable validation session was deleted afterward.
- [x] Commit the approved TUI milestone.

### 5. Evaluate a `/fast` workflow for Grok

- [x] Define the desired semantics with the user: lower reasoning, `grok-build-0.1`, a cheaper Grok 4.6 variant, or a
      temporary model switch for the current session.
  - Decision: `/fast` means xAI Priority Processing for the otherwise unchanged Grok model and reasoning settings. It
    must send `service_tier: "priority"`; it does not mean lower reasoning or switching to `grok-build-0.1`.
- [x] Check whether current OpenCode provides a native model variant, command, keybinding, agent switch, or equivalent
      that can implement those semantics.
  - OpenCode merges arbitrary variant options and namespaces native xAI options correctly, but OpenCode 1.18.31 pins
    `@ai-sdk/xai@3.0.102`, whose option schema discards `serviceTier` and whose serializers omit `service_tier`.
  - Vercel AI added complete Chat Completions and Responses support, including returned-tier metadata, in `4.0.38` and
    backported it to the compatible v3 line in `3.0.120`. OpenCode last bumped its xAI SDK on 2026-07-08, from
    `3.0.82` to `3.0.102`; its current `dev` branch remains pinned there.
  - A sanitized direct xAI API probe confirmed that this account and `grok-4.6` accept priority processing and return
    `service_tier: "priority"`.
- [x] If native support is insufficient, evaluate in this order:
  1. A custom OpenCode command or dedicated fast agent.
  2. A small local plugin with no external network access or dependencies.
  3. A shell-level alternate launcher only if in-session switching is impossible.
  - A custom command can select a separate model while sending a prompt, but is not a clean state-only variant toggle.
    A plugin or request wrapper could inject the field but would add unnecessary executable code and request access.
    A versioned SDK override appears possible but would bypass exact-package-name transformations and needs validation.
- [x] For any plugin, review the exact source, permissions, dependencies, update behavior, and data flows before use;
      do not install an unreviewed third-party plugin.
  - No plugin was selected or installed. The user chose to wait for OpenCode to acquire the upstream SDK support.
- [x] Implement only the approved approach and document how to enable, identify, and disable fast mode.
  - Approved outcome: make no configuration or runtime change now. Revisit after OpenCode bundles
    `@ai-sdk/xai@3.0.120` or newer, then use a `fast` model variant with `{"serviceTier":"priority"}` and verify the
    applied tier from `providerMetadata.xai.serviceTier` where OpenCode exposes it.
- [x] Verify the active model/options change as intended and can return safely to Grok 4.6 in the same workflow.
  - Deferred with the implementation. The direct API probe verifies xAI's transport behavior, but no OpenCode
    fast-mode state exists to enable or disable until its bundled SDK supports the option.
- [x] Commit the fast-mode milestone.

### 6. Evaluate web search with OpenCode and Grok

- [x] Research OpenCode's `websearch` tool availability, provider restrictions, search backend, data flow, credentials,
      retention, citations, and permission controls.
  - OpenCode 1.18.31 exposes its client-side `websearch` tool automatically only for the OpenCode/OpenCode Go
    providers, or for any provider when `OPENCODE_ENABLE_EXA` or `OPENCODE_ENABLE_PARALLEL` is truthy. It calls the
    selected provider's anonymous hosted MCP endpoint; it is not a provider-native model tool.
  - `OPENCODE_ENABLE_EXA=1` selects `https://mcp.exa.ai/mcp`. Exa receives the query and search options; OpenCode then
    passes returned text to xAI as tool output. The `websearch` permission uses the query as its pattern, and the
    approved global allow rule runs it without confirmation.
  - Exa requires no API key in this mode, but it is an additional data recipient outside the xAI ZDR boundary. Its
    public privacy policy says Query Data may be used for service improvement, training, and fine-tuning and warns
    against submitting personal information. Returned web content is untrusted and is passed to a fully autonomous
    agent without content sanitization, so search-result prompt injection remains an accepted risk.
- [x] Research xAI's native web/X search tools for Grok 4.6 and `grok-build-0.1`, including availability through the API,
      citations, domains/date filters, pricing, ZDR compatibility, and whether OpenCode's xAI integration exposes them.
  - xAI Responses supports provider-executed `web_search` and `x_search`, native citations, domain/handle/date filters,
    and image/video options. A direct request with `store:false` returned `x-zero-data-retention: true` for this team.
  - OpenCode uses xAI Responses and its bundled `@ai-sdk/xai@3.0.102` already implements both provider tools, but
    OpenCode registers neither. Model options, permissions, ordinary custom tools, and current plugin hooks cannot add
    a provider-defined tool to the original request.
- [x] Run controlled comparisons for freshness, source quality, citations, latency, failures, and prompt-injection
      handling.
  - One fixed-date query asked for the latest stable OpenCode release using official GitHub sources. Native Grok 4.6
    found the correct `v1.18.31` release in 18.986 seconds with one search and a valid citation. Native Grok Build took
    55.742 seconds, searched 12 times, cost roughly ten times as much, and incorrectly called an unpublished v2 tag a
    stable release. This is a controlled example, not a general benchmark, but it rejects Grok Build as the default
    research model.
  - Raw anonymous Exa and Parallel searches returned in approximately one second but were slightly stale for this
    rapidly changing target. Their raw retrieval output is not directly comparable to a complete model answer.
  - Every evaluated route can deliver hostile page content to the autonomous model. OpenCode's Exa/Parallel path has
    no prompt-injection sanitizer; xAI-native search reduces recipients but does not make retrieved content trusted.
- [x] Prefer native Grok search only if OpenCode exposes it reliably and it meets the security/privacy requirements;
      otherwise present OpenCode search, a reviewed plugin/MCP integration, or no search as explicit alternatives.
  - Native xAI search best matches the desired privacy boundary but is unavailable in the current OpenCode integration.
    Exact same-request support requires an OpenCode source change. A custom plugin can stay xAI-only, but must make a
    separate native-search model request and return its result to the main conversation.
  - Reviewed `emilsvennesson/opencode-websearch` at commit
    `775eac481fcf778080ef1effedb32988dd10974a`; its xAI adapter uses that separate-request custom-tool design rather than
    injecting native search into the original request.
- [x] Interview the user about permitted search providers, acceptable query/content disclosure, approval behavior, and
      whether search should be enabled by default.
  - Decision on 2026-09-18: enable anonymous Exa search by default as a small temporary change, accepting disclosure of
    search queries to Exa and automatic execution under the existing full-autonomy permission. Keep xAI as the only
    model provider; do not add an Exa credential, Parallel, MCP configuration, or third-party plugin.
  - Future follow-up, not required for this milestone: replace Exa with a small repository-owned xAI-only custom tool.
    It should use native `fetch`, the existing OpenCode credential, `grok-4.6`, `store:false`, a mandatory positive ZDR
    response header, compact answer/citation output, and focused tests. Remove the Exa flag only after live validation.
- [x] Configure the chosen path with least privilege and verify which service receives each query.
  - `docker/.bashrc` exports `OPENCODE_ENABLE_EXA=1` in its OpenCode section. A fresh shell exposed `websearch` to the
    Build agent, and one live Grok 4.6 call used it exactly once. The completed tool event identified provider `exa`,
    title `Exa Web Search`, and the requested official `opencode.ai/docs/tools` result. The disposable session was
    deleted afterward.
- [x] Commit the web-search milestone.

### 7. Verify prompt caching with xAI ZDR enabled

- [x] Research official xAI prompt-caching behavior for both selected models and determine whether ZDR changes cache
      eligibility, retention, routing, billing, or observability.
- [x] Inspect OpenCode's xAI request path for stable conversation/cache identifiers, prefix preservation, reasoning
      content handling, and exposure of cached-token usage.
- [x] Confirm ZDR on the actual API responses using xAI's documented response indicator; do not infer it only from the
      console setting.
- [x] Establish a repeatable test with one initial request and multiple same-session follow-ups whose prompt prefix is
      large and stable enough to qualify for caching.
- [x] Capture request-independent evidence from response usage or debug telemetry without logging prompts or the API
      key; compare first-request and follow-up cached-token counts, latency, and billed usage where available.
- [x] Repeat with Grok 4.6 and `grok-build-0.1`, streaming and tool calls if they are part of the final workflow, and
      after a container restart if persisted sessions are expected to continue.
  - Grok 4.6 and Grok Build passed direct and OpenCode tests. OpenCode's normal streaming path, separate-process
    persisted-session continuation, and a 13-step Grok Build function-tool loop all reported cache reads.
  - Before the external image rebuild, the repository-owned plugin was loaded and exercised directly from the tracked
    configuration directory because Docker is unavailable inside the container.
  - After the user's rebuild, OpenCode loaded the baked plugin from `/root/.config/opencode/plugins`, and the prepared
    session survived through `dev-data`. Its first continuation reused only the 512-token common prefix, showing that
    the earlier server cache entry had expired or been evicted during the rebuild interval; an immediate next turn
    reused 9,472 tokens and charged only 99 ordinary input tokens, confirming the header still worked. The disposable
    session was then deleted.
- [x] If caching misses, isolate whether OpenCode mutates prior messages, omits a cache/conversation identifier, drops
      reasoning content, changes tools/system prompts, or uses an incompatible endpoint.
  - OpenCode 1.18.31 uses xAI Chat Completions but supplies the Responses-style `promptCacheKey`; the pinned xAI SDK
    rejects that unknown option. Automatic caching still works, but one Grok 4.6 follow-up fell from 8,832 to 2,432
    cached tokens because no sticky-routing identifier reached xAI.
  - The pinned chat converter omits assistant reasoning parts during replay. Live tests show stable-prefix reuse still
    works, including tool loops, although this can limit how far a reasoning conversation's cached prefix extends.
- [x] Evaluate a minimal configuration, upstream issue, or reviewed plugin only after identifying the failure cause;
      never weaken ZDR merely to obtain cache hits without an explicit user decision.
  - Added `.config/opencode/plugins/xai-cache-routing.js`, a five-line xAI-only `chat.headers` hook that sends the
    OpenCode session ID as xAI's documented `x-grok-conv-id`. It makes no additional request and reads no credential.
  - Four temporary-plugin follow-ups and two tracked-plugin follow-ups remained on the long cached prefix. The tracked
    plugin auto-discovered successfully from the repository configuration through `XDG_CONFIG_HOME=/workspace/.config`.
- [x] Record a clear conclusion: caching confirmed, caching unavailable, or unresolved, including evidence and cost/
      privacy implications.
  - Caching is confirmed for both models with ZDR. Twelve direct Chat/Responses API responses all returned the canonical
    `x-zero-data-retention: true`; repeated calls reused nearly all 11–12k input tokens. On Chat Completions, exact xAI
    billed cost fell from $0.026508 to about $0.0079 for Grok 4.6 and from $0.0122626 to about $0.0028–$0.0030 for Grok
    Build. Latency improved for Grok 4.6 but was variable for Grok Build, so no latency guarantee is inferred.
  - xAI guarantees that ZDR prompts/outputs are not persisted to disk, while cache entries are server-local and may be
    evicted at any time. The exact cache-memory lifecycle under ZDR is not documented; live compatibility is confirmed,
    but transient inference-memory behavior is an evidence-based inference rather than an explicit xAI statement.
  - OpenCode exposes cache hits as `step_finish.part.tokens.cache.read` and uses the discounted cache-input rate in its
    local cost estimate. Direct xAI `cost_in_usd_ticks` remains authoritative for actual billing.
- [x] Commit the caching/ZDR milestone.

### 8. Final contingency validation

- [x] Confirm the cumulative live tests establish that OpenCode starts and operates through native xAI without relying
      on Codex, OpenAI, or OpenRouter. OpenRouter remains deliberately enabled as an optional provider but is not a
      dependency of the configured Grok workflow.
- [x] Accept the completed focused validation from items 2–7 instead of duplicating it: primary and small-model
      requests, unrestricted local tools, Exa web search, the intentionally deferred `/fast` integration, TUI behavior,
      credential/session/state persistence, ZDR, streaming/tool-loop caching, and container recreation were all tested.
- [x] Confirm the xAI secret is neither tracked nor baked into the image. Its only intentional durable location is the
      mode-0600 native credential store at `/data/share/opencode/auth.json`; unrestricted same-user tools and plugins
      can read it under the explicitly accepted full-autonomy policy.
- [x] Omit additional operational documentation at the user's request; the checklist retains the decisions and
      validation evidence needed for this setup.
- [x] Review the final task diff for unrelated changes and run the focused validation appropriate to the checklist-only
      closeout.
- [x] Commit the final validation closeout and provide a concise readiness report with remaining limitations.

## Current Status

- [x] Created branch `contingency-opencode-grok` from `trunk`.
- [x] Wrote this ordered checklist without implementing it.
- [x] Completed item 1: removed OpenRouter and installed OpenCode through the latest-tracking official installer.
- [x] Completed item 2's research, interview, threat model, configuration design, diagnostics, and live model tests.
- [x] Updated item 3 to use `/connect` with an expiring xAI key, removed the launch wrapper and environment injection,
      and documented the native credential file's persistence and exposure boundaries.
- [x] Rebuilt and validated the final item 3 workflow: connected xAI once, ran plain `opencode`, recreated the container,
      and confirmed credentials and sessions persist without another prompt.
- [x] Historical host recreation confirmed the superseded `dev-opencode-home` layout retained sessions without
      persisting the xAI key; the replacement shared-XDG layout is validated and the obsolete volume is deleted.
- [x] Completed item 4: added the approved Gruvbox TUI configuration and validated its load, cursor, mouse, title,
      status, default keybindings, and Grok request behavior with OpenCode 1.18.31.
- [x] Completed item 5 as an intentional deferral: `/fast` means xAI Priority Processing, but no workaround is installed
      while OpenCode remains on `@ai-sdk/xai@3.0.102`; revisit after it naturally updates to `3.0.120` or newer.
- [x] Completed item 6 with temporary anonymous Exa search enabled by default. Native xAI search is preferred but not
      exposed by OpenCode 1.18.31; a small repository-owned xAI-only custom tool is deferred as a future replacement.
- [x] Completed item 7: confirmed automatic caching for both models under ZDR, added reliable xAI session routing,
      validated streaming/tool loops and persisted-session replay across a container rebuild, and documented eviction.
- [x] Completed item 8 from the cumulative validation evidence; no duplicate smoke run or additional operational
      documentation was required.
- [x] OpenCode with Grok is ready as the contingency workflow.
