#!/usr/bin/env bash
set -euo pipefail

docker login

docker tag ddadon/dev:current ddadon/dev:previous
docker build --file docker/Dockerfile --tag ddadon/dev:current .
docker push ddadon/dev:previous
docker push ddadon/dev:current

docker tag ddadon/gitclient:current ddadon/gitclient:previous
docker build --file docker/Git.Dockerfile --tag ddadon/gitclient:current .
docker push ddadon/gitclient:previous
docker push ddadon/gitclient:current

docker image prune --force

limactl start azure
trap 'limactl stop azure' EXIT
docker --context azure tag ddadon/azureclient:current ddadon/azureclient:previous
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
docker --context azure push ddadon/azureclient:previous
docker --context azure push ddadon/azureclient:current

docker --context azure image prune --force
