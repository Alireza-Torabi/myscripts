#!/usr/bin/env bash

set -uo pipefail

# ============================================================
# 3x-ui DigitalOcean Bootstrap
#
# Flow:
#
#   1. Install dependencies
#   2. Detect DigitalOcean public IP
#   3. Install 3x-ui WITHOUT SSL
#   4. Save credentials immediately
#   5. Create SSH login banner immediately
#   6. Install/verify acme.sh
#   7. Issue Let's Encrypt short-lived IP certificate
#   8. Configure certificate for panel
#   9. Configure same certificate for subscription server
#  10. Restart x-ui
#  11. Authenticate API
#  12. Generate REALITY keys
#  13. Create 4 inbounds
#  14. Create shared Friend client
#  15. Build/test Friend subscription URL
#  16. Final validation
#
#
# Inbounds:
#
#   10253  VLESS / TCP   / none
#   443    VLESS / TCP   / REALITY / Samsung
#   2052   VLESS / XHTTP / REALITY / Docker
#   17667  VLESS / gRPC  / REALITY / k8s
#
#
# Outputs:
#
#   /opt/x-ui/panel-info.txt
#   /opt/x-ui/credentials.env
#   /opt/x-ui/client-info.env
#   /opt/x-ui/inbounds.json
#   /opt/x-ui/generated-inbounds/
#
#
# Log:
#
#   /var/log/x-ui-bootstrap.log
#
# ============================================================


# ============================================================
# GLOBAL SETTINGS
# ============================================================

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

RESULT_DIR="/opt/x-ui"
GENERATED_DIR="${RESULT_DIR}/generated-inbounds"

LOG_FILE="/var/log/x-ui-bootstrap.log"

OFFICIAL_RESULT="/etc/x-ui/install-result.env"

LOGIN_SCRIPT="/etc/profile.d/x-ui-login-info.sh"

DB_FILE="/etc/x-ui/x-ui.db"

COOKIE_JAR="${RESULT_DIR}/api-cookie.txt"

CERT_DIR="/root/cert/ip"

CERT_FULLCHAIN="${CERT_DIR}/fullchain.pem"

CERT_PRIVATE="${CERT_DIR}/privkey.pem"

ACME="/root/.acme.sh/acme.sh"


# ============================================================
# CLIENT SETTINGS
# ============================================================

CLIENT_EMAIL="Friend"

CLIENT_UUID="b7720bca-40a3-4c84-aeb0-b02e913e0cdb"

CLIENT_SUB_ID="lott2zqx6wo184ku"

CLIENT_AUTH="50y3dlr61x29hjgz"

CLIENT_PASSWORD="r0fc66v4g127l40t"

CLIENT_TOTAL_BYTES="1073741824000"


# ============================================================
# RUNTIME STATE
# ============================================================

BOOTSTRAP_STATUS="STARTING"

CONFIG_STATUS="NOT_STARTED"

SSL_STATUS="NOT_STARTED"

SUBSCRIPTION_URL="NOT_AVAILABLE"

SUB_TEST_STATUS="NOT_TESTED"

PUBLIC_IP="UNKNOWN"

AUTH_MODE="unknown"

CSRF_TOKEN=""

PANEL_URL="UNKNOWN"


mkdir -p "$RESULT_DIR"
mkdir -p "$GENERATED_DIR"

chmod 700 "$RESULT_DIR"
chmod 700 "$GENERATED_DIR"


exec > >(tee -a "$LOG_FILE") 2>&1


# ============================================================
# HELPERS
# ============================================================

log()
{
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
    echo
}


die()
{
    echo
    echo "FATAL ERROR:"
    echo "$*"
    echo
    echo "See:"
    echo "$LOG_FILE"
    echo

    exit 1
}


get_public_ip()
{
    local ip=""

    ip="$(
        curl \
            -fsS \
            --connect-timeout 3 \
            --max-time 5 \
            http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address \
            2>/dev/null \
            || true
    )"

    if [[ -z "$ip" ]]; then

        ip="$(
            curl \
                -4 \
                -fsS \
                --connect-timeout 5 \
                --max-time 10 \
                https://api.ipify.org \
                2>/dev/null \
                || true
        )"

    fi

    printf '%s' "$ip"
}


get_setting()
{
    local key="$1"

    if [[ ! -f "$DB_FILE" ]]; then
        return 0
    fi

    sqlite3 "$DB_FILE" \
        "SELECT value FROM settings WHERE key='${key}' LIMIT 1;" \
        2>/dev/null \
        || true
}


set_setting()
{
    local key="$1"
    local value="$2"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    sqlite3 "$DB_FILE" "
        INSERT INTO settings (key,value)
        VALUES ('$key','$value')
        ON CONFLICT(key)
        DO UPDATE SET value=excluded.value;
    "
}


write_panel_info()
{
    cat > "$RESULT_DIR/panel-info.txt" <<EOF
============================================================
                     3x-ui SERVER
============================================================

Bootstrap Status:
${BOOTSTRAP_STATUS}

Configuration Status:
${CONFIG_STATUS}

SSL Status:
${SSL_STATUS}


============================================================
                     SERVER
============================================================

Public IP:
${PUBLIC_IP}


============================================================
                     PANEL ACCESS
============================================================

Panel URL:

${PANEL_URL}

Username:
${XUI_USERNAME:-UNKNOWN}

Password:
${XUI_PASSWORD:-UNKNOWN}

Panel Port:
${XUI_PANEL_PORT:-UNKNOWN}

Panel Base Path:
${XUI_WEB_BASE_PATH:-UNKNOWN}


============================================================
                     TLS CERTIFICATE
============================================================

Certificate:

${CERT_FULLCHAIN}

Private Key:

${CERT_PRIVATE}


============================================================
                     FRIEND CLIENT
============================================================

Client Name:
${CLIENT_EMAIL}

UUID:
${CLIENT_UUID}

Sub ID:
${CLIENT_SUB_ID}

Traffic Limit:
1000 GiB

Expiry:
Unlimited


============================================================
                     SUBSCRIPTION
============================================================

Subscription URL:

${SUBSCRIPTION_URL}

Subscription Test:

${SUB_TEST_STATUS}


============================================================
                     INBOUNDS
============================================================

[1]

Name:
insecure

Protocol:
VLESS

Transport:
TCP

Security:
none

Port:
10253


------------------------------------------------------------

[2]

Name:
Vless-Reality-Row

Protocol:
VLESS

Transport:
TCP

Security:
REALITY

Port:
443

Target:
www.samsung.com:443


------------------------------------------------------------

[3]

Name:
Vless-Xhttp

Protocol:
VLESS

Transport:
XHTTP

Security:
REALITY

Port:
2052

Path:
/xhttp

Target:
www.docker.io:443


------------------------------------------------------------

[4]

Name:
Vless-Reality-gRPC

Protocol:
VLESS

Transport:
gRPC

Security:
REALITY

Port:
17667

Target:
www.k8s.io:443


============================================================
                     FILES
============================================================

Panel credentials:

/opt/x-ui/credentials.env


Friend client:

/opt/x-ui/client-info.env


Inbound snapshot:

/opt/x-ui/inbounds.json


Generated inbound JSON:

/opt/x-ui/generated-inbounds/


Bootstrap log:

/var/log/x-ui-bootstrap.log


Original installer result:

/etc/x-ui/install-result.env


============================================================
Last Updated:

$(date)

============================================================
EOF

    chmod 600 "$RESULT_DIR/panel-info.txt"
    chown root:root "$RESULT_DIR/panel-info.txt"
}


create_login_banner()
{
    cat > "$LOGIN_SCRIPT" <<'EOF'
#!/usr/bin/env bash

if [[ -n "${SSH_CONNECTION:-}" && $- == *i* ]]; then

    echo
    echo "################################################################"
    echo "#                                                              #"
    echo "#                    3x-ui SERVER INFO                         #"
    echo "#                                                              #"
    echo "################################################################"
    echo

    if [[ -r /opt/x-ui/panel-info.txt ]]; then
        cat /opt/x-ui/panel-info.txt
    else
        echo "/opt/x-ui/panel-info.txt not found."
    fi

    echo
    echo
    echo "################################################################"
    echo "#                    3x-ui CREDENTIALS                         #"
    echo "################################################################"
    echo

    if [[ -r /opt/x-ui/credentials.env ]]; then
        cat /opt/x-ui/credentials.env
    else
        echo "/opt/x-ui/credentials.env not found."
    fi

    echo
    echo "################################################################"
    echo

    echo "Useful commands:"
    echo

    echo "  cat /opt/x-ui/panel-info.txt"
    echo "  cat /opt/x-ui/credentials.env"
    echo "  cat /opt/x-ui/client-info.env"
    echo "  cat /opt/x-ui/inbounds.json"
    echo "  tail -n 200 /var/log/x-ui-bootstrap.log"
    echo "  systemctl status x-ui"
    echo "  x-ui"

    echo
    echo "################################################################"
    echo

fi
EOF

    chmod 755 "$LOGIN_SCRIPT"

    chown root:root "$LOGIN_SCRIPT"
}


# ============================================================
# API FUNCTIONS
# ============================================================

api_get_bearer()
{
    local uri="$1"

    curl \
        -k \
        -sS \
        --connect-timeout 3 \
        --max-time 10 \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        "${API_BASE}${uri}"
}


api_post_bearer()
{
    local uri="$1"
    local body="$2"

    curl \
        -k \
        -sS \
        --connect-timeout 3 \
        --max-time 30 \
        -X POST \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$body" \
        "${API_BASE}${uri}"
}


api_get_session()
{
    local uri="$1"

    curl \
        -k \
        -sS \
        --connect-timeout 3 \
        --max-time 10 \
        -b "$COOKIE_JAR" \
        "${API_BASE}${uri}"
}


api_post_session()
{
    local uri="$1"
    local body="$2"

    curl \
        -k \
        -sS \
        --connect-timeout 3 \
        --max-time 30 \
        -X POST \
        -b "$COOKIE_JAR" \
        -H "X-CSRF-Token: ${CSRF_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$body" \
        "${API_BASE}${uri}"
}


api_get()
{
    local uri="$1"

    if [[ "$AUTH_MODE" == "bearer" ]]; then
        api_get_bearer "$uri"
    else
        api_get_session "$uri"
    fi
}


api_post()
{
    local uri="$1"
    local body="$2"

    if [[ "$AUTH_MODE" == "bearer" ]]; then
        api_post_bearer "$uri" "$body"
    else
        api_post_session "$uri" "$body"
    fi
}


# ============================================================
# START
# ============================================================

log "3x-ui DigitalOcean Bootstrap"

echo "Started:"
date


# ============================================================
# 1. NETWORK
# ============================================================

log "[1/18] Waiting for network"


NETWORK_OK=0


for i in $(seq 1 40); do

    if curl \
        -fsS \
        --connect-timeout 3 \
        --max-time 5 \
        https://github.com \
        >/dev/null 2>&1
    then

        NETWORK_OK=1
        break

    fi

    sleep 2

done


if [[ "$NETWORK_OK" -ne 1 ]]; then

    die "Internet connection is not available."

fi


echo "Network OK."


# ============================================================
# 2. DEPENDENCIES
# ============================================================

log "[2/18] Installing dependencies"


apt-get update -y \
    || die "apt-get update failed."


apt-get install -y \
    curl \
    jq \
    sqlite3 \
    ca-certificates \
    openssl \
    uuid-runtime \
    iproute2 \
    socat \
    cron \
    || die "Dependency installation failed."


# ============================================================
# 3. PUBLIC IP
# ============================================================

log "[3/18] Detecting DigitalOcean public IPv4"


PUBLIC_IP="$(get_public_ip)"


if [[ -z "$PUBLIC_IP" ]]; then

    die "Could not determine public IPv4."

fi


echo "Public IP:"
echo "$PUBLIC_IP"


# ============================================================
# 4. INSTALL 3x-ui WITHOUT SSL
# ============================================================

log "[4/18] Installing 3x-ui WITHOUT SSL"


export XUI_NONINTERACTIVE=1

export XUI_DB_TYPE="sqlite"

# IMPORTANT:
# SSL is intentionally disabled during installer execution.
#
# We configure SSL ourselves AFTER installation to avoid
# the cloud-init/acme.sh race condition.
export XUI_SSL_MODE="none"


curl \
    -fsSL \
    https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh \
    -o /tmp/install-x-ui.sh \
    || die "Could not download 3x-ui installer."


chmod 700 /tmp/install-x-ui.sh


bash /tmp/install-x-ui.sh


INSTALL_RC=$?


if [[ "$INSTALL_RC" -ne 0 ]]; then

    die "3x-ui installer returned exit code ${INSTALL_RC}."

fi


# ============================================================
# 5. VERIFY INSTALLATION
# ============================================================

log "[5/18] Verifying x-ui installation"


if [[ ! -f "$OFFICIAL_RESULT" ]]; then

    die "$OFFICIAL_RESULT was not created."

fi


if ! systemctl is-active --quiet x-ui; then

    systemctl status x-ui \
        --no-pager \
        -l \
        || true

    die "x-ui service is not running."

fi


echo "x-ui service is running."


# ============================================================
# 6. LOAD AND SAVE CREDENTIALS
# ============================================================

log "[6/18] Loading panel credentials"


# shellcheck disable=SC1090
source "$OFFICIAL_RESULT"


install \
    -m 600 \
    -o root \
    -g root \
    "$OFFICIAL_RESULT" \
    "$RESULT_DIR/credentials.env" \
    || die "Could not save credentials.env."


WEB_PATH="${XUI_WEB_BASE_PATH#/}"
WEB_PATH="${WEB_PATH%/}"


BOOTSTRAP_STATUS="PANEL_INSTALLED"

CONFIG_STATUS="WAITING_FOR_SSL"

SSL_STATUS="PENDING"


PANEL_URL="http://${PUBLIC_IP}:${XUI_PANEL_PORT}/${WEB_PATH}"


write_panel_info

create_login_banner


# ============================================================
# 7. INSTALL / VERIFY acme.sh
# ============================================================

log "[7/18] Installing and verifying acme.sh"


if [[ ! -x "$ACME" ]]; then

    echo "acme.sh not found."

    echo "Installing acme.sh..."


    curl \
        -fsSL \
        https://get.acme.sh \
        -o /tmp/install-acme.sh \
        || die "Could not download acme.sh installer."


    chmod 700 /tmp/install-acme.sh


    bash /tmp/install-acme.sh


    ACME_INSTALL_RC=$?


    if [[ "$ACME_INSTALL_RC" -ne 0 ]]; then

        SSL_STATUS="FAILED: acme.sh installer"

        CONFIG_STATUS="FAILED"

        write_panel_info

        die "acme.sh installer failed."

    fi

fi


# ------------------------------------------------------------
# Wait until acme.sh really exists.
#
# This is the critical fix for the race we observed.
# ------------------------------------------------------------

ACME_READY=0


for i in $(seq 1 30); do

    if [[ -x "$ACME" ]]; then

        ACME_READY=1
        break

    fi

    sleep 1

done


if [[ "$ACME_READY" -ne 1 ]]; then

    SSL_STATUS="FAILED: acme.sh executable missing"

    CONFIG_STATUS="FAILED"

    write_panel_info

    die "$ACME does not exist after installation."

fi


echo "acme.sh verified:"
echo "$ACME"


"$ACME" --version \
    || die "acme.sh cannot execute."


# ============================================================
# 8. PREPARE ACME
# ============================================================

log "[8/18] Preparing Let's Encrypt IP certificate"


mkdir -p "$CERT_DIR"

chmod 700 "$CERT_DIR"


# ------------------------------------------------------------
# Verify port 80 is not already occupied locally.
# ------------------------------------------------------------

if ss -lnt |
    grep -q ':80[[:space:]]'
then

    echo "WARNING:"
    echo "TCP/80 already has a local listener."

    echo
    ss -lntp |
        grep ':80[[:space:]]' \
        || true

    echo
    echo "Standalone ACME validation requires local port 80."
    echo

    SSL_STATUS="FAILED: local port 80 occupied"

    CONFIG_STATUS="FAILED"

    write_panel_info

    exit 1

fi


echo "Local TCP/80 is free."


# ------------------------------------------------------------
# Select Let's Encrypt.
# ------------------------------------------------------------

"$ACME" \
    --set-default-ca \
    --server letsencrypt \
    --force \
    >/dev/null 2>&1 \
    || true


# ============================================================
# 9. ISSUE IP CERTIFICATE
# ============================================================

log "[9/18] Issuing Let's Encrypt short-lived IP certificate"


# ------------------------------------------------------------
# Remove failed old issuance state if this script was retried.
# ------------------------------------------------------------

rm -rf "/root/.acme.sh/${PUBLIC_IP}" \
       "/root/.acme.sh/${PUBLIC_IP}_ecc" \
       2>/dev/null \
       || true


"$ACME" \
    --issue \
    -d "$PUBLIC_IP" \
    --standalone \
    --server letsencrypt \
    --certificate-profile shortlived \
    --days 6 \
    --httpport 80 \
    --force


CERT_ISSUE_RC=$?


if [[ "$CERT_ISSUE_RC" -ne 0 ]]; then

    SSL_STATUS="FAILED: certificate issuance"

    CONFIG_STATUS="FAILED"

    write_panel_info

    echo
    echo "Certificate issuance failed."
    echo
    echo "Check:"
    echo
    echo "1. DigitalOcean Firewall TCP/80"
    echo "2. Any external firewall"
    echo "3. Routing to ${PUBLIC_IP}"
    echo "4. ACME log"
    echo

    exit 1

fi


echo "Certificate issuance succeeded."


# ============================================================
# 10. INSTALL CERTIFICATE FILES
# ============================================================

log "[10/18] Installing certificate files"


"$ACME" \
    --installcert \
    --force \
    -d "$PUBLIC_IP" \
    --key-file "$CERT_PRIVATE" \
    --fullchain-file "$CERT_FULLCHAIN" \
    --reloadcmd "systemctl restart x-ui" \
    || true


if [[ ! -s "$CERT_FULLCHAIN" ]]; then

    SSL_STATUS="FAILED: fullchain missing"

    CONFIG_STATUS="FAILED"

    write_panel_info

    die "Certificate file missing: $CERT_FULLCHAIN"

fi


if [[ ! -s "$CERT_PRIVATE" ]]; then

    SSL_STATUS="FAILED: private key missing"

    CONFIG_STATUS="FAILED"

    write_panel_info

    die "Private key missing: $CERT_PRIVATE"

fi


chmod 644 "$CERT_FULLCHAIN"

chmod 600 "$CERT_PRIVATE"


echo "Certificate:"
echo "$CERT_FULLCHAIN"

echo

echo "Private key:"
echo "$CERT_PRIVATE"


# ============================================================
# 11. CONFIGURE PANEL CERTIFICATE
# ============================================================

log "[11/18] Configuring x-ui panel SSL"


/usr/local/x-ui/x-ui cert \
    -webCert "$CERT_FULLCHAIN" \
    -webCertKey "$CERT_PRIVATE"


CERT_CONFIG_RC=$?


if [[ "$CERT_CONFIG_RC" -ne 0 ]]; then

    SSL_STATUS="FAILED: x-ui cert command"

    CONFIG_STATUS="FAILED"

    write_panel_info

    die "Could not configure panel certificate."

fi


# ============================================================
# 12. CONFIGURE SUBSCRIPTION CERTIFICATE
# ============================================================

log "[12/18] Configuring Subscription TLS"


# ------------------------------------------------------------
# Set same cert for Subscription Server.
#
# These are normal 3x-ui settings:
#
#   subCertFile
#   subKeyFile
# ------------------------------------------------------------

set_setting \
    "subCertFile" \
    "$CERT_FULLCHAIN" \
    || die "Could not configure subCertFile."


set_setting \
    "subKeyFile" \
    "$CERT_PRIVATE" \
    || die "Could not configure subKeyFile."


# Ensure subscription is enabled.
set_setting \
    "subEnable" \
    "true" \
    || true


SSL_STATUS="SUCCESS"


PANEL_URL="https://${PUBLIC_IP}:${XUI_PANEL_PORT}/${WEB_PATH}"


# ============================================================
# SAVE UPDATED CREDENTIAL FILE
# ============================================================

cat > "$RESULT_DIR/credentials.env" <<EOF
XUI_USERNAME=${XUI_USERNAME}
XUI_PASSWORD=${XUI_PASSWORD}
XUI_PANEL_PORT=${XUI_PANEL_PORT}
XUI_WEB_BASE_PATH=${XUI_WEB_BASE_PATH}
XUI_ACCESS_URL=${PANEL_URL}
XUI_API_TOKEN=${XUI_API_TOKEN}
XUI_DB_TYPE=${XUI_DB_TYPE}
XUI_CERT_FILE=${CERT_FULLCHAIN}
XUI_CERT_KEY=${CERT_PRIVATE}
EOF


chmod 600 "$RESULT_DIR/credentials.env"

chown root:root "$RESULT_DIR/credentials.env"


# ============================================================
# 13. RESTART x-ui
# ============================================================

log "[13/18] Restarting x-ui with TLS"


systemctl restart x-ui


sleep 5


if ! systemctl is-active --quiet x-ui; then

    CONFIG_STATUS="FAILED: x-ui restart after SSL"

    write_panel_info


    systemctl status x-ui \
        --no-pager \
        -l \
        || true


    exit 1

fi


echo "x-ui restarted successfully."


# ============================================================
# BUILD API BASE
# ============================================================

API_BASE="https://127.0.0.1:${XUI_PANEL_PORT}/${WEB_PATH}"


echo
echo "API Base:"
echo "$API_BASE"


# ============================================================
# WAIT FOR PANEL PORT
# ============================================================

PORT_READY=0


for i in $(seq 1 40); do

    if ss -lnt |
        grep -q ":${XUI_PANEL_PORT}[[:space:]]"
    then

        PORT_READY=1
        break

    fi

    sleep 2

done


if [[ "$PORT_READY" -ne 1 ]]; then

    CONFIG_STATUS="FAILED: panel TCP port"

    write_panel_info

    die "Panel port did not become ready."

fi


# ============================================================
# 14. AUTHENTICATE API
# ============================================================

log "[14/18] Authenticating 3x-ui API"


API_READY=0


for ATTEMPT in $(seq 1 30); do

    echo "API attempt ${ATTEMPT}/30"


    # --------------------------------------------------------
    # Bearer first
    # --------------------------------------------------------

    RESPONSE="$(
        api_get_bearer \
            "/panel/api/inbounds/list" \
            2>/dev/null \
            || true
    )"


    if echo "$RESPONSE" |
        jq -e '.success == true' \
        >/dev/null 2>&1
    then

        AUTH_MODE="bearer"

        API_READY=1

        break
    fi


    # --------------------------------------------------------
    # Normal login
    # --------------------------------------------------------

    LOGIN_PAYLOAD="$(
        jq -n \
            --arg username "$XUI_USERNAME" \
            --arg password "$XUI_PASSWORD" \
            '{
                username: $username,
                password: $password
            }'
    )"


    LOGIN_RESPONSE="$(
        curl \
            -k \
            -sS \
            --connect-timeout 3 \
            --max-time 10 \
            -c "$COOKIE_JAR" \
            -H "Content-Type: application/json" \
            --data "$LOGIN_PAYLOAD" \
            "${API_BASE}/login" \
            2>/dev/null \
            || true
    )"


    if echo "$LOGIN_RESPONSE" |
        jq -e '.success == true' \
        >/dev/null 2>&1
    then

        chmod 600 "$COOKIE_JAR" \
            2>/dev/null \
            || true


        RESPONSE="$(
            api_get_bearer \
                "/panel/api/inbounds/list" \
                2>/dev/null \
                || true
        )"


        if echo "$RESPONSE" |
            jq -e '.success == true' \
            >/dev/null 2>&1
        then

            AUTH_MODE="bearer"

            API_READY=1

            break
        fi


        # ----------------------------------------------------
        # Session fallback
        # ----------------------------------------------------

        CSRF_RESPONSE="$(
            curl \
                -k \
                -sS \
                --connect-timeout 3 \
                --max-time 10 \
                -b "$COOKIE_JAR" \
                "${API_BASE}/csrf-token" \
                2>/dev/null \
                || true
        )"


        CSRF_TOKEN="$(
            echo "$CSRF_RESPONSE" |
            jq -r '.obj // empty' \
            2>/dev/null \
            || true
        )"


        if [[ -n "$CSRF_TOKEN" ]]; then

            AUTH_MODE="session"


            RESPONSE="$(
                api_get_session \
                    "/panel/api/inbounds/list" \
                    2>/dev/null \
                    || true
            )"


            if echo "$RESPONSE" |
                jq -e '.success == true' \
                >/dev/null 2>&1
            then

                API_READY=1

                break
            fi

        fi

    fi


    sleep 3

done


if [[ "$API_READY" -ne 1 ]]; then

    CONFIG_STATUS="FAILED: API authentication"

    BOOTSTRAP_STATUS="PARTIAL_FAILURE"

    write_panel_info

    exit 1

fi


echo "API authentication:"
echo "$AUTH_MODE"


# ============================================================
# 15. CLEAN PREVIOUS MANAGED CONFIG
# ============================================================

log "[15/18] Preparing managed configuration"


DELETE_FRIEND_PAYLOAD='{
  "emails": [
    "Friend"
  ],
  "keepTraffic": false
}'


api_post \
    "/panel/api/clients/bulkDel" \
    "$DELETE_FRIEND_PAYLOAD" \
    >/dev/null 2>&1 \
    || true


CURRENT_LIST="$(
    api_get \
        "/panel/api/inbounds/list"
)"


for REMARK in \
    "insecure" \
    "Vless-Reality-Row" \
    "Vless-Xhttp" \
    "Vless-Reality-gRPC"
do

    IDS="$(
        echo "$CURRENT_LIST" |
        jq -r \
            --arg remark "$REMARK" \
            '.obj[]? |
             select(.remark == $remark) |
             .id'
    )"


    while read -r ID; do

        [[ -z "$ID" ]] && continue


        echo "Removing old managed inbound:"
        echo "${REMARK} / ID ${ID}"


        if [[ "$AUTH_MODE" == "bearer" ]]; then

            curl \
                -k \
                -sS \
                --connect-timeout 3 \
                --max-time 20 \
                -X POST \
                -H "Authorization: Bearer ${XUI_API_TOKEN}" \
                "${API_BASE}/panel/api/inbounds/del/${ID}" \
                >/dev/null \
                || true

        else

            curl \
                -k \
                -sS \
                --connect-timeout 3 \
                --max-time 20 \
                -X POST \
                -b "$COOKIE_JAR" \
                -H "X-CSRF-Token: ${CSRF_TOKEN}" \
                "${API_BASE}/panel/api/inbounds/del/${ID}" \
                >/dev/null \
                || true

        fi

    done <<< "$IDS"

done


sleep 2


CURRENT_LIST="$(
    api_get \
        "/panel/api/inbounds/list"
)"


# ------------------------------------------------------------
# Refuse to delete unknown inbounds on required ports.
# ------------------------------------------------------------

for PORT in 10253 443 2052 17667; do

    CONFLICT="$(
        echo "$CURRENT_LIST" |
        jq -r \
            --argjson port "$PORT" \
            '.obj[]? |
             select(.port == $port) |
             "\(.id)|\(.remark)"' |
        head -n1
    )"


    if [[ -n "$CONFLICT" ]]; then

        CONFIG_STATUS="FAILED: Port ${PORT} conflict"

        BOOTSTRAP_STATUS="PARTIAL_FAILURE"

        write_panel_info


        echo "Port conflict:"
        echo "$CONFLICT"

        exit 1

    fi

done


# ============================================================
# GENERATE REALITY MATERIAL
# ============================================================

generate_reality_material()
{
    local prefix="$1"

    local x25519=""
    local mldsa=""

    local private_key=""
    local public_key=""

    local mldsa_seed=""
    local mldsa_verify=""


    x25519="$(
        api_get \
            "/panel/api/server/getNewX25519Cert"
    )" \
        || return 1


    if ! echo "$x25519" |
        jq -e '.success == true' \
        >/dev/null
    then
        return 1
    fi


    private_key="$(
        echo "$x25519" |
        jq -r '.obj.privateKey // empty'
    )"


    public_key="$(
        echo "$x25519" |
        jq -r '.obj.publicKey // empty'
    )"


    mldsa="$(
        api_get \
            "/panel/api/server/getNewmldsa65"
    )" \
        || return 1


    if ! echo "$mldsa" |
        jq -e '.success == true' \
        >/dev/null
    then
        return 1
    fi


    mldsa_seed="$(
        echo "$mldsa" |
        jq -r '.obj.seed // empty'
    )"


    mldsa_verify="$(
        echo "$mldsa" |
        jq -r '.obj.verify // empty'
    )"


    if [[ \
        -z "$private_key" || \
        -z "$public_key" || \
        -z "$mldsa_seed" || \
        -z "$mldsa_verify" \
    ]]
    then

        return 1

    fi


    printf -v "${prefix}_PRIVATE" \
        '%s' \
        "$private_key"

    printf -v "${prefix}_PUBLIC" \
        '%s' \
        "$public_key"

    printf -v "${prefix}_MLDSA_SEED" \
        '%s' \
        "$mldsa_seed"

    printf -v "${prefix}_MLDSA_VERIFY" \
        '%s' \
        "$mldsa_verify"

    return 0
}


log "[16/18] Generating REALITY keys"


generate_reality_material "ROW" \
    || die "ROW REALITY key generation failed."


generate_reality_material "XHTTP" \
    || die "XHTTP REALITY key generation failed."


generate_reality_material "GRPC" \
    || die "gRPC REALITY key generation failed."


# ============================================================
# BUILD INBOUND JSON
# ============================================================


INBOUND_1="$(
jq -n '
{
  remark: "insecure",
  enable: true,
  expiryTime: 0,
  total: 0,
  trafficReset: "never",
  listen: "",
  port: 10253,
  protocol: "vless",

  settings: {
    clients: [],
    decryption: "none",
    encryption: "none"
  },

  streamSettings: {
    network: "tcp",

    tcpSettings: {
      acceptProxyProtocol: false,

      header: {
        type: "none"
      }
    },

    security: "none"
  },

  tag: "in-10253-tcp",

  sniffing: {
    enabled: false
  },

  shareAddrStrategy: "listen",
  shareAddr: "",
  subSortIndex: 1,
  originNodeGuid: ""
}'
)"


INBOUND_2="$(
jq -n \
  --arg privateKey "$ROW_PRIVATE" \
  --arg publicKey "$ROW_PUBLIC" \
  --arg mldsaSeed "$ROW_MLDSA_SEED" \
  --arg mldsaVerify "$ROW_MLDSA_VERIFY" \
'
{
  remark: "Vless-Reality-Row",
  enable: true,
  expiryTime: 0,
  total: 0,
  trafficReset: "never",
  listen: "",
  port: 443,
  protocol: "vless",

  settings: {
    clients: [],
    decryption: "none",
    encryption: "none",

    testseed: [
      900,
      500,
      900,
      256
    ]
  },

  streamSettings: {

    network: "tcp",

    tcpSettings: {

      acceptProxyProtocol: false,

      header: {
        type: "none"
      }
    },

    security: "reality",

    realitySettings: {

      show: false,
      xver: 0,

      target: "www.samsung.com:443",

      serverNames: [
        "www.samsung.com",
        "adn-stg.yourservice.samsung.com",
        "am-images.shop.samsung.com",
        "ap-author.led.samsung.com",
        "ap-author.semiconductor.samsung.com",
        "api-stg.semiconductor.samsung.cn",
        "api.led.samsung.com",
        "api.semiconductor.samsung.cn",
        "api.semiconductor.samsung.com",
        "au-images.shop.samsung.com",
        "au2-images.shop.samsung.com",
        "b2bshop.samsung.com",
        "cdn.samsung.com",
        "cstudio.semiconductor.samsung.com",
        "download.led.samsung.com",
        "download.semiconductor.samsung.com",
        "eu-images.shop.samsung.com",
        "eventadm.semiconductor.samsung.com",
        "eventapi.semiconductor.samsung.com",
        "image.led.samsung.com",
        "image.samsung.com",
        "image.semiconductor.samsung.com",
        "images.samsung.com",
        "led.samsung.com",
        "legal.samsungdm.com",
        "mena-images.shop.samsung.com",
        "org.semiconductor.samsung.com",
        "perf-prod.samsung.com",
        "pre-prod.samsung.com",
        "qa.semiconductor.samsung.com",
        "qapartners.sec.samsung.com",
        "ru-images.shop.samsung.com",
        "samsung.com",
        "search.led.samsung.com",
        "search.semiconductor.samsung.com",
        "semiconductor.samsung.com",
        "sribsrch.ecom-qa.samsung.com",
        "sribsrch.ecom.samsung.com",
        "stg-am-images.shop.samsung.com",
        "stg-au-images.shop.samsung.com",
        "stg-au2-images.shop.samsung.com",
        "stg-eu-images.shop.samsung.com",
        "stg-mena-images.shop.samsung.com",
        "stg-ru-images.shop.samsung.com",
        "streaming.samsung.com",
        "ue-author.semiconductor.samsung.com",
        "vdapi.samsung.com",
        "www-ams.samsung.com",
        "www.samsungebiz.com",
        "www.semiconductor.samsung.com"
      ],

      privateKey: $privateKey,

      minClientVer: "",
      maxClientVer: "",
      maxTimediff: 0,

      shortIds: [
        "7b",
        "d19a",
        "1059780f1c199b",
        "2da42c",
        "b2102f7fdf",
        "8e3deee4",
        "50922e6cff342142",
        "a96bb07558a5"
      ],

      mldsa65Seed: $mldsaSeed,

      settings: {
        publicKey: $publicKey,
        fingerprint: "chrome",
        serverName: "",
        spiderX: "/",
        mldsa65Verify: $mldsaVerify
      }
    }
  },

  tag: "in-443-tcp",

  sniffing: {
    enabled: false
  },

  shareAddrStrategy: "listen",
  shareAddr: "",
  subSortIndex: 1,
  originNodeGuid: ""
}'
)"


INBOUND_3="$(
jq -n \
  --arg privateKey "$XHTTP_PRIVATE" \
  --arg publicKey "$XHTTP_PUBLIC" \
  --arg mldsaSeed "$XHTTP_MLDSA_SEED" \
  --arg mldsaVerify "$XHTTP_MLDSA_VERIFY" \
'
{
  remark: "Vless-Xhttp",
  enable: true,
  expiryTime: 0,
  total: 0,
  trafficReset: "never",
  listen: "",
  port: 2052,
  protocol: "vless",

  settings: {
    clients: [],
    decryption: "none",
    encryption: "none"
  },

  streamSettings: {

    network: "xhttp",

    xhttpSettings: {
      path: "/xhttp",
      host: "",
      mode: "auto",
      xPaddingBytes: "100-1000",
      scMaxBufferedPosts: 30,
      scStreamUpServerSecs: "20-80"
    },

    security: "reality",

    realitySettings: {

      show: false,
      xver: 0,

      target: "www.docker.io:443",

      serverNames: [
        "dockercon.com",
        "docker.com",
        "docs.docker.com",
        "docker.io"
      ],

      privateKey: $privateKey,

      minClientVer: "",
      maxClientVer: "",
      maxTimediff: 0,

      shortIds: [
        "7d",
        "d556a878e8be",
        "0c8e04",
        "17d23956a0",
        "201979bdc76856",
        "c521",
        "2f7acf5f",
        "aa6f98d388cdef4e"
      ],

      mldsa65Seed: $mldsaSeed,

      settings: {
        publicKey: $publicKey,
        fingerprint: "chrome",
        serverName: "",
        spiderX: "/",
        mldsa65Verify: $mldsaVerify
      }
    }
  },

  tag: "in-2052-tcp",

  sniffing: {
    enabled: false
  },

  shareAddrStrategy: "listen",
  shareAddr: "",
  subSortIndex: 1,
  originNodeGuid: ""
}'
)"


INBOUND_4="$(
jq -n \
  --arg privateKey "$GRPC_PRIVATE" \
  --arg publicKey "$GRPC_PUBLIC" \
  --arg mldsaSeed "$GRPC_MLDSA_SEED" \
  --arg mldsaVerify "$GRPC_MLDSA_VERIFY" \
'
{
  remark: "Vless-Reality-gRPC",
  enable: true,
  expiryTime: 0,
  total: 0,
  trafficReset: "never",
  listen: "",
  port: 17667,
  protocol: "vless",

  settings: {
    clients: [],
    decryption: "none",
    encryption: "none"
  },

  streamSettings: {

    network: "grpc",

    grpcSettings: {
      serviceName: "",
      authority: "",
      multiMode: false
    },

    security: "reality",

    realitySettings: {

      show: false,
      xver: 0,

      target: "www.k8s.io:443",

      serverNames: [
        "k8s.io",
        "apt.k8s.io",
        "apt.kubernetes.io",
        "blog.k8s.io",
        "blog.kubernetes.io",
        "changelog.k8s.io",
        "changelog.kubernetes.io",
        "ci-test.k8s.io",
        "ci-test.kubernetes.io",
        "code.k8s.io",
        "code.kubernetes.io",
        "conduct.k8s.io",
        "conduct.kubernetes.io",
        "docs.k8s.io",
        "docs.kubernetes.io",
        "examples.k8s.io",
        "examples.kubernetes.io",
        "feature.k8s.io",
        "feature.kubernetes.io",
        "features.k8s.io",
        "features.kubernetes.io",
        "get.k8s.io",
        "get.kubernetes.io",
        "git.k8s.io",
        "git.kubernetes.io",
        "go.k8s.io",
        "go.kubernetes.io",
        "issue.k8s.io",
        "issue.kubernetes.io",
        "issues.k8s.io",
        "issues.kubernetes.io",
        "kep.k8s.io",
        "kep.kubernetes.io",
        "packages.k8s.io",
        "packages.kubernetes.io",
        "pkgs.k8s.io",
        "pkgs.kubernetes.io",
        "pr-test.k8s.io",
        "pr-test.kubernetes.io",
        "pr.k8s.io",
        "pr.kubernetes.io",
        "prs.k8s.io",
        "prs.kubernetes.io",
        "rel.k8s.io",
        "rel.kubernetes.io",
        "releases.k8s.io",
        "releases.kubernetes.io",
        "sbom.k8s.io",
        "sbom.kubernetes.io",
        "sigs.k8s.io",
        "sigs.kubernetes.io",
        "slack.k8s.io",
        "slack.kubernetes.io",
        "submit-queue.k8s.io",
        "submit-queue.kubernetes.io",
        "www.k8s.io",
        "youtube.k8s.io",
        "youtube.kubernetes.io",
        "yt.k8s.io",
        "yt.kubernetes.io",
        "yum.k8s.io",
        "yum.kubernetes.io"
      ],

      privateKey: $privateKey,

      minClientVer: "",
      maxClientVer: "",
      maxTimediff: 0,

      shortIds: [
        "aa5794f3",
        "d56131ba952ffb",
        "a1",
        "4302",
        "6779170a6abf3bd9",
        "6446b6",
        "7caf6afe05",
        "5df0cc840553"
      ],

      mldsa65Seed: $mldsaSeed,

      settings: {
        publicKey: $publicKey,
        fingerprint: "chrome",
        serverName: "",
        spiderX: "/",
        mldsa65Verify: $mldsaVerify
      }
    }
  },

  tag: "in-17667-tcp",

  sniffing: {
    enabled: false
  },

  shareAddrStrategy: "listen",
  shareAddr: "",
  subSortIndex: 1,
  originNodeGuid: ""
}'
)"


# ============================================================
# SAVE GENERATED PAYLOADS
# ============================================================

echo "$INBOUND_1" |
    jq . \
    > "$GENERATED_DIR/01-insecure.json"

echo "$INBOUND_2" |
    jq . \
    > "$GENERATED_DIR/02-reality-row.json"

echo "$INBOUND_3" |
    jq . \
    > "$GENERATED_DIR/03-xhttp.json"

echo "$INBOUND_4" |
    jq . \
    > "$GENERATED_DIR/04-grpc.json"


chmod 600 "$GENERATED_DIR"/*.json


# ============================================================
# CREATE INBOUND
# ============================================================

create_inbound()
{
    local name="$1"
    local payload="$2"

    echo
    echo "Creating:"
    echo "$name"


    local response=""


    response="$(
        api_post \
            "/panel/api/inbounds/add" \
            "$payload"
    )"


    echo "$response" |
        jq . \
        2>/dev/null \
        || echo "$response"


    if ! echo "$response" |
        jq -e '.success == true' \
        >/dev/null 2>&1
    then

        return 1

    fi


    return 0
}


create_inbound \
    "insecure" \
    "$INBOUND_1" \
    || die "Could not create insecure inbound."


create_inbound \
    "Vless-Reality-Row" \
    "$INBOUND_2" \
    || die "Could not create Vless-Reality-Row."


create_inbound \
    "Vless-Xhttp" \
    "$INBOUND_3" \
    || die "Could not create Vless-Xhttp."


create_inbound \
    "Vless-Reality-gRPC" \
    "$INBOUND_4" \
    || die "Could not create Vless-Reality-gRPC."


sleep 3


# ============================================================
# RESOLVE INBOUND IDs
# ============================================================

INBOUND_LIST="$(
    api_get \
        "/panel/api/inbounds/list"
)"


echo "$INBOUND_LIST" |
    jq . \
    > "$RESULT_DIR/inbounds.json"


chmod 600 "$RESULT_DIR/inbounds.json"


get_inbound_id()
{
    local remark="$1"

    echo "$INBOUND_LIST" |
        jq -r \
            --arg remark "$remark" \
            '.obj[]? |
             select(.remark == $remark) |
             .id' |
        head -n1
}


ID_INSECURE="$(get_inbound_id "insecure")"

ID_ROW="$(get_inbound_id "Vless-Reality-Row")"

ID_XHTTP="$(get_inbound_id "Vless-Xhttp")"

ID_GRPC="$(get_inbound_id "Vless-Reality-gRPC")"


for VALUE in \
    "$ID_INSECURE" \
    "$ID_ROW" \
    "$ID_XHTTP" \
    "$ID_GRPC"
do

    if [[ -z "$VALUE" || "$VALUE" == "null" ]]; then

        die "Could not resolve all inbound IDs."

    fi

done


# ============================================================
# 17. CREATE FRIEND
# ============================================================

log "[17/18] Creating Friend client"


CLIENT_PAYLOAD="$(
jq -n \
  --arg email "$CLIENT_EMAIL" \
  --arg uuid "$CLIENT_UUID" \
  --arg subId "$CLIENT_SUB_ID" \
  --arg auth "$CLIENT_AUTH" \
  --arg password "$CLIENT_PASSWORD" \
  --argjson totalGB "$CLIENT_TOTAL_BYTES" \
  --argjson i1 "$ID_INSECURE" \
  --argjson i2 "$ID_ROW" \
  --argjson i3 "$ID_XHTTP" \
  --argjson i4 "$ID_GRPC" \
'
[
  {
    client: {

      email: $email,

      id: $uuid,

      subId: $subId,

      auth: $auth,

      password: $password,

      totalGB: $totalGB,

      expiryTime: 0,

      limitIp: 0,

      limitHwid: 0,

      enable: true,

      reset: 0,

      security: "auto",

      tgId: 0,

      comment: ""
    },

    inboundIds: [
      $i1,
      $i2,
      $i3,
      $i4
    ]
  }
]
'
)"


CLIENT_RESPONSE="$(
    api_post \
        "/panel/api/clients/bulkCreate" \
        "$CLIENT_PAYLOAD"
)"


echo "$CLIENT_RESPONSE" |
    jq . \
    2>/dev/null \
    || echo "$CLIENT_RESPONSE"


if ! echo "$CLIENT_RESPONSE" |
    jq -e '.success == true' \
    >/dev/null 2>&1
then

    die "Friend client creation failed."

fi


# ============================================================
# 18. SUBSCRIPTION
# ============================================================

log "[18/18] Building Friend subscription"


SUB_PORT="$(get_setting "subPort")"

SUB_PATH="$(get_setting "subPath")"

SUB_DOMAIN="$(get_setting "subDomain")"


SUB_PORT="${SUB_PORT:-2096}"


if [[ -z "$SUB_PATH" ]]; then
    SUB_PATH="/sub/"
fi


SUB_PATH="/${SUB_PATH#/}"

SUB_PATH="${SUB_PATH%/}/"


if [[ -n "$SUB_DOMAIN" ]]; then
    SUB_HOST="$SUB_DOMAIN"
else
    SUB_HOST="$PUBLIC_IP"
fi


SUBSCRIPTION_URL="https://${SUB_HOST}:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"


echo
echo "Subscription URL:"
echo
echo "$SUBSCRIPTION_URL"
echo


# ------------------------------------------------------------
# Local subscription test
# ------------------------------------------------------------

LOCAL_SUB_URL="https://127.0.0.1:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"


SUB_HTTP_CODE="$(
    curl \
        -k \
        -sS \
        -o /tmp/friend-subscription.out \
        -w '%{http_code}' \
        --connect-timeout 3 \
        --max-time 10 \
        "$LOCAL_SUB_URL" \
        2>/dev/null \
        || true
)"


if [[ "$SUB_HTTP_CODE" == "200" ]]; then

    SUB_TEST_STATUS="PASS - HTTP 200"

else

    SUB_TEST_STATUS="WARNING - HTTP ${SUB_HTTP_CODE:-NO_RESPONSE}"

fi


# ============================================================
# SAVE CLIENT INFO
# ============================================================

cat > "$RESULT_DIR/client-info.env" <<EOF
CLIENT_EMAIL=${CLIENT_EMAIL}
CLIENT_UUID=${CLIENT_UUID}
CLIENT_SUB_ID=${CLIENT_SUB_ID}
CLIENT_AUTH=${CLIENT_AUTH}
CLIENT_PASSWORD=${CLIENT_PASSWORD}
CLIENT_TOTAL_BYTES=${CLIENT_TOTAL_BYTES}
SUBSCRIPTION_SCHEME=https
SUBSCRIPTION_HOST=${SUB_HOST}
SUBSCRIPTION_PORT=${SUB_PORT}
SUBSCRIPTION_PATH=${SUB_PATH}
SUBSCRIPTION_URL=${SUBSCRIPTION_URL}
EOF


chmod 600 "$RESULT_DIR/client-info.env"

chown root:root "$RESULT_DIR/client-info.env"


# ============================================================
# FINAL VALIDATION
# ============================================================

systemctl restart x-ui


sleep 5


if ! systemctl is-active --quiet x-ui; then

    CONFIG_STATUS="FAILED: final x-ui restart"

    BOOTSTRAP_STATUS="PARTIAL_FAILURE"

    write_panel_info

    exit 1

fi


FINAL_LIST="$(
    api_get \
        "/panel/api/inbounds/list" \
        2>/dev/null \
        || true
)"


EXPECTED_COUNT="$(
    echo "$FINAL_LIST" |
    jq '
      [
        .obj[]? |
        select(
          .remark == "insecure" or
          .remark == "Vless-Reality-Row" or
          .remark == "Vless-Xhttp" or
          .remark == "Vless-Reality-gRPC"
        )
      ] |
      length
    ' \
    2>/dev/null \
    || echo 0
)"


if [[ "$EXPECTED_COUNT" != "4" ]]; then

    CONFIG_STATUS="FAILED: expected 4 inbounds, found ${EXPECTED_COUNT}"

    BOOTSTRAP_STATUS="PARTIAL_FAILURE"

    write_panel_info

    exit 1

fi


BOOTSTRAP_STATUS="COMPLETED"

CONFIG_STATUS="SUCCESS"

SSL_STATUS="SUCCESS"


write_panel_info


# ============================================================
# FINAL OUTPUT
# ============================================================

log "INSTALLATION COMPLETED"


echo "Public IP:"
echo "$PUBLIC_IP"

echo

echo "Panel:"
echo "$PANEL_URL"

echo

echo "Username:"
echo "$XUI_USERNAME"

echo

echo "Password:"
echo "$XUI_PASSWORD"

echo

echo "Subscription:"
echo "$SUBSCRIPTION_URL"

echo

echo "Certificate:"
echo "$CERT_FULLCHAIN"

echo

echo "Configured inbounds:"
echo

echo "10253  VLESS / TCP / none"
echo "443    VLESS / TCP / REALITY"
echo "2052   VLESS / XHTTP / REALITY"
echo "17667  VLESS / gRPC / REALITY"

echo

echo "Panel info:"
echo "/opt/x-ui/panel-info.txt"

echo

echo "Credentials:"
echo "/opt/x-ui/credentials.env"

echo

echo "Client info:"
echo "/opt/x-ui/client-info.env"

echo

echo "Log:"
echo "/var/log/x-ui-bootstrap.log"

echo
echo "============================================================"
echo "DONE"
echo "============================================================"
