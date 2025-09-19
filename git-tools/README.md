# Git Multi-Repository Sync Tools

Automated Git synchronization tools for managing multiple repositories with automatic commit, push, and pull operations.

## Overview

These tools enable automatic synchronization of multiple Git repositories, perfect for keeping your projects backed up and synchronized across different machines without manual intervention.

## Files

- `multi-repo-auto-sync.sh` - Automatically commits and pushes changes across multiple repositories
- `multi-repo-auto-pull.sh` - Automatically pulls remote changes across multiple repositories
- `repo-sync-config.txt` - Configuration file listing repositories to sync
- `README.md` - This documentation

## Quick Setup

1. **Configure repositories**:
   Edit `repo-sync-config.txt` and add your repository paths:
   ```
   /Users/username/Projects/repo1
   /Users/username/Projects/repo2
   /path/to/another/repository
   ```

2. **Make scripts executable**:
   ```bash
   chmod +x multi-repo-auto-sync.sh
   chmod +x multi-repo-auto-pull.sh
   ```

3. **Add to crontab**:
   ```bash
   crontab -e
   # Add these lines (adjust paths as needed):
   */15 * * * * /path/to/multi-repo-auto-sync.sh >/dev/null 2>&1
   * * * * * /path/to/multi-repo-auto-pull.sh >/dev/null 2>&1
   ```

## Features

- **Multi-repository support**: Sync unlimited repositories
- **Cross-account compatibility**: Works with repositories from different GitHub accounts
- **Conflict resolution**: Handles merge conflicts with stashing
- **Comprehensive logging**: Detailed logs for troubleshooting
- **Lock mechanism**: Prevents overlapping sync operations
- **Graceful error handling**: Continues with other repos if one fails
- **Configurable**: Easy to add/remove repositories

## How It Works

### Auto-Sync Script
1. Reads repository paths from configuration file
2. For each repository:
   - Checks for uncommitted changes
   - Pulls remote changes first (to avoid conflicts)
   - Stages all changes (`git add -A`)
   - Commits with timestamp
   - Pushes to origin
3. Logs all activities and continues with other repos if one fails

### Auto-Pull Script
1. Reads repository paths from configuration file
2. For each repository:
   - Fetches latest remote references
   - Compares local vs remote commit hashes
   - Stashes local changes if needed
   - Pulls remote changes if available
   - Restores stashed changes
3. Handles merge conflicts gracefully

## Configuration

The `repo-sync-config.txt` file contains one repository path per line:

```bash
# Multi-Repository Sync Configuration
# Lines starting with # are comments

/Users/username/Projects/my-web-app
/Users/username/Projects/mobile-app
/Users/username/Documents/personal-projects/blog
```

## Prerequisites

- Git installed and configured
- SSH keys or credentials set up for each repository
- Each repository must have a remote origin configured
- Cron service running (for automation)

## Logs

- `multi-repo-sync.log` - Auto-sync operations log
- `multi-repo-pull.log` - Auto-pull operations log
- Individual repository logs in each repo's `.git/` directory

## Troubleshooting

### Common Issues

1. **Permission denied**: Ensure scripts are executable (`chmod +x`)
2. **Repository not found**: Check paths in `repo-sync-config.txt`
3. **Authentication failed**: Verify Git credentials/SSH keys for each repo
4. **Merge conflicts**: Check individual repository logs

### Manual Testing

Test the scripts:
```bash
./multi-repo-auto-sync.sh
./multi-repo-auto-pull.sh
```

Check logs:
```bash
tail -f multi-repo-sync.log
tail -f multi-repo-pull.log
```

## Security Notes

- Uses existing Git credentials and SSH keys
- No passwords or sensitive data stored in scripts
- Respects existing repository authentication setup
- Logs are stored locally only

## License

These tools are provided as-is for personal and professional use.