FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    docker.io \
    git \
    gnupg \
    jq \
    libcap2-bin \
    lsb-release \
    nano \
    unzip \
    vim \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Vault from the official HashiCorp apt repository.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg && \
    chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo ${VERSION_CODENAME}) main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y vault && \
    setcap -r /usr/bin/vault || true && \
    rm -rf /var/lib/apt/lists/*
