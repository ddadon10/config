# ISOLATED_AZURE_LIMA ExecPlan

## Purpose and Context

This task will move the existing Azure administration container behind a dedicated Lima virtual machine while leaving
Docker Desktop as the unchanged default backend for normal development. The observable result is that invoking the
existing `azure` shell function starts the stopped Lima instance named `azure`, runs `ddadon/azureclient:current` using
the Docker Engine inside that VM, removes the container when the session ends, and stops the VM. Ordinary commands such
as `docker build`, `docker run`, and `docker compose` must continue to target the caller's current Docker Desktop context.

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
- [`build.sh`](/workspace/build.sh) publishes `ddadon/azureclient:current` and `ddadon/azureclient:previous` to Docker Hub.
  The `current` image requires registry authentication for pulls.
- [`README.md`](/workspace/README.md) currently contains only the repository title and is the appropriate place for host
  installation and one-time setup instructions.
- The branch was clean at plan time. Lima v2.2.0 is installed on the user's Apple-silicon macOS host under `/usr/local`;
  it is intentionally unavailable inside this development container.

Assumptions and boundaries:

- Docker Desktop remains installed, running, and selected as the normal Docker backend. This task must not call
  `docker context use azure` or modify the global/default context.
- The macOS Docker CLI can retrieve the user's Docker Hub credentials through its existing Docker configuration and
  macOS credential helper. Context selection changes the daemon endpoint, not the client credential store.
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

### Milestone 2: Replace `azure()` with the isolated lifecycle

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
5. Ensure the `azure` network exists in the Lima Docker Engine by inspecting it first and creating it only when absent.
   Do not use unconditional `|| true`, because daemon or context failures must remain visible.
6. Run the existing image interactively with the equivalent of:

   ```sh
   docker --context azure run \
     --pull=always \
     --rm \
     --interactive \
     --tty \
     --detach-keys "ctrl-_" \
     --network azure \
     ddadon/azureclient:current
   ```

7. Stop the Lima VM through cleanup on normal shell exit, Docker failure, interruption, or termination.

Implement the lifecycle in a subshell-style zsh function or another mechanism that provides genuinely local traps.
Do not switch the current Docker context, export `DOCKER_HOST`/`DOCKER_CONTEXT`, mount macOS paths, mount the Docker
Desktop socket, add a named volume, or persist Azure configuration outside the disposable container.

`--pull=always` deliberately uses the macOS Docker client's existing registry credentials while storing the pulled image
inside the Lima Docker Engine. If an authenticated pull fails, first repair or repeat `docker login`; do not silently run
an unknown stale image. As a documented recovery option, the image can be built explicitly in the Lima engine with:

```sh
limactl start azure
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
limactl stop azure
```

Using that fallback requires deliberately changing `--pull=always` to a cache-compatible policy in both code and this
plan; it is not part of the initial implementation because macOS credential-helper authentication is the selected path.

Run `zsh -n .zshrc` after the related edit. Do not source the function from this Linux container as behavioral
validation, because the actual Lima and Docker endpoints exist only on macOS.

### Milestone 3: Document installation, setup, operation, and recovery

Expand [`README.md`](/workspace/README.md) with a focused Azure/Lima section covering:

1. The separate-kernel architecture and the fact that Docker Desktop remains the default backend.
2. Lima v2.2.0 installation on Apple silicon using the already-tested command:

   ```sh
   curl -fsSL "https://github.com/lima-vm/lima/releases/download/v2.2.0/lima-2.2.0-Darwin-arm64.tar.gz" |
     sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local
   ```

   Explain that `--no-same-owner` avoids restoring the release archive's `runner:staff` metadata. State that
   `/usr/local/bin`, `/usr/local/libexec`, and `/usr/local/share` are expected to be `root:wheel` for this installation,
   and recommend checking them before extraction rather than recursively changing unrelated `/usr/local` contents.
3. One-time configuration from the repository root:

   ```sh
   limactl validate lima/azure.yaml
   limactl create --name=azure lima/azure.yaml
   docker context create azure \
     --docker "host=$(limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock')"
   docker login
   ```

   `limactl create` must leave the new instance stopped so the `azure` function owns the first start. If an `azure`
   instance or Docker context already exists, setup must stop and ask the operator to inspect it rather than overwrite it.
4. Normal operation: invoke `azure`, authenticate to Azure inside the disposable container, exit when finished, and
   expect the VM to stop. Note that first startup provisions Docker and can take longer.
5. The selected VM profile: two CPUs, 2 GiB of memory, a sparse 20 GiB logical disk ceiling, native architecture, no
   explicit VM backend, no host proxy propagation, and no automatic guest TCP/UDP forwarding. Explain that actual host
   disk allocation grows with guest writes and can remain allocated after guest files or Docker layers are deleted.
6. The explicit persistence model: the VM's image cache and Docker network persist; the session container and its cloud
   configuration are removed by `--rm`; no macOS directory is mounted; no forensic-erasure guarantee is made.
7. The global-configuration assumption: the workflow trusts the checked-in YAML and does not defend against a user's
   `$LIMA_HOME/_config/default.yaml` or `override.yaml` weakening it. Operators using those files must inspect their
   effective configuration before creating or starting `azure`.
8. Inspection and recovery commands: `limactl list azure`, `docker context inspect azure`, `limactl start azure`,
   `limactl stop azure`, and authenticated pull testing. Document `docker context rm azure` and
   `limactl delete azure` only as intentional teardown actions, with a warning that deleting the VM removes its disk and
   cached images. Never make teardown automatic.

Keep the README instructions self-contained. A reader should not need this ExecPlan or prior conversation to install,
configure, operate, or troubleshoot the Azure environment.

### Milestone 4: Validate the complete behavior on macOS

Perform static checks once after all related edits:

```sh
zsh -n .zshrc
limactl validate lima/azure.yaml
limactl template yq lima/azure.yaml '.cpus'
limactl template yq lima/azure.yaml '.memory'
limactl template yq lima/azure.yaml '.disk'
limactl template yq lima/azure.yaml '.mounts'
limactl template yq lima/azure.yaml '.propagateProxyEnv'
limactl template yq lima/azure.yaml '.portForwards'
```

Then perform the following focused host integration checks. Record actual results under `Findings and Decisions`.

1. Before setup, record `docker context show`. After setup and every test, confirm the value is unchanged; `azure` must
   never become the global context.
2. Inspect the created context and confirm its endpoint ends in `/.lima/azure/sock/docker.sock`.
3. Confirm the expanded port-forward list contains the all-interface TCP/UDP ignore rule before the inherited Docker
   Unix-socket rule. Start the VM and confirm `docker --context azure info` succeeds, proving that the Unix-socket rule
   remains functional despite suppressing TCP/UDP forwards.
4. Run `limactl shell azure -- findmnt -rn -t virtiofs,9p,fuse.sshfs`. Expect no host filesystem mounts, then stop the VM.
5. Run `docker --context azure pull ddadon/azureclient:current`. Expect the macOS credential helper to authenticate and
   the image to be stored in the Lima engine, not Docker Desktop.
6. With the VM stopped, invoke `azure`, authenticate only as far as needed for a smoke test, exit the container, and
   confirm `limactl list azure --format '{{.Status}}'` returns `Stopped`. Confirm no exited Azure session container remains
   in `docker --context azure ps --all`.
7. Manually start the VM, invoke `azure`, and confirm the function rejects the session without launching a container or
   stopping the already-running VM. Stop it manually afterward.
8. Invoke `azure` from a stopped state and interrupt it once with Ctrl-C. Confirm the function returns a signal-related
   nonzero status and the VM reaches `Stopped`.
9. Confirm ordinary `docker context show`, `docker info`, and a non-mutating Docker Desktop command still address the
   original default backend.
10. Run one already-known VPN endpoint smoke check from the Azure container only if needed to ensure the final wrapper did
   not change networking. Do not broaden this into a VPN redesign.

The milestone passes only when the no-mount invariant, explicit context selection, reject-if-running behavior, cleanup on
normal exit and interruption, authenticated registry pull, and unchanged Docker Desktop default are all observed. If
cleanup fails, preserve the VM for diagnosis, stop it explicitly, inspect Lima logs, and do not delete its disk.

### Change management and recovery

During implementation, this ExecPlan is the living source of truth. At every stopping point, update `Progress`, record
evidence or changed decisions in `Findings and Decisions`, and add an `Audit Log` entry. Each Audit Log update requires a
local commit containing the ExecPlan and only the task-related changes covered by that entry. Never stage unrelated user
changes and never push.

The expected task files are exactly:

- `ISOLATED_AZURE_LIMA_EXECPLAN.md`
- `lima/azure.yaml`
- `.zshrc`
- `README.md`

Do not modify `docker/Azure.Dockerfile`, `build.sh`, Docker Desktop configuration, or other repository files unless new
evidence makes that necessary and the decision is first recorded here. Code rollback is by reverting the task's local
commits. Runtime rollback is separate: stop `azure`, remove only the Docker context if it is incorrect, and retain the VM
disk unless the operator explicitly chooses destructive deletion. Recreating either runtime object must use the checked-in
YAML and README commands.

## Progress

- [x] Inspected the current Azure shell function, image definition, build workflow, README, and clean branch state.
- [x] Verified Lima v2.2.0 Docker socket forwarding, plain-mode behavior, and `mounts: null` template expansion.
- [x] Resolved the public interface, names, registry delivery, no-`tmpfs` policy, and reject-if-running lifecycle.
- [x] Interviewed and resolved the VM resource, backend, proxy, port-forwarding, SSH, and guest-update choices.
- [ ] Create and validate `lima/azure.yaml` as specified in Milestone 1.
- [ ] Implement and syntax-check the isolated `azure()` lifecycle in `.zshrc`.
- [ ] Write the self-contained installation and operation documentation in `README.md`.
- [ ] Execute the macOS integration checks and record their exact results.
- [ ] Exact next action: create `lima/azure.yaml`, update this Progress section plus the Findings and Audit Log, stage only
  the plan and YAML, and create the first implementation commit.

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
- Anonymous access to `ddadon/azureclient:current` returned HTTP 401 during exploration. An authenticated pull is required,
  matching the existing authenticated push workflow in `build.sh`.
- The user selected the Azure-only interface, the name `azure`, and rejection when the instance is already running. The
  wrapper therefore never assumes ownership of a VM started elsewhere.
- The user explicitly rejected `tmpfs` complexity. `--rm` is the selected cleanup mechanism, with the documented disk
  persistence limitation.
- Installation guidance belongs in `README.md`; the YAML receives only concise comments explaining the security-relevant
  no-mount and port-forwarding settings, and `.zshrc` remains operational code rather than installation documentation.
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
- The exact final YAML has not yet been validated. An exploratory configuration containing the now-removed `vmType` and
  an incomplete port-ignore rule was used to expose the `guestIPMustBeZero` default; Milestone 1 must validate the agreed
  final form before creating the VM.
- No implementation files have been changed while writing or revising this plan.

## Audit Log

- 2026-09-20: Created the initial ExecPlan after local inspection and Lima v2.2.0 upstream validation. Recorded all agreed
  requirements, exclusions, exact file interfaces, lifecycle behavior, validation criteria, and recovery guidance. No
  implementation was started and no runtime state was changed.
- 2026-09-20: Revised the ExecPlan after the focused Lima configuration interview. Added the agreed two-CPU, 2 GiB,
  20 GiB sparse-disk profile; omitted `vmType`; disabled proxy propagation and automatic TCP/UDP forwarding; preserved
  inherited Docker socket forwarding; retained secure/default SSH and update settings; and expanded validation,
  documentation, findings, and recovery expectations. No implementation or host runtime state was changed.
