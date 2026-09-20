#!/usr/bin/env bash
set -euo pipefail

usage() { printf 'Usage: %s [--install]\n' "${0##*/}" >&2; }

if (( $# > 1 )) || { (( $# == 1 )) && [[ $1 != --install ]]; }; then
  usage
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_lima=false
if (( $# == 1 )); then
  install_lima=true
fi

if $install_lima; then
  if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
    printf 'Error: --install supports only arm64 macOS.\n' >&2
    exit 1
  fi

  for command_name in curl jq sudo tar; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Error: required command not found: %s\n' "$command_name" >&2
      exit 1
    fi
  done

  if command -v limactl >/dev/null 2>&1; then
    lima_names=$(limactl list --format '{{.Name}}')
    while IFS= read -r instance_name; do
      if [[ $instance_name == azure ]]; then
        azure_status=$(limactl list azure --format '{{.Status}}')
        if [[ $azure_status != Stopped ]]; then
          printf 'Error: Lima instance azure must be Stopped before installing or updating Lima (current: %s).\n' "$azure_status" >&2
          exit 1
        fi
        break
      fi
    done <<< "$lima_names"
  fi

  for install_dir in /usr/local/bin /usr/local/libexec /usr/local/share; do
    if [[ -e $install_dir ]]; then
      owner_group=$(stat -f '%Su:%Sg' "$install_dir")
      if [[ $owner_group != root:wheel ]]; then
        printf 'Error: %s is owned by %s; expected root:wheel. Correct it explicitly before installing Lima.\n' \
          "$install_dir" "$owner_group" >&2
        exit 1
      fi
    fi
  done

  VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | jq -er '.tag_name')
  if [[ ! $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Error: GitHub returned an invalid stable Lima release tag: %s\n' "$VERSION" >&2
    exit 1
  fi

  printf 'Installing Lima %s for Darwin arm64...\n' "$VERSION"
  curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-${VERSION#v}-Darwin-arm64.tar.gz" |
    sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local
  hash -r
fi

for command_name in limactl docker; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "$command_name" >&2
    if [[ $command_name == limactl ]]; then
      printf 'Run %s --install on Apple-silicon macOS.\n' "$0" >&2
    fi
    exit 1
  fi
done

printf 'Using %s\n' "$(limactl --version)"
limactl validate "$repo_root/lima/azure.yaml"

lima_names=$(limactl list --format '{{.Name}}')
docker_context_names=$(docker context ls --format '{{.Name}}')
instance_exists=false
context_exists=false
while IFS= read -r instance_name; do
  if [[ $instance_name == azure ]]; then
    instance_exists=true
    break
  fi
done <<< "$lima_names"
while IFS= read -r context_name; do
  if [[ $context_name == azure ]]; then
    context_exists=true
    break
  fi
done <<< "$docker_context_names"

if $instance_exists; then
  azure_status=$(limactl list azure --format '{{.Status}}')
  expected_endpoint=$(limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock')
fi
if $context_exists; then
  actual_endpoint=$(docker context inspect azure --format '{{.Endpoints.docker.Host}}')
fi

if $instance_exists && $context_exists; then
  if [[ $azure_status != Stopped ]]; then
    printf 'Error: Lima instance azure must be Stopped (current: %s). Inspect it with: limactl list azure\n' \
      "$azure_status" >&2
    exit 1
  fi
  if [[ $actual_endpoint != "$expected_endpoint" ]]; then
    printf 'Error: Docker context azure points to %s, expected %s.\n' "$actual_endpoint" "$expected_endpoint" >&2
    printf 'Inspect it with: docker context inspect azure\n' >&2
    exit 1
  fi
  printf 'Azure Lima setup is already complete and stopped.\n'
  exit 0
fi

if $instance_exists || $context_exists; then
  printf 'Error: partial Azure Lima setup detected (instance: %s, context: %s); no changes were made.\n' \
    "$instance_exists" "$context_exists" >&2
  printf 'Inspect with: limactl list azure; docker context inspect azure\n' >&2
  printf 'If teardown is intentional: docker context rm azure; limactl delete azure\n' >&2
  exit 1
fi

selected_context=$(docker context show)
limactl create --tty=false --name=azure "$repo_root/lima/azure.yaml"
expected_endpoint=$(limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock')
docker context create azure --docker "host=$expected_endpoint"

(
  limactl start azure

  cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    stop_status=0
    limactl stop azure || stop_status=$?
    if (( status == 0 && stop_status != 0 )); then
      status=$stop_status
    fi
    exit "$status"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  docker --context azure build --file "$repo_root/docker/Azure.Dockerfile" --tag ddadon/azureclient:current "$repo_root"
  docker --context azure image inspect ddadon/azureclient:current >/dev/null
)

final_status=$(limactl list azure --format '{{.Status}}')
if [[ $final_status != Stopped ]]; then
  printf 'Error: Lima instance azure should be Stopped after setup (current: %s).\n' "$final_status" >&2
  exit 1
fi
actual_endpoint=$(docker context inspect azure --format '{{.Endpoints.docker.Host}}')
if [[ $actual_endpoint != "$expected_endpoint" ]]; then
  printf 'Error: Docker context azure changed unexpectedly: %s\n' "$actual_endpoint" >&2
  exit 1
fi
if [[ $(docker context show) != "$selected_context" ]]; then
  printf 'Error: the selected Docker context changed unexpectedly.\n' >&2
  exit 1
fi

printf 'Azure Lima setup is complete; the VM is stopped and Docker context %s remains selected.\n' "$selected_context"
