# check=error=true

FROM debian:sid@sha256:a2aa46262453eba3f464d8b1c7a8c31db85eb15af180ae34dd400615d7208547
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG PATH="/root/go/bin:${PATH}"

ENV LANG=C.UTF-8

RUN apt-get update && apt-get install --yes --no-install-recommends \
    bash-completion \
    bat \
    bind9-dnsutils \
    build-essential \
    ca-certificates \
    chromium \
    curl \
    fd-find \
    fzf \
    git \
    git-delta \
    gnupg \
    golang \
    gopls \
    gron \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    less \
    libsimdjson33 \
    locales \
    lsof \
    man-db \
    manpages \
    manpages-dev \
    ncdu \
    ncurses-term \
    neovim \
    nodejs \
    npm \
    openjdk-21-jdk-headless \
    postgresql \
    procps \
    psmisc \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    strace \
    sudo \
    tree \
    tree-sitter-cli \
    unzip \
    vim \
    xz-utils \
    yarnpkg \
    yq \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN <<EOF
    cluster_version="$(pg_lsclusters --no-header | grep -o '^[^ ]*')"
    pg_ctlcluster "${cluster_version}" main start
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD 'postgres';\""
    pg_ctlcluster "${cluster_version}" main stop
EOF

# See: https://github.com/ghostty-org/ghostty/discussions/8268
RUN cp /usr/share/terminfo/g/ghostty /usr/share/terminfo/x/xterm-ghostty

RUN npm install -g typescript && npm cache clean --force

RUN npm install -g \
    @tailwindcss/language-server \
    bash-language-server \
    dockerfile-language-server-nodejs \
    typescript-language-server \
    vscode-langservers-extracted \
    yaml-language-server \
    && npm cache clean --force

RUN <<EOF
    machine=$(uname -m)
    case "${machine}" in
        x86_64) arch="x64" ;;
        aarch64) arch="arm64" ;;
        *) exit 1 ;;
    esac
    ver=$(curl -sSfL "https://api.github.com/repos/LuaLS/lua-language-server/releases/latest" | jq -r '.tag_name')
    mkdir -p /opt/lua-language-server
    curl -sSfL "https://github.com/LuaLS/lua-language-server/releases/download/${ver}/lua-language-server-${ver}-linux-${arch}.tar.gz" | tar -xzf - -C /opt/lua-language-server
    ln -s /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server
EOF

RUN <<EOF
    mkdir -p /opt/jdtls
    curl -fsSL "https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz" | tar -xzf - -C /opt/jdtls
    ln -s /opt/jdtls/bin/jdtls /usr/local/bin/jdtls
EOF

RUN <<EOF
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com trixie main" > /etc/apt/sources.list.d/hashicorp.list
    apt-get update
    apt-get install --yes --no-install-recommends terraform terraform-ls
    rm -rf /var/lib/apt/lists/*
EOF

RUN <<EOF
    machine=$(uname -m)
    case "${machine}" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) exit 1 ;;
    esac
    curl -sSfL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${arch}/kubectl"
    chmod +x /usr/local/bin/kubectl
EOF

RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

RUN <<EOF
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get update
    apt-get install --yes --no-install-recommends google-cloud-cli
    rm -rf /var/lib/apt/lists/*
EOF

RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/batcat /usr/local/bin/bat

RUN npm install -g firebase-tools && npm cache clean --force

RUN go install github.com/jesseduffield/lazygit@latest && go clean -cache -modcache

RUN go install github.com/sosedoff/pgweb@latest && go clean -cache -modcache

RUN npm install -g ccusage && npm cache clean --force

COPY .config/nvim /root/.config/nvim
RUN XDG_DATA_HOME=/usr/local/share DEV_IMAGE_BUILD=1 nvim --headless "+qa"

RUN npm install -g @openai/codex@0.155.1 && npm cache clean --force

# See: https://github.com/anomalyco/opencode/issues/46189
RUN curl -fsSL https://opencode.ai/install | bash -s -- --version 1.18.31 --no-modify-path && \
    mv /root/.opencode/bin/opencode /usr/local/bin/opencode && \
    rmdir /root/.opencode/bin /root/.opencode

COPY .config/opencode /root/.config/opencode

# See: https://github.com/anomalyco/opencode/issues/37888
RUN opencode_version="$(opencode --version)" && \
    npm install --prefix /root/.config/opencode "@opencode-ai/plugin@${opencode_version}" && \
    npm cache clean --force

COPY .config/lazygit.yml /root/.config/lazygit/config.yml
COPY docker/.bashrc /root/.bashrc
COPY .vimrc /root/.vimrc
COPY .npmrc /root/.npmrc
COPY .codex/config.toml /etc/codex/config.toml
COPY .codex/skills/ /etc/codex/skills/
COPY AGENTS.md /etc/codex/AGENTS.md
RUN ln -s /etc/codex/AGENTS.md /root/.config/opencode/AGENTS.md
RUN mkdir -p /data/share /data/state /data/cache/gomod /data/cache/npm /data/gradle

CMD ["/bin/bash"]
