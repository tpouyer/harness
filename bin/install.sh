#!/bin/bash
# Harness Installation Script
# Downloads and initializes harness for a project

set -e

HARNESS_ORG="${HARNESS_ORG:-your-org}"
HARNESS_PROJECT="${HARNESS_PROJECT:-harness}"
HARNESS_BRANCH="${HARNESS_BRANCH:-main}"
HARNESS_PATH="${HARNESS_PATH:-.harness-framework}"

echo "Installing Harness..."

if [ -d "$HARNESS_PATH" ]; then
    echo "Updating existing installation..."
    cd "$HARNESS_PATH"
    git pull origin "$HARNESS_BRANCH" 2>/dev/null || true
    cd - > /dev/null
else
    echo "Cloning harness..."
    git clone --depth 1 --branch "$HARNESS_BRANCH" \
        "https://github.com/${HARNESS_ORG}/${HARNESS_PROJECT}.git" \
        "$HARNESS_PATH" 2>/dev/null || {
            echo "Warning: Could not clone from remote. Using local reference."
            # For local development, copy instead
            if [ -d "../harness" ]; then
                cp -r "../harness" "$HARNESS_PATH"
            fi
        }
fi

echo "$HARNESS_PATH/Makefile"
