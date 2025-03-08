#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Error: .env file not found."
    exit 1
fi

# Dynamic variables
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="backup_${TIMESTAMP}"
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
SCRIPT_PATH=$(realpath "$0")
CRON_JOB="bash $SCRIPT_PATH --manual-backup"

# Server information
SERVER_NAME=$(hostname)
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check dependencies
for cmd in tar curl docker crontab; do
    if ! command -v "$cmd" &> /dev/null; then
        log "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help            Show this help message and exit
  --add-cron <schedule> Add a cron job for automatic backups (e.g., "0 2 * * *" for daily at 2 AM)
  --show-cron           Show information about the current cron job (if any)
  --remove-cron         Remove the cron job for automatic backups
  --manual-backup       Manually run the backup process and send it to Telegram

Description:
  This script creates backups of a specified folder and PostgreSQL database in a Docker container,
  archives them, and sends the result to a Telegram chat. It also supports cron scheduling.

Examples:
  $0 --add-cron "0 0 * * *"   # Schedule daily backups at midnight
  $0 --manual-backup          # Run a manual backup
  $0 --show-cron              # Check cron job status
EOF
}

# Function to backup folder
backup_folder() {
    log "Creating backup of folder $SOURCE_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$SOURCE_DIR" "$BACKUP_DIR/marzban_${TIMESTAMP}"
    if [ $? -eq 0 ]; then
        log "Folder backup successfully created."
    else
        log "Error while copying folder."
        exit 1
    fi
}

# Function to backup PostgreSQL database
backup_postgres() {
    log "Creating backup of PostgreSQL database from container $DOCKER_CONTAINER..."
    docker exec "$DOCKER_CONTAINER" pg_dump -U "$PG_USER" "$PG_DB" > "$BACKUP_DIR/pg_backup_${TIMESTAMP}.sql"
    if [ $? -eq 0 ]; then
        log "Database backup successfully created."
    else
        log "Error while creating database backup."
        exit 1
    fi
}

# Function to archive backups
archive_backups() {
    log "Archiving backups into $ARCHIVE_NAME..."
    tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "marzban_${TIMESTAMP}" "pg_backup_${TIMESTAMP}.sql"
    if [ $? -eq 0 ]; then
        log "Archive successfully created."
    else
        log "Error while creating archive."
        exit 1
    fi
}

# Function to send archive and message to Telegram
send_to_telegram() {
    log "Sending archive with caption to Telegram..."

    # Formatted message in HTML
    MESSAGE="
<b>📦 Backup Information</b>
📅 <b>Time:</b> $CURRENT_DATE
💻 <b>Server:</b> $SERVER_NAME
📁 <b>Folder:</b> $SOURCE_DIR
📸 <b>Database:</b> $PG_DB
📎 <b>Archive:</b> $ARCHIVE_NAME"

    # Send archive with caption
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "document=@$BACKUP_DIR/$ARCHIVE_NAME" \
        -F "caption=$MESSAGE" \
        -F "parse_mode=HTML" > /dev/null

    if [ $? -eq 0 ]; then
        log "Archive with caption successfully sent to Telegram."
    else
        log "Error while sending to Telegram."
        exit 1
    fi
}

# Function to clean up temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$BACKUP_DIR/marzban_${TIMESTAMP}" "$BACKUP_DIR/pg_backup_${TIMESTAMP}.sql" "$BACKUP_DIR/$ARCHIVE_NAME"
    if [ $? -eq 0 ]; then
        log "Temporary files removed."
    else
        log "Error during cleanup."
        exit 1
    fi
}

# Function to add cron job
add_cron() {
    local schedule="$1"
    log "Adding cron job with schedule: '$schedule'..."
    (crontab -l 2>/dev/null | grep -v "$CRON_JOB"; echo "$schedule $CRON_JOB") | crontab -
    if [ $? -eq 0 ]; then
        log "Cron job added successfully."
    else
        log "Error while adding cron job."
        exit 1
    fi
}

# Function to show cron job status
show_cron() {
    log "Checking cron job status..."
    if crontab -l 2>/dev/null | grep -q "$CRON_JOB"; then
        local cron_line=$(crontab -l | grep "$CRON_JOB")
        log "Cron job found: $cron_line"
    else
        log "No cron job found for this script."
    fi
}

# Function to remove cron job
remove_cron() {
    log "Removing cron job..."
    if crontab -l 2>/dev/null | grep -q "$CRON_JOB"; then
        crontab -l 2>/dev/null | grep -v "$CRON_JOB" | crontab -
        if [ $? -eq 0 ]; then
            log "Cron job removed successfully."
        else
            log "Error while removing cron job."
            exit 1
        fi
    else
        log "No cron job found to remove."
    fi
}

# Main backup process
run_backup() {
    log "Starting backup process..."
    backup_folder
    backup_postgres
    archive_backups
    send_to_telegram
    cleanup
    log "Backup process completed successfully."
}

# Argument parsing
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --add-cron)
            if [ -z "${2:-}" ]; then
                log "Error: Schedule not provided. Example: --add-cron '0 2 * * *'"
                exit 1
            fi
            add_cron "$2"
            shift 2
            ;;
        --show-cron)
            show_cron
            shift
            ;;
        --remove-cron)
            remove_cron
            shift
            ;;
        --manual-backup)
            run_backup
            shift
            ;;
        *)
            log "Error: Unknown option '$1'. Use --help for usage information."
            exit 1
            ;;
    esac
done

exit 0