# ISOLATED_AZURE_LIMA ExecPlan

## Purpose and Context

This task will move the existing Azure administration container behind a dedicated Lima virtual machine while leaving
Docker Desktop as the unchanged default backend for normal development. The observable result is that invoking the
existing `azure` shell function starts the Lima instance named `azure`, runs `ddadon/azureclient:current` using the
Docker Engine inside that VM, removes the container when the session ends, and then stops
the VM. `setup-lima.sh` optionally installs pinned Lima v2.2.0 and creates the Azure runtime state, while `build.sh`
builds and publishes the Azure image through the explicit `azure` Docker context. Ordinary commands such as
`docker build`, `docker run`, and `docker compose` must continue to target the caller's current Docker Desktop context.

The security boundary is the separate Lima Linux kernel. The Lima VM must have no macOS filesystem mounts, so it cannot
see the host home directory, source trees, `.ssh`, `.kube`, or host cloud configuration. The Docker Unix socket forwarded
by Lima is retained so the macOS Docker CLI can explicitly address the VM through a context named `azure`. The container
is disposable through `--rm`; by explicit decision, credentials may use the container writable layer and no `tmpfs` is
introduced. Consequently, credential files may touch the Lima disk during a session and deletion is not forensic erasure.

The VM is intentionally sized for one interactive Azure tooling container: two CPUs, 2 GiB of memory, and a 20 GiB
primary disk. The disk value is a logical capacity ceiling rather than an up-front host allocation; its allocated space
grows as the guest writes data. Docker images and layers persist between sessions, and deleting them makes guest space
reusable but may not immediately return the corresponding allocated space to macOS.

Relevant current repository state:

- [`.zshrc`](/workspace/.zshrc) defines the minimal `azure()` start, explicit-context Docker run, and stop lifecycle.
- [`docker/Azure.Dockerfile`](/workspace/docker/Azure.Dockerfile) builds the existing Azure tooling image with Azure CLI,
  `kubectl`, `kubelogin`, and `k9s`. It does not need modification for this task.
- [`build.sh`](/workspace/build.sh) uses the explicit `azure` context for Azure image operations while leaving the dev and
  git image workflows on the caller's default Docker context.
- [`setup-lima.sh`](/workspace/setup-lima.sh) is the entry point for optional pinned Lima installation, shallow
  instance and Docker-context creation, and the Azure image build.
- [`README.md`](/workspace/README.md) contains only the repository title and remains unchanged by explicit user direction.
- The branch was clean at plan time. Lima v2.2.0 is installed on the user's Apple-silicon macOS host under `/usr/local`;
  it is intentionally unavailable inside this development container.

Assumptions and boundaries:

- Docker Desktop remains installed, running, and selected as the normal Docker backend. This task must not call
  `docker context use azure` or modify the global/default context.
- The macOS Docker CLI can retrieve the user's Docker Hub credentials through its existing Docker configuration and
  macOS credential helper when `build.sh` publishes images.
- VPN connectivity from containers in the Lima VM has already been validated and does not need redesign.
- The VM uses the host-native architecture. `vmType` and `arch` are deliberately omitted: Lima selects its supported
  macOS default backend and native architecture, and the existing image build supports `aarch64` without Rosetta.
- The operator is responsible for ensuring global Lima defaults or overrides do not weaken this instance. The wrapper
  will trust the checked-in YAML rather than inspect global Lima configuration at runtime.
- The Lima instance, Docker context, and shell entry point are all named `azure`.
- The deliberately minimal runtime wrapper does not inspect prior VM state. It assumes ownership after a successful
  `limactl start azure` and stops the VM after the Docker command returns.
- This task is Azure-specific. It does not create a general `prod` command, add gcloud tooling, migrate development away
  from Docker Desktop, add persistent credential volumes, add `tmpfs`, or revisit Docker ECI, Docker Sandbox, or Apple's
  `container` tool.
- The design protects against compromise confined to a development container or the Docker Desktop Linux VM. It does
  not protect against compromise of macOS, the macOS user account, the Lima management files/socket, or the trusted
  Azure tooling image itself.

## Plan of Work

### Milestone 1: Add the constrained, no-mount Lima configuration

Create [`lima/azure.yaml`](/workspace/lima/azure.yaml) with this effective interface:

```yaml
minimumLimaVersion: 2.2.0
base: template:docker

cpus: 2
memory: 2GiB
disk: 20GiB

# Keep macOS files outside the Azure VM.
mounts: null

# Retain Unix-socket forwarding from template:docker, but suppress TCP/UDP forwarding.
portForwards:
- guestIP: 0.0.0.0
  guestIPMustBeZero: false
  proto: any
  ignore: true

propagateProxyEnv: false
```

`mounts: null` is intentional and must not be replaced by `mounts: []`. Verification against Lima v2.2.0 commit
`de0816ea4bdc5267b428ab21025889b8dd785526` showed that `null` overrides the mounts inherited from `template:docker`,
while the template's `guestSocket`/`hostSocket` Docker forwarding remains present. The configuration inherits Lima's
rootless Docker template rather than duplicating its provisioning scripts.

The `portForwards` ignore rule must retain `guestIPMustBeZero: false`. Without it, Lima expands the default to `true`, so
the rule ignores only listeners bound to `0.0.0.0` and localhost-only listeners can still reach Lima's automatic fallback
forward. With `false`, `0.0.0.0` matches listeners on any guest interface. This TCP/UDP rule must coexist with, not replace,
the inherited Docker Unix-socket forwarding. `propagateProxyEnv: false` prevents host proxy variables and possible
embedded credentials from entering the VM; VPN and DNS behavior continues through Lima's enabled host resolver.

Do not add `vmType`, `arch`, Rosetta, SSH forwarding, or `upgradePackages` entries. The selected behavior is Lima's native
architecture and current defaults for those settings, so explicit entries would only pin values that the design does not
need to override. In particular, `vmType` is not part of the security boundary: both supported backends provide a separate
guest kernel.

Validate on macOS with:

```sh
limactl validate lima/azure.yaml
limactl template yq lima/azure.yaml '.cpus'
limactl template yq lima/azure.yaml '.memory'
limactl template yq lima/azure.yaml '.disk'
limactl template yq lima/azure.yaml '.mounts'
limactl template yq lima/azure.yaml '.propagateProxyEnv'
limactl template yq lima/azure.yaml '.portForwards'
```

Expected results are successful validation; `2`, `2GiB`, and `20GiB` for the resource fields; `null` for mounts; `false`
for proxy propagation; an ignore rule covering guest ports 1-65535 on any interface; and a separate port-forward entry
from the rootless guest Docker socket to `{{.Dir}}/sock/docker.sock`. If template expansion does not produce those results,
stop before creating the VM. Do not compensate by enabling plain mode, copying host directories into the guest, or
removing the Docker socket forward.

### Milestone 2: Add the Lima installation and setup entry point

Create executable [`setup-lima.sh`](/workspace/setup-lima.sh) as a short Bash script with `set -euo pipefail`. Assume it
is invoked from the repository root, like `build.sh`.

When its first argument is `--install`, install the pinned Lima v2.2.0 Darwin arm64 archive under `/usr/local` using
`--no-same-owner`. Do not query the GitHub API, resolve versions dynamically, check the platform or directory ownership,
or reject other arguments.

Use shallow idempotency for setup: create the `azure` Lima instance only when `limactl list azure` fails, and create the
`azure` Docker context only when `docker context inspect azure` fails. Do not validate or reconcile existing objects.
Start the VM, install one `EXIT` trap that stops it, and build `ddadon/azureclient:current` directly through
`docker --context azure`. Do not pull or push an image during setup. Run `bash -n setup-lima.sh` after implementation.

### Milestone 3: Build and publish the Azure image through Lima

Update only the Azure section of [`build.sh`](/workspace/build.sh). Leave the dev and git image operations on their
existing default Docker backend. Start `azure` and assume `setup-lima.sh` already created
`ddadon/azureclient:current`; tag that image as `previous`, build `current`, push both tags, and prune dangling Azure
images. Then stop `azure` before the final unqualified Docker Desktop prune. Every Azure image operation must specify
`--context azure`. Do not install cleanup traps; if an intermediate command fails, the operator stops the VM manually.
Run `bash -n build.sh` after the edit.

### Milestone 4: Replace `azure()` with the isolated lifecycle

Update only the Azure section of [`.zshrc`](/workspace/.zshrc) with the selected straight-line lifecycle:

```zsh
azure() {
  limactl start azure || return
  docker --context azure run --rm -it ddadon/azureclient:current
  limactl stop azure
}
```

The argumentless `return` propagates a failed `limactl start` status and prevents Docker or stop from running. After a
successful start, Docker runs interactively through the explicit context and the VM is stopped when Docker returns. Do
not add status preflights, image preflights, a custom Docker network, traps, subshells, or exit-status bookkeeping.

`setup-lima.sh` performs the initial build, so runtime uses Docker's default pull policy. The explicit context ensures the
container runs in Lima rather than Docker Desktop.

Run `zsh -n .zshrc` after the related edit. Do not source the function from this Linux container as behavioral
validation, because the actual Lima and Docker endpoints exist only on macOS.

### Milestone 5: Keep repository documentation unchanged

Do not expand [`README.md`](/workspace/README.md). The user explicitly removed the generated operator guide after review;
the README remains its original `# Config` title only.

### Milestone 6: Validate the complete behavior on macOS

Perform static checks once after all related edits:

```sh
zsh -n .zshrc
bash -n build.sh
bash -n setup-lima.sh
limactl validate lima/azure.yaml
limactl template yq lima/azure.yaml '.cpus'
limactl template yq lima/azure.yaml '.memory'
limactl template yq lima/azure.yaml '.disk'
limactl template yq lima/azure.yaml '.mounts'
limactl template yq lima/azure.yaml '.propagateProxyEnv'
limactl template yq lima/azure.yaml '.portForwards'
```

Then perform the following focused host integration checks. Record actual results under `Findings and Decisions`.

1. Confirm the no-argument setup path does not install Lima. On Apple silicon, exercise `--install` and confirm it uses
   the pinned v2.2.0 Darwin arm64 archive with `--no-same-owner` before continuing into setup.
2. Before setup, record `docker context show`. Run the setup script from the repository root and confirm it
   creates both `azure` objects, builds the image only in the Azure engine, leaves the instance stopped, and leaves the
   selected Docker context unchanged.
3. Rerun setup against complete state and confirm the shallow existence checks reuse the instance and context, then
   start the VM, rebuild the image, and stop it.
4. Inspect the created context and confirm its endpoint ends in `/.lima/azure/sock/docker.sock`.
5. Confirm the expanded port-forward list contains the all-interface TCP/UDP ignore rule before the inherited Docker
   Unix-socket rule. Start the VM and confirm `docker --context azure info` succeeds, proving that the Unix-socket rule
   remains functional despite suppressing TCP/UDP forwards.
6. Run `limactl shell azure -- findmnt -rn -t virtiofs,9p,fuse.sshfs`. Expect no host filesystem mounts, then stop the VM.
7. Record the Docker Desktop image ID for `ddadon/azureclient:current`, or its absence. Run the Azure build workflow and
   confirm the image exists in the Azure engine while the Docker Desktop image ID or absence is unchanged. Confirm the
   VM returns to `Stopped` after the build. If pushes are exercised, expect the macOS credential helper to authenticate.
8. Confirm every Azure Docker command in `setup-lima.sh`, `build.sh`, and `.zshrc` explicitly selects `--context azure`.
9. With the VM stopped, invoke `azure`, authenticate only as far as needed for a smoke test, exit the container, and
   confirm `limactl list azure --format '{{.Status}}'` returns `Stopped`. Confirm no exited Azure session container remains
   in `docker --context azure ps --all`.
10. Invoke `azure` from a stopped state and interrupt Docker once with Ctrl-C. Confirm control proceeds to
   `limactl stop azure` and the VM reaches `Stopped`.
11. Confirm ordinary `docker context show`, `docker info`, and a non-mutating Docker Desktop command still address the
   original default backend.
12. Run one already-known VPN endpoint smoke check from the Azure container only if needed to ensure the final wrapper did
   not change networking. Do not broaden this into a VPN redesign.

The milestone passes only when install/update resolution, non-destructive setup, the no-mount invariant, explicit context
selection, straight-line runtime and successful-build stop behavior, Azure-engine image placement,
and unchanged Docker Desktop default are all observed. If cleanup fails, preserve the VM for diagnosis, stop it
explicitly, inspect Lima logs, and do not delete its disk.

### Change management and recovery

During implementation, this ExecPlan is the living source of truth. At every stopping point, update `Progress`, record
evidence or changed decisions in `Findings and Decisions`, and add an `Audit Log` entry. Each Audit Log update requires a
local commit containing the ExecPlan and only the task-related changes covered by that entry. Never stage unrelated user
changes and never push.

The expected task files are exactly:

- `ISOLATED_AZURE_LIMA_EXECPLAN.md`
- `lima/azure.yaml`
- `setup-lima.sh`
- `build.sh`
- `.zshrc`

Do not modify `docker/Azure.Dockerfile`, Docker Desktop configuration, or other repository files unless new evidence makes
that necessary and the decision is first recorded here. Code rollback is by reverting the task's local commits. Runtime
rollback is separate: stop `azure`, remove only the Docker context if it is incorrect, and retain the VM disk unless the
operator explicitly chooses destructive deletion. Recreating either runtime object must use the checked-in YAML and
setup script.

## Progress

- [x] Inspected the current Azure shell function, image definition, build workflow, README, and clean branch state.
- [x] Verified Lima v2.2.0 Docker socket forwarding, plain-mode behavior, and `mounts: null` template expansion.
- [x] Resolved the public interface, names, registry delivery, and no-`tmpfs` policy.
- [x] Interviewed and resolved the VM resource, backend, proxy, port-forwarding, SSH, and guest-update choices.
- [x] Builds the image explicitly in the Azure context before runtime.
- [x] Defined `setup-lima.sh` as the concise setup and optional pinned Lima v2.2.0 installation entry point.
- [x] Created and validated `lima/azure.yaml` as specified in Milestone 1.
- [x] Simplified and syntax-checked `setup-lima.sh` to pinned optional installation, shallow object existence checks, and
  one build cleanup trap.
- [x] Simplified and syntax-checked the Azure section of `build.sh` to straight-line previous/current publishing and an
  explicit stop before the final Docker Desktop prune.
- [x] Simplified and syntax-checked `azure()` to the selected straight-line start, Docker run, and stop lifecycle.
- [x] Restored `README.md` to its original title-only content by user direction.
- [x] Completed the full static validation set and safe container-side simulated integration checks.
- [ ] Execute the macOS integration checks and record their exact results.
- [ ] Exact next action: from the repository on the Apple-silicon Mac, run `./setup-lima.sh`, then execute the Milestone 6
  host checks against the real Lima VM, Docker Desktop, registry credentials, interactive terminal, VPN, and signals.

## Findings and Decisions

- Lima v2.2.0's `template:docker` provisions rootless Docker and forwards `/run/user/{{.UID}}/docker.sock` in the guest to
  `{{.Dir}}/sock/docker.sock` on macOS. This supports an ordinary Docker context without sharing a Linux kernel with
  Docker Desktop.
- Lima plain mode disables dynamic port forwarding and the guest agent, so it is incompatible with this desired host
  Docker CLI flow. `plain` remains false.
- A local template inheriting `template:docker` was expanded using the v2.2.0 template engine. With `mounts: null`, the
  expanded result retained `mounts: null`, retained both Docker socket-forward fields, and passed `limactl validate`.
- `mounts: []` is not selected because inherited template lists are merged; it does not state the override as reliably as
  the verified null value.
- Docker contexts and registry credentials are separate client concerns. The `azure` context selects the Lima daemon,
  while the macOS Docker CLI continues to obtain Docker Hub credentials from its normal configuration/keychain.
- Anonymous access to `ddadon/azureclient:current` returned HTTP 401 during exploration. Normal runtime uses the image
  built during setup, while `build.sh` publishes through the macOS Docker client's credentials.
- The user selected the Azure-only interface and the name `azure`, then explicitly replaced the defensive runtime wrapper
  with a straight-line lifecycle. The wrapper now assumes ownership after `limactl start azure` succeeds.
- The user explicitly rejected `tmpfs` complexity. `--rm` is the selected cleanup mechanism, with the known disk
  persistence limitation.
- The generated operator guide was too broad for this repository and was removed by user direction. `README.md` remains
  unchanged apart from its original title.
- The selected resource profile is two CPUs, 2 GiB of memory, and a 20 GiB primary disk. The disk is sparse: 20 GiB is
  its logical ceiling, while host allocation grows with written data and may not shrink after guest deletion.
- `vmType` and `arch` are omitted. Lima's supported macOS default and native architecture are sufficient, the Azure image
  supports `aarch64`, and pinning a backend is not necessary for the separate-kernel security property.
- Host proxy propagation is explicitly disabled. Lima's host resolver remains enabled by default because its DNS behavior
  is useful for the already-validated VPN path.
- Automatic guest TCP/UDP forwarding is suppressed. The ignore rule explicitly uses `guestIPMustBeZero: false`; v2.2.0
  expansion showed that omitting the field resolves it to `true`, which would not match localhost-only listeners. The
  separate Docker Unix-socket rule inherited from `template:docker` must remain.
- SSH-agent, host public-key, and X11 forwarding remain at Lima's disabled defaults instead of being repeated. Guest
  package upgrades also remain at the default `false`; the VM uses the packages in its selected Ubuntu image.
- The workflow trusts the local YAML and does not add runtime guards for global Lima defaults or overrides. This is an
  explicit operator assumption rather than a claim that global configuration cannot affect the VM.
- The Azure image is built directly into the Lima Docker engine. `build.sh` assumes setup created the current image, then
  uses a straight-line tag, build, push-both-tags, and prune sequence through the explicit `azure` context. It stops Lima
  before the final Docker Desktop prune; an earlier failure intentionally leaves manual VM cleanup to the operator.
- Runtime intentionally uses Docker's default pull policy because setup builds the image before use.
- `setup-lima.sh --install` installs the hardcoded Lima v2.2.0 Darwin arm64 archive with `--no-same-owner`; it deliberately
  performs no API version resolution, platform guard, ownership check, or post-install validation.
- Setup assumes repository-root execution. It creates the instance and context only when their respective inspection
  commands fail, without validating existing object state or endpoint consistency, then always starts, builds, and stops.
- The final `lima/azure.yaml` passed `limactl validate` using the Lima v2.2.0 binary and templates at upstream commit
  `de0816ea4bdc5267b428ab21025889b8dd785526`. Template expansion returned `2`, `2GiB`, `20GiB`, `null`, and `false` for
  the selected resource, mount, and proxy fields. It also produced the all-interface TCP/UDP ignore rule before a
  separate inherited rootless-Docker Unix-socket forwarding rule.
- `setup-lima.sh` passes `bash -n` and ShellCheck at warning severity. Stubbed tests verified the pinned install command,
  missing-object creation, existing-object reuse, explicit-context build, and EXIT-trap stop. Real Lima/Docker integration
  still requires the Apple-silicon macOS host.
- `build.sh` passes `bash -n` and ShellCheck at warning severity. Stubbed lifecycle tests verified the straight-line
  previous/current operations, explicit Azure context, and normal stop before the final default-context prune. The
  pre-existing dev/git commands and final prune remain unqualified and therefore stay on Docker Desktop.
- `.zshrc` passes `zsh -n`. The final minimal wrapper keeps only start failure propagation, the explicit-context
  `--rm -it` Docker run using the image built during setup, and a following VM stop.
- Final container-side validation passed: `zsh -n .zshrc`, `bash -n build.sh`, `bash -n setup-lima.sh`, ShellCheck at
  warning severity for both Bash scripts, `git diff --check`, and Lima v2.2.0 configuration validation. Effective template
  queries returned CPU `2`, memory `2GiB`, disk `20GiB`, mounts `null`, proxy propagation `false`, the full-port
  all-interface ignore rule, and the separate inherited Docker Unix-socket rule.
- Final simulated integration covered pinned optional installation, shallow creation and reuse of setup objects,
  `--no-same-owner`, first and repeat image builds, and build cleanup. The final minimal runtime wrapper verifies start
  failure propagation and the explicit-context `--rm -it` command followed by stop. Static auditing found
  no `docker context use`, `DOCKER_HOST`, or `DOCKER_CONTEXT`.
- This Linux container cannot execute the real macOS integration portion. No Lima VM, Docker context, Docker image,
  registry push, Azure login, VPN request, filesystem-mount inspection, interactive terminal, or signal cleanup was
  exercised on the user's Mac. Those observations remain required before the final milestone can be checked off.

## Audit Log

- 2026-09-20: Created the initial ExecPlan after local inspection and Lima v2.2.0 upstream validation. Recorded all agreed
  requirements, exclusions, exact file interfaces, lifecycle behavior, validation criteria, and recovery guidance. No
  implementation was started and no runtime state was changed.
- 2026-09-20: Revised the ExecPlan after the focused Lima configuration interview. Added the agreed two-CPU, 2 GiB,
  20 GiB sparse-disk profile; omitted `vmType`; disabled proxy propagation and automatic TCP/UDP forwarding; preserved
  inherited Docker socket forwarding; retained secure/default SSH and update settings; and expanded validation,
  documentation, findings, and recovery expectations. No implementation or host runtime state was changed.
- 2026-09-20: Replaced the runtime registry-pull design with explicit Azure-context builds. Added guarded Lima lifecycle
  requirements to `build.sh`, selected `--pull=never` for `azure()`, kept pushes as publishing-only behavior, added
  first-build and image-placement handling, and revised documentation, validation, recovery, scope, and progress. No
  implementation or host runtime state was changed.
- 2026-09-20: Added the planned `setup-lima.sh` interface. Made it responsible for non-destructive one-time setup, initial
  image build, and optional latest stable Lima installation/update through GitHub release metadata; added platform,
  ownership, state, cleanup, documentation, validation, recovery, scope, and progress requirements. No implementation or
  host runtime state was changed.
- 2026-09-20: Implemented `lima/azure.yaml` with the agreed resource limits, null host mounts, suppressed automatic
  TCP/UDP forwarding, retained inherited Docker Unix-socket forwarding, and disabled proxy propagation. Validated the
  final effective configuration with Lima v2.2.0; no VM or Docker runtime state was created in the Linux container.
- 2026-09-20: Added executable `setup-lima.sh` with guarded latest-release installation/update, ownership checks,
  compatible-version validation, non-destructive runtime-state handling, explicit-context instance creation and initial
  image build, context preservation, and failure-safe VM cleanup. Static checks and simulated state/lifecycle checks
  passed; host installation and integration remain pending on macOS.
- 2026-09-20: Reworked only the Azure section of `build.sh` to require a stopped VM, own its start/stop lifecycle, build
  directly in the `azure` engine, conditionally preserve and publish the previous image, publish the current image, and
  prune that engine through explicit context selection. Static checks and simulated success, rejection, and failure
  paths passed; real image construction and registry publishing remain pending on macOS.
- 2026-09-20: Replaced `azure()` with a subshell-scoped Lima lifecycle that rejects non-stopped state, starts and always
  stops the VM it owns, checks the local Azure-engine image, creates the isolated network when missing, and runs the
  disposable container with explicit context and no-pull policy. Syntax and simulated zsh lifecycle/failure checks
  passed; real interactive and signal behavior remain pending on macOS.
- 2026-09-20: Expanded `README.md` into a self-contained operator guide for the isolated Azure environment, including
  installation and updates, daily sessions, publishing, the resource/security/persistence model, inspection, recovery,
  and intentional teardown. Cross-checked the documented object names, image, contexts, paths, flags, and commands
  against the implemented files.
- 2026-09-20: Completed all validation possible in the Linux workspace. The combined syntax, lint, Lima v2.2 template,
  static policy, and simulated state/lifecycle suite passed, including installer safeguards and failure-status cleanup.
  Recorded the exact macOS-only integration gap and left the host milestone open rather than claiming VM behavior that
  this container cannot observe.
- 2026-09-20: Removed the generated Azure/Lima operator guide from `README.md` at the user's request and restored its
  original title-only content. Updated the plan to make repository documentation explicitly out of scope; no runtime or
  implementation behavior changed in this correction.
- 2026-09-20: Simplified `azure()` at the user's direction to a straight-line `limactl start`, explicit-context
  `docker run`, and `limactl stop`. Removed state and image preflights, the custom network, traps, subshell cleanup, detach
  configuration, and exit-status bookkeeping; retained `--pull=never`, `--rm`, and interactive terminal behavior.
- 2026-09-20: Simplified `setup-lima.sh` at the user's direction. Pinned Lima v2.2.0 directly, assumed repository-root
  execution, replaced the defensive state machine with shallow instance/context existence checks, and retained only one
  EXIT cleanup trap around the Azure-context image build.
- 2026-09-20: Simplified the Azure section of `build.sh` to a straight-line lifecycle with one EXIT cleanup trap while
  preserving previous/current tags and pushes. Removed runtime `--pull=never` from `.zshrc` because setup builds the image
  before use.
- 2026-09-20: Removed the `build.sh` EXIT trap at the user's direction and added a normal `limactl stop azure` after the
  Azure prune and before the final Docker Desktop prune. Intermediate failures now intentionally require manual cleanup.
