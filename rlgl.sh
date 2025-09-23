#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'  # reset

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --config FILE    Specify config file (default: config.yaml)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Example: $0 -c /path/to/custom-config.yaml"
}

# Parse command line arguments
CONFIG_FILE_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE_ARG="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Set config file path
if [[ -n "$CONFIG_FILE_ARG" ]]; then
    # Use absolute path if provided, or relative to current directory
    if [[ "$CONFIG_FILE_ARG" = /* ]]; then
        CONFIG_FILE="$CONFIG_FILE_ARG"
    else
        CONFIG_FILE="$(pwd)/$CONFIG_FILE_ARG"
    fi
else
    # Use default config file in script directory
    CONFIG_FILE="$SCRIPT_DIR/config.yaml"
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

echo "Using config file: $CONFIG_FILE"
sleep 2  # Brief pause to show the config file being used

start_time=$(date +%s%3N) # milliseconds since epoch
config_reload_count=0

# Variables to track previous state to avoid unnecessary redraws
previous_complete_display=""

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
    # Initialize arrays for sections
    declare -ga section_titles=()
    declare -ga section_check_names=()
    declare -ga section_check_commands=()

    # Get section starting lines (lines with "- title:")
    section_lines=$(grep -n "^[[:space:]]*-[[:space:]]*title:" "$1" | cut -d':' -f1)

    for section_line in $section_lines; do
        # Extract title
        title=$(sed -n "${section_line}s/.*title:[[:space:]]*\"*\([^\"]*\)\"*.*/\1/p" "$1")
        section_titles+=("$title")

        # Find checks for this section
        section_names=()
        section_commands=()

        # Find the next section start or end of file
        next_section_line=$(echo "$section_lines" | awk -v current="$section_line" '$1 > current {print $1; exit}')
        if [[ -z "$next_section_line" ]]; then
            next_section_line=$(wc -l < "$1")
            ((next_section_line++))
        fi

        # Find check entries between this section and the next
        check_lines=$(sed -n "${section_line},${next_section_line}p" "$1" | grep -n "^[[:space:]]*-[[:space:]]*name:" | cut -d':' -f1)

        for relative_line in $check_lines; do
            absolute_line=$((section_line + relative_line - 1))
            name=$(sed -n "${absolute_line}s/.*name:[[:space:]]*\"*\([^\"]*\)\"*.*/\1/p" "$1")

            # Look for command line in the next line
            cmd_line=$((absolute_line + 1))
            command=$(sed -n "${cmd_line}s/.*command:[[:space:]]*\"*\([^\"]*\)\"*.*/\1/p" "$1")

            if [[ -n "$name" && -n "$command" ]]; then
                section_names+=("$name")
                section_commands+=("$command")
            fi
        done

        # Store arrays as strings (bash limitation workaround)
        section_check_names+=("$(printf "%s\n" "${section_names[@]}")")
        section_check_commands+=("$(printf "%s\n" "${section_commands[@]}")")
    done
}

# Function to reload configuration
reload_config() {
    parse_config "$CONFIG_FILE"
    ((config_reload_count++))
    config_mtime=$(get_config_mtime)
    # Reset previous state to force redraw
    previous_complete_display=""
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

# Function to update complete display only if changed
update_complete_display() {
    local new_complete_display="$1"
    if [[ "$new_complete_display" != "$previous_complete_display" ]]; then
        clear
        echo -ne "$new_complete_display"
        previous_complete_display="$new_complete_display"
    fi
}

# Counter for config check frequency (check every 10 iterations = ~5 seconds)
config_check_counter=0

while true; do
    # Check for config file changes every 10 iterations (every ~5 seconds)
    if [[ $((config_check_counter % 10)) -eq 0 ]]; then
        check_config_changed
    fi
    ((config_check_counter++))

    # Build complete display
    display_content=""

    # Process each section
    for i in "${!section_titles[@]}"; do
        # Add section title
        title="${section_titles[i]}"
        title_length=${#title}
        box_width=$((title_length + 4))  # 2 spaces on each side

        # Create top border
        display_content+="┌"
        for ((j=0; j<box_width; j++)); do
            display_content+="─"
        done
        display_content+="┐\n"

        # Create title line
        display_content+="│  ${YELLOW}${title}${NC}  │\n"

        # Create bottom border
        display_content+="└"
        for ((j=0; j<box_width; j++)); do
            display_content+="─"
        done
        display_content+="┘\n\n"

        # Get checks for this section
        IFS=$'\n' read -d '' -r -a names <<< "${section_check_names[i]}" || true
        IFS=$'\n' read -d '' -r -a commands <<< "${section_check_commands[i]}" || true

        # Process checks for this section
        for j in "${!names[@]}"; do
            if [[ -n "${names[j]}" && -n "${commands[j]}" ]]; then
                # Execute the command
                (cd "$SCRIPT_DIR" && bash -c "${commands[j]}")
                result=$?

                if [[ $result -eq 0 ]]; then
                    display_content+="${GREEN}■ ${names[j]}${NC}\n"
                else
                    display_content+="${RED}■ ${names[j]}${NC}\n"
                fi
            fi
        done

        # Add spacing between sections
        if [[ $i -lt $((${#section_titles[@]} - 1)) ]]; then
            display_content+="\n"
        fi
    done

    # Calculate elapsed time
    now=$(date +%s%3N)
    elapsed=$((now - start_time))
    sec=$((elapsed / 1000))
    min=$((sec / 60))
    sec=$((sec % 60))

    # Add timer to the complete display
    display_content+="\n\n${YELLOW}$(printf "%02d:%02d" "$min" "$sec")${NC}\n"

    # Update complete display at once
    update_complete_display "${display_content}"

    # Sleep before next update
    sleep 0.5
done
