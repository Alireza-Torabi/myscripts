#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Dependency check (install only if missing, with permission)
# =========================================================
need_cmd() { command -v "$1" >/dev/null 2>&1; }

missing=()
need_cmd nc      || missing+=("netcat-openbsd")
need_cmd timeout || missing+=("coreutils")
need_cmd xargs   || missing+=("findutils")
need_cmd awk     || missing+=("gawk")
need_cmd python3 || missing+=("python3")

if ((${#missing[@]} > 0)); then
  echo "Missing dependencies:"
  printf "  - %s\n" "${missing[@]}"
  echo
  read -r -p "Install them now? (y/N): " ans
  if [[ "${ans,,}" == "y" ]]; then
    sudo apt update
    sudo apt install -y "${missing[@]}"
  else
    echo "Cannot continue without dependencies. Exiting."
    exit 1
  fi
fi

# =========================
# Disable terminal flow control (prevents Ctrl+S freeze)
# =========================
STTY_OLD="$(stty -g 2>/dev/null || true)"
stty -ixon 2>/dev/null || true

restore_tty() {
  [[ -n "${STTY_OLD:-}" ]] && stty "$STTY_OLD" 2>/dev/null || true
  tput cnorm 2>/dev/null || true
}

cleanup() { restore_tty; echo; exit 0; }
trap cleanup INT TERM
tput civis 2>/dev/null || true

# =========================
# Inputs
# =========================
IP_FILE="${1:-}"
if [[ -z "$IP_FILE" ]]; then
  read -r -p "Enter IP list file path (e.g. /root/ips.txt): " IP_FILE
fi
if [[ ! -f "$IP_FILE" ]]; then
  echo "File not found: $IP_FILE"
  exit 1
fi

read -r -p "Target port? (default 4370): " PORT
PORT="${PORT:-4370}"

read -r -p "Refresh interval in seconds? (default 1): " INTERVAL
INTERVAL="${INTERVAL:-1}"

read -r -p "Per-attempt timeout in seconds? (default 1): " HARD_T
HARD_T="${HARD_T:-1}"
HARD_TIMEOUT="${HARD_T}s"

read -r -p "Attempts per host (median/avg over N)? (default 3): " ATTEMPTS
ATTEMPTS="${ATTEMPTS:-3}"

read -r -p "Parallel checks count? (default 40): " PARALLEL
PARALLEL="${PARALLEL:-40}"

read -r -p "Green threshold (ms, <= green)? (default 50): " TH_GREEN
TH_GREEN="${TH_GREEN:-50}"

read -r -p "Yellow threshold (ms, <= yellow)? (default 150): " TH_YELLOW
TH_YELLOW="${TH_YELLOW:-150}"

# =========================
# Load IPs (clean)
# =========================
mapfile -t IPS < <(
  sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$IP_FILE" | awk 'NF'
)
if ((${#IPS[@]} == 0)); then
  echo "No valid IPs found."
  exit 1
fi

# =========================
# Colors
# =========================
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
DIM="\033[2m"
NC="\033[0m"

# =========================
# Output files
# =========================
STAMP="$(date '+%Y%m%d-%H%M%S')"
BASE="portcheck_${PORT}_${STAMP}"
OUT_TXT="${BASE}.txt"
OUT_CSV="${BASE}.csv"
OUT_JSON="${BASE}.json"

last_txt=""
last_csv=""
last_json=""
last_up=0
last_down=0

save_and_exit() {
  printf "%s\n" "$last_txt"  > "$OUT_TXT"
  printf "%s\n" "$last_csv"  > "$OUT_CSV"
  printf "%s\n" "$last_json" > "$OUT_JSON"
  restore_tty
  echo
  echo "Saved:"
  echo "  - $OUT_TXT"
  echo "  - $OUT_CSV"
  echo "  - $OUT_JSON"
  exit 0
}

# =========================
# Hotkeys (non-blocking)
# Ctrl+S (0x13) -> save & exit  (now works because -ixon)
# Ctrl+E (0x05) -> save & exit  (fallback)
# q             -> exit
# =========================
read_key_nonblocking() {
  local k=""
  if IFS= read -rsn1 -t 0.01 k 2>/dev/null; then
    [[ "$k" == $'\x13' ]] && save_and_exit
    [[ "$k" == $'\x05' ]] && save_and_exit
    [[ "$k" == "q" ]] && cleanup
  fi
}

# =========================
# Auto columns by terminal width (ASCII-safe)
# Each cell is fixed width.
# =================**========
CELL_W=28   # tune this if you want more spacing
GAP=2

calc_columns() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 120)"
  local per=$((CELL_W + GAP))
  local c=$(( cols / per ))
  (( c < 1 )) && c=1
  (( c > 10 )) && c=10
  echo "$c"
}

# =========================
# Color by median latency
# =========================
lat_color() {
  local ms="$1"
  if [[ "$ms" == "-" ]]; then
    echo "$RED"
  elif (( ms <= TH_GREEN )); then
    echo "$GREEN"
  elif (( ms <= TH_YELLOW )); then
    echo "$YELLOW"
  else
    echo "$RED"
  fi
}

# =========================
# Render grid (ASCII)
# Cell format:
#   ip  med/avgms  OK
# or
#   ip  -/-        DOWN
# =========================
render_grid() {
  local -n ordered_ref=$1
  local -n up_ref=$2
  local -n med_ref=$3
  local -n avg_ref=$4
  local columns="$5"

  local total="${#ordered_ref[@]}"
  local rows=$(( (total + columns - 1) / columns ))

  for ((r=0; r<rows; r++)); do
    for ((c=0; c<columns; c++)); do
      idx=$(( r + c*rows ))
      if (( idx < total )); then
        ip="${ordered_ref[idx]}"
        if [[ "${up_ref[$ip]:-0}" -eq 1 ]]; then
          m="${med_ref[$ip]}"
          a="${avg_ref[$ip]}"
          col="$(lat_color "$m")"
          cell="${ip} ${m}/${a}ms OK"
          # pad (strip colors not needed; we color whole cell after padding)
          pad=$(( CELL_W - ${#cell} ))
          (( pad < 0 )) && pad=0
          printf "%b%s%*s%b%*s" "$col" "$cell" "$pad" "" "$NC" "$GAP" ""
        else
          cell="${ip} -/- DOWN"
          pad=$(( CELL_W - ${#cell} ))
          (( pad < 0 )) && pad=0
          printf "%b%s%*s%b%*s" "$RED" "$cell" "$pad" "" "$NC" "$GAP" ""
        fi
      fi
    done
    echo
  done
}

# =========================
# Main loop
# =========================
while true; do
  read_key_nonblocking

  columns="$(calc_columns)"

  declare -A is_up=()
  declare -A med=()
  declare -A avg=()
  ups=()
  downs=()

  # Worker output:
  # UP|ip|median|avg|okcount
  # DOWN|ip|||0
  mapfile -t results < <(
    printf "%s\n" "${IPS[@]}" \
    | xargs -P "$PARALLEL" -n 1 bash -lc '
        ip="$1"
        PORT="'"$PORT"'"
        HARD_TIMEOUT="'"$HARD_TIMEOUT"'"
        ATTEMPTS="'"$ATTEMPTS"'"

        ok=0
        vals=()

        for ((i=1; i<=ATTEMPTS; i++)); do
          start=$(date +%s%N 2>/dev/null || echo 0)
          if timeout "$HARD_TIMEOUT" nc -z -w 2 "$ip" "$PORT" >/dev/null 2>&1; then
            end=$(date +%s%N 2>/dev/null || echo 0)
            if [[ "$start" != 0 && "$end" != 0 ]]; then
              ms=$(( (end - start) / 1000000 ))
            else
              ms=0
            fi
            vals+=("$ms")
            ok=$((ok+1))
          fi
        done

        if (( ok == 0 )); then
          echo "DOWN|$ip|||0"
          exit 0
        fi

        sorted=$(printf "%s\n" "${vals[@]}" | sort -n)
        mid=$(( (ok - 1) / 2 ))
        median=$(printf "%s\n" "$sorted" | sed -n "$((mid+1))p")

        sum=0
        for v in "${vals[@]}"; do sum=$((sum+v)); done
        avg=$(( sum / ok ))

        echo "UP|$ip|$median|$avg|$ok"
      ' _
  )

  for r in "${results[@]}"; do
    st="${r%%|*}"
    rest="${r#*|}"
    ip="${rest%%|*}"
    tail="${rest#*|}"
    m="${tail%%|*}"
    tail2="${tail#*|}"
    a="${tail2%%|*}"

    if [[ "$st" == "UP" ]]; then
      is_up["$ip"]=1
      med["$ip"]="$m"
      avg["$ip"]="$a"
    else
      is_up["$ip"]=0
    fi
  done

  # Sort UP by median asc, keep DOWN at bottom
  mapfile -t ups < <(
    for ip in "${IPS[@]}"; do
      [[ "${is_up[$ip]:-0}" -eq 1 ]] && echo "${med[$ip]}|$ip"
    done | sort -n | cut -d'|' -f2
  )
  mapfile -t downs < <(
    for ip in "${IPS[@]}"; do
      [[ "${is_up[$ip]:-0}" -eq 0 ]] && echo "$ip"
    done
  )

  ordered=( "${ups[@]}" "${downs[@]}" )

  total="${#IPS[@]}"
  upc="${#ups[@]}"
  downc="${#downs[@]}"
  last_up="$upc"
  last_down="$downc"

  now="$(date '+%Y-%m-%d %H:%M:%S')"
  clear
  echo -e "${YELLOW}TCP Port Monitor (median/avg latency, auto-columns)${NC} ${DIM}(Ctrl+S save+exit | Ctrl+E save+exit | q exit | Ctrl+C force)${NC}"
  echo -e "Time: $now"
  echo -e "File: $IP_FILE | Port: $PORT | Refresh: ${INTERVAL}s | Timeout/attempt: ${HARD_TIMEOUT} | Attempts: ${ATTEMPTS} | Parallel: ${PARALLEL} | Columns:auto($columns)"
  echo -e "Thresholds: ${GREEN}<=${TH_GREEN}ms${NC}  ${YELLOW}<=${TH_YELLOW}ms${NC}  ${RED}>${TH_YELLOW}ms${NC}"
  echo -e "Total: $total   ${GREEN}UP:$upc${NC}   ${RED}DOWN:$downc${NC}"
  echo

  render_grid ordered is_up med avg "$columns"

  # TXT snapshot (no ANSI)
  {
    echo "TCP Port Check Snapshot"
    echo "Time: $now"
    echo "IP file: $IP_FILE"
    echo "Port: $PORT"
    echo "Attempts: $ATTEMPTS"
    echo "Timeout/attempt: $HARD_TIMEOUT"
    echo "Parallel: $PARALLEL"
    echo "Total: $total  UP: $upc  DOWN: $downc"
    echo
    echo "UP (sorted by median): ip | median_ms | avg_ms"
    for ip in "${ups[@]}"; do
      echo "$ip | ${med[$ip]} | ${avg[$ip]}"
    done
    echo
    echo "DOWN:"
    printf "%s\n" "${downs[@]}"
  } > /tmp/.pw_txt.$$
  last_txt="$(cat /tmp/.pw_txt.$$)"
  rm -f /tmp/.pw_txt.$$

  # CSV
  {
    echo "ip,port,status,median_ms,avg_ms,attempts,checked_at"
    for ip in "${ups[@]}"; do
      echo "$ip,$PORT,UP,${med[$ip]},${avg[$ip]},$ATTEMPTS,$now"
    done
    for ip in "${downs[@]}"; do
      echo "$ip,$PORT,DOWN,,,${ATTEMPTS},$now"
    done
  } > /tmp/.pw_csv.$$
  last_csv="$(cat /tmp/.pw_csv.$$)"
  rm -f /tmp/.pw_csv.$$

  # JSON (generated from CSV safely)
  last_json="$(python3 - <<PY
import csv, io, json
csv_text = """$last_csv"""
r = csv.DictReader(io.StringIO(csv_text))
items = []
for row in r:
    def norm(x):
        x = (x or "").strip()
        return None if x == "" else x
    items.append({
        "ip": row["ip"],
        "port": int(row["port"]),
        "status": row["status"],
        "median_ms": int(row["median_ms"]) if norm(row.get("median_ms")) else None,
        "avg_ms": int(row["avg_ms"]) if norm(row.get("avg_ms")) else None,
        "attempts": int(row["attempts"]),
        "checked_at": row["checked_at"],
    })
out = {"port": $PORT, "attempts": $ATTEMPTS, "checked_at": "$now", "results": items}
print(json.dumps(out, indent=2))
PY
)"

  # Responsive sleep
  end=$((SECONDS + INTERVAL))
  while (( SECONDS < end )); do
    read_key_nonblocking
    sleep 0.05
  done
done
