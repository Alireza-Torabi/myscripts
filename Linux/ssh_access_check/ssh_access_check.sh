#!/usr/bin/env bash

# ============================================================
# Name: ssh_access_check.sh
# Description: Test SSH username/password access against a list of targets and export results to CSV with a live terminal dashboard.
# Version: 1.1.0
# Created: 2026-09-13
# Updated: 2026-09-13
# Requirements: bash, openssh-client, sshpass, coreutils
# Usage: ./ssh_access_check.sh [--plain] [ip_list_file]
# ============================================================

set -u
set -o pipefail

###############################################################################
# Script constants
###############################################################################

SCRIPT_VERSION="1.1.0"
RECENT_LIMIT=8
UI_ENABLED=0
UI_ACTIVE=0
FORCE_PLAIN=0
START_EPOCH=0
TEMP_DIR=""
OUTPUT_FILE=""
IP_FILE=""
SSH_USER=""
SSH_PASSWORD=""
SSH_PORT="22"
CONNECT_TIMEOUT="8"
TOTAL_TIMEOUT=13
TOTAL_TARGETS=0
PROCESSED_COUNT=0
SUCCESS_COUNT=0
FAILED_COUNT=0
CURRENT_INDEX=0
CURRENT_TARGET="-"
CURRENT_STATE="Waiting"

###############################################################################
# Color definitions
###############################################################################

if [[ -t 1 ]]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    CYAN="\033[0;36m"
    WHITE="\033[0;37m"
    BOLD="\033[1m"
    DIM="\033[2m"
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    WHITE=""
    BOLD=""
    DIM=""
    RESET=""
fi

###############################################################################
# Arrays used by the live dashboard
###############################################################################

declare -a RECENT_NUMBERS=()
declare -a RECENT_TARGETS=()
declare -a RECENT_RESULTS=()
declare -a RECENT_DETAILS=()

###############################################################################
# Output helper functions
###############################################################################

print_info() {
    printf "${CYAN}[INFO]${RESET} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${RESET} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${RESET} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1"
}

print_test() {
    printf "${BLUE}[TEST]${RESET} %s\n" "$1"
}

###############################################################################
# Display script usage
###############################################################################

show_help() {
    cat <<'HELP'
SSH Access Checker

Usage:
  ./ssh_access_check.sh [ip_list_file]
  ./ssh_access_check.sh --plain [ip_list_file]
  ./ssh_access_check.sh --help

Options:
  --plain       Disable the live dashboard and use normal line-by-line output.
  -h, --help    Display this help message.

Input file format:
  One IP address or hostname per line.
  Empty lines are ignored.
  Text after # is treated as a comment.

Example:
  192.168.1.10
  192.168.1.11
  server01.example.local

The script interactively asks for:
  - SSH username
  - SSH password
  - SSH port
  - Connection timeout
  - Output CSV filename
HELP
}

###############################################################################
# Run a command with root privileges when package installation is required
###############################################################################

run_as_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi

    print_error "Root privileges are required to install missing packages."
    print_error "Run this script as root or install sudo."
    exit 1
}

###############################################################################
# Detect the available Linux package manager
###############################################################################

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

###############################################################################
# Check required commands and install missing packages when possible
###############################################################################

install_dependencies() {
    local ssh_missing=0
    local sshpass_missing=0
    local timeout_missing=0
    local package_manager=""
    local packages=()

    command -v ssh >/dev/null 2>&1 || ssh_missing=1
    command -v sshpass >/dev/null 2>&1 || sshpass_missing=1
    command -v timeout >/dev/null 2>&1 || timeout_missing=1

    if [[ "$ssh_missing" -eq 0 &&
          "$sshpass_missing" -eq 0 &&
          "$timeout_missing" -eq 0 ]]; then

        print_success "All required dependencies are already installed."
        return 0
    fi

    print_warning "Some required dependencies are missing."

    [[ "$ssh_missing" -eq 1 ]] && print_warning "Missing command: ssh"
    [[ "$sshpass_missing" -eq 1 ]] && print_warning "Missing command: sshpass"
    [[ "$timeout_missing" -eq 1 ]] && print_warning "Missing command: timeout"

    package_manager="$(detect_package_manager)"
    print_info "Detected package manager: ${package_manager}"

    case "$package_manager" in
        apt)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-client")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Updating package repository..."
            run_as_root apt-get update || {
                print_error "Failed to update the package repository."
                exit 1
            }

            print_info "Installing required packages..."
            run_as_root env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y "${packages[@]}" || {
                    print_error "Failed to install required packages."
                    exit 1
                }
            ;;

        dnf)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-clients")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."
            run_as_root dnf install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                print_error "On some RHEL-family systems, sshpass may require an additional repository such as EPEL."
                exit 1
            }
            ;;

        yum)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-clients")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."
            run_as_root yum install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                print_error "On some RHEL-family systems, sshpass may require an additional repository such as EPEL."
                exit 1
            }
            ;;

        zypper)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."
            run_as_root zypper --non-interactive install "${packages[@]}" || {
                print_error "Failed to install required packages."
                exit 1
            }
            ;;

        pacman)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."
            run_as_root pacman -S --needed --noconfirm "${packages[@]}" || {
                print_error "Failed to install required packages."
                exit 1
            }
            ;;

        apk)
            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-client")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."
            run_as_root apk add --no-cache "${packages[@]}" || {
                print_error "Failed to install required packages."
                exit 1
            }
            ;;

        *)
            print_error "No supported package manager was found."
            print_error "Please install ssh, sshpass and timeout manually."
            exit 1
            ;;
    esac

    local dependency_error=0
    local command_name=""

    for command_name in ssh sshpass timeout; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            print_error "Required command is still unavailable: $command_name"
            dependency_error=1
        fi
    done

    if [[ "$dependency_error" -ne 0 ]]; then
        exit 1
    fi

    print_success "All required dependencies are available."
}

###############################################################################
# Escape a value so it can safely be written to a CSV file
###############################################################################

csv_escape() {
    local value="$1"

    value="${value//$'\r'/}"
    value="${value//$'\n'/ }"
    value="${value//\"/\"\"}"

    printf '"%s"' "$value"
}

###############################################################################
# Remove leading and trailing whitespace from a string
###############################################################################

trim_string() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

###############################################################################
# Remove control characters before displaying external error text
###############################################################################

sanitize_display_text() {
    local value="$1"

    printf '%s' "$value" | LC_ALL=C tr -cd '\11\12\15\40-\176'
}

###############################################################################
# Return a shortened version of a string for the dashboard table
###############################################################################

truncate_text() {
    local value="$1"
    local max_length="$2"

    if (( ${#value} <= max_length )); then
        printf '%s' "$value"
    elif (( max_length > 3 )); then
        printf '%s...' "${value:0:max_length-3}"
    else
        printf '%.*s' "$max_length" "$value"
    fi
}

###############################################################################
# Return elapsed time in HH:MM:SS format
###############################################################################

format_elapsed_time() {
    local now=0
    local elapsed=0
    local hours=0
    local minutes=0
    local seconds=0

    now="$(date +%s)"

    if [[ "$START_EPOCH" -gt 0 ]]; then
        elapsed=$((now - START_EPOCH))
    fi

    hours=$((elapsed / 3600))
    minutes=$(((elapsed % 3600) / 60))
    seconds=$((elapsed % 60))

    printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
}

###############################################################################
# Determine the terminal width for the live dashboard
###############################################################################

get_terminal_width() {
    local width="${COLUMNS:-}"

    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=""
    fi

    if [[ -z "$width" ]] && command -v tput >/dev/null 2>&1; then
        width="$(tput cols 2>/dev/null || true)"
    fi

    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=100
    fi

    if (( width < 80 )); then
        width=80
    fi

    if (( width > 120 )); then
        width=120
    fi

    printf '%s' "$width"
}

###############################################################################
# Print a horizontal separator for the live dashboard
###############################################################################

print_separator() {
    local width="$1"
    printf '%*s\n' "$width" '' | tr ' ' '-'
}

###############################################################################
# Add a completed target to the recent activity table
###############################################################################

add_recent_result() {
    local number="$1"
    local target="$2"
    local result="$3"
    local detail="$4"

    RECENT_NUMBERS+=("$number")
    RECENT_TARGETS+=("$target")
    RECENT_RESULTS+=("$result")
    RECENT_DETAILS+=("$detail")

    while (( ${#RECENT_TARGETS[@]} > RECENT_LIMIT )); do
        RECENT_NUMBERS=("${RECENT_NUMBERS[@]:1}")
        RECENT_TARGETS=("${RECENT_TARGETS[@]:1}")
        RECENT_RESULTS=("${RECENT_RESULTS[@]:1}")
        RECENT_DETAILS=("${RECENT_DETAILS[@]:1}")
    done
}

###############################################################################
# Configure whether the live dashboard can be used
###############################################################################

configure_ui() {
    if [[ "$FORCE_PLAIN" -eq 0 &&
          -t 0 &&
          -t 1 &&
          "${TERM:-dumb}" != "dumb" ]]; then
        UI_ENABLED=1
    else
        UI_ENABLED=0
    fi
}

###############################################################################
# Initialize the live terminal dashboard
###############################################################################

start_ui() {
    if [[ "$UI_ENABLED" -eq 1 ]]; then
        UI_ACTIVE=1

        # Hide the cursor while the dashboard is being redrawn.
        printf '\033[?25l'

        # Clear the terminal and move the cursor to the top-left corner.
        printf '\033[2J\033[H'
    fi
}

###############################################################################
# Restore normal terminal behavior
###############################################################################

restore_ui() {
    if [[ "$UI_ACTIVE" -eq 1 ]]; then
        # Restore the cursor before leaving the dashboard.
        printf '\033[?25h'
        UI_ACTIVE=0
    fi
}

###############################################################################
# Render the K9s-inspired live dashboard
###############################################################################

render_dashboard() {
    [[ "$UI_ENABLED" -eq 1 ]] || return 0

    local terminal_width=0
    local bar_width=0
    local filled=0
    local empty=0
    local percent=0
    local remaining=0
    local filled_bar=""
    local empty_bar=""
    local elapsed=""
    local display_target=""
    local i=0
    local display_result=""
    local display_detail=""
    local target_width=22
    local detail_width=31

    terminal_width="$(get_terminal_width)"
    bar_width=$((terminal_width - 27))

    if (( bar_width < 20 )); then
        bar_width=20
    elif (( bar_width > 70 )); then
        bar_width=70
    fi

    if (( TOTAL_TARGETS > 0 )); then
        percent=$((PROCESSED_COUNT * 100 / TOTAL_TARGETS))
    else
        percent=0
    fi

    if (( percent > 100 )); then
        percent=100
    fi

    filled=$((percent * bar_width / 100))
    empty=$((bar_width - filled))
    remaining=$((TOTAL_TARGETS - PROCESSED_COUNT))

    if (( remaining < 0 )); then
        remaining=0
    fi

    filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
    empty_bar="$(printf '%*s' "$empty" '' | tr ' ' '-')"
    elapsed="$(format_elapsed_time)"
    display_target="$(truncate_text "$CURRENT_TARGET" 45)"

    # Move to the top-left and clear the current dashboard content.
    printf '\033[H\033[J'

    printf "${BOLD}${CYAN}SSH ACCESS CHECKER${RESET} ${DIM}v%s${RESET}  ${BOLD}| LIVE DASHBOARD${RESET}\n" "$SCRIPT_VERSION"
    print_separator "$terminal_width"

    printf "${BOLD}User:${RESET} %-18s ${BOLD}Port:${RESET} %-6s ${BOLD}Timeout:${RESET} %-4ss ${BOLD}Elapsed:${RESET} %s\n" \
        "$SSH_USER" "$SSH_PORT" "$CONNECT_TIMEOUT" "$elapsed"

    printf "${BOLD}Input:${RESET} %-35s ${BOLD}Output:${RESET} %s\n" \
        "$(truncate_text "$IP_FILE" 35)" \
        "$(truncate_text "$OUTPUT_FILE" 38)"

    print_separator "$terminal_width"

    printf "${BOLD}Progress:${RESET} [${GREEN}%s${RESET}${DIM}%s${RESET}] ${BOLD}%3d%%${RESET}  (%d/%d)\n" \
        "$filled_bar" "$empty_bar" "$percent" "$PROCESSED_COUNT" "$TOTAL_TARGETS"

    printf "${GREEN}${BOLD}Accessible: %-5d${RESET}  ${RED}${BOLD}Failed: %-5d${RESET}  ${YELLOW}${BOLD}Remaining: %-5d${RESET}\n" \
        "$SUCCESS_COUNT" "$FAILED_COUNT" "$remaining"

    print_separator "$terminal_width"

    printf "${BOLD}Current Target:${RESET} %s:%s\n" "$display_target" "$SSH_PORT"
    printf "${BOLD}Current State :${RESET} %s\n" "$CURRENT_STATE"

    print_separator "$terminal_width"

    printf "${BOLD}RECENT ACTIVITY${RESET}\n"
    printf "%-5s %-22s %-27s %s\n" "#" "TARGET" "RESULT" "DETAIL"
    printf "%-5s %-22s %-27s %s\n" "-----" "----------------------" "---------------------------" "-------------------------------"

    if (( ${#RECENT_TARGETS[@]} == 0 )); then
        printf "${DIM}No completed checks yet.${RESET}\n"
    else
        for ((i = 0; i < ${#RECENT_TARGETS[@]}; i++)); do
            display_result="${RECENT_RESULTS[$i]}"
            display_detail="$(truncate_text "${RECENT_DETAILS[$i]}" "$detail_width")"

            if [[ "$display_result" == "ACCESS_OK" ]]; then
                printf "%-5s %-22s ${GREEN}%-27s${RESET} %s\n" \
                    "${RECENT_NUMBERS[$i]}" \
                    "$(truncate_text "${RECENT_TARGETS[$i]}" "$target_width")" \
                    "$display_result" \
                    "$display_detail"
            else
                printf "%-5s %-22s ${RED}%-27s${RESET} %s\n" \
                    "${RECENT_NUMBERS[$i]}" \
                    "$(truncate_text "${RECENT_TARGETS[$i]}" "$target_width")" \
                    "$display_result" \
                    "$display_detail"
            fi
        done
    fi

    print_separator "$terminal_width"
    printf "${DIM}Ctrl+C: stop safely | CSV is updated after every completed target | --plain: disable dashboard${RESET}\n"
}

###############################################################################
# Remove temporary data and sensitive variables when the script exits
###############################################################################

cleanup() {
    restore_ui
    unset SSH_PASSWORD 2>/dev/null || true

    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

###############################################################################
# Handle Ctrl+C and preserve already completed CSV results
###############################################################################

handle_interrupt() {
    restore_ui
    printf "\n"
    print_warning "Execution interrupted by the user."
    print_warning "Processed targets: ${PROCESSED_COUNT}/${TOTAL_TARGETS}"

    if [[ -n "${OUTPUT_FILE:-}" ]]; then
        print_warning "Partial results were saved to: $OUTPUT_FILE"
    fi

    exit 130
}

###############################################################################
# Handle external termination signals
###############################################################################

handle_termination() {
    restore_ui
    printf "\n"
    print_warning "Termination signal received."
    print_warning "Processed targets: ${PROCESSED_COUNT}/${TOTAL_TARGETS}"

    if [[ -n "${OUTPUT_FILE:-}" ]]; then
        print_warning "Partial results were saved to: $OUTPUT_FILE"
    fi

    exit 143
}

trap cleanup EXIT
trap handle_interrupt INT
trap handle_termination TERM

###############################################################################
# Process command-line options
###############################################################################

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;

        --plain)
            FORCE_PLAIN=1
            shift
            ;;

        --*)
            print_error "Unknown option: $1"
            show_help
            exit 2
            ;;

        *)
            if [[ -n "$IP_FILE" ]]; then
                print_error "Only one input file may be specified."
                show_help
                exit 2
            fi

            IP_FILE="$1"
            shift
            ;;
    esac
done

###############################################################################
# Display startup banner
###############################################################################

printf "\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"
printf "${BOLD}${CYAN}          SSH ACCESS CHECKER${RESET}\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"
printf "\n"

###############################################################################
# Check and install dependencies
###############################################################################

print_info "Checking required dependencies..."
install_dependencies
printf "\n"

###############################################################################
# Read the target list filename
###############################################################################

if [[ -z "$IP_FILE" ]]; then
    read -r -p "Enter the path to the IP address list file: " IP_FILE
fi

if [[ ! -f "$IP_FILE" ]]; then
    print_error "Input file does not exist: $IP_FILE"
    exit 1
fi

if [[ ! -r "$IP_FILE" ]]; then
    print_error "Input file is not readable: $IP_FILE"
    exit 1
fi

print_success "Input file loaded: $IP_FILE"

###############################################################################
# Read SSH username
###############################################################################

while true; do
    read -r -p "Enter the SSH username: " SSH_USER

    if [[ -n "$SSH_USER" ]]; then
        break
    fi

    print_warning "Username cannot be empty."
done

###############################################################################
# Read SSH password without displaying it on the terminal
###############################################################################

while true; do
    read -r -s -p "Enter the SSH password: " SSH_PASSWORD
    printf "\n"

    if [[ -n "$SSH_PASSWORD" ]]; then
        break
    fi

    print_warning "Password cannot be empty."
done

###############################################################################
# Read SSH port
###############################################################################

read -r -p "Enter the SSH port [22]: " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] ||
   (( SSH_PORT < 1 || SSH_PORT > 65535 )); then

    print_error "Invalid SSH port: $SSH_PORT"
    exit 1
fi

###############################################################################
# Read connection timeout
###############################################################################

read -r -p "Enter the connection timeout in seconds [8]: " CONNECT_TIMEOUT
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-8}"

if ! [[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] ||
   (( CONNECT_TIMEOUT < 1 )); then

    print_error "Invalid timeout value."
    exit 1
fi

###############################################################################
# Allow a few extra seconds for authentication after TCP connection setup
###############################################################################

TOTAL_TIMEOUT=$((CONNECT_TIMEOUT + 5))

###############################################################################
# Read output CSV filename
###############################################################################

DEFAULT_OUTPUT_FILE="ssh_access_results_$(date '+%Y%m%d_%H%M%S').csv"
read -r -p "Enter the output CSV filename [$DEFAULT_OUTPUT_FILE]: " OUTPUT_FILE
OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"

if [[ -d "$OUTPUT_FILE" ]]; then
    print_error "The output path points to a directory: $OUTPUT_FILE"
    exit 1
fi

if [[ -e "$OUTPUT_FILE" ]]; then
    read -r -p "Output file already exists. Overwrite it? [y/N]: " OVERWRITE_CONFIRMATION

    case "${OVERWRITE_CONFIRMATION,,}" in
        y|yes)
            ;;
        *)
            print_warning "Operation cancelled. Existing output file was not modified."
            exit 0
            ;;
    esac
fi

###############################################################################
# Create a private temporary directory for SSH runtime files
###############################################################################

TEMP_DIR="$(mktemp -d)" || {
    print_error "Failed to create a temporary directory."
    exit 1
}

KNOWN_HOSTS_FILE="$TEMP_DIR/known_hosts"
SSH_ERROR_FILE="$TEMP_DIR/ssh_error.log"

touch "$KNOWN_HOSTS_FILE" "$SSH_ERROR_FILE" || {
    print_error "Failed to create temporary runtime files."
    exit 1
}

###############################################################################
# Create the CSV file and write its header
###############################################################################

if ! printf '%s\n' \
    'Target,Port,Username,Access,Result,TestedAt' \
    > "$OUTPUT_FILE"; then

    print_error "Failed to create the CSV output file: $OUTPUT_FILE"
    exit 1
fi

print_success "CSV output file created: $OUTPUT_FILE"
printf "\n"

###############################################################################
# Count valid targets before starting
###############################################################################

while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove comments from the line.
    line="${line%%#*}"

    # Remove leading and trailing whitespace.
    line="$(trim_string "$line")"

    # Ignore empty lines.
    [[ -z "$line" ]] && continue

    ((TOTAL_TARGETS++))
done < "$IP_FILE"

if [[ "$TOTAL_TARGETS" -eq 0 ]]; then
    print_error "No valid targets were found in the input file."
    exit 1
fi

print_info "Targets found: $TOTAL_TARGETS"

###############################################################################
# Configure and start the dashboard after all interactive questions are done
###############################################################################

configure_ui
START_EPOCH="$(date +%s)"

if [[ "$UI_ENABLED" -eq 1 ]]; then
    start_ui
    CURRENT_STATE="Ready"
    render_dashboard
else
    printf "\n"
    print_info "Live dashboard is disabled. Using plain output mode."
    printf "\n"
fi

###############################################################################
# Open the target list on a dedicated file descriptor
#
# File descriptor 4 prevents SSH or another command from consuming lines from
# the input file through standard input.
###############################################################################

exec 4< "$IP_FILE" || {
    restore_ui
    print_error "Failed to open the input file for processing."
    exit 1
}

###############################################################################
# Test SSH access to every target
###############################################################################

while IFS= read -r TARGET <&4 || [[ -n "$TARGET" ]]; do
    ###########################################################################
    # Remove comments and whitespace
    ###########################################################################

    TARGET="${TARGET%%#*}"
    TARGET="$(trim_string "$TARGET")"

    [[ -z "$TARGET" ]] && continue

    CURRENT_INDEX=$((PROCESSED_COUNT + 1))
    CURRENT_TARGET="$TARGET"
    CURRENT_STATE="Testing ${TARGET}:${SSH_PORT} as ${SSH_USER}"

    if [[ "$UI_ENABLED" -eq 1 ]]; then
        render_dashboard
    else
        printf "${BLUE}--------------------------------------------------${RESET}\n"
        print_test "[$CURRENT_INDEX/$TOTAL_TARGETS] Testing $TARGET:$SSH_PORT as $SSH_USER"
    fi

    ###########################################################################
    # Clear the previous SSH error message
    ###########################################################################

    : > "$SSH_ERROR_FILE"

    ###########################################################################
    # Provide the password to sshpass through file descriptor 3
    #
    # This avoids placing the password directly in the process command line.
    ###########################################################################

    exec 3<<<"$SSH_PASSWORD"

    ###########################################################################
    # Perform the SSH login test
    #
    # The -n option redirects SSH standard input from /dev/null. This prevents
    # SSH from consuming target lines from the input list.
    #
    # Public-key authentication is disabled intentionally because this script
    # specifically tests the username/password supplied by the user.
    ###########################################################################

    if timeout \
        --signal=TERM \
        --kill-after=2s \
        "${TOTAL_TIMEOUT}s" \
        sshpass -d 3 \
        ssh -n \
        -p "$SSH_PORT" \
        -l "$SSH_USER" \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        -o ConnectionAttempts=1 \
        -o NumberOfPasswordPrompts=1 \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
        -o LogLevel=ERROR \
        "$TARGET" \
        "exit 0" \
        2>"$SSH_ERROR_FILE"
    then
        SSH_EXIT_CODE=0
    else
        SSH_EXIT_CODE=$?
    fi

    exec 3<&-

    ###########################################################################
    # Classify the SSH result
    ###########################################################################

    ACCESS="NO"
    RESULT="SSH_ERROR"
    DETAIL=""

    if [[ "$SSH_EXIT_CODE" -eq 0 ]]; then
        ACCESS="YES"
        RESULT="ACCESS_OK"
        DETAIL="Login successful"
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))

        if [[ "$SSH_EXIT_CODE" -eq 5 ]]; then
            RESULT="AUTHENTICATION_FAILED"

        elif [[ "$SSH_EXIT_CODE" -eq 124 ||
                "$SSH_EXIT_CODE" -eq 137 ]]; then
            RESULT="TIMEOUT"

        elif grep -qiE \
            'Permission denied|Authentication failed' \
            "$SSH_ERROR_FILE"; then
            RESULT="AUTHENTICATION_FAILED"

        elif grep -qi \
            'Connection refused' \
            "$SSH_ERROR_FILE"; then
            RESULT="CONNECTION_REFUSED"

        elif grep -qiE \
            'No route to host|Network is unreachable' \
            "$SSH_ERROR_FILE"; then
            RESULT="HOST_UNREACHABLE"

        elif grep -qiE \
            'Connection timed out|Operation timed out' \
            "$SSH_ERROR_FILE"; then
            RESULT="TIMEOUT"

        elif grep -qiE \
            'Could not resolve hostname|Name or service not known|Temporary failure in name resolution' \
            "$SSH_ERROR_FILE"; then
            RESULT="DNS_ERROR"

        elif grep -qiE \
            'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED' \
            "$SSH_ERROR_FILE"; then
            RESULT="HOST_KEY_ERROR"

        elif grep -qiE \
            'no matching host key type found|no matching key exchange method found|no matching cipher found' \
            "$SSH_ERROR_FILE"; then
            RESULT="SSH_NEGOTIATION_FAILED"

        elif grep -qiE \
            'Connection closed|Connection reset' \
            "$SSH_ERROR_FILE"; then
            RESULT="CONNECTION_CLOSED"
        fi

        DETAIL="$(
            grep -v '^[[:space:]]*$' \
                "$SSH_ERROR_FILE" |
                tail -n 1
        )"

        DETAIL="$(sanitize_display_text "$DETAIL")"

        if [[ -z "$DETAIL" ]]; then
            DETAIL="SSH exit code: $SSH_EXIT_CODE"
        fi
    fi

    ###########################################################################
    # Save the completed result to CSV immediately
    ###########################################################################

    TEST_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"

    printf '%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$TARGET")" \
        "$(csv_escape "$SSH_PORT")" \
        "$(csv_escape "$SSH_USER")" \
        "$(csv_escape "$ACCESS")" \
        "$(csv_escape "$RESULT")" \
        "$(csv_escape "$TEST_TIME")" \
        >> "$OUTPUT_FILE"

    ###########################################################################
    # Update counters and recent activity after the result has been saved
    ###########################################################################

    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))

    add_recent_result \
        "$PROCESSED_COUNT" \
        "$TARGET" \
        "$RESULT" \
        "$DETAIL"

    if [[ "$RESULT" == "ACCESS_OK" ]]; then
        CURRENT_STATE="Completed: ACCESS_OK"
    else
        CURRENT_STATE="Completed: $RESULT"
    fi

    if [[ "$UI_ENABLED" -eq 1 ]]; then
        render_dashboard
    else
        if [[ "$RESULT" == "ACCESS_OK" ]]; then
            printf "${GREEN}[ACCESS OK]${RESET} %s\n" "$TARGET"
        else
            printf "${RED}[ACCESS FAILED]${RESET} %s - %s\n" \
                "$TARGET" \
                "$RESULT"

            printf "${YELLOW}[DETAIL]${RESET} %s\n" "$DETAIL"
        fi

        PERCENT=$((PROCESSED_COUNT * 100 / TOTAL_TARGETS))

        printf "${CYAN}[PROGRESS]${RESET} %d%% (%d/%d)\n" \
            "$PERCENT" \
            "$PROCESSED_COUNT" \
            "$TOTAL_TARGETS"
    fi
done

exec 4<&-

###############################################################################
# Verify that all discovered targets were processed
###############################################################################

PROCESSING_COMPLETE=1

if [[ "$PROCESSED_COUNT" -ne "$TOTAL_TARGETS" ]]; then
    PROCESSING_COMPLETE=0
    CURRENT_STATE="WARNING: Not all targets were processed"
else
    CURRENT_STATE="Completed successfully"
fi

CURRENT_TARGET="-"

if [[ "$UI_ENABLED" -eq 1 ]]; then
    render_dashboard
    restore_ui
    printf "\n"
fi

###############################################################################
# Display final summary
###############################################################################

printf "\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"
printf "${BOLD}${CYAN}               FINAL SUMMARY${RESET}\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"

printf "Targets found : %s\n" "$TOTAL_TARGETS"
printf "Targets tested: %s\n" "$PROCESSED_COUNT"

printf "${GREEN}Accessible    : %s${RESET}\n" \
    "$SUCCESS_COUNT"

printf "${RED}Not accessible: %s${RESET}\n" \
    "$FAILED_COUNT"

printf "Elapsed time  : %s\n" \
    "$(format_elapsed_time)"

printf "\n"

###############################################################################
# Return a meaningful final exit status
###############################################################################

if [[ "$PROCESSING_COMPLETE" -eq 1 ]]; then
    print_success "All targets were processed."
    print_success "Results saved to: $OUTPUT_FILE"
    exit 0
else
    print_warning "Not all targets were processed."
    print_warning "The CSV file contains only the targets that completed processing."
    print_warning "Results saved to: $OUTPUT_FILE"
    exit 3
fi
