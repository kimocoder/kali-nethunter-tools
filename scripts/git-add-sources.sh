#!/bin/bash
# Helper script to add source directories to git without their .git folders
# This temporarily moves .git folders, adds the sources, then restores them

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
TEMP_DIR="/tmp/kali-nethunter-tools-git-backup"

echo "Creating temporary backup directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Find all .git directories in src/
echo "Moving .git directories to temporary location..."
find "$SRC_DIR" -mindepth 2 -maxdepth 2 -type d -name ".git" | while read gitdir; do
    tool=$(basename $(dirname "$gitdir"))
    echo "  Backing up: $tool/.git"
    mkdir -p "$TEMP_DIR/$tool"
    mv "$gitdir" "$TEMP_DIR/$tool/"
done

echo ""
echo "Now you can add sources without warnings:"
echo "  git add src/"
echo ""
echo "After committing, restore .git folders with:"
echo "  $0 --restore"
echo ""

# If --restore flag is passed, restore the .git folders
if [ "$1" = "--restore" ]; then
    echo "Restoring .git directories..."
    find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | while read tooldir; do
        tool=$(basename "$tooldir")
        if [ -d "$tooldir/.git" ]; then
            echo "  Restoring: $tool/.git"
            mv "$tooldir/.git" "$SRC_DIR/$tool/"
        fi
    done
    echo "Removing temporary backup directory..."
    rm -rf "$TEMP_DIR"
    echo "Done! .git folders restored."
fi
