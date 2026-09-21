#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--install" ]]; then
  lima_version="v2.2.0"
  lima_sha256="bbdef91774885a0d05f7b048c4eb89ae2bcf3a0c252ae7ca7934e63df76d93c3"
  lima_archive="lima-${lima_version#v}-Darwin-arm64.tar.gz"
  lima_url="https://github.com/lima-vm/lima/releases/download/${lima_version}/${lima_archive}"
  curl -fsSLo "${lima_archive}" "${lima_url}"
  echo "${lima_sha256}  ${lima_archive}" | shasum --algorithm 256 --check
  sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local --file "${lima_archive}"
  rm "${lima_archive}"
fi

limactl list azure >/dev/null 2>&1 || limactl create --tty=false --name=azure lima/azure.yaml
lima_host=$(limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock')
docker context inspect azure >/dev/null 2>&1 || docker context create azure --description "Azure CLI environment" --docker "host=${lima_host}"

limactl start azure
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
limactl stop azure
