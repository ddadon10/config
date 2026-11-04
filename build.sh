#!/usr/bin/env bash
set -euo pipefail

docker login

docker tag ddadon/dev:current ddadon/dev:previous
docker build --file docker/Dockerfile --tag ddadon/dev:current .
docker push ddadon/dev:previous
docker push ddadon/dev:current

docker image prune --force

limactl start azure
docker --context azure tag ddadon/azureclient:current ddadon/azureclient:previous
docker --context azure build --file docker/Azure.Dockerfile --tag ddadon/azureclient:current .
docker --context azure push ddadon/azureclient:previous
docker --context azure push ddadon/azureclient:current

docker --context azure image prune --force
limactl stop azure
