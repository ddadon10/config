# ISOLATED_AZURE_LIMA ExecPlan

## Purpose and Context

This task will move the existing Azure administration container behind a dedicated Lima virtual machine while leaving
Docker Desktop as the unchanged default backend for normal development. The observable result is that invoking the
existing `azure` shell function starts the stopped Lima instance named `azure`, runs `ddadon/azureclient:current` using
the Docker Engine inside that VM without pulling it at runtime, removes the container when the session ends, and stops
the VM. `setup-lima.sh` optionally installs or updates Lima and creates the one-time Azure runtime state, while `build.sh`
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

- [`.zshrc`](/workspace/.zshrc) defines `azure()` at lines 60-69 and currently runs the image on whichever Docker backend
  is active.
- [`docker/Azure.Dockerfile`](/workspace/docker/Azure.Dockerfile) builds the existing Azure tooling image with Azure CLI,
  `kubectl`, `kubelogin`, and `k9s`. It does not need modification for this task.
- [`build.sh`](/workspace/build.sh) currently builds, tags, pushes, and prunes the Azure image through the caller's default
  Docker context. Its Azure operations must move to the explicit `azure` context without changing the dev or git image
  workflows.
- [`setup-lima.sh`](/workspace/setup-lima.sh) is the entry point for optional Lima installation/update, configuration
  validation, instance and Docker-context creation, and the initial Azure image build.
- [`README.md`](/workspace/README.md) contains only the repository title and remains unchanged by explicit user direction.
- The branch was clean at plan time. Lima v2.2.0 is installed on the user's Apple-silicon macOS host under `/usr/local`;
  it is intentionally unavailable inside this development container.

Assumptions and boundaries:

- Docker Desktop remains installed, running, and selected as the normal Docker backend. This task must not call
  `docker context use azure` or modify the global/default context.
- The macOS Docker CLI can retrieve the user's Docker Hub credentials through its existing Docker configuration and
  macOS credential helper when `build.sh` publishes images. Registry access is not part of the runtime `azure()` path.
- VPN connectivity from containers in the Lima VM has already been validated and does not need redesign.
- The VM uses the host-native architecture. `vmType` and `arch` are deliberately omitted: Lima selects its supported
  macOS default backend and native architecture, and the existing image build supports `aarch64` without Rosetta.
- The operator is responsible for ensuring global Lima defaults or overrides do not weaken this instance. The wrapper
  will trust the checked-in YAML rather than inspect global Lima configuration at runtime.
- The Lima instance, Docker context, Docker network, and shell entry point are all named `azure`.
- An invocation must be rejected unless the Lima instance is in the `Stopped` state. In particular, it must not join or
  stop an instance that was already running.
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

Create executable [`setup-lima.sh`](/workspace/setup-lima.sh) as a Bash script with `set -euo pipefail`. It accepts either
no argument or exactly `--install`; reject all other arguments with a concise usage message. It resolves
repository-relative paths from the script's own directory so it behaves consistently when invoked from another working
directory.

With `--install`, perform these steps before Azure runtime setup:

1. Require a `Darwin` host with `arm64` architecture and the commands `curl`, `jq`, `sudo`, and `tar`. This installer does
   not silently select an Intel or Linux archive.
2. If an `azure` instance already exists, require it to be stopped before replacing Lima binaries. Do not install over a
   running managed VM.
3. Resolve GitHub's latest stable Lima release tag and require a simple stable semantic version such as `v2.2.0`:

   ```sh
   VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | jq -er '.tag_name')
   ```

   Reject an empty or malformed tag before constructing a download URL. Strip the leading `v` only for the archive
   filename; retain it in the release path.
4. Install or update Lima with the dynamically resolved equivalent of:

   ```sh
   curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-${VERSION#v}-Darwin-arm64.tar.gz" |
     sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local
   ```

   Do not omit `--no-same-owner`. Before extraction, reject existing `/usr/local/bin`, `/usr/local/libexec`, or
   `/usr/local/share` directories that are not `root:wheel`; do not recursively change unrelated `/usr/local` ownership.
   After extraction, report `limactl --version` and verify that the installed version satisfies `lima/azure.yaml`.

Without `--install`, require `limactl` and a Lima version accepted by `lima/azure.yaml`; do not contact the GitHub releases
API. In both modes, require `docker` and validate `lima/azure.yaml` before creating runtime state.

The setup state machine must be non-destructive and support later `--install` updates:

1. Inspect the `azure` Lima instance and Docker context without changing either. If neither exists, continue with initial
   setup. If both exist, require the instance to be stopped and the context endpoint to equal that instance's
   `unix://.../.lima/azure/sock/docker.sock`, report that setup is already complete, and exit successfully. This lets
   `./setup-lima.sh --install` update Lima without recreating a valid Azure environment.
2. If only one object exists, the endpoint is mismatched, or the instance is not stopped, fail with inspection and
   recovery commands. Never delete, overwrite, start, or stop ambiguous pre-existing state.
3. On a fresh setup, run `limactl create --tty=false --name=azure lima/azure.yaml` and create the `azure` Docker context
   from `limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock'`. Never call `docker context use azure`.
4. Start the newly created instance and immediately install local cleanup that stops it on success, build failure,
   interruption, or termination while preserving the original failure status.
5. Build `ddadon/azureclient:current` directly through `docker --context azure` using `docker/Azure.Dockerfile`. Do not
   pull or push an image during setup.
6. Stop the instance and verify its final status is `Stopped`, the context endpoint is correct, and the image exists in
   the Azure engine. Leave Docker Desktop's selected context unchanged.

Do not automatically remove an instance or context if a later setup step fails; those are persistent objects and may be
useful for diagnosis. Cleanup owns only the VM start performed by the script. Document exact inspection and intentional
teardown commands for retrying a partial setup. Run `bash -n setup-lima.sh` after implementation.

### Milestone 3: Build and publish the Azure image through Lima

Update only the Azure section of [`build.sh`](/workspace/build.sh). Leave the dev and git image operations on their
existing default Docker backend. Every Azure image operation, including `image inspect`, `tag`, `build`, `push`, and
`image prune`, must specify `--context azure`; do not switch the global Docker context or export Docker endpoint variables.

The Azure build section must implement this contract:

1. Read `limactl list azure --format '{{.Status}}'` and continue only when the instance is `Stopped`. For a missing,
   running, broken, installing, or otherwise unexpected instance, fail without changing its state.
2. Start `azure`, then install subshell-local cleanup that stops only the VM started by this build. Preserve a failing
   Docker command's status, and surface a stop failure when all Docker commands succeeded.
3. If `ddadon/azureclient:current` already exists in the Azure engine, tag it as `ddadon/azureclient:previous`. On the
   first build, skip the previous tag and push rather than failing because no prior image exists.
4. Build `ddadon/azureclient:current` from `docker/Azure.Dockerfile` directly in the Azure engine:

   ```sh
   docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
   ```

5. Push `ddadon/azureclient:previous` when it was created, then push `ddadon/azureclient:current`. Publishing continues
   to use the macOS Docker client's existing registry credentials, but neither push is used to seed runtime state.
6. Run `docker --context azure image prune --force` so dangling Azure-engine images do not unnecessarily consume the
   20 GiB VM disk. Retain the existing unqualified final prune for the Docker Desktop build workflow.
7. Stop the VM through cleanup on success, Docker failure, interruption, or termination.

Use a subshell or another mechanism that scopes cleanup to the Azure section. Do not make `build.sh` join or stop a VM
that was already running. Run `bash -n build.sh` after the edit. The first build can take longer because it provisions
Docker in the VM and builds the Azure toolchain there.

### Milestone 4: Replace `azure()` with the isolated lifecycle

Update only the Azure section of [`.zshrc`](/workspace/.zshrc). Preserve the public function name `azure`, its interactive
terminal behavior, the `ctrl-_` detach sequence, the `azure` Docker network, and the image
`ddadon/azureclient:current`. Every Docker operation belonging to this function must specify `--context azure`.

The function must implement this contract in order:

1. Read the exact instance status with `limactl list azure --format '{{.Status}}'`.
2. Continue only when the result is `Stopped`. For a missing, `Running`, `Broken`, `Installing`, or otherwise unexpected
   instance, print a concise actionable error and return nonzero without changing VM state.
3. Run `limactl start azure` and return immediately if startup or Docker provisioning fails.
4. Immediately after successful startup, install function-local/subshell-local cleanup for `EXIT`, `HUP`, `INT`, and
   `TERM`. Cleanup must always attempt `limactl stop azure`, must not leak traps into the caller's interactive shell, and
   must preserve the container command's nonzero status. If the container succeeds but stopping fails, return the stop
   failure so a running VM is not silently reported as cleaned up.
5. Confirm `ddadon/azureclient:current` exists in the Azure engine. If it is absent, print an actionable instruction to
   build it from the repository and return nonzero through cleanup; do not pull it from a registry.
6. Ensure the `azure` network exists in the Lima Docker Engine by inspecting it first and creating it only when absent.
   Do not use unconditional `|| true`, because daemon or context failures must remain visible.
7. Run the existing image interactively with the equivalent of:

   ```sh
   docker --context azure run \
     --pull=never \
     --rm \
     --interactive \
     --tty \
     --detach-keys "ctrl-_" \
     --network azure \
     ddadon/azureclient:current
   ```

8. Stop the Lima VM through cleanup on normal shell exit, Docker failure, interruption, or termination.

Implement the lifecycle in a subshell-style zsh function or another mechanism that provides genuinely local traps.
Do not switch the current Docker context, export `DOCKER_HOST`/`DOCKER_CONTEXT`, mount macOS paths, mount the Docker
Desktop socket, add a named volume, or persist Azure configuration outside the disposable container.

`--pull=never` is mandatory. Merely omitting the option would select Docker's `missing` policy and could pull the image
automatically. The image is seeded or updated only by an explicit build against the Azure context, for example:

```sh
limactl start azure
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
limactl stop azure
```

`setup-lima.sh` performs the initial build. The manual sequence above is the recovery path; subsequent repository-wide
builds use the guarded Azure section in `build.sh`. The explicit context and no-pull runtime policy prevent the managed
workflow from silently placing or running the Azure image in Docker Desktop. Do not remove `--context azure` even though
`--pull=never` is also present.

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

1. Confirm `setup-lima.sh` rejects unknown arguments, and confirm its no-argument path does not call the GitHub release
   API. On Apple silicon, exercise `--install` and verify the resolved version is installed under `/usr/local` with the
   expected ownership. On other hosts, confirm `--install` rejects the platform before downloading or extracting.
2. Before setup, record `docker context show`. Run the setup script from outside the repository root and confirm it
   creates both `azure` objects, builds the image only in the Azure engine, leaves the instance stopped, and leaves the
   selected Docker context unchanged.
3. Rerun setup against the complete state and confirm it performs no runtime mutation. Exercise `--install` against the
   complete stopped state and confirm it can update Lima while preserving the instance, context, and stopped status.
   Validate partial or mismatched-state rejection through read-only inspection where destructive test setup is unsafe.
4. Inspect the created context and confirm its endpoint ends in `/.lima/azure/sock/docker.sock`.
5. Confirm the expanded port-forward list contains the all-interface TCP/UDP ignore rule before the inherited Docker
   Unix-socket rule. Start the VM and confirm `docker --context azure info` succeeds, proving that the Unix-socket rule
   remains functional despite suppressing TCP/UDP forwards.
6. Run `limactl shell azure -- findmnt -rn -t virtiofs,9p,fuse.sshfs`. Expect no host filesystem mounts, then stop the VM.
7. Record the Docker Desktop image ID for `ddadon/azureclient:current`, or its absence. Run the Azure build workflow and
   confirm the image exists in the Azure engine while the Docker Desktop image ID or absence is unchanged. Confirm the
   VM returns to `Stopped` after the build. If pushes are exercised, expect the macOS credential helper to authenticate.
8. Confirm every Azure Docker command in `setup-lima.sh`, `build.sh`, and `.zshrc` explicitly selects `--context azure`,
   and confirm the runtime command contains `--pull=never` rather than relying on Docker's default missing-image pull
   policy.
9. With the VM stopped, invoke `azure`, authenticate only as far as needed for a smoke test, exit the container, and
   confirm `limactl list azure --format '{{.Status}}'` returns `Stopped`. Confirm no exited Azure session container remains
   in `docker --context azure ps --all`.
10. Manually start the VM, invoke `azure`, and confirm the function rejects the session without launching a container or
   stopping the already-running VM. Stop it manually afterward.
11. Invoke `azure` from a stopped state and interrupt it once with Ctrl-C. Confirm the function returns a signal-related
   nonzero status and the VM reaches `Stopped`.
12. Confirm ordinary `docker context show`, `docker info`, and a non-mutating Docker Desktop command still address the
   original default backend.
13. Run one already-known VPN endpoint smoke check from the Azure container only if needed to ensure the final wrapper did
   not change networking. Do not broaden this into a VPN redesign.

The milestone passes only when install/update resolution, non-destructive setup, the no-mount invariant, explicit context
selection, reject-if-running behavior, build and runtime cleanup, no-pull runtime policy, Azure-engine image placement,
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
- [x] Resolved the public interface, names, registry delivery, no-`tmpfs` policy, and reject-if-running lifecycle.
- [x] Interviewed and resolved the VM resource, backend, proxy, port-forwarding, SSH, and guest-update choices.
- [x] Replaced runtime pulls with an explicit Azure-context build and `--pull=never` policy in the plan.
- [x] Defined `setup-lima.sh` as the non-destructive setup and optional latest-Lima install/update entry point.
- [x] Created and validated `lima/azure.yaml` as specified in Milestone 1.
- [x] Implemented and syntax-checked `setup-lima.sh`; exercised fresh, complete, partial, and invalid-argument paths with
  command stubs because the macOS runtime is outside this container.
- [x] Implemented and syntax-checked the Azure-context image workflow in `build.sh`; exercised first-build,
  repeat-build, reject-if-running, and build-failure cleanup paths with command stubs.
- [x] Implemented and syntax-checked the isolated `azure()` lifecycle in `.zshrc`; exercised success, rejection,
  missing-image, container-failure, and stop-failure paths with command stubs under zsh.
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
- Anonymous access to `ddadon/azureclient:current` returned HTTP 401 during exploration. The runtime no longer pulls this
  image; registry authentication is needed only when `build.sh` publishes it.
- The user selected the Azure-only interface, the name `azure`, and rejection when the instance is already running. The
  wrapper therefore never assumes ownership of a VM started elsewhere.
- The user explicitly rejected `tmpfs` complexity. `--rm` is the selected cleanup mechanism, with the documented disk
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
- The Azure image is built directly into the Lima Docker engine. `build.sh` retains registry publishing but explicitly
  targets the `azure` context for every Azure image operation and owns the VM lifecycle only from a stopped state.
- Runtime uses `--pull=never`, not an omitted pull option, because Docker's default missing-image policy could otherwise
  contact the registry. A missing image is an actionable build error, and runtime registry availability is irrelevant.
- `setup-lima.sh` is the setup entry point. Its `--install` mode resolves the latest stable GitHub release
  tag, validates the Apple-silicon macOS target and tag shape, installs with `--no-same-owner`, and doubles as a future
  Lima updater without recreating valid Azure state.
- Setup distinguishes absent, complete, and partial runtime state. It creates only from the fully absent state, treats a
  matching stopped instance and context as complete, and rejects partial, mismatched, or running state without teardown.
- The final `lima/azure.yaml` passed `limactl validate` using the Lima v2.2.0 binary and templates at upstream commit
  `de0816ea4bdc5267b428ab21025889b8dd785526`. Template expansion returned `2`, `2GiB`, `20GiB`, `null`, and `false` for
  the selected resource, mount, and proxy fields. It also produced the all-interface TCP/UDP ignore rule before a
  separate inherited rootless-Docker Unix-socket forwarding rule.
- `setup-lima.sh` passes `bash -n` and ShellCheck at warning severity. Stubbed command tests verified that a complete
  stopped state exits without mutation, a partial state is rejected without mutation, invalid arguments print usage,
  and a fresh state creates the instance and context, starts it, builds and inspects the image only through the `azure`
  context, stops it, and leaves the selected context unchanged. The install/update path and real Lima/Docker integration
  still require the Apple-silicon macOS host.
- `build.sh` passes `bash -n` and ShellCheck at warning severity. Stubbed lifecycle tests verified that the first Azure
  build skips the absent previous image, a repeat build tags and pushes it, every Azure image operation carries
  `--context azure`, a running VM is rejected without Lima mutation, and a simulated build status of 42 is preserved
  while the VM is stopped exactly once. The pre-existing dev/git commands and final default-context prune remain
  unqualified and therefore stay on Docker Desktop.
- `.zshrc` passes `zsh -n`. Direct stubbed execution under zsh verified creation of a missing Azure network, the complete
  explicit-context `--pull=never --rm` run command, one stop after success, rejection of a running VM without mutation,
  cleanup after a missing image, preservation of a container exit status of 37, reporting of a stop-only status of 55,
  and preservation of the container failure when both the container and stop fail. Testing also caught and removed use
  of zsh's read-only special parameter `status` from cleanup before commit.
- Final container-side validation passed: `zsh -n .zshrc`, `bash -n build.sh`, `bash -n setup-lima.sh`, ShellCheck at
  warning severity for both Bash scripts, `git diff --check`, and Lima v2.2.0 configuration validation. Effective template
  queries returned CPU `2`, memory `2GiB`, disk `20GiB`, mounts `null`, proxy propagation `false`, the full-port
  all-interface ignore rule, and the separate inherited Docker Unix-socket rule.
- Final simulated integration covered setup from outside the repository; no-argument avoidance of the GitHub API;
  complete, partial, running, and mismatched state handling; unchanged context selection; latest-tag URL construction;
  `--no-same-owner`; ownership and malformed-tag rejection before download/extraction; first and repeat image builds;
  running-state build rejection; cleanup with preserved failures; missing-image behavior; network creation; `--rm` and
  `--pull=never`; and stop-only failure reporting. Static auditing found no `docker context use`, `DOCKER_HOST`, or
  `DOCKER_CONTEXT`, and every Azure-engine Docker operation explicitly selects `--context azure`.
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
