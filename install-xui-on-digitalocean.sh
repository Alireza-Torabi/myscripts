#!/usr/bin/env bash
set -uo pipefail

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

RESULT_DIR="/opt/x-ui"
GENERATED_DIR="${RESULT_DIR}/generated-inbounds"
LOG_FILE="/var/log/x-ui-bootstrap.log"
OFFICIAL_RESULT="/etc/x-ui/install-result.env"
LOGIN_SCRIPT="/etc/profile.d/x-ui-login-info.sh"
DB_FILE="/etc/x-ui/x-ui.db"
CERT_DIR="/root/cert/ip"
CERT_FULLCHAIN="${CERT_DIR}/fullchain.pem"
CERT_PRIVATE="${CERT_DIR}/privkey.pem"
ACME="/root/.acme.sh/acme.sh"

CLIENT_EMAIL="Friend"
CLIENT_UUID="b7720bca-40a3-4c84-aeb0-b02e913e0cdb"
CLIENT_SUB_ID="lott2zqx6wo184ku"
CLIENT_AUTH="50y3dlr61x29hjgz"
CLIENT_PASSWORD="r0fc66v4g127l40t"
CLIENT_TOTAL_BYTES="1073741824000"

BOOTSTRAP_STATUS="STARTING"
CONFIG_STATUS="NOT_STARTED"
SSL_STATUS="NOT_STARTED"
SUBSCRIPTION_URL="NOT_AVAILABLE"
SUB_TEST_STATUS="NOT_TESTED"
PUBLIC_IP="UNKNOWN"
PANEL_URL="UNKNOWN"
API_BASE=""

mkdir -p "$RESULT_DIR" "$GENERATED_DIR"
chmod 700 "$RESULT_DIR" "$GENERATED_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
  echo
}

die() {
  local msg="$1"
  CONFIG_STATUS="FAILED: ${msg}"
  BOOTSTRAP_STATUS="PARTIAL_FAILURE"
  write_panel_info 2>/dev/null || true
  echo
  echo "FATAL ERROR: ${msg}"
  echo "Log: ${LOG_FILE}"
  exit 1
}

get_public_ip() {
  local ip=""
  ip="$(curl -fsS --connect-timeout 3 --max-time 5 \
    http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s' "$ip"
}

get_setting() {
  local key="$1"
  [[ -f "$DB_FILE" ]] || return 0
  sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='${key}' LIMIT 1;" 2>/dev/null || true
}

set_setting() {
  local key="$1"
  local value="$2"
  [[ -f "$DB_FILE" ]] || return 1
  sqlite3 "$DB_FILE" "
    UPDATE settings SET value='${value}' WHERE key='${key}';
    INSERT INTO settings(key,value)
    SELECT '${key}','${value}'
    WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='${key}');
  "
}

write_panel_info() {
  cat > "$RESULT_DIR/panel-info.txt" <<INFOEOF
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

[1] insecure
Protocol: VLESS
Transport: TCP
Security: none
Port: 10253

[2] Vless-Reality-Row
Protocol: VLESS
Transport: TCP
Security: REALITY
Port: 443
Target: www.samsung.com:443

[3] Vless-Xhttp
Protocol: VLESS
Transport: XHTTP
Security: REALITY
Port: 2052
Path: /xhttp
Target: www.docker.io:443

[4] Vless-Reality-gRPC
Protocol: VLESS
Transport: gRPC
Security: REALITY
Port: 17667
Target: www.k8s.io:443

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

============================================================
Last Updated:
$(date)
============================================================
INFOEOF
  chmod 600 "$RESULT_DIR/panel-info.txt"
  chown root:root "$RESULT_DIR/panel-info.txt"
}

create_login_banner() {
  cat > "$LOGIN_SCRIPT" <<'BANNEREOF'
#!/usr/bin/env bash
if [[ -n "${SSH_CONNECTION:-}" && $- == *i* ]]; then
  echo
  echo "################################################################"
  echo "#                    3x-ui SERVER INFO                         #"
  echo "################################################################"
  echo
  [[ -r /opt/x-ui/panel-info.txt ]] && cat /opt/x-ui/panel-info.txt || echo "/opt/x-ui/panel-info.txt not found."
  echo
  echo "################################################################"
  echo "#                    3x-ui CREDENTIALS                         #"
  echo "################################################################"
  echo
  [[ -r /opt/x-ui/credentials.env ]] && cat /opt/x-ui/credentials.env || echo "/opt/x-ui/credentials.env not found."
  echo
  echo "Useful commands:"
  echo "  cat /opt/x-ui/panel-info.txt"
  echo "  cat /opt/x-ui/credentials.env"
  echo "  cat /opt/x-ui/client-info.env"
  echo "  cat /opt/x-ui/inbounds.json"
  echo "  tail -n 200 /var/log/x-ui-bootstrap.log"
  echo "  systemctl status x-ui"
  echo "  x-ui"
  echo
fi
BANNEREOF
  chmod 755 "$LOGIN_SCRIPT"
  chown root:root "$LOGIN_SCRIPT"
}

api_get() {
  local uri="$1"
  curl -k -sS --connect-timeout 3 --max-time 12 \
    -H "Authorization: Bearer ${XUI_API_TOKEN}" \
    "${API_BASE}${uri}"
}

api_post() {
  local uri="$1"
  local body="$2"
  curl -k -sS --connect-timeout 3 --max-time 30 \
    -X POST \
    -H "Authorization: Bearer ${XUI_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$body" \
    "${API_BASE}${uri}"
}

wait_for_api() {
  local response=""
  for i in $(seq 1 40); do
    response="$(api_get "/panel/api/inbounds/list" 2>/dev/null || true)"
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

generate_reality_material() {
  local prefix="$1"
  local x25519 mldsa private_key public_key mldsa_seed mldsa_verify

  x25519="$(api_get "/panel/api/server/getNewX25519Cert")" || return 1
  echo "$x25519" | jq -e '.success == true' >/dev/null || return 1
  private_key="$(echo "$x25519" | jq -r '.obj.privateKey // empty')"
  public_key="$(echo "$x25519" | jq -r '.obj.publicKey // empty')"

  mldsa="$(api_get "/panel/api/server/getNewmldsa65")" || return 1
  echo "$mldsa" | jq -e '.success == true' >/dev/null || return 1
  mldsa_seed="$(echo "$mldsa" | jq -r '.obj.seed // empty')"
  mldsa_verify="$(echo "$mldsa" | jq -r '.obj.verify // empty')"

  [[ -n "$private_key" && -n "$public_key" && -n "$mldsa_seed" && -n "$mldsa_verify" ]] || return 1

  printf -v "${prefix}_PRIVATE" '%s' "$private_key"
  printf -v "${prefix}_PUBLIC" '%s' "$public_key"
  printf -v "${prefix}_MLDSA_SEED" '%s' "$mldsa_seed"
  printf -v "${prefix}_MLDSA_VERIFY" '%s' "$mldsa_verify"
}

create_inbound() {
  local name="$1"
  local payload="$2"
  local response
  echo "Creating inbound: ${name}"
  response="$(api_post "/panel/api/inbounds/add" "$payload")" || return 1
  echo "$response" | jq . 2>/dev/null || echo "$response"
  echo "$response" | jq -e '.success == true' >/dev/null 2>&1
}

log "3x-ui DigitalOcean Bootstrap"
echo "Started: $(date)"

log "[1/18] Waiting for network"
NETWORK_OK=0
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 3 --max-time 5 https://github.com >/dev/null 2>&1; then
    NETWORK_OK=1
    break
  fi
  sleep 2
done
[[ "$NETWORK_OK" -eq 1 ]] || die "Internet connection is not available"

log "[2/18] Installing dependencies"
apt-get update -y || die "apt-get update failed"
apt-get install -y curl jq sqlite3 ca-certificates openssl uuid-runtime iproute2 socat cron \
  || die "Dependency installation failed"

log "[3/18] Detecting public IPv4"
PUBLIC_IP="$(get_public_ip)"
[[ -n "$PUBLIC_IP" ]] || die "Could not determine public IPv4"
echo "Public IP: $PUBLIC_IP"

log "[4/18] Installing 3x-ui without installer-managed SSL"
export XUI_NONINTERACTIVE=1
export XUI_DB_TYPE="sqlite"
export XUI_SSL_MODE="none"

curl -fsSL https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o /tmp/install-x-ui.sh \
  || die "Could not download 3x-ui installer"
chmod 700 /tmp/install-x-ui.sh
bash /tmp/install-x-ui.sh || die "3x-ui installer failed"

log "[5/18] Verifying x-ui installation"
[[ -f "$OFFICIAL_RESULT" ]] || die "$OFFICIAL_RESULT was not created"
systemctl is-active --quiet x-ui || die "x-ui service is not running"

log "[6/18] Saving panel credentials"
# shellcheck disable=SC1090
source "$OFFICIAL_RESULT"
install -m 600 -o root -g root "$OFFICIAL_RESULT" "$RESULT_DIR/credentials.env" \
  || die "Could not save credentials.env"

WEB_PATH="${XUI_WEB_BASE_PATH#/}"
WEB_PATH="${WEB_PATH%/}"
PANEL_URL="http://${PUBLIC_IP}:${XUI_PANEL_PORT}/${WEB_PATH}"
BOOTSTRAP_STATUS="PANEL_INSTALLED"
CONFIG_STATUS="WAITING_FOR_SSL"
SSL_STATUS="PENDING"
write_panel_info
create_login_banner

log "[7/18] Installing and verifying acme.sh"
if [[ ! -x "$ACME" ]]; then
  curl -fsSL https://get.acme.sh -o /tmp/install-acme.sh || die "Could not download acme.sh installer"
  chmod 700 /tmp/install-acme.sh
  bash /tmp/install-acme.sh || die "acme.sh installer failed"
fi

ACME_READY=0
for i in $(seq 1 30); do
  if [[ -x "$ACME" ]]; then
    ACME_READY=1
    break
  fi
  sleep 1
done
[[ "$ACME_READY" -eq 1 ]] || die "acme.sh executable missing after installation"
"$ACME" --version || die "acme.sh cannot execute"

log "[8/18] Preparing IP certificate"
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"
if ss -lnt | grep -q ':80[[:space:]]'; then
  ss -lntp | grep ':80[[:space:]]' || true
  die "Local TCP/80 is already occupied"
fi
"$ACME" --set-default-ca --server letsencrypt --force >/dev/null 2>&1 || true

log "[9/18] Issuing Let's Encrypt short-lived IP certificate"
rm -rf "/root/.acme.sh/${PUBLIC_IP}" "/root/.acme.sh/${PUBLIC_IP}_ecc" 2>/dev/null || true
"$ACME" --issue \
  -d "$PUBLIC_IP" \
  --standalone \
  --server letsencrypt \
  --certificate-profile shortlived \
  --days 6 \
  --httpport 80 \
  --force \
  || die "IP certificate issuance failed"

log "[10/18] Installing certificate files"
"$ACME" --installcert --force -d "$PUBLIC_IP" \
  --key-file "$CERT_PRIVATE" \
  --fullchain-file "$CERT_FULLCHAIN" \
  --reloadcmd "systemctl restart x-ui 2>/dev/null || true" \
  >/dev/null 2>&1 || true

[[ -s "$CERT_FULLCHAIN" ]] || die "Certificate fullchain file missing"
[[ -s "$CERT_PRIVATE" ]] || die "Certificate private key missing"
chmod 644 "$CERT_FULLCHAIN"
chmod 600 "$CERT_PRIVATE"
"$ACME" --upgrade --auto-upgrade >/dev/null 2>&1 || true

log "[11/18] Configuring panel and subscription TLS"
/usr/local/x-ui/x-ui cert -webCert "$CERT_FULLCHAIN" -webCertKey "$CERT_PRIVATE" \
  || die "Could not configure panel certificate"
set_setting "subCertFile" "$CERT_FULLCHAIN" || die "Could not configure subCertFile"
set_setting "subKeyFile" "$CERT_PRIVATE" || die "Could not configure subKeyFile"
set_setting "subEnable" "true" || die "Could not enable subscription server"

SSL_STATUS="SUCCESS"
PANEL_URL="https://${PUBLIC_IP}:${XUI_PANEL_PORT}/${WEB_PATH}"
cat > "$RESULT_DIR/credentials.env" <<CREDEOF
XUI_USERNAME=${XUI_USERNAME}
XUI_PASSWORD=${XUI_PASSWORD}
XUI_PANEL_PORT=${XUI_PANEL_PORT}
XUI_WEB_BASE_PATH=${XUI_WEB_BASE_PATH}
XUI_ACCESS_URL=${PANEL_URL}
XUI_API_TOKEN=${XUI_API_TOKEN}
XUI_DB_TYPE=${XUI_DB_TYPE}
XUI_CERT_FILE=${CERT_FULLCHAIN}
XUI_CERT_KEY=${CERT_PRIVATE}
CREDEOF
chmod 600 "$RESULT_DIR/credentials.env"

log "[12/18] Restarting x-ui and waiting for API"
systemctl restart x-ui
sleep 5
systemctl is-active --quiet x-ui || die "x-ui failed after SSL restart"
API_BASE="https://127.0.0.1:${XUI_PANEL_PORT}/${WEB_PATH}"
wait_for_api || die "Authenticated API did not become ready"
CONFIG_STATUS="API_READY"
write_panel_info

log "[13/18] Removing previous managed objects"
# Remove Friend first if a previous run partially created it.
DELETE_FRIEND_PAYLOAD="$(jq -n --arg email "$CLIENT_EMAIL" '{emails:[$email],keepTraffic:false}')"
api_post "/panel/api/clients/bulkDel" "$DELETE_FRIEND_PAYLOAD" >/dev/null 2>&1 || true

CURRENT_LIST="$(api_get "/panel/api/inbounds/list")" || die "Could not list existing inbounds"
for REMARK in "insecure" "Vless-Reality-Row" "Vless-Xhttp" "Vless-Reality-gRPC"; do
  IDS="$(echo "$CURRENT_LIST" | jq -r --arg remark "$REMARK" '.obj[]? | select(.remark == $remark) | .id')"
  while read -r ID; do
    [[ -z "$ID" ]] && continue
    curl -k -sS --connect-timeout 3 --max-time 20 -X POST \
      -H "Authorization: Bearer ${XUI_API_TOKEN}" \
      "${API_BASE}/panel/api/inbounds/del/${ID}" >/dev/null || true
  done <<< "$IDS"
done
sleep 2

CURRENT_LIST="$(api_get "/panel/api/inbounds/list")" || die "Could not refresh inbound list"
for PORT in 10253 443 2052 17667; do
  CONFLICT="$(echo "$CURRENT_LIST" | jq -r --argjson port "$PORT" '.obj[]? | select(.port == $port) | "\(.id)|\(.remark)"' | head -n1)"
  [[ -z "$CONFLICT" ]] || die "Port ${PORT} already used by ${CONFLICT}"
done

log "[14/18] Generating REALITY material"
generate_reality_material "ROW" || die "ROW REALITY key generation failed"
generate_reality_material "XHTTP" || die "XHTTP REALITY key generation failed"
generate_reality_material "GRPC" || die "gRPC REALITY key generation failed"

log "[15/18] Creating four inbounds"
INBOUND_1="$(jq -n '
{
  remark:"insecure", enable:true, expiryTime:0, total:0, trafficReset:"never",
  listen:"", port:10253, protocol:"vless",
  settings:{clients:[],decryption:"none",encryption:"none"},
  streamSettings:{network:"tcp",tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}},security:"none"},
  tag:"in-10253-tcp", sniffing:{enabled:false},
  shareAddrStrategy:"listen",shareAddr:"",subSortIndex:1,originNodeGuid:""
}')"

INBOUND_2="$(jq -n \
  --arg privateKey "$ROW_PRIVATE" \
  --arg publicKey "$ROW_PUBLIC" \
  --arg mldsaSeed "$ROW_MLDSA_SEED" \
  --arg mldsaVerify "$ROW_MLDSA_VERIFY" '
{
  remark:"Vless-Reality-Row", enable:true, expiryTime:0, total:0, trafficReset:"never",
  listen:"", port:443, protocol:"vless",
  settings:{clients:[],decryption:"none",encryption:"none",testseed:[900,500,900,256]},
  streamSettings:{
    network:"tcp",
    tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}},
    security:"reality",
    realitySettings:{
      show:false,xver:0,target:"www.samsung.com:443",
      serverNames:[
        "www.samsung.com","adn-stg.yourservice.samsung.com","am-images.shop.samsung.com",
        "ap-author.led.samsung.com","ap-author.semiconductor.samsung.com",
        "api-stg.semiconductor.samsung.cn","api.led.samsung.com",
        "api.semiconductor.samsung.cn","api.semiconductor.samsung.com",
        "au-images.shop.samsung.com","au2-images.shop.samsung.com","b2bshop.samsung.com",
        "cdn.samsung.com","cstudio.semiconductor.samsung.com","download.led.samsung.com",
        "download.semiconductor.samsung.com","eu-images.shop.samsung.com",
        "eventadm.semiconductor.samsung.com","eventapi.semiconductor.samsung.com",
        "image.led.samsung.com","image.samsung.com","image.semiconductor.samsung.com",
        "images.samsung.com","led.samsung.com","legal.samsungdm.com",
        "mena-images.shop.samsung.com","org.semiconductor.samsung.com",
        "perf-prod.samsung.com","pre-prod.samsung.com","qa.semiconductor.samsung.com",
        "qapartners.sec.samsung.com","ru-images.shop.samsung.com","samsung.com",
        "search.led.samsung.com","search.semiconductor.samsung.com","semiconductor.samsung.com",
        "sribsrch.ecom-qa.samsung.com","sribsrch.ecom.samsung.com",
        "stg-am-images.shop.samsung.com","stg-au-images.shop.samsung.com",
        "stg-au2-images.shop.samsung.com","stg-eu-images.shop.samsung.com",
        "stg-mena-images.shop.samsung.com","stg-ru-images.shop.samsung.com",
        "streaming.samsung.com","ue-author.semiconductor.samsung.com",
        "vdapi.samsung.com","www-ams.samsung.com","www.samsungebiz.com",
        "www.semiconductor.samsung.com"
      ],
      privateKey:$privateKey,minClientVer:"",maxClientVer:"",maxTimediff:0,
      shortIds:["7b","d19a","1059780f1c199b","2da42c","b2102f7fdf","8e3deee4","50922e6cff342142","a96bb07558a5"],
      mldsa65Seed:$mldsaSeed,
      settings:{publicKey:$publicKey,fingerprint:"chrome",serverName:"",spiderX:"/",mldsa65Verify:$mldsaVerify}
    }
  },
  tag:"in-443-tcp", sniffing:{enabled:false},
  shareAddrStrategy:"listen",shareAddr:"",subSortIndex:2,originNodeGuid:""
}')"

INBOUND_3="$(jq -n \
  --arg privateKey "$XHTTP_PRIVATE" \
  --arg publicKey "$XHTTP_PUBLIC" \
  --arg mldsaSeed "$XHTTP_MLDSA_SEED" \
  --arg mldsaVerify "$XHTTP_MLDSA_VERIFY" '
{
  remark:"Vless-Xhttp", enable:true, expiryTime:0, total:0, trafficReset:"never",
  listen:"", port:2052, protocol:"vless",
  settings:{clients:[],decryption:"none",encryption:"none"},
  streamSettings:{
    network:"xhttp",
    xhttpSettings:{path:"/xhttp",host:"",mode:"auto",xPaddingBytes:"100-1000",scMaxBufferedPosts:30,scStreamUpServerSecs:"20-80"},
    security:"reality",
    realitySettings:{
      show:false,xver:0,target:"www.docker.io:443",
      serverNames:["dockercon.com","docker.com","docs.docker.com","docker.io"],
      privateKey:$privateKey,minClientVer:"",maxClientVer:"",maxTimediff:0,
      shortIds:["7d","d556a878e8be","0c8e04","17d23956a0","201979bdc76856","c521","2f7acf5f","aa6f98d388cdef4e"],
      mldsa65Seed:$mldsaSeed,
      settings:{publicKey:$publicKey,fingerprint:"chrome",serverName:"",spiderX:"/",mldsa65Verify:$mldsaVerify}
    }
  },
  tag:"in-2052-tcp", sniffing:{enabled:false},
  shareAddrStrategy:"listen",shareAddr:"",subSortIndex:3,originNodeGuid:""
}')"

INBOUND_4="$(jq -n \
  --arg privateKey "$GRPC_PRIVATE" \
  --arg publicKey "$GRPC_PUBLIC" \
  --arg mldsaSeed "$GRPC_MLDSA_SEED" \
  --arg mldsaVerify "$GRPC_MLDSA_VERIFY" '
{
  remark:"Vless-Reality-gRPC", enable:true, expiryTime:0, total:0, trafficReset:"never",
  listen:"", port:17667, protocol:"vless",
  settings:{clients:[],decryption:"none",encryption:"none"},
  streamSettings:{
    network:"grpc",
    grpcSettings:{serviceName:"",authority:"",multiMode:false},
    security:"reality",
    realitySettings:{
      show:false,xver:0,target:"www.k8s.io:443",
      serverNames:[
        "k8s.io","apt.k8s.io","apt.kubernetes.io","blog.k8s.io","blog.kubernetes.io",
        "changelog.k8s.io","changelog.kubernetes.io","ci-test.k8s.io","ci-test.kubernetes.io",
        "code.k8s.io","code.kubernetes.io","conduct.k8s.io","conduct.kubernetes.io",
        "docs.k8s.io","docs.kubernetes.io","examples.k8s.io","examples.kubernetes.io",
        "feature.k8s.io","feature.kubernetes.io","features.k8s.io","features.kubernetes.io",
        "get.k8s.io","get.kubernetes.io","git.k8s.io","git.kubernetes.io",
        "go.k8s.io","go.kubernetes.io","issue.k8s.io","issue.kubernetes.io",
        "issues.k8s.io","issues.kubernetes.io","kep.k8s.io","kep.kubernetes.io",
        "packages.k8s.io","packages.kubernetes.io","pkgs.k8s.io","pkgs.kubernetes.io",
        "pr-test.k8s.io","pr-test.kubernetes.io","pr.k8s.io","pr.kubernetes.io",
        "prs.k8s.io","prs.kubernetes.io","rel.k8s.io","rel.kubernetes.io",
        "releases.k8s.io","releases.kubernetes.io","sbom.k8s.io","sbom.kubernetes.io",
        "sigs.k8s.io","sigs.kubernetes.io","slack.k8s.io","slack.kubernetes.io",
        "submit-queue.k8s.io","submit-queue.kubernetes.io","www.k8s.io",
        "youtube.k8s.io","youtube.kubernetes.io","yt.k8s.io","yt.kubernetes.io",
        "yum.k8s.io","yum.kubernetes.io"
      ],
      privateKey:$privateKey,minClientVer:"",maxClientVer:"",maxTimediff:0,
      shortIds:["aa5794f3","d56131ba952ffb","a1","4302","6779170a6abf3bd9","6446b6","7caf6afe05","5df0cc840553"],
      mldsa65Seed:$mldsaSeed,
      settings:{publicKey:$publicKey,fingerprint:"chrome",serverName:"",spiderX:"/",mldsa65Verify:$mldsaVerify}
    }
  },
  tag:"in-17667-tcp", sniffing:{enabled:false},
  shareAddrStrategy:"listen",shareAddr:"",subSortIndex:4,originNodeGuid:""
}')"

printf '%s\n' "$INBOUND_1" | jq . > "$GENERATED_DIR/01-insecure.json"
printf '%s\n' "$INBOUND_2" | jq . > "$GENERATED_DIR/02-reality-row.json"
printf '%s\n' "$INBOUND_3" | jq . > "$GENERATED_DIR/03-xhttp.json"
printf '%s\n' "$INBOUND_4" | jq . > "$GENERATED_DIR/04-grpc.json"
chmod 600 "$GENERATED_DIR"/*.json

create_inbound "insecure" "$INBOUND_1" || die "Could not create insecure inbound"
create_inbound "Vless-Reality-Row" "$INBOUND_2" || die "Could not create Vless-Reality-Row inbound"
create_inbound "Vless-Xhttp" "$INBOUND_3" || die "Could not create Vless-Xhttp inbound"
create_inbound "Vless-Reality-gRPC" "$INBOUND_4" || die "Could not create Vless-Reality-gRPC inbound"

sleep 3
INBOUND_LIST="$(api_get "/panel/api/inbounds/list")" || die "Could not list newly created inbounds"
printf '%s\n' "$INBOUND_LIST" | jq . > "$RESULT_DIR/inbounds.json"
chmod 600 "$RESULT_DIR/inbounds.json"

get_inbound_id() {
  local remark="$1"
  echo "$INBOUND_LIST" | jq -r --arg remark "$remark" '.obj[]? | select(.remark == $remark) | .id' | head -n1
}

ID_INSECURE="$(get_inbound_id "insecure")"
ID_ROW="$(get_inbound_id "Vless-Reality-Row")"
ID_XHTTP="$(get_inbound_id "Vless-Xhttp")"
ID_GRPC="$(get_inbound_id "Vless-Reality-gRPC")"

for VALUE in "$ID_INSECURE" "$ID_ROW" "$ID_XHTTP" "$ID_GRPC"; do
  [[ -n "$VALUE" && "$VALUE" != "null" ]] || die "Could not resolve all inbound IDs"
done

EXPECTED_COUNT="$(echo "$INBOUND_LIST" | jq '[.obj[]? | select(.remark=="insecure" or .remark=="Vless-Reality-Row" or .remark=="Vless-Xhttp" or .remark=="Vless-Reality-gRPC")] | length')"
[[ "$EXPECTED_COUNT" == "4" ]] || die "Expected 4 managed inbounds, found ${EXPECTED_COUNT}"

log "[16/18] Creating Friend and attaching it to all four inbounds"
CLIENT_PAYLOAD="$(jq -n \
  --arg email "$CLIENT_EMAIL" \
  --arg uuid "$CLIENT_UUID" \
  --arg subId "$CLIENT_SUB_ID" \
  --arg auth "$CLIENT_AUTH" \
  --arg password "$CLIENT_PASSWORD" \
  --argjson totalGB "$CLIENT_TOTAL_BYTES" \
  --argjson i1 "$ID_INSECURE" \
  --argjson i2 "$ID_ROW" \
  --argjson i3 "$ID_XHTTP" \
  --argjson i4 "$ID_GRPC" '
[
  {
    client:{
      email:$email,
      id:$uuid,
      subId:$subId,
      auth:$auth,
      password:$password,
      totalGB:$totalGB,
      expiryTime:0,
      limitIp:0,
      limitHwid:0,
      enable:true,
      reset:0,
      security:"auto",
      tgId:0,
      comment:""
    },
    inboundIds:[$i1,$i2,$i3,$i4]
  }
]
')"

printf '%s\n' "$CLIENT_PAYLOAD" > "$RESULT_DIR/friend-client-payload.json"
chmod 600 "$RESULT_DIR/friend-client-payload.json"

CLIENT_RESPONSE="$(api_post "/panel/api/clients/bulkCreate" "$CLIENT_PAYLOAD")" || die "Friend bulkCreate request failed"
echo "$CLIENT_RESPONSE" | jq . 2>/dev/null || echo "$CLIENT_RESPONSE"
echo "$CLIENT_RESPONSE" | jq -e '.success == true' >/dev/null 2>&1 || die "Friend creation failed"

# bulkCreate can return success=true with skipped items, so verify the actual result.
SKIPPED_COUNT="$(echo "$CLIENT_RESPONSE" | jq -r '(.obj.skipped // []) | length' 2>/dev/null || echo 0)"
if [[ "$SKIPPED_COUNT" != "0" ]]; then
  echo "$CLIENT_RESPONSE" | jq '.obj.skipped'
  die "Friend creation was skipped by 3x-ui"
fi

sleep 3
CLIENT_EXPORT="$(api_get "/panel/api/clients/export")" || die "Could not export clients for verification"
echo "$CLIENT_EXPORT" | jq -e '.success == true' >/dev/null 2>&1 || die "Client export verification failed"

ATTACH_COUNT="$(echo "$CLIENT_EXPORT" | jq -r --arg email "$CLIENT_EMAIL" '
  [.obj[]? | select(.client.email == $email) | .inboundIds[]?] | unique | length
')"
[[ "$ATTACH_COUNT" == "4" ]] || die "Friend is attached to ${ATTACH_COUNT}/4 inbounds"

FRIEND_SUB_ID="$(echo "$CLIENT_EXPORT" | jq -r --arg email "$CLIENT_EMAIL" '.obj[]? | select(.client.email == $email) | .client.subId' | head -n1)"
[[ "$FRIEND_SUB_ID" == "$CLIENT_SUB_ID" ]] || die "Friend subId verification failed"

log "[17/18] Configuring and validating Subscription"
set_setting "subEnable" "true" || die "Could not enable subscription server"
set_setting "subCertFile" "$CERT_FULLCHAIN" || die "Could not configure subscription certificate"
set_setting "subKeyFile" "$CERT_PRIVATE" || die "Could not configure subscription key"

SUB_PORT="$(get_setting "subPort")"
SUB_PATH="$(get_setting "subPath")"
SUB_DOMAIN="$(get_setting "subDomain")"
SUB_PORT="${SUB_PORT:-2096}"
[[ -n "$SUB_PATH" ]] || SUB_PATH="/sub/"
SUB_PATH="/${SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"
SUB_HOST="${SUB_DOMAIN:-$PUBLIC_IP}"
SUBSCRIPTION_URL="https://${SUB_HOST}:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"

systemctl restart x-ui
sleep 5
systemctl is-active --quiet x-ui || die "x-ui failed after subscription configuration"
wait_for_api || die "API did not return after final restart"

LOCAL_SUB_URL="https://127.0.0.1:${SUB_PORT}${SUB_PATH}${CLIENT_SUB_ID}"
SUB_HTTP_CODE="$(curl -k -sS -o "$RESULT_DIR/friend-subscription.raw" -w '%{http_code}' \
  --connect-timeout 3 --max-time 15 "$LOCAL_SUB_URL" 2>/dev/null || true)"

if [[ "$SUB_HTTP_CODE" == "200" && -s "$RESULT_DIR/friend-subscription.raw" ]]; then
  SUB_TEST_STATUS="PASS - HTTP 200"
else
  die "Subscription validation failed: HTTP ${SUB_HTTP_CODE:-NO_RESPONSE}"
fi

cat > "$RESULT_DIR/client-info.env" <<CLIENTEOF
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
CLIENTEOF
chmod 600 "$RESULT_DIR/client-info.env"
chown root:root "$RESULT_DIR/client-info.env"

log "[18/18] Final validation"
FINAL_LIST="$(api_get "/panel/api/inbounds/list")" || die "Final inbound list failed"
FINAL_EXPECTED_COUNT="$(echo "$FINAL_LIST" | jq '[.obj[]? | select(.remark=="insecure" or .remark=="Vless-Reality-Row" or .remark=="Vless-Xhttp" or .remark=="Vless-Reality-gRPC")] | length')"
[[ "$FINAL_EXPECTED_COUNT" == "4" ]] || die "Final inbound count is ${FINAL_EXPECTED_COUNT}, expected 4"

FINAL_EXPORT="$(api_get "/panel/api/clients/export")" || die "Final client export failed"
FINAL_ATTACH_COUNT="$(echo "$FINAL_EXPORT" | jq -r --arg email "$CLIENT_EMAIL" '[.obj[]? | select(.client.email == $email) | .inboundIds[]?] | unique | length')"
[[ "$FINAL_ATTACH_COUNT" == "4" ]] || die "Final Friend attachment count is ${FINAL_ATTACH_COUNT}, expected 4"

printf '%s\n' "$FINAL_LIST" | jq . > "$RESULT_DIR/inbounds.json"
chmod 600 "$RESULT_DIR/inbounds.json"

BOOTSTRAP_STATUS="COMPLETED"
CONFIG_STATUS="SUCCESS"
SSL_STATUS="SUCCESS"
write_panel_info

log "INSTALLATION COMPLETED"
echo "Public IP: $PUBLIC_IP"
echo "Panel: $PANEL_URL"
echo "Username: $XUI_USERNAME"
echo "Password: $XUI_PASSWORD"
echo "Friend Subscription: $SUBSCRIPTION_URL"
echo
echo "Configured inbounds:"
echo "  10253  VLESS / TCP / none"
echo "  443    VLESS / TCP / REALITY"
echo "  2052   VLESS / XHTTP / REALITY"
echo "  17667  VLESS / gRPC / REALITY"
echo
echo "Panel info: /opt/x-ui/panel-info.txt"
echo "Credentials: /opt/x-ui/credentials.env"
echo "Client info: /opt/x-ui/client-info.env"
echo "Log: /var/log/x-ui-bootstrap.log"
