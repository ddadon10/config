# check=skip=SecretsUsedInArgOrEnv;error=true

FROM debian:13-slim@sha256:89c1ea91e897f0fe0a3731595330bc45b8bdef4047464a07116f891a94054b31
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ENV SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
ENV LANG=C.UTF-8
ENV COLORTERM=truecolor
ENV TERM=xterm-256color

RUN apt-get update && apt-get install --yes --no-install-recommends \
    bash-completion \
    ca-certificates \
    curl \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/share/ghostty && \
    curl -fsSL https://raw.githubusercontent.com/ghostty-org/ghostty/refs/tags/v1.3.1/src/shell-integration/bash/ghostty.bash \
        -o /usr/local/share/ghostty/ghostty.bash

RUN git config --global push.autoSetupRemote true

RUN mkdir -p /root/.ssh
RUN ssh-keyscan github.com vs-ssh.visualstudio.com >> /root/.ssh/known_hosts

COPY <<'EOF' /root/.bashrc
export COLORTERM=truecolor
export SHELL=/bin/bash
export TERM=xterm-256color

PROMPT_COMMAND='printf "\033]2;gitsh | %s\033\134" "${PWD#/}"'

# Ghostty Shell Integration
builtin source /usr/local/share/ghostty/ghostty.bash

ps1_git_orange='\[\033[38;2;240;80;50m\]'
ps1_path_blue='\[\033[38;2;69;133;136m\]'
ps1_arrow_yellow='\[\033[38;2;215;153;33m\]'
ps1_reset_attr='\[\033[0m\]'
ps1_git_icon=$'\uE702'
ps1_arrow_icon=$'\u276F'

PS1="${ps1_git_orange}${ps1_git_icon}${ps1_reset_attr} ${ps1_path_blue}\\w${ps1_reset_attr} ${ps1_arrow_yellow}${ps1_arrow_icon}${ps1_reset_attr} "

# Bash Completion
source /usr/share/bash-completion/bash_completion
bind '"\C-i": menu-complete'
bind '"\e[Z": menu-complete-backward'
bind 'set bell-style none'
bind 'set colored-completion-prefix on'
bind 'set colored-stats on'
bind 'set menu-complete-display-prefix on'
bind 'set show-all-if-ambiguous on'
EOF

CMD ["/bin/bash"]
