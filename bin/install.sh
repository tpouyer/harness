#!/bin/bash
# Build Harness Installation Script
# Downloads and initializes build-harness for a project

set -e

BUILD_HARNESS_ORG="${BUILD_HARNESS_ORG:-your-org}"
BUILD_HARNESS_PROJECT="${BUILD_HARNESS_PROJECT:-build-harness}"
BUILD_HARNESS_BRANCH="${BUILD_HARNESS_BRANCH:-main}"
BUILD_HARNESS_PATH="${BUILD_HARNESS_PATH:-.build-harness}"

echo "Installing Build Harness..."

if [ -d "$BUILD_HARNESS_PATH" ]; then
    echo "Updating existing installation..."
    cd "$BUILD_HARNESS_PATH"
    git pull origin "$BUILD_HARNESS_BRANCH" 2>/dev/null || true
    cd - > /dev/null
else
    echo "Cloning build-harness..."
    git clone --depth 1 --branch "$BUILD_HARNESS_BRANCH" \
        "https://github.com/${BUILD_HARNESS_ORG}/${BUILD_HARNESS_PROJECT}.git" \
        "$BUILD_HARNESS_PATH" 2>/dev/null || {
            echo "Warning: Could not clone from remote. Using local reference."
            # For local development, copy instead
            if [ -d "../build-harness" ]; then
                cp -r "../build-harness" "$BUILD_HARNESS_PATH"
            fi
        }
fi

echo "$BUILD_HARNESS_PATH/Makefile"
