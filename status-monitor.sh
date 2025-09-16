#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
config_reload_count=0

# Variables to track previous state to avoid unnecessary redraws
previous_status_line=""
previous_time_line=""

# Get initial config file modification time
get_config_mtime() {
    if [[ -f "$CONFIG_FILE" ]]; then
        stat -c %Y "$CONFIG_FILE" 2>/dev/null || stat -f %m "$CONFIG_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

config_mtime=$(get_config_mtime)

# Cleanup function
cleanup() {
    clear
    tput cnorm
    exit
}

trap cleanup INT  # cleanup on Ctrl+C
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

# Function to reload configuration
reload_config() {
    parse_config "$CONFIG_FILE"
    ((config_reload_count++))
    config_mtime=$(get_config_mtime)
    # Clear the screen and redraw
    draw_static
    # Reset previous state to force redraw
    previous_status_line=""
    previous_time_line=""
}

# Check if config file has been modified
check_config_changed() {
    local current_mtime
    current_mtime=$(get_config_mtime)

    if [[ "$current_mtime" != "$config_mtime" ]]; then
        reload_config
    fi
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
}

# Function to update status line only if changed
update_status() {
    local new_status_line="$1"
    if [[ "$new_status_line" != "$previous_status_line" ]]; then
        tput cup 4 0
        echo -ne "$new_status_line"
        # Clear any remaining characters from previous line
        tput el
        previous_status_line="$new_status_line"
    fi
}

# Function to update time line only if changed
update_time() {
    local new_time_line="$1"
    if [[ "$new_time_line" != "$previous_time_line" ]]; then
        tput cup 6 0
        echo -ne "$new_time_line"
        # Clear any remaining characters from previous line
        tput el
        previous_time_line="$new_time_line"
    fi
}

# Initial screen setup
draw_static

# Counter for config check frequency (check every 10 iterations = ~5 seconds)
config_check_counter=0

while true; do
    # Check for config file changes every 10 iterations (every ~5 seconds)
    if [[ $((config_check_counter % 10)) -eq 0 ]]; then
        check_config_changed
    fi
    ((config_check_counter++))

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

    # Update status only if it changed
    update_status "$status_line"

    # Calculate elapsed time
    now=$(date +%s%3N)
    elapsed=$((now - start_time))
    sec=$((elapsed / 1000))
    min=$((sec / 60))
    sec=$((sec % 60))

    time_line="${YELLOW}$(printf "%02d:%02d" "$min" "$sec")${NC}"

    # Update time only if it changed
    update_time "$time_line"

    # Sleep before next update
    sleep 0.5
done