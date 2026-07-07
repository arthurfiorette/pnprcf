# syntax=docker/dockerfile:1

ARG PNPR_VERSION=0.0.0-26070301
ARG TIGRISFS_VERSION=v1.2.1
FROM ghcr.io/pnpm/pnpr:${PNPR_VERSION}

ARG TIGRISFS_VERSION

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl fuse \
  && rm -rf /var/lib/apt/lists/* \
  && arch="$(uname -m)" \
  && case "$arch" in \
  x86_64) arch="amd64" ;; \
  aarch64) arch="arm64" ;; \
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://github.com/tigrisdata/tigrisfs/releases/download/${TIGRISFS_VERSION}/tigrisfs_${TIGRISFS_VERSION#v}_linux_${arch}.tar.gz" -o /tmp/tigrisfs.tar.gz \
  && tar -xzf /tmp/tigrisfs.tar.gz -C /usr/local/bin \
  && rm /tmp/tigrisfs.tar.gz \
  && chmod 0755 /usr/local/bin/tigrisfs \
  && mkdir -p /mnt/r2 /pnpr/cache \
  && chown -R pnpr:pnpr /mnt/r2 /pnpr/cache

COPY --chown=pnpr:pnpr pnpr.yaml /pnpr/config.yaml
COPY --chown=pnpr:pnpr startup.sh /pnpr/startup.sh
RUN chmod 0755 /pnpr/startup.sh

USER pnpr

EXPOSE 7677

ENTRYPOINT ["/pnpr/startup.sh"]
