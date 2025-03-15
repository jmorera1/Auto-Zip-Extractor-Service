#!/bin/bash
#
# ========================================================
# AUTO ZIP EXTRACTOR SERVICE - Author: Je 03-15-2025
# ========================================================
#
# OVERVIEW:
# This script automatically monitors directories for new zip files and extracts them.
# It uses inotify for real-time file system monitoring and extracts zip files as soon
# as they are fully written to disk. The script avoids re-extracting previously processed
# files by using both checksum tracking and directory name pattern matching.
#
# FEATURES:
# - Real-time monitoring (no polling)
# - Recursive subdirectory watching
# - Email notifications for success and failure
# - Dual-method duplicate prevention
# - Runs as a systemd service
# - Parallel extraction for better performance
#
#

# ======== CONFIGURATION ========
# Directory to monitor (absolute path)
MONITOR_DIR="/sunflower-data/arch/"

# Email settings
SUCCESS_EMAIL="jmorera@archgroup.com"      # For success notifications
FAILURE_EMAIL="jmorera@archgroup.com"     # For failure notifications
EMAIL_FROM="zipextractor@$(hostname)"  # From address

# Log and database files
LOG_FILE="/var/log/auto-zip-extractor.log"
DB_FILE="/var/lib/auto-zip-extractor/processed_files.db"

# Maximum parallel extractions
MAX_PARALLEL=4
# ======== END CONFIGURATION ========

# Ensure required directories exist
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$DB_FILE")"
touch "$DB_FILE"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Email notification function
send_email() {
    local recipient="$1"
    local subject="$2"
    local message="$3"

    echo "$message" | mail -s "$subject" -r "$EMAIL_FROM" "$recipient"
}

# Check if a zip file has already been processed
is_processed() {
    local zip_file="$1"
    local checksum=$(md5sum "$zip_file" | cut -d' ' -f1)
    local basename=$(basename "$zip_file" .zip)
    local dirname=$(dirname "$zip_file")

    # Method 1: Check database for checksum
    if grep -q "$checksum" "$DB_FILE"; then
        log "Skipping $zip_file - already processed (checksum match)"
        return 0
    fi

    # Method 2: Check for existing extraction directory
    if find "$dirname" -maxdepth 1 -type d -name "${basename}_[0-9]*" | grep -q .; then
        log "Skipping $zip_file - directory pattern match found"
        return 0
    fi

    return 1
}

# Extract a zip file
extract_zip() {
    local zip_file="$1"
    local basename=$(basename "$zip_file" .zip)
    local dirname=$(dirname "$zip_file")
    local extract_dir="${dirname}/${basename}_$(date '+%Y%m%d_%H%M%S')"
    local checksum=$(md5sum "$zip_file" | cut -d' ' -f1)

    log "Extracting $zip_file to $extract_dir"

    # Create extraction directory
    mkdir -p "$extract_dir"

    # Extract the zip file
    if unzip -q "$zip_file" -d "$extract_dir"; then
        # Record successful extraction
        echo "$checksum $zip_file" >> "$DB_FILE"

        log "SUCCESS: Extracted $zip_file to $extract_dir"

        # Send success email
        send_email "$SUCCESS_EMAIL" \
                  "[ZIP Extractor] Success: $(basename "$zip_file")" \
                  "Successfully extracted:\n$zip_file\nTo:\n$extract_dir\n\nTime: $(date)"
    else
        log "ERROR: Failed to extract $zip_file"

        # Clean up the failed extraction
        rm -rf "$extract_dir"

        # Send failure email
        send_email "$FAILURE_EMAIL" \
                  "[ZIP Extractor] FAILED: $(basename "$zip_file")" \
                  "Failed to extract:\n$zip_file\n\nTime: $(date)\n\nPlease check the log at $LOG_FILE"
    fi
}

# Process a new zip file
process_zip() {
    local zip_file="$1"

    # Verify it's a zip file
    if ! file "$zip_file" | grep -q "Zip archive data"; then
        return
    fi

    # Wait for file to stabilize (ensure it's fully written)
    local size1=0
    local size2=1

    while [ $size1 -ne $size2 ]; do
        size1=$(stat -c%s "$zip_file" 2>/dev/null || echo "0")
        sleep 1
        size2=$(stat -c%s "$zip_file" 2>/dev/null || echo "0")

        # Exit if file disappeared
        [ "$size2" = "0" ] && return
    done

    # Check if already processed
    if ! is_processed "$zip_file"; then
        extract_zip "$zip_file" &
    fi
}

# Main function
main() {
    log "Starting Auto Zip Extractor Service"
    log "Monitoring directory: $MONITOR_DIR"

    # Process any existing zip files
    log "Scanning for existing zip files..."
    find "$MONITOR_DIR" -type f -name "*.zip" | while read -r zip_file; do
        # Limit concurrent extractions
        while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
            sleep 1
        done

        process_zip "$zip_file"
    done

    # Start monitoring for new files
    log "Starting real-time file monitoring..."
    inotifywait -m -r -e close_write,moved_to --format '%w%f' "$MONITOR_DIR" | while read -r file_path; do
        if [[ "$file_path" == *.zip ]]; then
            # Limit concurrent extractions
            while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
                sleep 1
            done

            process_zip "$file_path"
        fi
    done
}

# Start the script
main
