# check=error=true

FROM debian:13-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8

RUN apt-get update && apt-get install --yes --no-install-recommends \
    bash-completion \
    bind9-dnsutils \
    ca-certificates \
    curl \
    fzf \
    iproute2 \
    jq \
    less \
    openssh-client \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -fsSL 'https://azurecliprod.blob.core.windows.net/$root/deb_install.sh' | bash

# Install kubectl and kubelogin
RUN az aks install-cli

# Install k9s
RUN <<EOF
    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            version="v0.51.0"
            checksum="c3752ad51a5a4015a113819c4eeb6e55a4d0e4b8e652494797532f6fc8161dd7"
            ;;
        aarch64)
            arch="arm64"
            version="v0.51.0"
            checksum="3ee05c82e5f9198928a4e86133608ba6a2c10a2244d6a7789e820f78319d640c"
            ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    curl -fsSLo k9s.tar.gz "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${arch}.tar.gz"
    echo "${checksum}  k9s.tar.gz" | sha256sum --check -
    tar -xzf k9s.tar.gz -C /usr/local/bin k9s
    rm k9s.tar.gz
EOF

RUN kubectl completion bash > /etc/bash_completion.d/kubectl && \
    kubelogin completion bash > /etc/bash_completion.d/kubelogin && \
    k9s completion bash > /etc/bash_completion.d/k9s

COPY <<'EOF' /root/.bashrc
export COLORTERM=truecolor
export EDITOR=vim
export SHELL=/bin/bash
export TERM=xterm-256color

ps1_azure_blue='\[\033[38;2;0;120;212m\]'
ps1_path_blue='\[\033[38;2;69;133;136m\]'
ps1_arrow_yellow='\[\033[38;2;215;153;33m\]'
ps1_reset_attr='\[\033[0m\]'
ps1_azure_icon=$'\U000F0805'
ps1_arrow_icon=$'\u276F'

PS1="${ps1_azure_blue}${ps1_azure_icon}${ps1_reset_attr} ${ps1_path_blue}\\w${ps1_reset_attr} ${ps1_arrow_yellow}${ps1_arrow_icon}${ps1_reset_attr} "
shopt -s histappend
shopt -s extglob
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
source /usr/share/bash-completion/bash_completion

# Interactive Azure and Kubernetes selection
azsub() {
    local subscription
    subscription=$(az account list --query '[].[name,id]' -o tsv) || {
        echo 'Could not list Azure subscriptions.' >&2
        return 1
    }
    [[ -n "$subscription" ]] || {
        echo 'No Azure subscriptions found.' >&2
        return 1
    }
    subscription=$(fzf --height='~33%' --prompt='Subscription: ' <<< "$subscription") || {
        echo 'No Azure subscription selected.' >&2
        return 1
    }
    az account set --subscription "$(printf '%s' "$subscription" | cut -f2)" || {
        echo 'Could not change the Azure subscription.' >&2
        return 1
    }
    echo "Azure subscription changed to: $(printf '%s' "$subscription" | cut -f1)"
}

azaks() {
    local cluster
    cluster=$(az aks list --query '[].[resourceGroup,name]' -o tsv) || {
        echo 'Could not list AKS clusters.' >&2
        return 1
    }
    [[ -n "$cluster" ]] || {
        echo 'No AKS clusters found in the selected subscription.' >&2
        return 1
    }
    cluster=$(fzf --height='~33%' --prompt='AKS cluster: ' <<< "$cluster") || {
        echo 'No AKS cluster selected.' >&2
        return 1
    }
    az aks get-credentials \
        --resource-group "$(printf '%s' "$cluster" | cut -f1)" \
        --name "$(printf '%s' "$cluster" | cut -f2)"
}

azns() {
    local namespace
    namespace=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}') || {
        echo 'Could not list Kubernetes namespaces.' >&2
        return 1
    }
    [[ -n "$namespace" ]] || {
        echo 'No Kubernetes namespaces found.' >&2
        return 1
    }
    namespace=$(fzf --height='~33%' --prompt='Namespace: ' <<< "$namespace") || {
        echo 'No Kubernetes namespace selected.' >&2
        return 1
    }
    kubectl config set-context --current --namespace="$namespace"
}
EOF

CMD ["/bin/bash"]
