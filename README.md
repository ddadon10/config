# Config

## Isolated Azure client

Azure administration runs in a disposable Docker container inside a dedicated Lima VM. Normal development remains on
Docker Desktop:

```text
macOS
├── Docker Desktop         normal docker/build/compose commands
└── Lima VM: azure         separate Linux kernel, no macOS filesystem mounts
    └── Docker Engine
        └── ddadon/azureclient:current
```

The separate Lima kernel is the security boundary between development containers and production-capable Azure tooling.
This does not protect against compromise of macOS, the macOS user account, Lima's management files or socket, or the
Azure image itself.

### One-time setup and Lima updates

Run one of these commands from the repository root on an Apple-silicon Mac:

```sh
./setup-lima.sh           # Use an already-installed compatible Lima.
./setup-lima.sh --install # Install/update Lima, then set up Azure if needed.
```

The default mode requires `limactl` 2.2.0 or newer and `docker`. `--install` additionally requires `curl`, `jq`,
`sudo`, and `tar`. It queries GitHub for the latest stable Lima tag, accepts only a stable semantic-version tag, and
installs the Darwin arm64 archive under `/usr/local`. It is intentionally rejected on Intel Macs and non-macOS systems.

Before installation, `/usr/local/bin`, `/usr/local/libexec`, and `/usr/local/share`, when present, must be owned by
`root:wheel`. The extraction uses `--no-same-owner`, so archive ownership is not restored. If ownership is wrong, the
script stops and reports it; correct only the named directories explicitly rather than recursively changing unrelated
contents of `/usr/local`.

For troubleshooting, the resolved install is equivalent to:

```sh
VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | jq -er '.tag_name')
curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-${VERSION#v}-Darwin-arm64.tar.gz" |
  sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local
```

The setup script validates [`lima/azure.yaml`](lima/azure.yaml), creates the `azure` Lima instance and matching Docker
context, starts the VM, builds `ddadon/azureclient:current` directly in its Docker Engine, and stops the VM. It never
selects the `azure` context globally, so `docker context show` should remain unchanged. The first start can take longer
while Lima provisions Docker in the guest.

Setup is deliberately non-destructive. If the instance and context already exist, match, and the VM is stopped, setup
reports success without recreating them; this also lets `./setup-lima.sh --install` update Lima independently. A partial
setup, mismatched context, or running VM is rejected without mutation. Inspect the reported state before deciding how to
recover.

### Daily use

After loading this repository's `.zshrc`, run:

```sh
azure
```

The function requires the VM to be stopped, starts it, confirms that the image exists locally in the Lima Docker Engine,
creates the persistent `azure` Docker network when needed, and runs the container interactively. Runtime uses
`--pull=never` and does not depend on Docker Hub. Authenticate to Azure inside the container and exit when finished. The
container and its Azure configuration are removed by `--rm`, and the VM is stopped even when the session fails or is
interrupted. `Ctrl-_` remains the Docker detach sequence.

The function refuses to join or stop a VM that was already running. If the VM is running intentionally, finish that work
and run `limactl stop azure` before invoking `azure`.

### Build and publish

`setup-lima.sh` performs the initial Azure image build without pulling or pushing it. Subsequent repository-wide builds
use:

```sh
docker login # Required only for publishing images from build.sh.
./build.sh
```

The dev and git image sections continue to use the currently selected Docker backend, expected to be Docker Desktop. The
Azure section requires a stopped VM, starts it, builds directly through `docker --context azure`, pushes the previous
image when one exists and then the current image, prunes dangling layers in that engine, and stops the VM. Every Azure
image operation specifies the context; the script never changes the selected context.

### VM profile and persistence

The VM uses two CPUs, 2 GiB of memory, the host-native architecture, and a sparse 20 GiB logical disk. No VM backend is
pinned. The disk consumes host space as data is written rather than allocating 20 GiB immediately; deleting guest files
or Docker layers makes space reusable inside the guest but may not immediately return allocated space to macOS.

No macOS directory is mounted in the VM. Host proxy variables are not propagated, and automatic guest TCP/UDP forwarding
is suppressed; Lima's Unix-socket forwarding remains enabled for the explicit Docker context. The VM disk, Docker image
cache, and `azure` network persist between sessions. The session container and cloud configuration in its writable layer
are removed on exit, but neither `--rm` nor deletion inside a VM provides forensic erasure of previously written blocks.

The workflow trusts the checked-in YAML. If `$LIMA_HOME/_config/default.yaml` or `override.yaml` exists, inspect the
effective configuration before creating or starting `azure`; a global override can weaken these settings.

### Inspection and recovery

These commands do not select the Azure context globally:

```sh
limactl list azure
docker context inspect azure
docker context show

limactl start azure
docker --context azure info
docker --context azure image inspect ddadon/azureclient:current
limactl stop azure
```

The Docker context endpoint should end in `/.lima/azure/sock/docker.sock`. To confirm that no macOS filesystem transport
is mounted after starting the VM:

```sh
limactl shell azure -- findmnt -rn -t virtiofs,9p,fuse.sshfs
```

No output is expected. If initial image construction failed after the instance and context were created, rebuild it from
the repository root without using Docker Desktop:

```sh
limactl start azure
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
limactl stop azure
```

If cleanup fails, run `limactl stop azure`, inspect the instance with `limactl list azure`, and retain its disk for
diagnosis. Setup never removes persistent state automatically.

Only when intentional teardown is required, first stop the VM and then run:

```sh
docker context rm azure
limactl delete azure
```

Deleting the Lima instance destroys its VM disk, cached images, network, and any other guest state. Recreate it with
`./setup-lima.sh`.
