#!/bin/bash

# Dynamic variables
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="backup_${TIMESTAMP}"
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
ENCRYPTED_ARCHIVE_NAME="${ARCHIVE_NAME}.gpg"
SCRIPT_PATH=$(realpath "$0")
CRON_JOB="bash $SCRIPT_PATH --manual-backup"

# Load environment variables from .env file in the script's directory
SCRIPT_DIR=$(dirname "$(realpath "$0")")
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Error: .env file not found in $SCRIPT_DIR."
    exit 1
fi

# Server information
SERVER_NAME=$(hostname)
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check dependencies
for cmd in tar curl docker crontab gpg; do
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
  archives them, encrypts the archive with GPG symmetric encryption (AES-256), and sends the result to a Telegram chat.
  It also supports cron scheduling for automation.

Examples:
  $0 --add-cron "0 0 * * *"   # Schedule daily backups at midnight
  $0 --manual-backup          # Run a manual backup
  $0 --show-cron              # Check cron job status
EOF
}

# Function to backup folder
backup_folders() {
    log "Creating backup of folder $MARZBAN_DB_FOLDER..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$MARZBAN_DB_FOLDER" "$BACKUP_DIR/marzban_db_${TIMESTAMP}"
    if [ $? -eq 0 ]; then
        log "Marzban db folder backup successfully created."
    else
        log "Error while copying marzban db folder."
        exit 1
    fi

    log "Creating backup of folder $MARZBAN_ENV_FOLDER..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$MARZBAN_ENV_FOLDER" "$BACKUP_DIR/marzban_env_${TIMESTAMP}"
    if [ $? -eq 0 ]; then
        log "Marzban env folder backup successfully created."
    else
        log "Error while copying marzban env folder."
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
    tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "marzban_db_${TIMESTAMP}" "marzban_env_${TIMESTAMP}" "pg_backup_${TIMESTAMP}.sql"
    if [ $? -eq 0 ]; then
        log "Archive successfully created."
    else
        log "Error while creating archive."
        exit 1
    fi
}

# Function to encrypt archive with GPG symmetric encryption
encrypt_archive() {
    log "Encrypting archive $ARCHIVE_NAME with GPG symmetric encryption..."
    gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$GPG_PASSPHRASE" -o "$BACKUP_DIR/$ENCRYPTED_ARCHIVE_NAME" "$BACKUP_DIR/$ARCHIVE_NAME"
    if [ $? -eq 0 ]; then
        log "Archive successfully encrypted as $ENCRYPTED_ARCHIVE_NAME."
    else
        log "Error while encrypting archive."
        exit 1
    fi
}

# Function to send encrypted archive and message to Telegram
send_to_telegram() {
    log "Sending encrypted archive with caption to Telegram..."

    # Formatted message in HTML
    MESSAGE="
<b>Encrypted Backup Saved:</b>
📅 <b>Time:</b> $CURRENT_DATE
💻 <b>Server:</b> $SERVER_NAME
📁 <b>Marzban DB folder:</b> $MARZBAN_DB_FOLDER
📁 <b>Marzban ENV folder:</b> $MARZBAN_ENV_FOLDER
📁 <b>Backup service folder:</b> $SCRIPT_DIR
📸 <b>Database:</b> $PG_DB
📎 <b>Encrypted Archive:</b> $ENCRYPTED_ARCHIVE_NAME
🔒 <b>Note:</b> Use for decrypt: <code>sudo gpg --decrypt --output $ARCHIVE_NAME $ENCRYPTED_ARCHIVE_NAME</code>"

    # Send encrypted archive with caption
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "document=@$BACKUP_DIR/$ENCRYPTED_ARCHIVE_NAME" \
        -F "caption=$MESSAGE" \
        -F "parse_mode=HTML" > /dev/null

    if [ $? -eq 0 ]; then
        log "Encrypted archive with caption successfully sent to Telegram."
    else
        log "Error while sending to Telegram."
        exit 1
    fi
}

# Function to clean up temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$BACKUP_DIR/marzban_${TIMESTAMP}" "$BACKUP_DIR/pg_backup_${TIMESTAMP}.sql" "$BACKUP_DIR/$ARCHIVE_NAME" "$BACKUP_DIR/$ENCRYPTED_ARCHIVE_NAME"
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
    backup_folders
    backup_postgres
    archive_backups
    encrypt_archive
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