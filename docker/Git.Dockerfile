# check=skip=SecretsUsedInArgOrEnv;error=true

FROM debian:stable-slim@sha256:5bc3287b25407c965a30f38e32603dc253a3869e1b12a21ac09bfc27fd8b13ce
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

ENTRYPOINT ["/usr/bin/git"]
CMD ["--help"]
