#!/usr/bin/env bash

set -u
set -o pipefail

###############################################################################
# SSH Access Checker
#
# This script:
#   1. Checks required dependencies.
#   2. Installs missing dependencies when possible.
#   3. Reads a list of IP addresses or hostnames from a text file.
#   4. Prompts the user for SSH credentials.
#   5. Tests SSH access to every target.
#   6. Displays color-coded results on the terminal.
#   7. Saves the final result as a CSV file.
#
# Input file format:
#   One IP address or hostname per line.
#
# Example:
#   192.168.1.10
#   192.168.1.11
#   server01.example.local
#
###############################################################################

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
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    BOLD=""
    RESET=""
fi


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
# Run a command as root
#
# If the current user is root, the command is executed directly.
# Otherwise sudo is used.
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
# Detect the Linux package manager
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
# Install missing dependencies
###############################################################################

install_dependencies() {

    local ssh_missing=0
    local sshpass_missing=0
    local timeout_missing=0

    if ! command -v ssh >/dev/null 2>&1; then
        ssh_missing=1
    fi

    if ! command -v sshpass >/dev/null 2>&1; then
        sshpass_missing=1
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        timeout_missing=1
    fi

    if [[ "$ssh_missing" -eq 0 &&
          "$sshpass_missing" -eq 0 &&
          "$timeout_missing" -eq 0 ]]; then

        print_success "All required dependencies are already installed."
        return
    fi

    print_warning "Some required dependencies are missing."

    [[ "$ssh_missing" -eq 1 ]] && print_warning "Missing command: ssh"
    [[ "$sshpass_missing" -eq 1 ]] && print_warning "Missing command: sshpass"
    [[ "$timeout_missing" -eq 1 ]] && print_warning "Missing command: timeout"

    local package_manager

    package_manager="$(detect_package_manager)"

    print_info "Detected package manager: ${package_manager}"

    case "$package_manager" in

        apt)
            local packages=()

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
            local packages=()

            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-clients")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root dnf install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                exit 1
            }
            ;;

        yum)
            local packages=()

            [[ "$ssh_missing" -eq 1 ]] && packages+=("openssh-clients")
            [[ "$sshpass_missing" -eq 1 ]] && packages+=("sshpass")
            [[ "$timeout_missing" -eq 1 ]] && packages+=("coreutils")

            print_info "Installing required packages..."

            run_as_root yum install -y "${packages[@]}" || {
                print_error "Failed to install required packages."
                exit 1
            }
            ;;

        zypper)
            local packages=()

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
            local packages=()

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
            local packages=()

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


    ###########################################################################
    # Verify the dependencies after installation
    ###########################################################################

    local dependency_error=0

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
# Escape a value so it can safely be written into a CSV file
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
# Cleanup temporary files and sensitive variables
###############################################################################

cleanup() {

    unset SSH_PASSWORD 2>/dev/null || true

    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM


###############################################################################
# Display banner
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
#
# The filename can also be supplied as the first command-line argument.
###############################################################################

IP_FILE="${1:-}"

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
# Define the maximum total time allowed for one SSH attempt
#
# The additional five seconds allow SSH time to complete authentication after
# the TCP connection has been established.
###############################################################################

TOTAL_TIMEOUT=$((CONNECT_TIMEOUT + 5))


###############################################################################
# Ask for output CSV filename
###############################################################################

DEFAULT_OUTPUT_FILE="ssh_access_results_$(date '+%Y%m%d_%H%M%S').csv"

read -r -p "Enter the output CSV filename [$DEFAULT_OUTPUT_FILE]: " OUTPUT_FILE

OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"


###############################################################################
# Create temporary directory
#
# A private known_hosts file is used so the script does not modify the user's
# normal SSH known_hosts file.
###############################################################################

TEMP_DIR="$(mktemp -d)"

KNOWN_HOSTS_FILE="$TEMP_DIR/known_hosts"
SSH_ERROR_FILE="$TEMP_DIR/ssh_error.log"

touch "$KNOWN_HOSTS_FILE"


###############################################################################
# Create the CSV file and write its header
###############################################################################

printf '%s\n' \
    'Target,Port,Username,Access,Result,TestedAt' \
    > "$OUTPUT_FILE"

print_success "CSV output file created: $OUTPUT_FILE"

printf "\n"


###############################################################################
# Count valid targets before starting
###############################################################################

TOTAL_TARGETS=0

while IFS= read -r line || [[ -n "$line" ]]; do

    # Remove comments from the line
    line="${line%%#*}"

    # Remove leading and trailing whitespace
    line="$(trim_string "$line")"

    # Ignore empty lines
    [[ -z "$line" ]] && continue

    ((TOTAL_TARGETS++))

done < "$IP_FILE"


if [[ "$TOTAL_TARGETS" -eq 0 ]]; then
    print_error "No valid targets were found in the input file."
    exit 1
fi

print_info "Targets found: $TOTAL_TARGETS"

printf "\n"


###############################################################################
# Counters
###############################################################################

SUCCESS_COUNT=0
FAILED_COUNT=0
CURRENT_TARGET=0


###############################################################################
# Test SSH access to every target
###############################################################################

while IFS= read -r TARGET || [[ -n "$TARGET" ]]; do

    ###########################################################################
    # Remove comments and whitespace
    ###########################################################################

    TARGET="${TARGET%%#*}"
    TARGET="$(trim_string "$TARGET")"

    [[ -z "$TARGET" ]] && continue

    ((CURRENT_TARGET++))

    printf "${BLUE}--------------------------------------------------${RESET}\n"

    print_test \
        "[$CURRENT_TARGET/$TOTAL_TARGETS] Testing $TARGET:$SSH_PORT as $SSH_USER"

    ###########################################################################
    # Clear the previous SSH error message
    ###########################################################################

    : > "$SSH_ERROR_FILE"


    ###########################################################################
    # Send the password to sshpass using file descriptor 3
    #
    # This avoids placing the password directly in the process command line.
    ###########################################################################

    exec 3<<<"$SSH_PASSWORD"


    ###########################################################################
    # Perform the SSH login test
    #
    # Pubkey authentication is disabled intentionally because this script is
    # specifically testing the username/password supplied by the user.
    #
    # StrictHostKeyChecking=accept-new automatically accepts previously unknown
    # host keys but still detects key changes during the current script run.
    ###########################################################################

    if timeout \
        --signal=TERM \
        "${TOTAL_TIMEOUT}s" \
        sshpass -d 3 \
        ssh \
        -p "$SSH_PORT" \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        -o ConnectionAttempts=1 \
        -o NumberOfPasswordPrompts=1 \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
        -o LogLevel=ERROR \
        "${SSH_USER}@${TARGET}" \
        "exit 0" \
        2>"$SSH_ERROR_FILE"
    then

        SSH_EXIT_CODE=0

    else

        SSH_EXIT_CODE=$?

    fi

    exec 3<&-


    ###########################################################################
    # Determine the test result
    ###########################################################################

    ACCESS="NO"
    RESULT="SSH_ERROR"


    if [[ "$SSH_EXIT_CODE" -eq 0 ]]; then

        ACCESS="YES"
        RESULT="ACCESS_OK"

        ((SUCCESS_COUNT++))

        printf "${GREEN}[ACCESS OK]${RESET} %s\n" "$TARGET"

    else

        ((FAILED_COUNT++))

        SSH_ERROR_MESSAGE="$(cat "$SSH_ERROR_FILE")"


        #######################################################################
        # sshpass exit code 5 normally indicates an invalid password
        #######################################################################

        if [[ "$SSH_EXIT_CODE" -eq 5 ]]; then

            RESULT="AUTHENTICATION_FAILED"


        #######################################################################
        # GNU timeout normally returns exit code 124 when the timeout expires
        #######################################################################

        elif [[ "$SSH_EXIT_CODE" -eq 124 ]]; then

            RESULT="TIMEOUT"


        #######################################################################
        # Detect authentication errors
        #######################################################################

        elif grep -qiE \
            'Permission denied|Authentication failed' \
            "$SSH_ERROR_FILE"; then

            RESULT="AUTHENTICATION_FAILED"


        #######################################################################
        # Detect connection refused
        #######################################################################

        elif grep -qi \
            'Connection refused' \
            "$SSH_ERROR_FILE"; then

            RESULT="CONNECTION_REFUSED"


        #######################################################################
        # Detect unreachable networks or hosts
        #######################################################################

        elif grep -qiE \
            'No route to host|Network is unreachable' \
            "$SSH_ERROR_FILE"; then

            RESULT="HOST_UNREACHABLE"


        #######################################################################
        # Detect connection timeout
        #######################################################################

        elif grep -qiE \
            'Connection timed out|Operation timed out' \
            "$SSH_ERROR_FILE"; then

            RESULT="TIMEOUT"


        #######################################################################
        # Detect hostname resolution errors
        #######################################################################

        elif grep -qiE \
            'Could not resolve hostname|Name or service not known|Temporary failure in name resolution' \
            "$SSH_ERROR_FILE"; then

            RESULT="DNS_ERROR"


        #######################################################################
        # Detect SSH host key errors
        #######################################################################

        elif grep -qi \
            'Host key verification failed' \
            "$SSH_ERROR_FILE"; then

            RESULT="HOST_KEY_ERROR"


        #######################################################################
        # Detect connections closed or reset by the remote system
        #######################################################################

        elif grep -qiE \
            'Connection closed|Connection reset' \
            "$SSH_ERROR_FILE"; then

            RESULT="CONNECTION_CLOSED"

        fi


        printf "${RED}[ACCESS FAILED]${RESET} %s - %s\n" \
            "$TARGET" \
            "$RESULT"


        #######################################################################
        # Display the last SSH error line when available
        #######################################################################

        LAST_ERROR="$(
            grep -v '^[[:space:]]*$' "$SSH_ERROR_FILE" |
            tail -n 1
        )"

        if [[ -n "$LAST_ERROR" ]]; then
            printf "${YELLOW}[DETAIL]${RESET} %s\n" "$LAST_ERROR"
        fi

    fi


    ###########################################################################
    # Save the result to CSV
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

done < "$IP_FILE"


###############################################################################
# Display final summary
###############################################################################

printf "\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"
printf "${BOLD}${CYAN}               FINAL SUMMARY${RESET}\n"
printf "${BOLD}${CYAN}=============================================${RESET}\n"

printf "Total targets : %s\n" "$TOTAL_TARGETS"
printf "${GREEN}Accessible    : %s${RESET}\n" "$SUCCESS_COUNT"
printf "${RED}Not accessible: %s${RESET}\n" "$FAILED_COUNT"

printf "\n"

print_success "Results saved to: $OUTPUT_FILE"

printf "\n"
