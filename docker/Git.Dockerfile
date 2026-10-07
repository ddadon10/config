# check=skip=SecretsUsedInArgOrEnv;error=true

FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ENV SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
ENV LANG=C.UTF-8
ENV COLORTERM=truecolor
ENV TERM=xterm-256color

RUN apt-get update && apt-get install --yes --no-install-recommends \
    ca-certificates \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global push.autoSetupRemote true

RUN mkdir -p /root/.ssh
RUN ssh-keyscan github.com vs-ssh.visualstudio.com >> /root/.ssh/known_hosts

COPY <<'EOF' /root/.bashrc
export COLORTERM=truecolor
export SHELL=/bin/bash
export TERM=xterm-256color

ps1_git_orange='\[\033[38;2;240;80;50m\]'
ps1_path_blue='\[\033[38;2;69;133;136m\]'
ps1_arrow_yellow='\[\033[38;2;215;153;33m\]'
ps1_reset_attr='\[\033[0m\]'
ps1_git_icon=$'\ue702'
ps1_arrow_icon=$'\u276F'

PS1="${ps1_git_orange}${ps1_git_icon}${ps1_reset_attr} ${ps1_path_blue}\\w${ps1_reset_attr} ${ps1_arrow_yellow}${ps1_arrow_icon}${ps1_reset_attr} "
EOF

CMD ["/bin/bash"]
