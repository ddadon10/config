#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "--install" ]]; then
  lima_url="https://github.com/lima-vm/lima/releases/download/v2.2.0/lima-2.2.0-Darwin-arm64.tar.gz"
  curl -fsSL "${lima_url}" | sudo tar --extract --modification-time --no-same-owner --verbose --directory /usr/local
fi

limactl list azure >/dev/null 2>&1 || limactl create --tty=false --name=azure lima/azure.yaml
lima_host=$(limactl list azure --format 'unix://{{.Dir}}/sock/docker.sock')
docker context inspect azure >/dev/null 2>&1 || docker context create azure --description "Azure CLI environment" --docker "host=${lima_host}"

limactl start azure
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
limactl stop azure
