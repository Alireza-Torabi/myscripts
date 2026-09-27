#!/usr/bin/env bash

set -uo pipefail

# ============================================================
# 3x-ui DigitalOcean Bootstrap
#
# Installs 3x-ui and creates:
#
#   1. insecure
#      VLESS / TCP / none
#      Port 10253
#
#   2. Vless-Reality-Row
#      VLESS / TCP / REALITY
#      Port 443
#
#   3. Vless-Xhttp
#      VLESS / XHTTP / REALITY
#      Port 2052
#
#   4. Vless-Reality-gRPC
#      VLESS / gRPC / REALITY
#      Port 17667
#
# Shared client:
#   Friend
#
# Outputs:
#   /opt/x-ui/panel-info.txt
#   /opt/x-ui/credentials.env
#   /opt/x-ui/client-info.env
#   /opt/x-ui/inbounds.json
#   /opt/x-ui/generated-inbounds/
#
# Login banner:
#   /etc/profile.d/x-ui-login-info.sh
#
# Log:
#   /var/log/x-ui-bootstrap.log
# ============================================================


# ============================================================
# CONSTANTS
# ============================================================

export DEBIAN_FRONTEND=noninteractive

RESULT_DIR="/opt/x-ui"
GENERATED_DIR="${RESULT_DIR}/generated-inbounds"

LOG_FILE="/var/log/x-ui-bootstrap.log"

OFFICIAL_RESULT="/etc/x-ui/install-result.env"

LOGIN_SCRIPT="/etc/profile.d/x-ui-login-info.sh"

DB_FILE="/etc/x-ui/x-ui.db"


# ------------------------------------------------------------
# Friend client
# ------------------------------------------------------------

CLIENT_EMAIL="Friend"

CLIENT_UUID="b7720bca-40a3-4c84-aeb0-b02e913e0cdb"

CLIENT_SUB_ID="lott2zqx6wo184ku"

CLIENT_AUTH="50y3dlr61x29hjgz"

CLIENT_PASSWORD="r0fc66v4g127l40t"

CLIENT_TOTAL_BYTES="1073741824000"


# ------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------

BOOTSTRAP_STATUS="STARTING"

CONFIG_STATUS="NOT_STARTED"

SUBSCRIPTION_URL="NOT_AVAILABLE"

SUB_TEST_STATUS="NOT_TESTED"

PUBLIC_IP="UNKNOWN"


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
    echo "FATAL ERROR: $*"
    echo
    echo "See:"
    echo "$LOG_FILE"
    exit 1
}


get_public_ip()
{
    local ip=""

    ip="$(
        curl \
            -fsS \
            --connect-timeout 5 \
            http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address \
            2>/dev/null
    )"

    if [[ -z "$ip" ]]; then

        ip="$(
            curl \
                -4 \
                -fsS \
                --connect-timeout 10 \
                https://api.ipify.org \
                2>/dev/null
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
        2>/dev/null
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


============================================================
                     SERVER
============================================================

Public IP:
${PUBLIC_IP}


============================================================
                     PANEL ACCESS
============================================================

Panel URL:
${XUI_ACCESS_URL:-UNKNOWN}

Username:
${XUI_USERNAME:-UNKNOWN}

Password:
${XUI_PASSWORD:-UNKNOWN}

Panel Port:
${XUI_PANEL_PORT:-UNKNOWN}

Panel Base Path:
${XUI_WEB_BASE_PATH:-UNKNOWN}


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
                     EXPECTED INBOUNDS
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


Client information:

/opt/x-ui/client-info.env


Inbound snapshot:

/opt/x-ui/inbounds.json


Generated inbound JSON files:

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
# START
# ============================================================

log "3x-ui DigitalOcean Bootstrap"

echo "Started:"
date


# ============================================================
# 1. NETWORK
# ============================================================

log "[1/15] Waiting for network"

NETWORK_OK=0

for i in $(seq 1 60); do

    if curl \
        -fsS \
        --connect-timeout 5 \
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

log "[2/15] Installing dependencies"

apt-get update -y || die "apt-get update failed."


apt-get install -y \
    curl \
    jq \
    sqlite3 \
    ca-certificates \
    openssl \
    uuid-runtime \
    iproute2 \
    || die "Dependency installation failed."


# ============================================================
# 3. PUBLIC IP
# ============================================================

log "[3/15] Detecting DigitalOcean public IPv4"

PUBLIC_IP="$(get_public_ip)"


if [[ -z "$PUBLIC_IP" ]]; then
    die "Could not determine public IPv4."
fi


echo "Public IP:"
echo "$PUBLIC_IP"


# ============================================================
# 4. INSTALL 3x-ui
# ============================================================

log "[4/15] Installing 3x-ui"


export XUI_NONINTERACTIVE=1

export XUI_DB_TYPE="sqlite"

# Try IP-based TLS.
# Port 80 must be publicly reachable for ACME issuance.
#
# If certificate issuance fails, current installer continues
# and the bootstrap can still complete.
export XUI_SSL_MODE="ip"


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
# 5. VERIFY BASIC INSTALL
# ============================================================

log "[5/15] Verifying basic installation"


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
# 6. SAVE PANEL CREDENTIALS IMMEDIATELY
# ============================================================

log "[6/15] Saving panel credentials"


# shellcheck disable=SC1090
source "$OFFICIAL_RESULT"


install \
    -m 600 \
    -o root \
    -g root \
    "$OFFICIAL_RESULT" \
    "$RESULT_DIR/credentials.env" \
    || die "Could not save credentials.env."


PANEL_SCHEME="${XUI_ACCESS_URL%%://*}"

WEB_PATH="${XUI_WEB_BASE_PATH#/}"
WEB_PATH="${WEB_PATH%/}"


if [[ -n "$WEB_PATH" ]]; then

    API_BASE="${PANEL_SCHEME}://127.0.0.1:${XUI_PANEL_PORT}/${WEB_PATH}"

else

    API_BASE="${PANEL_SCHEME}://127.0.0.1:${XUI_PANEL_PORT}"

fi


echo "Panel URL:"
echo "$XUI_ACCESS_URL"

echo

echo "Local API base:"
echo "$API_BASE"


# ============================================================
# 7. CREATE PANEL-INFO AND LOGIN BANNER NOW
# ============================================================

log "[7/15] Creating recovery information and SSH login banner"


BOOTSTRAP_STATUS="PANEL_INSTALLED"

CONFIG_STATUS="PENDING"


write_panel_info

create_login_banner


echo "Created:"
echo "$RESULT_DIR/panel-info.txt"

echo

echo "Created:"
echo "$LOGIN_SCRIPT"


# ============================================================
# API HELPERS
# ============================================================

api_get()
{
    local uri="$1"

    curl \
        -k \
        -fsS \
        --connect-timeout 10 \
        --max-time 30 \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        "${API_BASE}${uri}"
}


api_post()
{
    local uri="$1"
    local body="$2"

    curl \
        -k \
        -fsS \
        --connect-timeout 10 \
        --max-time 60 \
        -X POST \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$body" \
        "${API_BASE}${uri}"
}


# ============================================================
# 8. RESTART PANEL
# ============================================================

log "[8/15] Restarting x-ui before API bootstrap"


systemctl restart x-ui


sleep 5


if ! systemctl is-active --quiet x-ui; then

    CONFIG_STATUS="FAILED: x-ui restart"

    write_panel_info

    die "x-ui failed after restart."
fi


# ============================================================
# 9. WAIT FOR TCP PORT
# ============================================================

log "[9/15] Waiting for panel TCP port"


PORT_READY=0


for i in $(seq 1 90); do

    if ss -lnt | grep -q ":${XUI_PANEL_PORT}[[:space:]]"; then

        PORT_READY=1
        break

    fi

    sleep 2

done


if [[ "$PORT_READY" -ne 1 ]]; then

    CONFIG_STATUS="FAILED: panel TCP port not ready"

    write_panel_info

    die "Panel port ${XUI_PANEL_PORT} did not become ready."
fi


echo "Panel TCP port is listening."


# ============================================================
# 10. WAIT FOR AUTHENTICATED API
# ============================================================

log "[10/15] Waiting for authenticated 3x-ui API"


API_READY=0


for i in $(seq 1 90); do

    RESPONSE="$(
        api_get "/panel/api/inbounds/list" \
        2>/dev/null
    )"

    RC=$?


    if [[ "$RC" -eq 0 ]] && \
       echo "$RESPONSE" | jq -e '.success == true' >/dev/null 2>&1
    then

        API_READY=1
        break

    fi


    sleep 2

done


if [[ "$API_READY" -ne 1 ]]; then

    CONFIG_STATUS="FAILED: API did not become ready"

    write_panel_info

    echo
    echo "Panel is installed and usable."
    echo
    echo "Inbound bootstrap was not executed."
    echo
    echo "Check:"
    echo "$LOG_FILE"
    echo

    exit 1
fi


echo "Authenticated API is ready."


# ============================================================
# 11. CLEAN OUR PREVIOUS OBJECTS
# ============================================================

log "[11/15] Preparing managed configuration"


# ------------------------------------------------------------
# Delete Friend if this script was partially run before.
# Ignore failure when Friend does not exist.
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Remove only inbounds owned by THIS bootstrap.
# Do not delete arbitrary port conflicts.
# ------------------------------------------------------------

CURRENT_LIST="$(
    api_get "/panel/api/inbounds/list"
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


        echo "Removing previous managed inbound:"
        echo "${REMARK} / ID ${ID}"


        curl \
            -k \
            -fsS \
            --connect-timeout 10 \
            --max-time 30 \
            -X POST \
            -H "Authorization: Bearer ${XUI_API_TOKEN}" \
            "${API_BASE}/panel/api/inbounds/del/${ID}" \
            >/dev/null \
            || true

    done <<< "$IDS"

done


sleep 3


CURRENT_LIST="$(
    api_get "/panel/api/inbounds/list"
)"


# ------------------------------------------------------------
# Refuse to destroy unrelated configurations.
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

        CONFIG_STATUS="FAILED: Port ${PORT} already used by ${CONFLICT}"

        write_panel_info

        echo
        echo "Port conflict detected:"
        echo "$CONFLICT"
        echo

        exit 1
    fi

done


# ============================================================
# 12. GENERATE REALITY MATERIAL
# ============================================================

log "[12/15] Generating REALITY cryptographic material"


generate_reality_material()
{
    local prefix="$1"

    local x25519
    local mldsa

    local private_key
    local public_key

    local mldsa_seed
    local mldsa_verify


    x25519="$(
        api_get "/panel/api/server/getNewX25519Cert"
    )" || return 1


    if ! echo "$x25519" |
        jq -e '.success == true' >/dev/null
    then
        return 1
    fi


    private_key="$(
        echo "$x25519" |
        jq -r '.obj.privateKey'
    )"


    public_key="$(
        echo "$x25519" |
        jq -r '.obj.publicKey'
    )"


    mldsa="$(
        api_get "/panel/api/server/getNewmldsa65"
    )" || return 1


    if ! echo "$mldsa" |
        jq -e '.success == true' >/dev/null
    then
        return 1
    fi


    mldsa_seed="$(
        echo "$mldsa" |
        jq -r '.obj.seed'
    )"


    mldsa_verify="$(
        echo "$mldsa" |
        jq -r '.obj.verify'
    )"


    if [[ \
        -z "$private_key" || \
        "$private_key" == "null" || \
        -z "$public_key" || \
        "$public_key" == "null" \
    ]]; then
        return 1
    fi


    printf -v "${prefix}_PRIVATE" '%s' "$private_key"

    printf -v "${prefix}_PUBLIC" '%s' "$public_key"

    printf -v "${prefix}_MLDSA_SEED" '%s' "$mldsa_seed"

    printf -v "${prefix}_MLDSA_VERIFY" '%s' "$mldsa_verify"

    return 0
}


if ! generate_reality_material "ROW"; then

    CONFIG_STATUS="FAILED: ROW REALITY key generation"

    write_panel_info

    exit 1
fi


if ! generate_reality_material "XHTTP"; then

    CONFIG_STATUS="FAILED: XHTTP REALITY key generation"

    write_panel_info

    exit 1
fi


if ! generate_reality_material "GRPC"; then

    CONFIG_STATUS="FAILED: gRPC REALITY key generation"

    write_panel_info

    exit 1
fi


echo "REALITY keys generated successfully."


# ============================================================
# 13. BUILD INBOUND JSON
# ============================================================

log "[13/15] Building and creating inbounds"


# ------------------------------------------------------------
# Inbound 1
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Inbound 2 - Samsung REALITY TCP
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Inbound 3 - Docker REALITY XHTTP
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Inbound 4 - Kubernetes REALITY gRPC
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Save generated payloads
# ------------------------------------------------------------

echo "$INBOUND_1" |
    jq . > "$GENERATED_DIR/01-insecure.json"

echo "$INBOUND_2" |
    jq . > "$GENERATED_DIR/02-reality-row.json"

echo "$INBOUND_3" |
    jq . > "$GENERATED_DIR/03-xhttp.json"

echo "$INBOUND_4" |
    jq . > "$GENERATED_DIR/04-grpc.json"


chmod 600 "$GENERATED_DIR"/*.json


# ============================================================
# CREATE INBOUND HELPER
# ============================================================

create_inbound()
{
    local name="$1"
    local payload="$2"

    echo
    echo "Creating inbound:"
    echo "$name"


    local response


    response="$(
        api_post \
            "/panel/api/inbounds/add" \
            "$payload"
    )"

    local rc=$?


    if [[ "$rc" -ne 0 ]]; then

        echo "HTTP/API call failed:"
        echo "$name"

        return 1
    fi


    echo "$response" |
        jq . \
        || echo "$response"


    if ! echo "$response" |
        jq -e '.success == true' >/dev/null 2>&1
    then

        echo "3x-ui rejected inbound:"
        echo "$name"

        return 1
    fi


    return 0
}


if ! create_inbound \
    "insecure" \
    "$INBOUND_1"
then

    CONFIG_STATUS="FAILED: insecure inbound"

    write_panel_info

    exit 1
fi


if ! create_inbound \
    "Vless-Reality-Row" \
    "$INBOUND_2"
then

    CONFIG_STATUS="FAILED: Vless-Reality-Row inbound"

    write_panel_info

    exit 1
fi


if ! create_inbound \
    "Vless-Xhttp" \
    "$INBOUND_3"
then

    CONFIG_STATUS="FAILED: Vless-Xhttp inbound"

    write_panel_info

    exit 1
fi


if ! create_inbound \
    "Vless-Reality-gRPC" \
    "$INBOUND_4"
then

    CONFIG_STATUS="FAILED: Vless-Reality-gRPC inbound"

    write_panel_info

    exit 1
fi


# ============================================================
# GET NEW INBOUND IDS
# ============================================================

sleep 3


INBOUND_LIST="$(
    api_get "/panel/api/inbounds/list"
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


ID_INSECURE="$(
    get_inbound_id "insecure"
)"


ID_ROW="$(
    get_inbound_id "Vless-Reality-Row"
)"


ID_XHTTP="$(
    get_inbound_id "Vless-Xhttp"
)"


ID_GRPC="$(
    get_inbound_id "Vless-Reality-gRPC"
)"


for VALUE in \
    "$ID_INSECURE" \
    "$ID_ROW" \
    "$ID_XHTTP" \
    "$ID_GRPC"
do

    if [[ -z "$VALUE" || "$VALUE" == "null" ]]; then

        CONFIG_STATUS="FAILED: Could not resolve inbound IDs"

        write_panel_info

        exit 1
    fi

done


echo
echo "Inbound IDs:"
echo
echo "insecure            : $ID_INSECURE"
echo "Vless-Reality-Row   : $ID_ROW"
echo "Vless-Xhttp         : $ID_XHTTP"
echo "Vless-Reality-gRPC  : $ID_GRPC"


# ============================================================
# 14. CREATE FRIEND
# ============================================================

log "[14/15] Creating Friend client"


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


echo "$CLIENT_PAYLOAD" \
    > "$RESULT_DIR/friend-client-payload.json"


chmod 600 "$RESULT_DIR/friend-client-payload.json"


CLIENT_RESPONSE="$(
    api_post \
        "/panel/api/clients/bulkCreate" \
        "$CLIENT_PAYLOAD"
)"


CLIENT_RC=$?


if [[ "$CLIENT_RC" -ne 0 ]]; then

    CONFIG_STATUS="FAILED: Friend API request"

    write_panel_info

    exit 1
fi


echo "$CLIENT_RESPONSE" |
    jq . \
    || echo "$CLIENT_RESPONSE"


if ! echo "$CLIENT_RESPONSE" |
    jq -e '.success == true' >/dev/null 2>&1
then

    CONFIG_STATUS="FAILED: Friend creation"

    write_panel_info

    exit 1
fi


# ------------------------------------------------------------
# Verify Friend through export API
# ------------------------------------------------------------

sleep 3


CLIENT_EXPORT="$(
    api_get "/panel/api/clients/export"
)"


if ! echo "$CLIENT_EXPORT" |
    jq -e \
        --arg email "$CLIENT_EMAIL" \
        '.obj[]? |
         select(.client.email == $email)' \
        >/dev/null
then

    CONFIG_STATUS="FAILED: Friend verification"

    write_panel_info

    exit 1
fi


echo "Friend verified."


# ============================================================
# 15. SUBSCRIPTION
# ============================================================

log "[15/15] Building Friend subscription URL"


SUB_ENABLE="$(get_setting "subEnable")"

SUB_PORT="$(get_setting "subPort")"

SUB_PATH="$(get_setting "subPath")"

SUB_DOMAIN="$(get_setting "subDomain")"

SUB_CERT="$(get_setting "subCertFile")"

SUB_KEY="$(get_setting "subKeyFile")"


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


# ------------------------------------------------------------
# Detect subscription scheme
# ------------------------------------------------------------

if [[ \
    -n "$SUB_CERT" && \
    -n "$SUB_KEY" && \
    -f "$SUB_CERT" && \
    -f "$SUB_KEY" \
]]
then

    SUB_SCHEME="https"

else

    # Modern 3x-ui can still report HTTPS with internally
    # managed certificate paths. Probe the local server.

    HTTPS_TEST="$(
        curl \
            -k \
            -sS \
            -o /dev/null \
            -w '%{http_code}' \
            --connect-timeout 5 \
            "https://127.0.0.1:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}" \
            2>/dev/null
    )"


    if [[ "$HTTPS_TEST" =~ ^[0-9]{3}$ ]] && \
       [[ "$HTTPS_TEST" != "000" ]]
    then

        SUB_SCHEME="https"

    else

        SUB_SCHEME="http"

    fi

fi


if [[ \
    "$SUB_SCHEME" == "https" && \
    "$SUB_PORT" == "443" \
]]
then

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}${SUB_PATH}${CLIENT_SUB_ID}"

elif [[ \
    "$SUB_SCHEME" == "http" && \
    "$SUB_PORT" == "80" \
]]
then

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}${SUB_PATH}${CLIENT_SUB_ID}"

else

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"

fi


echo
echo "Subscription URL:"
echo
echo "$SUBSCRIPTION_URL"
echo


# ------------------------------------------------------------
# Test subscription URL locally
# ------------------------------------------------------------

SUB_HTTP_CODE="$(
    curl \
        -k \
        -sS \
        -o /tmp/friend-subscription.out \
        -w '%{http_code}' \
        --connect-timeout 10 \
        --max-time 20 \
        "$SUBSCRIPTION_URL" \
        2>/dev/null
)"


if [[ "$SUB_HTTP_CODE" == "200" ]]; then

    SUB_TEST_STATUS="PASS - HTTP 200"

else

    SUB_TEST_STATUS="WARNING - HTTP ${SUB_HTTP_CODE:-NO_RESPONSE}"

fi


# ------------------------------------------------------------
# Save Friend information
# ------------------------------------------------------------

cat > "$RESULT_DIR/client-info.env" <<EOF
CLIENT_EMAIL=${CLIENT_EMAIL}
CLIENT_UUID=${CLIENT_UUID}
CLIENT_SUB_ID=${CLIENT_SUB_ID}
CLIENT_AUTH=${CLIENT_AUTH}
CLIENT_PASSWORD=${CLIENT_PASSWORD}
CLIENT_TOTAL_BYTES=${CLIENT_TOTAL_BYTES}
SUBSCRIPTION_SCHEME=${SUB_SCHEME}
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

log "Final validation"


systemctl restart x-ui


sleep 5


if ! systemctl is-active --quiet x-ui; then

    CONFIG_STATUS="FAILED: x-ui stopped after final configuration"

    BOOTSTRAP_STATUS="PARTIAL_FAILURE"

    write_panel_info

    systemctl status x-ui \
        --no-pager \
        -l \
        || true

    exit 1
fi


# ------------------------------------------------------------
# Refresh snapshot
# ------------------------------------------------------------

FINAL_LIST="$(
    api_get "/panel/api/inbounds/list" \
    2>/dev/null
)"


if [[ -n "$FINAL_LIST" ]]; then

    echo "$FINAL_LIST" |
        jq . \
        > "$RESULT_DIR/inbounds.json" \
        2>/dev/null \
        || true

fi


chmod 600 "$RESULT_DIR/inbounds.json" \
    2>/dev/null \
    || true


# ------------------------------------------------------------
# Check expected ports
# ------------------------------------------------------------

echo
echo "Listening ports:"
echo


ss -lntp |
    grep -E \
        ':(443|2052|10253|17667|2096)[[:space:]]' \
    || true


# ------------------------------------------------------------
# Mark completed
# ------------------------------------------------------------

BOOTSTRAP_STATUS="COMPLETED"

CONFIG_STATUS="SUCCESS"


write_panel_info


# ============================================================
# FINAL OUTPUT
# ============================================================

log "INSTALLATION COMPLETED"


echo "Server IP:"
echo "$PUBLIC_IP"

echo

echo "Panel:"
echo "$XUI_ACCESS_URL"

echo

echo "Username:"
echo "$XUI_USERNAME"

echo

echo "Password:"
echo "$XUI_PASSWORD"

echo

echo "Friend Subscription:"
echo "$SUBSCRIPTION_URL"

echo

echo "------------------------------------------------------------"

echo

echo "Configured inbounds:"

echo

echo "10253  VLESS / TCP / none"

echo "443    VLESS / TCP / REALITY"

echo "2052   VLESS / XHTTP / REALITY"

echo "17667  VLESS / gRPC / REALITY"

echo

echo "------------------------------------------------------------"

echo

echo "Panel information:"
echo "/opt/x-ui/panel-info.txt"

echo

echo "Credentials:"
echo "/opt/x-ui/credentials.env"

echo

echo "Friend client:"
echo "/opt/x-ui/client-info.env"

echo

echo "Inbound snapshot:"
echo "/opt/x-ui/inbounds.json"

echo

echo "Bootstrap log:"
echo "/var/log/x-ui-bootstrap.log"

echo

echo "============================================================"
echo "DONE"
echo "============================================================"
