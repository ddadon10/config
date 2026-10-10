# General Aliases
alias rm='rm -i'
alias ls='ls -aF'

# Load git-related ssh keys into the default ssh agent
if ! ssh-add -l >/dev/null 2>&1; then
  ssh-add --apple-load-keychain "${HOME}/.ssh/github_ed25519" "${HOME}/.ssh/azure_rsa"
fi

# dev starts a development container.
dev() {
  while :; do
    dev_web_port=$((RANDOM % 16384 + 49152))
    lsof -nP -iTCP:"${dev_web_port}" -sTCP:LISTEN >/dev/null 2>&1 || break
  done

  docker network create dev >/dev/null 2>&1 || true
  docker run \
    --rm \
    --interactive \
    --tty \
    --detach-keys "ctrl-_" \
    --env "GIT_USER_NAME=$(/usr/bin/git config --global user.name)" \
    --env "GIT_USER_EMAIL=$(/usr/bin/git config --global user.email)" \
    --env "DEV_WEB_PORT=${dev_web_port}" \
    --publish "127.0.0.1:${dev_web_port}:${dev_web_port}" \
    --network dev \
    --mount "type=volume,src=workspace,dst=/workspace" \
    --mount "type=volume,src=dev-codex-home,dst=/root/.codex" \
    --mount "type=volume,src=dev-data,dst=/data" \
    --mount "type=volume,src=dev-maven,dst=/root/.m2" \
    --workdir /workspace \
    ddadon/dev:current
}

# gitsh starts a git client container.
gitsh() {
  docker network create git >/dev/null 2>&1 || true
  docker run \
    --rm \
    --interactive \
    --tty \
    --detach-keys "ctrl-_" \
    --network git \
    --mount "type=bind,src=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock" \
    --mount "type=volume,src=workspace,dst=/workspace" \
    --workdir /workspace \
    ddadon/gitclient:current "$@"
}

# azure starts an Azure client container in a Lima VM.
azure() {
  limactl start azure || return
  docker --context azure run \
    --rm \
    --interactive \
    --tty \
    ddadon/azureclient:current
  limactl stop azure
}

# dcp copies a file or folder from the host to /data/shared.
dcp() {
  [[ $# == 1 ]] || { printf 'Usage: dcp <file-or-folder>\n' >&2; return 1; }
  local container_id
  container_id=$(docker create --mount "type=volume,src=dev-data,dst=/data" ddadon/dev:current) || return
  trap "docker rm \"${container_id}\" >/dev/null" EXIT
  docker cp --quiet "${1:a}" "${container_id}:/data/shared/"
}

# dget copies a file or folder from /data/shared to the host.
dget() {
  [[ $# == 2 && -d "$2" ]] || { printf 'Usage: dget <source> <existing-destination-folder>\n' >&2; return 1; }
  local container_id
  container_id=$(docker create --mount "type=volume,src=dev-data,dst=/data" ddadon/dev:current) || return
  trap "docker rm \"${container_id}\" >/dev/null" EXIT
  docker cp --quiet "${container_id}:/data/shared/$1" "${2:a}"
}

# Shell customization
export PS1="%n@mbp %~ %% "
