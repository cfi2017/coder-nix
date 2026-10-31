# syntax=docker/dockerfile:1
FROM ubuntu:26.04 AS base

ARG TARGETARCH
ARG NIX_VERSION=2.34.1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash bash-completion bubblewrap build-essential bzip2 ca-certificates curl direnv \
    git gnupg iproute2 jq less locales man-db openssh-client procps ripgrep \
    sudo tmux unzip wget xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 \
    && userdel -r ubuntu \
    && groupadd --gid 1000 coder \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash coder \
    && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder \
    && mkdir -p /nix /etc/nix \
    && chown coder:coder /nix

# Explicit checksums keep the installer and its payload pinned together.
RUN case "$TARGETARCH" in \
      amd64) system=x86_64-linux; sha=92fc64a0740353215dec590508b9008cc8bd8e7c3d2b387a65da28146a78442f ;; \
      arm64) system=aarch64-linux; sha=81aed0600605ee0494d2cd82c441b1ff6ecad7d3efcc6d4505a70aefc67b865c ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 3 \
      "https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${system}.tar.xz" -o /tmp/nix.tar.xz \
    && echo "$sha  /tmp/nix.tar.xz" | sha256sum --check \
    && mkdir /tmp/nix-install \
    && tar -xJf /tmp/nix.tar.xz -C /tmp/nix-install --strip-components=1 \
    && sudo -u coder /tmp/nix-install/install --no-daemon --no-channel-add --no-modify-profile \
    && ln -s "$(readlink -f /home/coder/.nix-profile)" /opt/nix \
    && mkdir -p /nix/var/nix/gcroots \
    && ln -s /opt/nix /nix/var/nix/gcroots/workspace-nix \
    && rm -rf /tmp/nix.tar.xz /tmp/nix-install

COPY nix.conf /etc/nix/nix.conf
COPY nix-profile.sh /etc/profile.d/nix.sh
COPY shell/bashrc /etc/coder/bashrc
RUN echo '. /etc/coder/bashrc' >> /etc/bash.bashrc
ENV USER=coder \
    HOME=/home/coder \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    NIX_REMOTE=local \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/home/coder/.local/bin:/home/coder/.nix-profile/bin:/home/coder/.local/state/nix/profile/bin:/opt/nix/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Coder replaces the entrypoint with its agent bootstrap. No daemon or
# entrypoint initialization is needed, including with an empty mounted home.
USER coder
WORKDIR /home/coder
CMD ["sleep", "infinity"]

# Optional reverse-engineering workspace. Keep the ordinary image as default.
FROM base AS rea
USER root
COPY rea /etc/coder/rea
RUN chmod +x /etc/coder/rea/setup-agents \
    && ln -s /etc/coder/rea/setup-agents /usr/local/bin/rea-setup-agents
USER coder
RUN nix-build /etc/coder/rea/tools.nix --out-link /tmp/rea-tools \
    && sudo ln -s "$(readlink -f /tmp/rea-tools)" /opt/rea-tools \
    && ln -s /opt/rea-tools /nix/var/nix/gcroots/workspace-rea \
    && rm /tmp/rea-tools
ENV PATH=/opt/rea/bin:/opt/rea-tools/bin:/home/coder/.local/bin:/home/coder/.nix-profile/bin:/home/coder/.local/state/nix/profile/bin:/opt/nix/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    REA_ANALYSIS_PROVIDER=ghidra
ARG REA_VERSION=6.8.0
USER root
RUN npm install --global --prefix /opt/rea "rea-agents@${REA_VERSION}" \
    && npm cache clean --force
USER coder

FROM base AS workspace
