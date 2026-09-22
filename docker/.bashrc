# Aliases
alias cat='bat --plain --paging never'
alias codexplorer='codex --model gpt-5.6-sol --config model_reasoning_effort=ultra'
alias gclone='git clone'
alias gfetch='git fetch'
alias glsremote='git ls-remote'
alias gpull='git pull'
alias gpush='git push'
alias grep='grep --color=auto'
alias ls='ls -aF --color=auto'

# General
export BAT_THEME=gruvbox-dark
export COLORTERM=truecolor
export EDITOR=nvim
export LANG=C.UTF-8
export MANPAGER='bat --plain --language man'
export PATH="${HOME}/.local/bin:${HOME}/go/bin:${PATH}"
export SHELL=/bin/bash
export TERM=xterm-ghostty

# XDG
export XDG_CACHE_HOME=/data/cache
export XDG_DATA_HOME=/data/share
export XDG_STATE_HOME=/data/state

# Go
export CGO_ENABLED=0
export GOMODCACHE="${XDG_CACHE_HOME}/gomod"

# Java
dpkg_arch="$(dpkg --print-architecture)"
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-${dpkg_arch}"
export GRADLE_USER_HOME=/data/gradle

# Node
export NPM_CONFIG_CACHE="${XDG_CACHE_HOME}/npm"

# Codex
export IS_SANDBOX=1
ln -sfn /etc/agents/AGENTS.md /root/.codex/AGENTS.md

# OpenCode
export OPENCODE_DISABLE_CLAUDE_CODE=1
export OPENCODE_DISABLE_LSP_DOWNLOAD=true
# See: https://github.com/anomalyco/opencode/blob/014614d35b397775e5d397a490fc72368c894ec2/packages/opencode/src/share/share-next.ts#L23
export OPENCODE_DISABLE_SHARE=1

# Git
[ "$(git config --global --get user.name 2>/dev/null || true)" = "${GIT_USER_NAME}" ] || git config --global user.name "${GIT_USER_NAME}"
[ "$(git config --global --get user.email 2>/dev/null || true)" = "${GIT_USER_EMAIL}" ] || git config --global user.email "${GIT_USER_EMAIL}"

# PS1
ps1_debian_red='\[\033[38;2;206;0;86m\]'
ps1_path_blue='\[\033[38;2;69;133;136m\]'
ps1_arrow_yellow='\[\033[38;2;215;153;33m\]'
ps1_reset_attr='\[\033[0m\]'
ps1_debian_icon=$'\uF306'
ps1_arrow_icon=$'\u276F'

PS1="${ps1_debian_red}${ps1_debian_icon}${ps1_reset_attr} ${ps1_path_blue}\\w${ps1_reset_attr} ${ps1_arrow_yellow}${ps1_arrow_icon}${ps1_reset_attr} "

# Shell Options
shopt -s histappend
shopt -s extglob

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups

# Terminal Title
trap 'printf "\033]2;%s\033\\\\" "❯ ${BASH_COMMAND} - ${PWD}"' DEBUG
PROMPT_COMMAND='printf "\033]2;%s\033\\\\" "❯ ${PWD}"'

# Clipboard (OSC-52)
pbcopy() {
  local b64
  b64=$(base64 | tr -d '\n')
  printf '\033]52;c;%s\a' "$b64" >/dev/tty
}

# Bash Completion
source /usr/share/bash-completion/bash_completion
