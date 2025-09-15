#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'  # reset

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

start_time=$(date +%s%3N) # milliseconds since epoch
trap "tput cnorm; exit" INT  # cleanup on Ctrl+C
tput civis  # hide cursor

# Parse configuration file
parse_config() {
    # Initialize arrays
    declare -ga check_names=()
    declare -ga check_commands=()

    # Get list of check entries
    check_lines=$(grep -n "^[[:space:]]*-[[:space:]]*name:" "$1" | cut -d':' -f1)

    for line in $check_lines; do
        name=$(sed -n "${line}s/.*name:[[:space:]]*\"*\([^\"]*\)\"*.*/\1/p" "$1")
        # Look for command line in the next few lines
        cmd_line=$((line + 1))
        command=$(sed -n "${cmd_line}s/.*command:[[:space:]]*\"*\([^\"]*\)\"*.*/\1/p" "$1")

        if [[ -n "$name" && -n "$command" ]]; then
            check_names+=("$name")
            check_commands+=("$command")
        fi
    done
}

# Load the configuration
parse_config "$CONFIG_FILE"

# Draw the static part of the display once
draw_static() {
    clear
    echo -e "┌──────────────────────┐"
    echo -e "│        ${YELLOW}STATUS${NC}        │"
    echo -e "└──────────────────────┘"

    # Add empty lines for status and time
    echo
    echo
    echo

    # Move cursor back to where we'll update status
    tput cup 4 0
}

# Initial screen setup
draw_static

while true; do
    # Move cursor to status line position
    tput cup 4 0

    # Build status line
    status_line=""
    for i in "${!check_names[@]}"; do
        # Execute the command in the context of the script directory
        (cd "$SCRIPT_DIR" && bash -c "${check_commands[i]}")
        result=$?

        if [[ $result -eq 0 ]]; then
            status_line+="${GREEN}■ ${check_names[i]}${NC} "
        else
            status_line+="${RED}■ ${check_names[i]}${NC} "
        fi
    done

    # Clear the status line and display new status
    tput el
    echo -e "$status_line"

    # Calculate elapsed time
    now=$(date +%s%3N)
    elapsed=$((now - start_time))
    sec=$((elapsed / 1000))
    min=$((sec / 60))
    sec=$((sec % 60))

    # Move to time line and update
    tput cup 6 0
    tput el
    echo -e "${YELLOW}$(printf "%02d:%02d" "$min" "$sec")${NC}"

    # Move cursor back to status line for next update
    tput cup 4 0

    # Sleep before next update
    sleep 0.5
done