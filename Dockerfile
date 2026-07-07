# syntax=docker/dockerfile:1

ARG PNPR_VERSION=0.0.0-26070301
FROM ghcr.io/pnpm/pnpr:${PNPR_VERSION}

COPY --chown=pnpr:pnpr pnpr.yaml /pnpr/config.yaml

EXPOSE 7677

# Use a shell so Cloudflare-provided runtime env vars can configure the public
# URL without baking deployment-specific hostnames into the image.
ENTRYPOINT ["/bin/sh", "-c"]
CMD ["exec pnpr --listen 0.0.0.0:7677 --config /pnpr/config.yaml --public-url \"${PNPR_PUBLIC_URL:?PNPR_PUBLIC_URL is required}\""]
