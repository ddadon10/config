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

- [ ] Create an exploration workspace and concise journal following the repository's Explore instructions; report the
      journal path.
- [ ] Research current official OpenCode documentation and its original upstream repository for:
  - Configuration locations, precedence, schemas, environment interpolation, provider definitions, model definitions,
    agents, instructions, permissions, tools, commands, plugins, MCP servers, sharing, updates, snapshots, logging, and
    session storage.
  - The native xAI provider and whether custom provider configuration is necessary or less desirable.
- [ ] Research current official xAI documentation for Grok 4.6 and `grok-build-0.1`:
  - Exact model IDs, availability, API compatibility, context/output limits, reasoning controls, tool calling,
    streaming, pricing-relevant settings, rate limits, and supported server-side tools.
- [ ] Verify every model ID and option against the live xAI API or OpenCode model listing instead of relying solely on
      documentation examples.
- [ ] Interview the user, one question at a time, and record each answer before writing configuration. Cover at least:
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
      model; use `high` reasoning for build and `xhigh` for plan.
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
    - Remaining interview branches: custom tools, LSP/formatters, Claude compatibility, compaction, logging/telemetry,
      and any final tool-specific exception.
- [ ] Produce a least-privilege threat model covering prompt injection, secret exfiltration, malicious repository
      instructions, shell execution, filesystem escape, untrusted plugins/MCP servers, telemetry, sharing, and local
      credential/session exposure.
- [ ] Propose the minimal global `opencode.json`/`opencode.jsonc` configuration and clearly separate user-wide settings
      from any project-specific settings that should be committed here.
- [ ] Validate the proposed configuration against the current OpenCode schema and with OpenCode's own diagnostics.
- [ ] Run a harmless Grok 4.6 smoke test and a small-model task; confirm which configuration and model are actually in
      use.
- [ ] Commit the approved configuration milestone.

### 3. Decide API-key injection and configuration persistence

- [ ] Document exactly where OpenCode reads credentials and where `/connect` stores them, including file permissions,
      plaintext/encryption behavior, precedence, and whether credentials enter logs, shell history, or process
      environments.
- [ ] Present three materially different credential approaches where viable:
  1. A prompt-on-launch shell function that exports `XAI_API_KEY` only to the OpenCode child process (expected default).
  2. OpenCode's native credential store populated via `/connect`.
  3. Host secret-manager or Docker-secret integration, if it fits this local development workflow.
- [ ] Interview the user to choose between entering the key for every launch and persisting it across containers.
- [ ] Design an `opencode-grok` alias or shell function modeled on the former OpenRouter flow, with hidden input, empty
      input rejection, no command-line argument exposure, and no key written to disk unless explicitly selected.
- [ ] Map all OpenCode state that may need persistence: general/TUI config, credentials, sessions, logs, caches,
      plugins, downloaded packages, and other XDG data/state/cache paths.
- [ ] Present and compare persistence layouts:
  - Reuse an existing broad volume only if isolation and ownership remain clear.
  - Add dedicated OpenCode config/data/cache volumes.
  - Bake non-secret defaults into the image and keep credentials/session data ephemeral.
- [ ] Interview the user about which state should survive container recreation and which state must remain ephemeral.
- [ ] Update `docker/.bashrc`, `docker/Dockerfile`, and `.zshrc` only as required by the approved credential and
      persistence design.
- [ ] Verify the key is absent from Git, image layers, shell history, process arguments, OpenCode logs, and diagnostic
      output; document unavoidable exposure to the target process environment.
- [ ] Recreate the container and confirm the selected configuration/state persists while secrets follow the approved
      policy.
- [ ] Commit the credential and persistence milestone.

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
- [ ] Next action: begin item 2 by creating the exploration workspace and journal, then research the configuration.
