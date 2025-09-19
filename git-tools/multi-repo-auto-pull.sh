#!/bin/bash
#
# File: multi-repo-auto-pull.sh
# File Description: Multi-repository automatic pull from GitHub
# Purpose: Keep multiple local repos synchronized with GitHub changes
#
# Usage: ./multi-repo-auto-pull.sh [config_file]
#
# Setup Instructions:
#   1. Use same repo-sync-config.txt as multi-repo-auto-sync.sh
#   2. Make executable with: chmod +x multi-repo-auto-pull.sh
#   3. Add to crontab for regular pull checks:
#      * * * * * /path/to/multi-repo-auto-pull.sh >/dev/null 2>&1
#
# Configuration:
#   - Default config file: repo-sync-config.txt
#   - Format: One absolute repository path per line
#   - Lines starting with # are comments
#   - Empty lines are ignored
#
# How it works:
#   - Reads repository paths from configuration file
#   - For each repository, fetches latest remote references
#   - Compares local HEAD with remote HEAD hashes
#   - Pulls only if remote has newer commits
#   - Handles merge conflicts gracefully with stashing
#   - Logs all pull activities per repository
#   - Continues with other repos if one fails
#
# Dependencies: Git, GitHub remote origin configured for each repo
# Security/RLS: Uses existing git credentials and SSH keys per repository
# Notes: Complements multi-repo push automation for full bidirectional sync
#

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="${1:-$SCRIPT_DIR/repo-sync-config.txt}"
MASTER_LOG_FILE="$SCRIPT_DIR/multi-repo-pull.log"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$MASTER_LOG_FILE"
}

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_msg "ERROR: Configuration file not found: $CONFIG_FILE"
    log_msg "Please create $CONFIG_FILE with repository paths (one per line)"
    exit 1
fi

# Read repositories from config file
declare -a REPOSITORIES
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Add repository path to array
    REPOSITORIES+=("$line")
done < "$CONFIG_FILE"

if [[ ${#REPOSITORIES[@]} -eq 0 ]]; then
    log_msg "ERROR: No repositories found in $CONFIG_FILE"
    exit 1
fi

log_msg "Starting multi-repository pull for ${#REPOSITORIES[@]} repositories"

# Process each repository
for REPO_PATH in "${REPOSITORIES[@]}"; do
    log_msg "Processing repository: $REPO_PATH"

    # Check if directory exists and is a git repository
    if [[ ! -d "$REPO_PATH" ]]; then
        log_msg "WARNING: Directory does not exist: $REPO_PATH"
        continue
    fi

    if [[ ! -d "$REPO_PATH/.git" ]]; then
        log_msg "WARNING: Not a git repository: $REPO_PATH"
        continue
    fi

    # Change to repository directory
    if ! cd "$REPO_PATH"; then
        log_msg "ERROR: Cannot access repository: $REPO_PATH"
        continue
    fi

    # Create repository-specific log
    REPO_LOG_FILE=".git/auto-pull.log"

    # Create repository-specific lock
    LOCK_ROOT=".git/locks"
    LOCK_DIR="$LOCK_ROOT/sync.lock"

    # Create lock root and acquire non-blocking lock
    mkdir -p "$LOCK_ROOT" 2>/dev/null || true
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_msg "SKIP: Another sync process running for $REPO_PATH"
        continue
    fi

    # Ensure lock is cleaned up
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

    BRANCH=$(git branch --show-current)
    log_msg "[$REPO_PATH] Checking for remote changes on $BRANCH..."

    # Fetch latest remote refs without merging
    if ! git fetch origin "$BRANCH" 2>/dev/null; then
        log_msg "[$REPO_PATH] Failed to fetch from origin/$BRANCH"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
    fi

    # Compare local and remote commit hashes
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "$LOCAL_HASH")

    if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
        log_msg "[$REPO_PATH] Remote changes detected (local: ${LOCAL_HASH:0:8}, remote: ${REMOTE_HASH:0:8})"

        # Check for local uncommitted changes
        if ! git diff-index --quiet HEAD --; then
            log_msg "[$REPO_PATH] Local changes detected, stashing before pull..."
            git stash push -m "Auto-stash before pull $(date '+%Y-%m-%d %H:%M:%S')"
            STASHED=1
        else
            STASHED=0
        fi

        # Attempt to pull remote changes
        if git pull origin "$BRANCH" 2>/dev/null; then
            log_msg "[$REPO_PATH] Successfully pulled changes from origin/$BRANCH"

            # Restore stashed changes if any
            if [[ $STASHED -eq 1 ]]; then
                log_msg "[$REPO_PATH] Restoring stashed local changes..."
                if git stash pop 2>/dev/null; then
                    log_msg "[$REPO_PATH] Successfully restored local changes"
                else
                    log_msg "[$REPO_PATH] Conflict restoring stash - manual resolution needed"
                fi
            fi
        else
            log_msg "[$REPO_PATH] Failed to pull from origin/$BRANCH - may need manual merge"

            # Restore stash on failed pull
            if [[ $STASHED -eq 1 ]]; then
                log_msg "[$REPO_PATH] Restoring stash after failed pull..."
                git stash pop 2>/dev/null || log_msg "[$REPO_PATH] Failed to restore stash"
            fi
        fi
    else
        log_msg "[$REPO_PATH] Local branch up to date with remote"
    fi

    # Clean up lock
    rmdir "$LOCK_DIR" 2>/dev/null || true
done

log_msg "Multi-repository pull completed"