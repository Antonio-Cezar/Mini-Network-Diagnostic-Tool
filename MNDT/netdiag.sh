#!/usr/bin/env bash
set -Eeuo pipefail

# ─────────────  Config  ─────────────
# Usage: ./netdiag.sh [target1 target2 ...]
# If no targets are provided, these are used:
DEFAULT_TARGETS=("1.1.1.1" "8.8.8.8" "google.com")
PING_COUNT="${PING_COUNT:-4}"      # pings per target
PING_TIMEOUT="${PING_TIMEOUT:-2}"  # seconds per reply
STEP_TIMEOUT="${STEP_TIMEOUT:-25}" # max seconds per step

LOG_DIR="${HOME}/.local/var/netdiag"
mkdir -p "$LOG_DIR"
TS_UTC="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/netdiag_${TS_UTC}.log"

# ─────────────  UI  ─────────────
GREEN="$(printf '\033[32m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"
OK="${GREEN}OK${RESET}"
FAIL="${RED}FEIL${RESET}"
WARN="${YELLOW}ADVARSEL${RESET}"

# ─────────────  Helpers  ─────────────
have() { command -v "$1" >/dev/null 2>&1; }

# LOG ONLY to file (keeps terminal clean)
log() {
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

header() {
  # show header in terminal AND in log
  {
    echo "--------------------------------------------------"
    echo "Mini Network Diagnostic Tool"
    echo "Tid (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "Logg: $LOG_FILE"
    echo "--------------------------------------------------"
  } | tee -a "$LOG_FILE"
}

usage_deps() {
  cat <<EOF
${YELLOW}Mangler verktøy? Installer på Ubuntu/WSL:${RESET}
  sudo apt update && sudo apt install -y traceroute dnsutils
(Valgfri fallback: 'tracepath' (iputils) og 'dig' (dnsutils) kan brukes automatisk.)
EOF
}

# Choose traceroute command (traceroute → tracepath)
pick_tracer() {
  if have traceroute; then echo "traceroute -n -w 2 -q 1"; return 0; fi
  if have tracepath; then echo "tracepath -n"; return 0; fi
  return 1
}

# DNS lookup: nslookup → dig
dns_lookup() {
  local host="$1"
  if have nslookup; then
    nslookup "$host"
    return $?
  elif have dig; then
    local out
    out="$(dig +short "$host")"
    echo "$out"
    [[ -n "$out" ]]
    return $?
  else
    return 127
  fi
}
# Make function visible to the timed subshell (used by run_step)
export -f dns_lookup
export -f have

# Run a step with timeout and log details to file only
run_step() {
  local title="$1"; shift
  local cmdline=("$@")

  log "==> $title"
  if ! have timeout; then
    # Run without timeout; log only
    "${cmdline[@]}" >>"$LOG_FILE" 2>&1
    return $?
  fi

  timeout "${STEP_TIMEOUT}" bash -c 'exec "$@"' _ "${cmdline[@]}" >>"$LOG_FILE" 2>&1
  local rc=$?
  if [[ $rc -eq 124 || $rc -eq 137 ]]; then
    log "[TIMEOUT] $title etter ${STEP_TIMEOUT}s"
  end
  return "$rc"
}

# ─────────────  Start  ─────────────
header

# Check base tools
missing=()
have ping || missing+=("ping (iputils-ping)")
pick_tracer >/dev/null || missing+=("traceroute eller tracepath")
{ have nslookup || have dig; } || missing+=("nslookup eller dig")

if ((${#missing[@]})); then
  echo "${RED}Mangler:${RESET} ${missing[*]}" | tee -a "$LOG_FILE"
  usage_deps
fi

# Targets
TARGETS=("$@")
((${#TARGETS[@]})) || TARGETS=("${DEFAULT_TARGETS[@]}")

declare -A STATUS_PING STATUS_TRACE STATUS_DNS
overall_ok=0

TRACER_CMD="$(pick_tracer || true)"

for host in "${TARGETS[@]}"; do
  echo | tee -a "$LOG_FILE"
  echo "${CYAN}${BOLD}>> Tester: ${host}${RESET}" | tee -a "$LOG_FILE"

  # 1) PING
  if have ping; then
    if run_step "PING $host" ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$host"; then
      STATUS_PING["$host"]="OK"
      echo "PING: ${OK}"
    else
      STATUS_PING["$host"]="FEIL"
      echo "PING: ${FAIL}"
      overall_ok=1
    fi
  else
    STATUS_PING["$host"]="Mangler ping"
    echo "PING: ${WARN} – ping ikke tilgjengelig"
    overall_ok=1
  fi

  # 2) TRACEROUTE/TRACEPATH
  if [[ -n "$TRACER_CMD" ]]; then
    # shellcheck disable=SC2086
    if run_step "TRACE $host" $TRACER_CMD "$host"; then
      STATUS_TRACE["$host"]="OK"
      echo "TRACE: ${OK}"
    else
      STATUS_TRACE["$host"]="FEIL"
      echo "TRACE: ${FAIL}"
      overall_ok=1
    fi
  else
    STATUS_TRACE["$host"]="Mangler traceroute/tracepath"
    echo "TRACE: ${WARN} – verktøy ikke tilgjengelig"
    overall_ok=1
  fi

  # 3) DNS (nslookup/dig)
  if have nslookup || have dig; then
    if run_step "DNS $host" bash -c 'dns_lookup "$1"' _ "$host"; then
      STATUS_DNS["$host"]="OK"
      echo "DNS : ${OK}"
    else
      STATUS_DNS["$host"]="FEIL"
      echo "DNS : ${FAIL}"
      overall_ok=1
    fi
  else
    STATUS_DNS["$host"]="Mangler nslookup/dig"
    echo "DNS : ${WARN} – verktøy ikke tilgjengelig"
    overall_ok=1
  fi
done

# ─────────────  Summary  ─────────────
echo
echo "=================== RESULTAT ==================="
printf '%-28s %-8s %-8s %-8s\n' "Mål" "PING" "TRACE" "DNS"
echo "------------------------------------------------"
for host in "${TARGETS[@]}"; do
  printf '%-28s %-8s %-8s %-8s\n' \
    "$host" \
    "${STATUS_PING[$host]:-NA}" \
    "${STATUS_TRACE[$host]:-NA}" \
    "${STATUS_DNS[$host]:-NA}"
done
echo "------------------------------------------------"
if [[ $overall_ok -eq 0 ]]; then
  echo "Status: ${GREEN}ALLE TESTER OK${RESET}"
else
  echo "Status: ${RED}EN ELLER FLERE TESTER FEIL${RESET}"
fi
echo "Logg lagret: ${BOLD}${LOG_FILE}${RESET}"
exit "$overall_ok"
