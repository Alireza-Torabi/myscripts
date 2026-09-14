#!/usr/bin/env bash

# ============================================================
# Name: ssh_access_check.sh
# Description: Test SSH username/password access against a list of targets using controlled parallel workers, a live terminal dashboard, and ordered CSV output.
# Version: 1.2.0
# Created: 2026-09-13
# Updated: 2026-09-14
# Requirements: bash, openssh-client, sshpass, coreutils
# Usage: ./ssh_access_check.sh [--plain] [ip_list_file]
# ============================================================

set -u
set -o pipefail

###############################################################################
# Script constants and runtime state
###############################################################################

SCRIPT_VERSION="1.2.0"
DEFAULT_WORKERS=5
MAX_WORKERS=50
RECOMMENDED_MAX_WORKERS=10
RECENT_LIMIT=8
POLL_INTERVAL="0.20"

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
WORKER_COUNT="$DEFAULT_WORKERS"
TOTAL_TARGETS=0
PROCESSED_COUNT=0
SUCCESS_COUNT=0
FAILED_COUNT=0
RUNNING_COUNT=0
NEXT_LAUNCH_INDEX=1
NEXT_CSV_INDEX=1
CURRENT_STATE="Waiting"
INTERRUPTED=0

###############################################################################
# Color definitions
###############################################################################

if [[ -t 1 ]]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    CYAN="\033[0;36m"
    BOLD="\033[1m"
    DIM="\033[2m"
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    BOLD=""
    DIM=""
    RESET=""
fi

###############################################################################
# Arrays used for targets, workers, and dashboard activity
###############################################################################

declare -a TARGETS=()
declare -a ACTIVE_PIDS=()
declare -a ACTIVE_INDICES=()
declare -a PROCESSED_FLAGS=()
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
  - Number of concurrent SSH workers
  - Output CSV filename

Important:
  Parallel workers improve scan speed, but high concurrency can increase the
  chance of account lockout, SSH rate limiting, IDS/IPS alerts, or transient
  connection failures. The recommended starting value is 5 workers.

CSV ordering:
  The final CSV always follows the exact original input order, regardless of
  the order in which parallel workers finish.
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
    local dependency_error=0
    local command_name=""

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

    [[ "$ssh_missing" -eq 1 ]] &&
        print_warning "Missing command: ssh"

    [[ "$sshpass_missing" -eq 1 ]] &&
        print_warning "Missing command: sshpass"

    [[ "$timeout_missing" -eq 1 ]] &&
        print_warning "Missing command: timeout"

    package_manager="$(detect_package_manager)"

    print_info "Detected package manager: ${package_manager}"

    case "$package_manager" in

        apt)
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh-client")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

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
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh-clients")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root dnf install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                print_error "On some RHEL-family systems, sshpass may require an additional repository such as EPEL."
                exit 1
            }
            ;;

        yum)
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh-clients")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root yum install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                print_error "On some RHEL-family systems, sshpass may require an additional repository such as EPEL."
                exit 1
            }
            ;;

        zypper)
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root zypper \
                --non-interactive \
                install \
                "${packages[@]}" || {
                    print_error "Failed to install required packages."
                    exit 1
                }
            ;;

        pacman)
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root pacman \
                -S \
                --needed \
                --noconfirm \
                "${packages[@]}" || {
                    print_error "Failed to install required packages."
                    exit 1
                }
            ;;

        apk)
            [[ "$ssh_missing" -eq 1 ]] &&
                packages+=("openssh-client")

            [[ "$sshpass_missing" -eq 1 ]] &&
                packages+=("sshpass")

            [[ "$timeout_missing" -eq 1 ]] &&
                packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root apk \
                add \
                --no-cache \
                "${packages[@]}" || {
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

    printf '%s' "$value" |
        LC_ALL=C tr -cd '\11\12\15\40-\176'
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

    printf '%02d:%02d:%02d' \
        "$hours" \
        "$minutes" \
        "$seconds"
}

###############################################################################
# Determine the terminal width for the live dashboard
###############################################################################

get_terminal_width() {
    local width="${COLUMNS:-}"

    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=""
    fi

    if [[ -z "$width" ]] &&
       command -v tput >/dev/null 2>&1; then

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

    printf '%*s\n' "$width" '' |
        tr ' ' '-'
}

###############################################################################
# Return the path of a worker result file for an input index
###############################################################################

result_file_for_index() {
    local index="$1"

    printf '%s/results/result_%06d.dat' \
        "$TEMP_DIR" \
        "$index"
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
# Convert SSH and sshpass failures into useful result categories
###############################################################################

classify_ssh_failure() {
    local exit_code="$1"
    local error_file="$2"

    local result="SSH_ERROR"
    local detail="Unclassified SSH failure (exit code: ${exit_code})"
    local raw_error=""

    raw_error="$(
        grep -v '^[[:space:]]*$' \
            "$error_file" \
            2>/dev/null |
            tail -n 1
    )"

    raw_error="$(sanitize_display_text "$raw_error")"

    if [[ "$exit_code" -eq 5 ]]; then

        result="AUTHENTICATION_FAILED"
        detail="Password authentication rejected"

    elif [[ "$exit_code" -eq 4 ]]; then

        result="SSHPASS_ERROR"
        detail="sshpass could not parse the SSH response"

    elif [[ "$exit_code" -eq 6 ||
            "$exit_code" -eq 7 ]]; then

        result="HOST_KEY_ERROR"
        detail="SSH host key verification problem"

    elif [[ "$exit_code" -eq 124 ||
            "$exit_code" -eq 137 ]]; then

        result="TIMEOUT"
        detail="Connection or authentication attempt timed out"

    elif grep -qiE \
        'Permission denied|Authentication failed|Access denied|Too many authentication failures' \
        "$error_file"; then

        result="AUTHENTICATION_FAILED"
        detail="Password authentication rejected"

    elif grep -qi \
        'Connection refused' \
        "$error_file"; then

        result="CONNECTION_REFUSED"
        detail="SSH port refused the connection"

    elif grep -qiE \
        'No route to host|Network is unreachable|Host is down' \
        "$error_file"; then

        result="HOST_UNREACHABLE"
        detail="Target is unreachable from this host"

    elif grep -qiE \
        'Connection timed out|Operation timed out|connect to host .* port .* timed out' \
        "$error_file"; then

        result="TIMEOUT"
        detail="Connection to the SSH service timed out"

    elif grep -qiE \
        'Could not resolve hostname|Name or service not known|Temporary failure in name resolution' \
        "$error_file"; then

        result="DNS_ERROR"
        detail="Hostname resolution failed"

    elif grep -qiE \
        'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED|Offending .* key' \
        "$error_file"; then

        result="HOST_KEY_ERROR"
        detail="SSH host key verification failed"

    elif grep -qiE \
        'no matching host key type found|no matching key exchange method found|no matching cipher found|no matching MAC found|Unable to negotiate' \
        "$error_file"; then

        result="SSH_NEGOTIATION_FAILED"
        detail="SSH algorithm negotiation failed"

    elif grep -qiE \
        'kex_exchange_identification|ssh_exchange_identification|banner exchange|Bad protocol version identification|Protocol mismatch' \
        "$error_file"; then

        result="SSH_PROTOCOL_ERROR"
        detail="SSH handshake or protocol negotiation failed"

    elif grep -qiE \
        'Connection closed|Connection reset|closed by remote host|reset by peer' \
        "$error_file"; then

        result="CONNECTION_CLOSED"
        detail="Remote host closed the SSH connection"

    elif grep -qiE \
        'Bad configuration option|Unsupported option|command-line line .* Bad configuration' \
        "$error_file"; then

        result="SSH_CLIENT_ERROR"
        detail="Local SSH client configuration error"

    elif [[ -n "$raw_error" ]]; then

        result="SSH_ERROR"
        detail="$raw_error"

    elif [[ "$exit_code" -eq 255 ]]; then

        result="SSH_ERROR"
        detail="SSH client returned exit code 255 without diagnostic output"

    fi

    printf '%s\n%s\n' \
        "$result" \
        "$detail"
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

        # Hide the terminal cursor while the dashboard is active.
        printf '\033[?25l'

        # Clear the terminal and move to the top-left corner.
        printf '\033[2J\033[H'

    fi
}

###############################################################################
# Restore normal terminal behavior
###############################################################################

restore_ui() {
    if [[ "$UI_ACTIVE" -eq 1 ]]; then

        # Restore the terminal cursor.
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

    filled_bar="$(
        printf '%*s' "$filled" '' |
            tr ' ' '#'
    )"

    empty_bar="$(
        printf '%*s' "$empty" '' |
            tr ' ' '-'
    )"

    elapsed="$(format_elapsed_time)"

    # Move to the top-left corner and redraw the complete dashboard.
    printf '\033[H\033[J'

    printf \
        "${BOLD}${CYAN}SSH ACCESS CHECKER${RESET} ${DIM}v%s${RESET}  ${BOLD}| PARALLEL LIVE DASHBOARD${RESET}\n" \
        "$SCRIPT_VERSION"

    print_separator "$terminal_width"

    printf \
        "${BOLD}User:${RESET} %-24s ${BOLD}Port:${RESET} %-5s ${BOLD}Timeout:${RESET} %ss  ${BOLD}Elapsed:${RESET} %s\n" \
        "$SSH_USER" \
        "$SSH_PORT" \
        "$CONNECT_TIMEOUT" \
        "$elapsed"

    printf \
        "${BOLD}Workers:${RESET} %-4s ${BOLD}Running:${RESET} %-4s ${BOLD}CSV order:${RESET} Input order\n" \
        "$WORKER_COUNT" \
        "$RUNNING_COUNT"

    printf \
        "${BOLD}Input:${RESET} %-35s ${BOLD}Output:${RESET} %s\n" \
        "$(truncate_text "$IP_FILE" 35)" \
        "$(truncate_text "$OUTPUT_FILE" 38)"

    print_separator "$terminal_width"

    printf \
        "${BOLD}Progress:${RESET} [${GREEN}%s${RESET}${DIM}%s${RESET}] ${BOLD}%3d%%${RESET}  (%d/%d)\n" \
        "$filled_bar" \
        "$empty_bar" \
        "$percent" \
        "$PROCESSED_COUNT" \
        "$TOTAL_TARGETS"

    printf \
        "${GREEN}${BOLD}Accessible: %-5d${RESET}  ${RED}${BOLD}Failed: %-5d${RESET}  ${YELLOW}${BOLD}Remaining: %-5d${RESET}\n" \
        "$SUCCESS_COUNT" \
        "$FAILED_COUNT" \
        "$remaining"

    print_separator "$terminal_width"

    printf \
        "${BOLD}Current State:${RESET} %s\n" \
        "$CURRENT_STATE"

    print_separator "$terminal_width"

    printf \
        "${BOLD}RECENT ACTIVITY${RESET} ${DIM}(completion order; CSV remains in input order)${RESET}\n"

    printf \
        "%-5s %-22s %-27s %s\n" \
        "#" \
        "TARGET" \
        "RESULT" \
        "DETAIL"

    printf \
        "%-5s %-22s %-27s %s\n" \
        "-----" \
        "----------------------" \
        "---------------------------" \
        "-------------------------------"

    if (( ${#RECENT_TARGETS[@]} == 0 )); then

        printf \
            "${DIM}No completed checks yet.${RESET}\n"

    else

        for ((i = 0; i < ${#RECENT_TARGETS[@]}; i++)); do

            display_result="${RECENT_RESULTS[$i]}"

            display_detail="$(
                truncate_text \
                    "${RECENT_DETAILS[$i]}" \
                    "$detail_width"
            )"

            if [[ "$display_result" == "ACCESS_OK" ]]; then

                printf \
                    "%-5s %-22s ${GREEN}%-27s${RESET} %s\n" \
                    "${RECENT_NUMBERS[$i]}" \
                    "$(truncate_text "${RECENT_TARGETS[$i]}" "$target_width")" \
                    "$display_result" \
                    "$display_detail"

            else

                printf \
                    "%-5s %-22s ${RED}%-27s${RESET} %s\n" \
                    "${RECENT_NUMBERS[$i]}" \
                    "$(truncate_text "${RECENT_TARGETS[$i]}" "$target_width")" \
                    "$display_result" \
                    "$display_detail"

            fi

        done

    fi

    print_separator "$terminal_width"

    printf \
        "${DIM}Ctrl+C: stop safely | Results use dedicated worker files | --plain: disable dashboard${RESET}\n"
}

###############################################################################
# Write the CSV header
###############################################################################

write_csv_header() {
    printf '%s\n' \
        'Target,Port,Username,Access,Result,TestedAt' \
        > "$OUTPUT_FILE"
}

###############################################################################
# Append a worker result file to the CSV
###############################################################################

append_result_file_to_csv() {
    local result_file="$1"
    local lines=()

    local target=""
    local access=""
    local result=""
    local tested_at=""

    mapfile -t lines < "$result_file"

    target="${lines[0]:-UNKNOWN}"
    access="${lines[1]:-NO}"
    result="${lines[2]:-WORKER_ERROR}"
    tested_at="${lines[4]:-UNKNOWN}"

    printf '%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$target")" \
        "$(csv_escape "$SSH_PORT")" \
        "$(csv_escape "$SSH_USER")" \
        "$(csv_escape "$access")" \
        "$(csv_escape "$result")" \
        "$(csv_escape "$tested_at")" \
        >> "$OUTPUT_FILE"
}

###############################################################################
# Flush only the contiguous completed result sequence to the CSV
#
# This allows the CSV to be updated during the scan without ever breaking input
# order. If result 10 finishes before result 9, result 10 waits until result 9
# is available before both are appended in their original order.
###############################################################################

flush_ordered_results_to_csv() {
    local result_file=""

    while (( NEXT_CSV_INDEX <= TOTAL_TARGETS )); do

        result_file="$(
            result_file_for_index \
                "$NEXT_CSV_INDEX"
        )"

        if [[ ! -f "$result_file" ]]; then
            break
        fi

        append_result_file_to_csv \
            "$result_file"

        NEXT_CSV_INDEX=$((NEXT_CSV_INDEX + 1))

    done
}

###############################################################################
# Rebuild a partial CSV from all completed workers in exact input order
#
# This is used when the user interrupts the scan. Completed results are retained
# and written in original input order even if there are gaps from unfinished
# targets.
###############################################################################

rebuild_partial_csv() {
    local index=0
    local result_file=""

    [[ -n "$OUTPUT_FILE" ]] || return 0

    [[ -n "$TEMP_DIR" &&
       -d "$TEMP_DIR/results" ]] || return 0

    write_csv_header || return 1

    for ((index = 1; index <= TOTAL_TARGETS; index++)); do

        result_file="$(
            result_file_for_index \
                "$index"
        )"

        if [[ -f "$result_file" ]]; then

            append_result_file_to_csv \
                "$result_file"

        fi

    done
}

###############################################################################
# Execute one SSH test in an isolated worker process
#
# Every worker uses unique error, known_hosts, temporary, and result files.
# This avoids race conditions between parallel SSH sessions.
###############################################################################

worker_test_target() {
    local index="$1"
    local target="$2"

    local error_file="$TEMP_DIR/errors/error_$(printf '%06d' "$index").log"
    local known_hosts_file="$TEMP_DIR/known_hosts/known_hosts_$(printf '%06d' "$index")"

    local result_file=""
    local temp_result_file=""
    local ssh_exit_code=0
    local access="NO"
    local result=""
    local detail=""
    local tested_at=""
    local classified=()

    result_file="$(
        result_file_for_index \
            "$index"
    )"

    temp_result_file="${result_file}.tmp.$$"

    : > "$error_file"
    : > "$known_hosts_file"

    ###########################################################################
    # Provide the password to sshpass through file descriptor 3
    #
    # The password is inherited by the worker process but is not placed in the
    # SSH command line.
    ###########################################################################

    exec 3<<<"$SSH_PASSWORD"

    ###########################################################################
    # Perform the SSH authentication test
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
        -o UserKnownHostsFile="$known_hosts_file" \
        -o LogLevel=ERROR \
        "$target" \
        "exit 0" \
        2>"$error_file"
    then

        ssh_exit_code=0

    else

        ssh_exit_code=$?

    fi

    exec 3<&-

    ###########################################################################
    # Classify the worker result
    ###########################################################################

    if [[ "$ssh_exit_code" -eq 0 ]]; then

        access="YES"
        result="ACCESS_OK"
        detail="Login successful"

    else

        mapfile -t classified < <(
            classify_ssh_failure \
                "$ssh_exit_code" \
                "$error_file"
        )

        result="${classified[0]:-SSH_ERROR}"
        detail="${classified[1]:-Unable to classify SSH failure}"

    fi

    tested_at="$(
        date '+%Y-%m-%d %H:%M:%S %z'
    )"

    ###########################################################################
    # Write the worker result atomically
    #
    # The temporary file is renamed only after it has been completely written.
    # The parent therefore never sees a partially-written worker result.
    ###########################################################################

    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$target" \
        "$access" \
        "$result" \
        "$detail" \
        "$tested_at" \
        > "$temp_result_file"

    mv -f \
        "$temp_result_file" \
        "$result_file"
}

###############################################################################
# Launch a worker for a target index
###############################################################################

launch_worker() {
    local index="$1"
    local target="${TARGETS[$((index - 1))]}"
    local pid=0

    worker_test_target \
        "$index" \
        "$target" &

    pid=$!

    ACTIVE_PIDS+=("$pid")
    ACTIVE_INDICES+=("$index")

    RUNNING_COUNT=$((RUNNING_COUNT + 1))
}

###############################################################################
# Create a synthetic result if a worker terminates without producing output
###############################################################################

create_worker_error_result() {
    local index="$1"
    local target="${TARGETS[$((index - 1))]}"

    local result_file=""
    local temp_result_file=""
    local tested_at=""

    result_file="$(
        result_file_for_index \
            "$index"
    )"

    temp_result_file="${result_file}.tmp.parent.$$"

    tested_at="$(
        date '+%Y-%m-%d %H:%M:%S %z'
    )"

    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$target" \
        "NO" \
        "WORKER_ERROR" \
        "Worker terminated without producing a result" \
        "$tested_at" \
        > "$temp_result_file"

    mv -f \
        "$temp_result_file" \
        "$result_file"
}

###############################################################################
# Process one newly completed worker result in the parent process
###############################################################################

process_completed_result() {
    local index="$1"
    local result_file=""
    local lines=()

    local target=""
    local access=""
    local result=""
    local detail=""

    if [[ "${PROCESSED_FLAGS[$index]:-0}" -eq 1 ]]; then
        return 0
    fi

    result_file="$(
        result_file_for_index \
            "$index"
    )"

    if [[ ! -f "$result_file" ]]; then

        create_worker_error_result \
            "$index"

    fi

    mapfile -t lines < "$result_file"

    target="${lines[0]:-${TARGETS[$((index - 1))]}}"
    access="${lines[1]:-NO}"
    result="${lines[2]:-WORKER_ERROR}"
    detail="${lines[3]:-Worker result file was incomplete}"

    PROCESSED_FLAGS[$index]=1

    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))

    if [[ "$access" == "YES" &&
          "$result" == "ACCESS_OK" ]]; then

        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

    else

        FAILED_COUNT=$((FAILED_COUNT + 1))

    fi

    ###########################################################################
    # Recent activity intentionally uses completion order.
    #
    # The input index is displayed so the original location is still clear.
    ###########################################################################

    add_recent_result \
        "$index" \
        "$target" \
        "$result" \
        "$detail"

    CURRENT_STATE="Completed input #${index}: ${target} -> ${result}"

    ###########################################################################
    # Plain mode displays results immediately in actual completion order.
    #
    # This does not affect CSV ordering.
    ###########################################################################

    if [[ "$UI_ENABLED" -eq 0 ]]; then

        if [[ "$result" == "ACCESS_OK" ]]; then

            printf \
                "${GREEN}[ACCESS OK]${RESET} [input #%d] %s\n" \
                "$index" \
                "$target"

        else

            printf \
                "${RED}[ACCESS FAILED]${RESET} [input #%d] %s - %s\n" \
                "$index" \
                "$target" \
                "$result"

            printf \
                "${YELLOW}[DETAIL]${RESET} %s\n" \
                "$detail"

        fi

        printf \
            "${CYAN}[PROGRESS]${RESET} %d%% (%d/%d)\n" \
            "$((PROCESSED_COUNT * 100 / TOTAL_TARGETS))" \
            "$PROCESSED_COUNT" \
            "$TOTAL_TARGETS"

    fi
}

###############################################################################
# Poll active workers and collect any workers that have completed
###############################################################################

poll_workers() {
    local new_pids=()
    local new_indices=()

    local array_position=0
    local pid=0
    local index=0
    local result_file=""
    local completed_now=0

    for ((
        array_position = 0;
        array_position < ${#ACTIVE_PIDS[@]};
        array_position++
    )); do

        pid="${ACTIVE_PIDS[$array_position]}"
        index="${ACTIVE_INDICES[$array_position]}"

        result_file="$(
            result_file_for_index \
                "$index"
        )"

        #######################################################################
        # A result file means the worker completed its atomic result write.
        #######################################################################

        if [[ -f "$result_file" ]]; then

            wait "$pid" 2>/dev/null || true

            RUNNING_COUNT=$((RUNNING_COUNT - 1))

            process_completed_result \
                "$index"

            completed_now=$((completed_now + 1))

        #######################################################################
        # The process is still running.
        #######################################################################

        elif kill -0 "$pid" 2>/dev/null; then

            new_pids+=("$pid")
            new_indices+=("$index")

        #######################################################################
        # The process disappeared without producing a result file.
        #######################################################################

        else

            wait "$pid" 2>/dev/null || true

            RUNNING_COUNT=$((RUNNING_COUNT - 1))

            create_worker_error_result \
                "$index"

            process_completed_result \
                "$index"

            completed_now=$((completed_now + 1))

        fi

    done

    ACTIVE_PIDS=("${new_pids[@]}")
    ACTIVE_INDICES=("${new_indices[@]}")

    ###########################################################################
    # Update the CSV only after new results become available.
    #
    # The flush function will never write a later target before an earlier one.
    ###########################################################################

    if (( completed_now > 0 )); then

        flush_ordered_results_to_csv

    fi

    return 0
}

###############################################################################
# Stop all currently active workers
###############################################################################

terminate_active_workers() {
    local pid=0

    for pid in "${ACTIVE_PIDS[@]}"; do

        if kill -0 "$pid" 2>/dev/null; then

            kill -TERM \
                "$pid" \
                2>/dev/null ||
                true

        fi

    done

    sleep 0.2

    for pid in "${ACTIVE_PIDS[@]}"; do

        if kill -0 "$pid" 2>/dev/null; then

            kill -KILL \
                "$pid" \
                2>/dev/null ||
                true

        fi

        wait "$pid" \
            2>/dev/null ||
            true

    done

    ACTIVE_PIDS=()
    ACTIVE_INDICES=()

    RUNNING_COUNT=0
}

###############################################################################
# Remove temporary data and sensitive variables when the script exits
###############################################################################

cleanup() {
    restore_ui

    unset SSH_PASSWORD \
        2>/dev/null ||
        true

    if [[ -n "${TEMP_DIR:-}" &&
          -d "$TEMP_DIR" ]]; then

        rm -rf "$TEMP_DIR"

    fi
}

###############################################################################
# Handle Ctrl+C and preserve completed results in original input order
###############################################################################

handle_interrupt() {
    trap - INT TERM

    INTERRUPTED=1

    terminate_active_workers

    ###########################################################################
    # Rebuild the CSV from all workers that completed before interruption.
    #
    # Even if worker 20 completed while worker 19 did not, completed results
    # are still written according to their original input positions.
    ###########################################################################

    rebuild_partial_csv ||
        true

    restore_ui

    printf "\n"

    print_warning "Execution interrupted by the user."

    print_warning \
        "Completed targets: ${PROCESSED_COUNT}/${TOTAL_TARGETS}"

    if [[ -n "${OUTPUT_FILE:-}" ]]; then

        print_warning \
            "Completed results were saved in original input order to: $OUTPUT_FILE"

    fi

    exit 130
}

###############################################################################
# Handle external termination signals
###############################################################################

handle_termination() {
    trap - INT TERM

    INTERRUPTED=1

    terminate_active_workers

    rebuild_partial_csv ||
        true

    restore_ui

    printf "\n"

    print_warning "Termination signal received."

    print_warning \
        "Completed targets: ${PROCESSED_COUNT}/${TOTAL_TARGETS}"

    if [[ -n "${OUTPUT_FILE:-}" ]]; then

        print_warning \
            "Completed results were saved in original input order to: $OUTPUT_FILE"

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
# Read and validate the target list filename
###############################################################################

if [[ -z "$IP_FILE" ]]; then

    read -r -p \
        "Enter the path to the IP address list file: " \
        IP_FILE

fi

if [[ ! -f "$IP_FILE" ]]; then

    print_error \
        "Input file does not exist: $IP_FILE"

    exit 1

fi

if [[ ! -r "$IP_FILE" ]]; then

    print_error \
        "Input file is not readable: $IP_FILE"

    exit 1

fi

print_success \
    "Input file loaded: $IP_FILE"

###############################################################################
# Load targets into memory while preserving exact input order
###############################################################################

while IFS= read -r line ||
      [[ -n "$line" ]]; do

    # Remove comments from the line.
    line="${line%%#*}"

    # Remove leading and trailing whitespace.
    line="$(trim_string "$line")"

    # Ignore empty lines.
    [[ -z "$line" ]] &&
        continue

    TARGETS+=("$line")

done < "$IP_FILE"

TOTAL_TARGETS="${#TARGETS[@]}"

if [[ "$TOTAL_TARGETS" -eq 0 ]]; then

    print_error \
        "No valid targets were found in the input file."

    exit 1

fi

print_info \
    "Targets found: $TOTAL_TARGETS"

###############################################################################
# Read SSH username
###############################################################################

while true; do

    read -r -p \
        "Enter the SSH username: " \
        SSH_USER

    if [[ -n "$SSH_USER" ]]; then
        break
    fi

    print_warning \
        "Username cannot be empty."

done

###############################################################################
# Read SSH password without displaying it on the terminal
###############################################################################

while true; do

    read -r -s -p \
        "Enter the SSH password: " \
        SSH_PASSWORD

    printf "\n"

    if [[ -n "$SSH_PASSWORD" ]]; then
        break
    fi

    print_warning \
        "Password cannot be empty."

done

###############################################################################
# Read SSH port
###############################################################################

read -r -p \
    "Enter the SSH port [22]: " \
    SSH_PORT

SSH_PORT="${SSH_PORT:-22}"

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] ||
   (( SSH_PORT < 1 || SSH_PORT > 65535 )); then

    print_error \
        "Invalid SSH port: $SSH_PORT"

    exit 1

fi

###############################################################################
# Read connection timeout
###############################################################################

read -r -p \
    "Enter the connection timeout in seconds [8]: " \
    CONNECT_TIMEOUT

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-8}"

if ! [[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] ||
   (( CONNECT_TIMEOUT < 1 )); then

    print_error \
        "Invalid timeout value."

    exit 1

fi

TOTAL_TIMEOUT=$((CONNECT_TIMEOUT + 5))

###############################################################################
# Read the number of concurrent workers
###############################################################################

read -r -p \
    "Enter the number of concurrent SSH workers [${DEFAULT_WORKERS}]: " \
    WORKER_COUNT

WORKER_COUNT="${WORKER_COUNT:-$DEFAULT_WORKERS}"

if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] ||
   (( WORKER_COUNT < 1 || WORKER_COUNT > MAX_WORKERS )); then

    print_error \
        "Worker count must be between 1 and ${MAX_WORKERS}."

    exit 1

fi

###############################################################################
# Do not create more workers than available targets
###############################################################################

if (( WORKER_COUNT > TOTAL_TARGETS )); then

    WORKER_COUNT="$TOTAL_TARGETS"

fi

###############################################################################
# Warn before using aggressive concurrency
###############################################################################

if (( WORKER_COUNT > RECOMMENDED_MAX_WORKERS )); then

    print_warning \
        "High concurrency can trigger account lockout faster when credentials are invalid."

    print_warning \
        "It can also trigger SSH rate limits, IDS/IPS alerts, or transient connection failures."

    read -r -p \
        "Continue with ${WORKER_COUNT} concurrent workers? [y/N]: " \
        HIGH_CONCURRENCY_CONFIRMATION

    case "${HIGH_CONCURRENCY_CONFIRMATION,,}" in

        y|yes)
            ;;

        *)
            print_warning \
                "Operation cancelled."

            exit 0
            ;;

    esac

fi

print_info \
    "Concurrent SSH workers: $WORKER_COUNT"

print_info \
    "Final CSV order: exact input order"

###############################################################################
# Read output CSV filename
###############################################################################

DEFAULT_OUTPUT_FILE="ssh_access_results_$(date '+%Y%m%d_%H%M%S').csv"

read -r -p \
    "Enter the output CSV filename [$DEFAULT_OUTPUT_FILE]: " \
    OUTPUT_FILE

OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"

if [[ -d "$OUTPUT_FILE" ]]; then

    print_error \
        "The output path points to a directory: $OUTPUT_FILE"

    exit 1

fi

if [[ -e "$OUTPUT_FILE" ]]; then

    read -r -p \
        "Output file already exists. Overwrite it? [y/N]: " \
        OVERWRITE_CONFIRMATION

    case "${OVERWRITE_CONFIRMATION,,}" in

        y|yes)
            ;;

        *)
            print_warning \
                "Operation cancelled. Existing output file was not modified."

            exit 0
            ;;

    esac

fi

###############################################################################
# Create isolated temporary directories for worker runtime data
###############################################################################

TEMP_DIR="$(mktemp -d)" || {
    print_error \
        "Failed to create a temporary directory."

    exit 1
}

mkdir -p \
    "$TEMP_DIR/results" \
    "$TEMP_DIR/errors" \
    "$TEMP_DIR/known_hosts" || {

        print_error \
            "Failed to create worker runtime directories."

        exit 1
    }

###############################################################################
# Create the ordered CSV file
###############################################################################

if ! write_csv_header; then

    print_error \
        "Failed to create the CSV output file: $OUTPUT_FILE"

    exit 1

fi

print_success \
    "CSV output file created: $OUTPUT_FILE"

###############################################################################
# Configure and start the live dashboard
###############################################################################

configure_ui

START_EPOCH="$(date +%s)"

CURRENT_STATE="Starting ${WORKER_COUNT} parallel workers"

if [[ "$UI_ENABLED" -eq 1 ]]; then

    start_ui

    render_dashboard

else

    printf "\n"

    print_info \
        "Live dashboard is disabled. Using plain output mode."

    printf "\n"

fi

###############################################################################
# Main parallel scheduler
#
# Workers may complete in any order.
#
# Only the parent process updates:
#   - Counters
#   - Dashboard
#   - CSV output
#
# This prevents race conditions.
###############################################################################

while (( PROCESSED_COUNT < TOTAL_TARGETS )); do

    ###########################################################################
    # Fill all available worker slots
    ###########################################################################

    while (( RUNNING_COUNT < WORKER_COUNT &&
             NEXT_LAUNCH_INDEX <= TOTAL_TARGETS )); do

        launch_worker \
            "$NEXT_LAUNCH_INDEX"

        CURRENT_STATE="Launched input #${NEXT_LAUNCH_INDEX}: ${TARGETS[$((NEXT_LAUNCH_INDEX - 1))]}"

        NEXT_LAUNCH_INDEX=$((NEXT_LAUNCH_INDEX + 1))

    done

    ###########################################################################
    # Collect workers that completed since the previous polling cycle
    ###########################################################################

    poll_workers

    ###########################################################################
    # Refresh the live dashboard
    ###########################################################################

    if [[ "$UI_ENABLED" -eq 1 ]]; then

        render_dashboard

    fi

    ###########################################################################
    # Avoid unnecessary CPU usage while waiting for SSH workers
    ###########################################################################

    if (( PROCESSED_COUNT < TOTAL_TARGETS )); then

        sleep "$POLL_INTERVAL"

    fi

done

###############################################################################
# Ensure every result has been flushed to the CSV in original input order
###############################################################################

flush_ordered_results_to_csv

CURRENT_STATE="Completed successfully"

if [[ "$UI_ENABLED" -eq 1 ]]; then

    render_dashboard

    restore_ui

    printf "\n"

fi

###############################################################################
# Verify that every input target was processed and written
###############################################################################

PROCESSING_COMPLETE=1

if [[ "$PROCESSED_COUNT" -ne "$TOTAL_TARGETS" ]]; then

    PROCESSING_COMPLETE=0

fi

###############################################################################
# NEXT_CSV_INDEX must point one position beyond the final input item
###############################################################################

if [[ "$NEXT_CSV_INDEX" -ne $((TOTAL_TARGETS + 1)) ]]; then

    PROCESSING_COMPLETE=0

fi

###############################################################################
# Display final summary
###############################################################################

printf "\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"
printf "${BOLD}${CYAN}               FINAL SUMMARY${RESET}\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"

printf \
    "Targets found : %s\n" \
    "$TOTAL_TARGETS"

printf \
    "Targets tested: %s\n" \
    "$PROCESSED_COUNT"

printf \
    "Workers used  : %s\n" \
    "$WORKER_COUNT"

printf \
    "${GREEN}Accessible    : %s${RESET}\n" \
    "$SUCCESS_COUNT"

printf \
    "${RED}Not accessible: %s${RESET}\n" \
    "$FAILED_COUNT"

printf \
    "Elapsed time  : %s\n" \
    "$(format_elapsed_time)"

printf \
    "CSV ordering  : Input order preserved\n"

printf "\n"

###############################################################################
# Return a meaningful final exit status
###############################################################################

if [[ "$PROCESSING_COMPLETE" -eq 1 ]]; then

    print_success \
        "All targets were processed."

    print_success \
        "CSV order exactly matches the input target order."

    print_success \
        "Results saved to: $OUTPUT_FILE"

    exit 0

else

    print_warning \
        "The scan finished, but result integrity verification failed."

    print_warning \
        "Review the CSV before using it as an authoritative result."

    print_warning \
        "Results saved to: $OUTPUT_FILE"

    exit 3

fi
