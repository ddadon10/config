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
  - OpenCode 1.18.31 recognizes `XAI_API_KEY` for the native `xai` provider. A launch-time environment key remains in
    the OpenCode process environment and is inherited by its shell tools, but a hidden-input wrapper can keep the value
    out of command arguments, shell history, and disk.
  - `/connect` and `opencode auth login` offer xAI's `Manually enter API Key` method and store the key as unencrypted
    JSON in `${XDG_DATA_HOME:-~/.local/share}/opencode/auth.json`, written with mode `0600`. With this repository's
    current environment, the concrete path is `/root/.local/share/opencode/auth.json`.
  - In the current provider loader, stored API credentials are merged after environment credentials and therefore take
    precedence when both exist. Stored credentials are not copied into the process environment, although this profile's
    unrestricted filesystem tools can still read the credential file.
  - The normal hidden prompt/storage paths do not intentionally log the key; the live environment-key smoke tests found
    no exact key in OpenCode logs or state. Plugins, arbitrary shell commands, and unrestricted file access remain able
    to disclose either credential form under the approved full-autonomy policy.
- [x] Present three materially different credential approaches where viable:
  1. A prompt-on-launch shell function that exports `XAI_API_KEY` only to the OpenCode child process (expected default).
  2. OpenCode's native credential store populated via `/connect`.
  3. Host secret-manager or Docker-secret integration, if it fits this local development workflow.
- [x] Interview the user to choose between entering the key for every launch and persisting it across containers.
  - Decision on 2026-09-18: use an `opencode-grok` prompt on every launch, matching the former OpenRouter workflow.
    Keep the key ephemeral: hidden input, reject an empty value, pass `XAI_API_KEY` only to the OpenCode child, and do
    not write the key to the native credential store, repository, image, shell history, or command arguments.
- [x] Design an `opencode-grok` alias or shell function modeled on the former OpenRouter flow, with hidden input, empty
      input rejection, no command-line argument exposure, and no key written to disk unless explicitly selected.
- [x] Map all OpenCode state that may need persistence: general/TUI config, credentials, sessions, logs, caches,
      plugins, downloaded packages, and other XDG data/state/cache paths.
  - `${XDG_CONFIG_HOME:-~/.config}/opencode`: global `opencode.json`, `tui.json`, and global agents, commands, modes,
    plugins, skills, themes, tools, dependency manifests, and installed plugin packages. Repository-managed defaults can
    be baked into `/root/.config/opencode`; project `.opencode` content remains in the `/workspace` bind mount.
  - `${XDG_DATA_HOME:-~/.local/share}/opencode`: `opencode.db` sessions/messages plus logs, plans, truncated tool output,
    managed worktrees/repository data, and any `auth.json` or `mcp-auth.json`. This is the sensitive durable-data tier.
  - `${XDG_STATE_HOME:-~/.local/state}/opencode`: recent-model/variant selection, plugin metadata, and process locks. It
    is convenient rather than essential and can remain ephemeral when the model is pinned in global configuration.
  - `${XDG_CACHE_HOME:-~/.cache}/opencode`: refreshable models.dev metadata, skill cache, and downloaded helper binaries.
    This repository already sets `XDG_CACHE_HOME=/data/cache`, so it already lands in the persistent `dev-data` volume.
  - `${TMPDIR:-/tmp}/opencode`: disposable runtime files. `/root/.opencode/bin/opencode` is the image-installed executable,
    not the configuration directory, and is restored by rebuilding the image.
- [x] Present and compare persistence layouts:
  - Reuse the existing `dev-data` volume for OpenCode data and cache while baking non-secret configuration into the
    image.
  - Add a dedicated `dev-opencode-data` named volume while continuing to bake non-secret configuration into the image.
  - Bind-mount a host directory for directly inspectable and independently backed-up OpenCode data.
- [x] Interview the user about which state should survive container recreation and which state must remain ephemeral.
  - Decision on 2026-09-18: reuse the existing `dev-data` volume. The `opencode-grok` child will use
    `XDG_DATA_HOME=/data`, so its database, sessions, logs, plans, and tool-output data live under `/data/opencode`.
    Continue using the existing `/data/cache/opencode` cache. Keep credentials ephemeral, bake repository-managed global
    configuration into the image, and leave recent-model/plugin state and locks under `/root/.local/state/opencode`
    ephemeral. No additional `.zshrc` volume mount is needed.
  - Decision on 2026-09-18: keep the repository source of truth at `.config/opencode/opencode.json` and copy it to
    `/root/.config/opencode/opencode.json` in the image. This mirrors the existing Neovim layout, uses OpenCode's normal
    global configuration path, and preserves the ability for trusted project configuration to override global values.
  - Decision on 2026-09-18: retain sessions and the append-only INFO log until manual cleanup. Use
    `XDG_DATA_HOME=/data opencode session delete <sessionID>` for targeted session removal; document a deliberate full
    `/data/opencode` reset procedure after OpenCode is stopped. Do not add automatic age-based deletion or `logrotate`.
- [x] Update `docker/.bashrc`, `docker/Dockerfile`, and `.zshrc` only as required by the approved credential and
      persistence design.
  - Added the hidden-input `opencode-grok` function and approved environment flags to `docker/.bashrc`; added the
    repository-managed global configuration copy to `docker/Dockerfile`. The existing `dev-data` mount already meets
    the selected layout, so `.zshrc` required no change.
- [x] Verify the key is absent from Git, image layers, shell history, process arguments, OpenCode logs, and diagnostic
      output; document unavoidable exposure to the target process environment.
  - The function accepts the key through silent standard input and places only the variable name—not its value—in the
    tracked shell definition. It passes the key through the child environment, never a command argument. Exact-value
    scans after a live launch found no key in the repository, configuration, OpenCode data/logs, state, or cache.
  - Unavoidable exposure: OpenCode and every unrestricted shell command or plugin it launches can read `XAI_API_KEY`
    for that process lifetime. The key is removed with the process and is prompted again on the next launch.
- [ ] Recreate the container and confirm the selected configuration/state persists while secrets follow the approved
      policy.
  - Docker is unavailable in this container. Current-process validation proved that the tracked configuration resolves,
    a live Grok request succeeds, and the database/log land under `/data/opencode`. Host check after rebuilding: launch
    with `dev`, create a session with `opencode-grok`, exit, launch `dev` again, then run
    `XDG_DATA_HOME=/data opencode session list` and confirm the session remains while the key is requested again.
  - Manual cleanup: stop OpenCode before changing its files. Delete one session with
    `XDG_DATA_HOME=/data opencode session delete <sessionID>`. Rotate the log recoverably by moving
    `/data/opencode/log/opencode.log` aside. Reset all durable OpenCode data recoverably by moving `/data/opencode` to a
    backup name; the next `opencode-grok` launch recreates it.
- [x] Commit the credential and persistence milestone in the same end-of-phase commit as the approved configuration.

### 4. Match the OpenCode TUI to the current environment

- [ ] Compare current Codex, Ghostty, shell, Vim/Neovim, and VS Code preferences with supported OpenCode TUI settings.
- [ ] Research the current dedicated `tui.json` schema and avoid deprecated TUI keys in `opencode.json`.
- [ ] Propose a minimal TUI configuration using the built-in Gruvbox theme when it matches the current palette.
- [ ] Configure a non-blinking block cursor if OpenCode can control it reliably; otherwise document the terminal-level
      fallback and avoid conflicting cursor controls.
- [ ] Interview the user about notifications, sounds, mouse support, scrolling/acceleration, diff display, status
      information, keybindings, and terminal-title behavior.
- [ ] Check for conflicts with Ghostty's existing cursor and shell-integration settings.
- [ ] Validate the TUI interactively for color, cursor behavior, diffs, scrolling, notifications, and keybindings.
- [ ] Commit the approved TUI milestone.

### 5. Evaluate a `/fast` workflow for Grok

- [ ] Define the desired semantics with the user: lower reasoning, `grok-build-0.1`, a cheaper Grok 4.6 variant, or a
      temporary model switch for the current session.
- [ ] Check whether current OpenCode provides a native model variant, command, keybinding, agent switch, or equivalent
      that can implement those semantics.
- [ ] If native support is insufficient, evaluate in this order:
  1. A custom OpenCode command or dedicated fast agent.
  2. A small local plugin with no external network access or dependencies.
  3. A shell-level alternate launcher only if in-session switching is impossible.
- [ ] For any plugin, review the exact source, permissions, dependencies, update behavior, and data flows before use;
      do not install an unreviewed third-party plugin.
- [ ] Implement only the approved approach and document how to enable, identify, and disable fast mode.
- [ ] Verify the active model/options change as intended and can return safely to Grok 4.6 in the same workflow.
- [ ] Commit the fast-mode milestone.

### 6. Evaluate web search with OpenCode and Grok

- [ ] Research OpenCode's `websearch` tool availability, provider restrictions, search backend, data flow, credentials,
      retention, citations, and permission controls.
- [ ] Research xAI's native web/X search tools for Grok 4.6 and `grok-build-0.1`, including availability through the API,
      citations, domains/date filters, pricing, ZDR compatibility, and whether OpenCode's xAI integration exposes them.
- [ ] Run controlled comparisons for freshness, source quality, citations, latency, failures, and prompt-injection
      handling.
- [ ] Prefer native Grok search only if OpenCode exposes it reliably and it meets the security/privacy requirements;
      otherwise present OpenCode search, a reviewed plugin/MCP integration, or no search as explicit alternatives.
- [ ] Interview the user about permitted search providers, acceptable query/content disclosure, approval behavior, and
      whether search should be enabled by default.
- [ ] Configure the chosen path with least privilege and verify which service receives each query.
- [ ] Commit the web-search milestone.

### 7. Verify prompt caching with xAI ZDR enabled

- [ ] Research official xAI prompt-caching behavior for both selected models and determine whether ZDR changes cache
      eligibility, retention, routing, billing, or observability.
- [ ] Inspect OpenCode's xAI request path for stable conversation/cache identifiers, prefix preservation, reasoning
      content handling, and exposure of cached-token usage.
- [ ] Confirm ZDR on the actual API responses using xAI's documented response indicator; do not infer it only from the
      console setting.
- [ ] Establish a repeatable test with one initial request and multiple same-session follow-ups whose prompt prefix is
      large and stable enough to qualify for caching.
- [ ] Capture request-independent evidence from response usage or debug telemetry without logging prompts or the API
      key; compare first-request and follow-up cached-token counts, latency, and billed usage where available.
- [ ] Repeat with Grok 4.6 and `grok-build-0.1`, streaming and tool calls if they are part of the final workflow, and
      after a container restart if persisted sessions are expected to continue.
- [ ] If caching misses, isolate whether OpenCode mutates prior messages, omits a cache/conversation identifier, drops
      reasoning content, changes tools/system prompts, or uses an incompatible endpoint.
- [ ] Evaluate a minimal configuration, upstream issue, or reviewed plugin only after identifying the failure cause;
      never weaken ZDR merely to obtain cache hits without an explicit user decision.
- [ ] Record a clear conclusion: caching confirmed, caching unavailable, or unresolved, including evidence and cost/
      privacy implications.
- [ ] Commit the caching/ZDR milestone.

### 8. Final contingency validation and documentation

- [ ] Simulate Codex/OpenAI being unavailable and start OpenCode without relying on any OpenAI or OpenRouter service.
- [ ] Verify primary and small-model requests, tool permissions, editing, shell approvals, web search, fast mode, TUI,
      restart persistence, ZDR, and cache behavior against the decisions recorded above.
- [ ] Confirm no OpenRouter configuration or credential remains and no xAI secret is tracked or baked into the image.
- [ ] Document installation, launch, key rotation/removal, configuration locations, persisted volumes, updates,
      troubleshooting, and complete uninstall/rollback steps.
- [ ] Review the final diff for unrelated changes and run focused validation once after the related edits.
- [ ] Commit the final documentation and provide a concise readiness report with verified facts, remaining risks, and
      any unresolved gaps.

## Current Status

- [x] Created branch `contingency-opencode-grok` from `trunk`.
- [x] Wrote this ordered checklist without implementing it.
- [x] Completed item 1: removed OpenRouter and installed OpenCode through the latest-tracking official installer.
- [x] Completed item 2's research, interview, threat model, configuration design, diagnostics, and live model tests.
- [x] Implemented item 3's approved prompt and persistence layout; configuration diagnostics, wrapper checks, a live
      Grok request, and exact-key persistence scans passed.
- [ ] Host-only check: rebuild and recreate the container to confirm the named volume retains `/data/opencode`.
- [ ] Next action after the host check: begin item 4's TUI comparison and interview.
