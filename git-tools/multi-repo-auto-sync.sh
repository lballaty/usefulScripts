#!/bin/bash
#
# File: multi-repo-auto-sync.sh
# File Description: Multi-repository auto-commit and push script for GitHub synchronization
# Purpose: Automatically commit and push uncommitted changes across multiple repositories
#
# Usage: ./multi-repo-auto-sync.sh [config_file]
#
# Setup Instructions:
#   1. Create repo-sync-config.txt with repository paths (one per line)
#   2. Make executable with: chmod +x multi-repo-auto-sync.sh
#   3. Add to crontab for automatic execution:
#      */15 * * * * /path/to/multi-repo-auto-sync.sh >/dev/null 2>&1
#   4. Runs every 15 minutes across all configured repositories
#
# Configuration:
#   - Default config file: repo-sync-config.txt
#   - Format: One absolute repository path per line
#   - Lines starting with # are comments
#   - Empty lines are ignored
#
# How it works:
#   - Reads repository paths from configuration file
#   - For each repository, checks for uncommitted changes
#   - Pulls remote changes first to avoid conflicts
#   - Stages all files and commits with timestamp
#   - Pushes to GitHub origin automatically
#   - Logs all activities per repository
#   - Handles failures gracefully and continues with other repos
#
# Dependencies: Git, GitHub remote origin configured for each repo, cron
# Security/RLS: Uses existing git credentials and SSH keys per repository
# Notes: Extends single-repo auto-sync to multiple repositories
#

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="${1:-$SCRIPT_DIR/repo-sync-config.txt}"
MASTER_LOG_FILE="$SCRIPT_DIR/multi-repo-sync.log"

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

log_msg "Starting multi-repository sync for ${#REPOSITORIES[@]} repositories"

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
    REPO_LOG_FILE=".git/auto-sync.log"

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

    # First, check for and pull any remote changes
    BRANCH=$(git branch --show-current)
    log_msg "[$REPO_PATH] Checking for remote changes on $BRANCH..."

    # Fetch latest remote refs
    if git fetch origin "$BRANCH" 2>/dev/null; then
        # Check if remote has new commits
        LOCAL_HASH=$(git rev-parse HEAD)
        REMOTE_HASH=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "$LOCAL_HASH")

        if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
            log_msg "[$REPO_PATH] Remote changes detected, pulling..."
            if git pull origin "$BRANCH" 2>/dev/null; then
                log_msg "[$REPO_PATH] Successfully pulled changes from origin/$BRANCH"
            else
                log_msg "[$REPO_PATH] Failed to pull from origin/$BRANCH (may need manual merge)"
            fi
        else
            log_msg "[$REPO_PATH] Local branch up to date with remote"
        fi
    else
        log_msg "[$REPO_PATH] WARNING: Failed to fetch from origin/$BRANCH"
    fi

    # Check if there are changes (staged, unstaged, or untracked)
    if ! git diff-index --quiet HEAD --; then
        log_msg "[$REPO_PATH] Changes detected, committing..."

        # Add all changes (modified, new, deleted)
        git add -A

        # Commit with timestamp and automation indicator
        COMMIT_MSG="Auto-sync: $(date '+%Y-%m-%d %H:%M:%S') [automated]"
        git commit -m "$COMMIT_MSG"

        # Push to remote origin
        if git push origin "$BRANCH" 2>/dev/null; then
            log_msg "[$REPO_PATH] Successfully pushed to origin/$BRANCH"
        else
            log_msg "[$REPO_PATH] Failed to push to origin/$BRANCH"
        fi
    else
        log_msg "[$REPO_PATH] No changes to sync"
    fi

    # Clean up lock
    rmdir "$LOCK_DIR" 2>/dev/null || true
done

log_msg "Multi-repository sync completed"