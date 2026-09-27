#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# 3x-ui / DigitalOcean Bootstrap
#
# Creates:
#   - 3x-ui panel
#   - VLESS TCP :10253
#   - VLESS REALITY TCP :443
#   - VLESS REALITY XHTTP :2052
#   - VLESS REALITY gRPC :17667
#   - Shared client: Friend
#   - Subscription URL
#
# Outputs:
#   /opt/x-ui/panel-info.txt
#   /opt/x-ui/credentials.env
#   /opt/x-ui/client-info.env
#   /opt/x-ui/inbounds.json
#
# Also displays panel-info.txt + credentials.env on SSH login.
# ============================================================


# ------------------------------------------------------------
# Global variables
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

RESULT_DIR="/opt/x-ui"
LOG_FILE="/var/log/x-ui-bootstrap.log"
OFFICIAL_RESULT="/etc/x-ui/install-result.env"
LOGIN_SCRIPT="/etc/profile.d/x-ui-login-info.sh"

CLIENT_EMAIL="Friend"

CLIENT_UUID="b7720bca-40a3-4c84-aeb0-b02e913e0cdb"
CLIENT_SUB_ID="lott2zqx6wo184ku"
CLIENT_AUTH="50y3dlr61x29hjgz"
CLIENT_PASSWORD="r0fc66v4g127l40t"

CLIENT_TOTAL_GB=1073741824000

mkdir -p "$RESULT_DIR"
chmod 700 "$RESULT_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1


error_handler() {

    EXIT_CODE=$?

    echo
    echo "============================================================"
    echo "BOOTSTRAP FAILED"
    echo "============================================================"
    echo "Exit code : $EXIT_CODE"
    echo "Log       : $LOG_FILE"
    echo "Time      : $(date)"
    echo "============================================================"

    exit "$EXIT_CODE"
}

trap error_handler ERR


echo
echo "============================================================"
echo "3x-ui DigitalOcean Bootstrap"
echo "Started: $(date)"
echo "============================================================"
echo


# ============================================================
# 1. Wait for network
# ============================================================

echo "[1/14] Waiting for network..."

NETWORK_OK=0

for i in $(seq 1 60); do

    if curl -fsS \
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
    echo "ERROR: Internet connection is not available."
    exit 1
fi

echo "Network OK."


# ============================================================
# 2. Install dependencies
# ============================================================

echo
echo "[2/14] Installing dependencies..."

apt-get update -y

apt-get install -y \
    curl \
    jq \
    sqlite3 \
    ca-certificates \
    openssl \
    uuid-runtime


# ============================================================
# 3. Detect public IPv4
# ============================================================

echo
echo "[3/14] Detecting DigitalOcean public IPv4..."

PUBLIC_IP=""

PUBLIC_IP="$(
    curl -fsS \
        --connect-timeout 5 \
        http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address \
        2>/dev/null || true
)"

if [[ -z "$PUBLIC_IP" ]]; then

    PUBLIC_IP="$(
        curl -4 \
            -fsS \
            --connect-timeout 10 \
            https://api.ipify.org \
            2>/dev/null || true
    )"

fi

if [[ -z "$PUBLIC_IP" ]]; then
    echo "ERROR: Could not determine public IPv4."
    exit 1
fi

echo "Public IP: $PUBLIC_IP"


# ============================================================
# 4. Prepare installation
# ============================================================

echo
echo "[4/14] Preparing unattended 3x-ui installation..."

export XUI_NONINTERACTIVE=1

# SQLite is used intentionally.
export XUI_DB_TYPE="sqlite"

# Panel certificate for public IP.
# TCP/80 must be reachable during certificate issuance.
export XUI_SSL_MODE="ip"


# ============================================================
# 5. Install 3x-ui
# ============================================================

echo
echo "[5/14] Installing latest stable 3x-ui..."

bash <(
    curl -fsSL \
        https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
)


# ============================================================
# 6. Verify installation
# ============================================================

echo
echo "[6/14] Verifying x-ui..."

sleep 5

if ! systemctl is-active --quiet x-ui; then

    echo "ERROR: x-ui service is not running."

    systemctl status x-ui \
        --no-pager \
        -l || true

    exit 1
fi

if [[ ! -f "$OFFICIAL_RESULT" ]]; then

    echo "ERROR:"
    echo "$OFFICIAL_RESULT"
    echo "was not created."

    exit 1
fi

echo "x-ui service is running."


# ============================================================
# 7. Load panel credentials
# ============================================================

echo
echo "[7/14] Loading generated panel credentials..."

# shellcheck disable=SC1090
source "$OFFICIAL_RESULT"

install \
    -m 600 \
    -o root \
    -g root \
    "$OFFICIAL_RESULT" \
    "$RESULT_DIR/credentials.env"


PANEL_SCHEME="${XUI_ACCESS_URL%%://*}"

WEB_PATH="${XUI_WEB_BASE_PATH#/}"
WEB_PATH="${WEB_PATH%/}"

if [[ -n "$WEB_PATH" ]]; then
    API_BASE="${PANEL_SCHEME}://127.0.0.1:${XUI_PANEL_PORT}/${WEB_PATH}"
else
    API_BASE="${PANEL_SCHEME}://127.0.0.1:${XUI_PANEL_PORT}"
fi

echo "Panel URL : $XUI_ACCESS_URL"
echo "API URL   : $API_BASE"


# ============================================================
# API helper
# ============================================================

api_get() {

    local URI="$1"

    curl \
        -k \
        -fsS \
        --connect-timeout 10 \
        --max-time 30 \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        "${API_BASE}${URI}"
}


api_post_json() {

    local URI="$1"
    local JSON="$2"

    curl \
        -k \
        -fsS \
        --connect-timeout 10 \
        --max-time 60 \
        -X POST \
        -H "Authorization: Bearer ${XUI_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$JSON" \
        "${API_BASE}${URI}"
}


# ============================================================
# 8. Wait for API
# ============================================================

echo
echo "[8/14] Waiting for 3x-ui API..."

API_READY=0

for i in $(seq 1 60); do

    RESPONSE="$(
        api_get "/panel/api/inbounds/list" \
        2>/dev/null || true
    )"

    if echo "$RESPONSE" |
        jq -e '.success == true' \
        >/dev/null 2>&1
    then

        API_READY=1
        break
    fi

    sleep 2
done

if [[ "$API_READY" -ne 1 ]]; then
    echo "ERROR: 3x-ui API did not become ready."
    exit 1
fi

echo "3x-ui API OK."


# ============================================================
# Delete automatically created conflicting inbounds if any
# ============================================================

echo
echo "Checking configured ports..."

CURRENT_INBOUNDS="$(
    api_get "/panel/api/inbounds/list"
)"

for PORT in 10253 443 2052 17667; do

    CONFLICT_ID="$(
        echo "$CURRENT_INBOUNDS" |
        jq -r \
            --argjson port "$PORT" \
            '.obj[]? |
             select(.port == $port) |
             .id' |
        head -n1
    )"

    if [[ -n "$CONFLICT_ID" && "$CONFLICT_ID" != "null" ]]; then

        echo "Removing existing inbound using port $PORT..."

        curl \
            -k \
            -fsS \
            -X POST \
            -H "Authorization: Bearer ${XUI_API_TOKEN}" \
            "${API_BASE}/panel/api/inbounds/del/${CONFLICT_ID}" \
            >/dev/null
    fi

done


# ============================================================
# 9. Generate fresh Reality keys
# ============================================================

echo
echo "[9/14] Generating Reality cryptographic material..."


generate_reality_material() {

    local PREFIX="$1"

    X25519_RESPONSE="$(
        api_get "/panel/api/server/getNewX25519Cert"
    )"

    PRIVATE_KEY="$(
        echo "$X25519_RESPONSE" |
        jq -r '.obj.privateKey'
    )"

    PUBLIC_KEY="$(
        echo "$X25519_RESPONSE" |
        jq -r '.obj.publicKey'
    )"

    MLDSA_RESPONSE="$(
        api_get "/panel/api/server/getNewmldsa65"
    )"

    MLDSA_SEED="$(
        echo "$MLDSA_RESPONSE" |
        jq -r '.obj.seed'
    )"

    MLDSA_VERIFY="$(
        echo "$MLDSA_RESPONSE" |
        jq -r '.obj.verify'
    )"

    if [[ \
        -z "$PRIVATE_KEY" || \
        "$PRIVATE_KEY" == "null" || \
        -z "$PUBLIC_KEY" || \
        "$PUBLIC_KEY" == "null" \
    ]]; then

        echo "ERROR: Could not generate X25519 keys."
        exit 1
    fi

    printf -v "${PREFIX}_PRIVATE" '%s' "$PRIVATE_KEY"
    printf -v "${PREFIX}_PUBLIC" '%s' "$PUBLIC_KEY"
    printf -v "${PREFIX}_MLDSA_SEED" '%s' "$MLDSA_SEED"
    printf -v "${PREFIX}_MLDSA_VERIFY" '%s' "$MLDSA_VERIFY"
}


generate_reality_material "ROW"
generate_reality_material "XHTTP"
generate_reality_material "GRPC"

echo "Reality keys generated."


# ============================================================
# 10. Create Inbound #1
# VLESS / TCP / no security / 10253
# ============================================================

echo
echo "[10/14] Creating VLESS inbounds..."


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

    sniffing: {
        enabled: false
    }
}'
)"

RESPONSE="$(
    api_post_json \
        "/panel/api/inbounds/add" \
        "$INBOUND_1"
)"

echo "$RESPONSE" | jq .

if ! echo "$RESPONSE" |
    jq -e '.success == true' >/dev/null
then
    echo "ERROR creating insecure inbound."
    exit 1
fi


# ============================================================
# Inbound #2
# VLESS REALITY TCP :443
# ============================================================

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

    sniffing: {
        enabled: false
    }
}'
)"

RESPONSE="$(
    api_post_json \
        "/panel/api/inbounds/add" \
        "$INBOUND_2"
)"

echo "$RESPONSE" | jq .

if ! echo "$RESPONSE" |
    jq -e '.success == true' >/dev/null
then
    echo "ERROR creating Vless-Reality-Row."
    exit 1
fi


# ============================================================
# Inbound #3
# VLESS REALITY XHTTP :2052
# ============================================================

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

    sniffing: {
        enabled: false
    }
}'
)"

RESPONSE="$(
    api_post_json \
        "/panel/api/inbounds/add" \
        "$INBOUND_3"
)"

echo "$RESPONSE" | jq .

if ! echo "$RESPONSE" |
    jq -e '.success == true' >/dev/null
then
    echo "ERROR creating Vless-Xhttp."
    exit 1
fi


# ============================================================
# Inbound #4
# VLESS REALITY gRPC :17667
# ============================================================

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

    sniffing: {
        enabled: false
    }
}'
)"

RESPONSE="$(
    api_post_json \
        "/panel/api/inbounds/add" \
        "$INBOUND_4"
)"

echo "$RESPONSE" | jq .

if ! echo "$RESPONSE" |
    jq -e '.success == true' >/dev/null
then
    echo "ERROR creating Vless-Reality-gRPC."
    exit 1
fi


# ============================================================
# 11. Resolve inbound IDs
# ============================================================

echo
echo "[11/14] Resolving inbound IDs..."

sleep 3

INBOUND_LIST="$(
    api_get "/panel/api/inbounds/list"
)"

echo "$INBOUND_LIST" \
    > "$RESULT_DIR/inbounds.json"

chmod 600 "$RESULT_DIR/inbounds.json"


get_inbound_id() {

    local REMARK="$1"

    echo "$INBOUND_LIST" |
        jq -r \
            --arg remark "$REMARK" \
            '.obj[] |
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
        echo "ERROR: Could not resolve all inbound IDs."
        exit 1
    fi
done


echo "Inbound IDs:"
echo "  insecure            : $ID_INSECURE"
echo "  Vless-Reality-Row   : $ID_ROW"
echo "  Vless-Xhttp         : $ID_XHTTP"
echo "  Vless-Reality-gRPC  : $ID_GRPC"


# ============================================================
# 12. Create shared Friend client
# ============================================================

echo
echo "[12/14] Creating shared Friend client..."


CLIENT_PAYLOAD="$(
jq -n \
    --arg email "$CLIENT_EMAIL" \
    --arg uuid "$CLIENT_UUID" \
    --arg subId "$CLIENT_SUB_ID" \
    --arg auth "$CLIENT_AUTH" \
    --arg password "$CLIENT_PASSWORD" \
    --argjson totalGB "$CLIENT_TOTAL_GB" \
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
    api_post_json \
        "/panel/api/clients/bulkCreate" \
        "$CLIENT_PAYLOAD"
)"

echo "$CLIENT_RESPONSE" | jq .


if ! echo "$CLIENT_RESPONSE" |
    jq -e '.success == true' >/dev/null
then

    echo "ERROR: Friend client creation failed."
    exit 1
fi


# ============================================================
# Verify Friend
# ============================================================

sleep 3

CLIENT_LIST="$(
    api_get "/panel/api/clients/list"
)"

FRIEND_EXISTS="$(
    echo "$CLIENT_LIST" |
    jq -r \
        --arg email "$CLIENT_EMAIL" \
        '[.obj[]? |
          select(.email == $email)] |
         length'
)"

if [[ "$FRIEND_EXISTS" -lt 1 ]]; then

    echo "ERROR: Friend client not found after creation."
    exit 1
fi

echo "Friend client created successfully."


# ============================================================
# 13. Determine subscription URL
# ============================================================

echo
echo "[13/14] Determining Friend subscription URL..."


DB="/etc/x-ui/x-ui.db"


get_setting() {

    local KEY="$1"

    sqlite3 "$DB" \
        "SELECT value FROM settings WHERE key='$KEY' LIMIT 1;" \
        2>/dev/null || true
}


SUB_ENABLE="$(
    get_setting "subEnable"
)"

SUB_PORT="$(
    get_setting "subPort"
)"

SUB_PATH="$(
    get_setting "subPath"
)"

SUB_DOMAIN="$(
    get_setting "subDomain"
)"

SUB_CERT="$(
    get_setting "subCertFile"
)"

SUB_KEY="$(
    get_setting "subKeyFile"
)"


# Defaults if not found
SUB_PORT="${SUB_PORT:-2096}"
SUB_PATH="${SUB_PATH:-/sub/}"


if [[ "$SUB_PATH" != /* ]]; then
    SUB_PATH="/${SUB_PATH}"
fi

if [[ "$SUB_PATH" != */ ]]; then
    SUB_PATH="${SUB_PATH}/"
fi


# Use configured subscription domain when present;
# otherwise use DigitalOcean public IPv4.
if [[ -n "$SUB_DOMAIN" ]]; then
    SUB_HOST="$SUB_DOMAIN"
else
    SUB_HOST="$PUBLIC_IP"
fi


if [[ \
    -n "$SUB_CERT" && \
    -n "$SUB_KEY" && \
    -f "$SUB_CERT" && \
    -f "$SUB_KEY" \
]]; then

    SUB_SCHEME="https"

else

    SUB_SCHEME="http"

fi


if [[ \
    "$SUB_PORT" == "80" && \
    "$SUB_SCHEME" == "http" \
]]; then

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}${SUB_PATH}${CLIENT_SUB_ID}"

elif [[ \
    "$SUB_PORT" == "443" && \
    "$SUB_SCHEME" == "https" \
]]; then

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}${SUB_PATH}${CLIENT_SUB_ID}"

else

    SUBSCRIPTION_URL="${SUB_SCHEME}://${SUB_HOST}:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"

fi


echo "Subscription URL:"
echo "$SUBSCRIPTION_URL"


# ============================================================
# Test subscription locally
# ============================================================

SUB_TEST_CODE="$(
    curl \
        -k \
        -s \
        -o /dev/null \
        -w '%{http_code}' \
        --connect-timeout 5 \
        --max-time 10 \
        "$SUBSCRIPTION_URL" \
        || true
)"

echo "Subscription HTTP status: $SUB_TEST_CODE"


# ============================================================
# Save client information
# ============================================================

cat > "$RESULT_DIR/client-info.env" <<EOF
CLIENT_EMAIL=${CLIENT_EMAIL}
CLIENT_UUID=${CLIENT_UUID}
CLIENT_SUB_ID=${CLIENT_SUB_ID}
CLIENT_AUTH=${CLIENT_AUTH}
CLIENT_PASSWORD=${CLIENT_PASSWORD}
CLIENT_TOTAL_GB=${CLIENT_TOTAL_GB}
SUBSCRIPTION_URL=${SUBSCRIPTION_URL}
EOF

chmod 600 "$RESULT_DIR/client-info.env"
chown root:root "$RESULT_DIR/client-info.env"


# ============================================================
# Build panel-info.txt
# ============================================================

cat > "$RESULT_DIR/panel-info.txt" <<EOF
============================================================
                     3x-ui SERVER
============================================================

Server Public IP:
$PUBLIC_IP


============================================================
                     PANEL ACCESS
============================================================

Panel URL:
${XUI_ACCESS_URL}

Username:
${XUI_USERNAME}

Password:
${XUI_PASSWORD}

Panel Port:
${XUI_PANEL_PORT}

Panel Base Path:
${XUI_WEB_BASE_PATH}


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
1000 GB

Expiry:
Unlimited


============================================================
                     SUBSCRIPTION
============================================================

Subscription URL:

${SUBSCRIPTION_URL}


Subscription Server:

Scheme:
${SUB_SCHEME}

Host:
${SUB_HOST}

Port:
${SUB_PORT}

Path:
${SUB_PATH}


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


Client information:

/opt/x-ui/client-info.env


Inbound snapshot:

/opt/x-ui/inbounds.json


Bootstrap log:

/var/log/x-ui-bootstrap.log


Original installer result:

/etc/x-ui/install-result.env


============================================================
Installed:
$(date)
============================================================
EOF


chmod 600 "$RESULT_DIR/panel-info.txt"
chown root:root "$RESULT_DIR/panel-info.txt"


# ============================================================
# 14. Display automatically on SSH login
# ============================================================

echo
echo "[14/14] Configuring SSH login information..."


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
    echo "#                  3x-ui CREDENTIALS                           #"
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
    echo "  systemctl status x-ui"
    echo "  x-ui"
    echo
    echo "################################################################"
    echo

fi
EOF


chmod 755 "$LOGIN_SCRIPT"
chown root:root "$LOGIN_SCRIPT"


# ============================================================
# Restart and final validation
# ============================================================

echo
echo "Restarting x-ui..."

systemctl restart x-ui

sleep 5


if ! systemctl is-active --quiet x-ui; then

    echo "ERROR: x-ui failed after final restart."

    systemctl status x-ui \
        --no-pager \
        -l || true

    exit 1
fi


# ============================================================
# Verify listening ports
# ============================================================

echo
echo "Listening ports:"
echo

ss -lntp |
    grep -E ':(443|2052|10253|17667|2096)[[:space:]]' \
    || true


# ============================================================
# Final output
# ============================================================

echo
echo
echo "============================================================"
echo "              INSTALLATION COMPLETED"
echo "============================================================"
echo
echo "Server IP:"
echo "$PUBLIC_IP"
echo
echo "Panel:"
echo "$XUI_ACCESS_URL"
echo
echo "Panel Username:"
echo "$XUI_USERNAME"
echo
echo "Panel Password:"
echo "$XUI_PASSWORD"
echo
echo "Friend Subscription:"
echo "$SUBSCRIPTION_URL"
echo
echo "------------------------------------------------------------"
echo
echo "Inbound ports:"
echo
echo "TCP / insecure       : 10253"
echo "TCP / REALITY        : 443"
echo "XHTTP / REALITY      : 2052"
echo "gRPC / REALITY       : 17667"
echo
echo "------------------------------------------------------------"
echo
echo "Information:"
echo "/opt/x-ui/panel-info.txt"
echo
echo "Credentials:"
echo "/opt/x-ui/credentials.env"
echo
echo "Client:"
echo "/opt/x-ui/client-info.env"
echo
echo "Log:"
echo "/var/log/x-ui-bootstrap.log"
echo
echo "============================================================"
echo
