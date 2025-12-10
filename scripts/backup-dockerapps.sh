#!/bin/bash
set -e

# 1. Dynamic Setup: Resolve the TRUE location of the script (chasing symlinks)
# This ensures it works even when run from the /home/user shortcut
REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$REAL_PATH")

# Now it knows it is in /mnt/pool01/dockerapps/scripts
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
    # Load the variables (PUID, PGID, BACKUP_USER)
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# 2. Validation: Ensure BACKUP_USER was found
if [ -z "$BACKUP_USER" ]; then
    echo "Error: BACKUP_USER is not set in your .env file!"
    exit 1
fi

# 3. Define Variables (Using the dynamic user)
SOURCE_DIR="/mnt/pool01/dockerapps"
DEST_DIR="onedrive:backup/cachyos/dockerapps"
CONFIG_FILE="/home/$BACKUP_USER/.config/rclone/rclone.conf"
EXCLUDE_FILE="$SCRIPT_DIR/rclone-excludes.txt"
LOG_FILE="/home/$BACKUP_USER/rclone-backup.log"

echo "========================================================"
echo "Starting Docker Backup: $(date)"
echo "User: $BACKUP_USER"
echo "Source: $SOURCE_DIR"
echo "--------------------------------------------------------"

# 4. Run the Sync
# Note: We removed 'sudo' here because this script is triggered 
# by the ROOT crontab, so it is already running as root.
rclone sync "$SOURCE_DIR" "$DEST_DIR" \
    --config "$CONFIG_FILE" \
    --exclude-from "$EXCLUDE_FILE" \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    --checkers=16 \
    --transfers=8 \
    --delete-excluded

# 5. Fix Log Ownership
# Since root ran this, the log file is owned by root. 
# We change it back to user so can read/delete it.
chown "$BACKUP_USER":"$BACKUP_USER" "$LOG_FILE"

echo "Backup Complete: $(date)"
echo "========================================================"
