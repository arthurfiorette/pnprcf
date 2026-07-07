#!/bin/sh
set -eu

: "${PNPR_PUBLIC_URL:?PNPR_PUBLIC_URL is required}"
: "${PNPR_R2_ACCOUNT_ID:?PNPR_R2_ACCOUNT_ID is required}"
: "${PNPR_R2_BUCKET:?PNPR_R2_BUCKET is required}"
: "${PNPR_R2_ACCESS_KEY_ID:?PNPR_R2_ACCESS_KEY_ID is required}"
: "${PNPR_R2_SECRET_ACCESS_KEY:?PNPR_R2_SECRET_ACCESS_KEY is required}"

export AWS_ACCESS_KEY_ID="$PNPR_R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$PNPR_R2_SECRET_ACCESS_KEY"

mkdir -p /mnt/r2

R2_ENDPOINT="https://${PNPR_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
echo "Mounting R2 bucket ${PNPR_R2_BUCKET} at /mnt/r2..."
tigrisfs --endpoint "$R2_ENDPOINT" -f "$PNPR_R2_BUCKET" /mnt/r2 &

# FUSE mount readiness is eventual; wait until the configured cache prefix can
# be created through the mount before starting pnpr.
for attempt in $(seq 1 30); do
  if mkdir -p /mnt/r2/cache 2>/dev/null; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "R2 FUSE mount did not become writable" >&2
    exit 1
  fi
  sleep 1
done

exec pnpr --listen 0.0.0.0:7677 --config /pnpr/config.yaml --public-url "$PNPR_PUBLIC_URL"
