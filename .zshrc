# General Aliases
alias rm='rm -i'
alias ls='ls -aF'

# Load git-related ssh keys into the default ssh agent
if ! ssh-add -l >/dev/null 2>&1; then
  ssh-add --apple-load-keychain "${HOME}/.ssh/github_ed25519" "${HOME}/.ssh/azure_rsa"
fi

# Dev Env
dev() {
  while :; do
    dev_web_port=$((RANDOM % 16384 + 49152))
    lsof -nP -iTCP:"$dev_web_port" -sTCP:LISTEN >/dev/null 2>&1 || break
  done

  docker network create dev >/dev/null 2>&1 || true
  docker run \
    --rm \
    --interactive \
    --tty \
    --detach-keys "ctrl-_" \
    --env "GIT_USER_NAME=$(/usr/bin/git config --global user.name)" \
    --env "GIT_USER_EMAIL=$(/usr/bin/git config --global user.email)" \
    --env "DEV_PROJECT_ROOT=${PWD}" \
    --env "DEV_WEB_PORT=${dev_web_port}" \
    --publish "127.0.0.1:${dev_web_port}:${dev_web_port}" \
    --network dev \
    --mount "type=bind,src=${PWD},dst=/workspace" \
    --mount "type=volume,src=dev-codex-home,dst=/root/.codex" \
    --mount "type=volume,src=dev-data,dst=/data" \
    --mount "type=volume,src=dev-maven,dst=/root/.m2" \
    --workdir /workspace \
    ddadon/dev:current
}

# Git Client
git() { echo "Git is disabled on the host. Use gclone, gfetch, glsremote, gpull, gpush or run git from a container." >&2; return 1; }

_gitclient() {
  docker network create git >/dev/null 2>&1 || true
  docker run \
    --rm \
    --interactive \
    --tty \
    --detach-keys "ctrl-_" \
    --mount "type=bind,src=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock" \
    --network git \
    --mount "type=bind,src=${PWD},dst=/workspace" \
    --workdir /workspace \
    ddadon/gitclient:current "$@"
}

alias gclone='_gitclient clone'
alias gfetch='_gitclient fetch'
alias glsremote='_gitclient ls-remote'
alias gpull='_gitclient pull'
alias gpush='_gitclient push'

# Azure Client
azure() (
  local azure_status
  if ! azure_status=$(limactl list azure --format '{{.Status}}'); then
    print -u2 'Error: cannot inspect Lima instance azure. Run ./setup-lima.sh from the configuration repository.'
    return 1
  fi
  if [[ $azure_status != Stopped ]]; then
    print -u2 "Error: Lima instance azure must be Stopped before use (current: $azure_status)."
    return 1
  fi

  limactl start azure || return

  cleanup() {
    local command_status=$?
    trap - EXIT HUP INT TERM
    local stop_status=0
    limactl stop azure || stop_status=$?
    if (( command_status == 0 && stop_status != 0 )); then
      command_status=$stop_status
    fi
    exit "$command_status"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! docker --context azure image inspect ddadon/azureclient:current >/dev/null 2>&1; then
    print -u2 'Error: ddadon/azureclient:current is unavailable in Lima. Run ./build.sh from the configuration repository.'
    return 1
  fi
  if ! docker --context azure network inspect azure >/dev/null 2>&1; then
    docker --context azure network create azure >/dev/null
  fi

  docker --context azure run \
    --pull=never \
    --rm \
    --interactive \
    --tty \
    --detach-keys "ctrl-_" \
    --network azure \
    ddadon/azureclient:current
)

# Shell customization
export PS1="%n@mbp %~ %% "
