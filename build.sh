#!/usr/bin/env bash
set -euo pipefail

docker tag ddadon/dev:current ddadon/dev:previous
docker build --file docker/Dockerfile --tag ddadon/dev:current .
docker push ddadon/dev:previous
docker push ddadon/dev:current

docker tag ddadon/gitclient:current ddadon/gitclient:previous
docker build --file docker/Git.Dockerfile --tag ddadon/gitclient:current .
docker push ddadon/gitclient:previous
docker push ddadon/gitclient:current

azure_status=$(limactl list azure --format '{{.Status}}')
if [[ $azure_status != Stopped ]]; then
  printf 'Error: Lima instance azure must be Stopped before the Azure build (current: %s).\n' "$azure_status" >&2
  exit 1
fi

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

  previous_image=false
  if docker --context azure image inspect ddadon/azureclient:current >/dev/null 2>&1; then
    docker --context azure tag ddadon/azureclient:current ddadon/azureclient:previous
    previous_image=true
  fi

  docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
  if $previous_image; then
    docker --context azure push ddadon/azureclient:previous
  fi
  docker --context azure push ddadon/azureclient:current
  docker --context azure image prune --force
)

docker image prune --force
