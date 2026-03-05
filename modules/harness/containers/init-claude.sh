#!/bin/bash
# Init script — runs as root to copy mounted credentials,
# then drops to the harness user for the real entrypoint.

set -e

ADC_MOUNT="/tmp/adc.json"
GCLOUD_DIR="/home/harness/.config/gcloud"

# Copy the mounted ADC file (owned by host UID, unreadable by harness)
# into the harness user's gcloud config directory.
if [ -f "$ADC_MOUNT" ]; then
    cp "$ADC_MOUNT" "$GCLOUD_DIR/application_default_credentials.json"
    chown harness:harness "$GCLOUD_DIR/application_default_credentials.json"
    chmod 600 "$GCLOUD_DIR/application_default_credentials.json"
fi

# Drop to harness user and run the real entrypoint
exec gosu harness /usr/local/bin/entrypoint.sh "$@"
