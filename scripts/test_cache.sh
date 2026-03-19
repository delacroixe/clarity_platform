#!/usr/bin/env bash
# ------------------------------------------------------------------
# test_cache.sh — Verify API Gateway cache behaviour
#
# Usage:
#   ./scripts/test_cache.sh [API_BASE_URL] [SECURITY_ID]
#
# If API_BASE_URL is omitted the script reads it from Terraform output.
# SECURITY_ID defaults to the first ID returned by GET /securities.
# ------------------------------------------------------------------
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

# ---------- resolve API base URL ----------
if [[ -n "${1:-}" ]]; then
  API_BASE_URL="$1"
else
  echo -e "${CYAN}Resolving API URL from Terraform outputs …${RESET}"
  API_BASE_URL=$(cd terraform && terraform output -raw api_base_url 2>/dev/null) || {
    echo -e "${RED}ERROR: Could not read api_base_url from Terraform outputs."
    echo -e "Pass the URL as argument: ./scripts/test_cache.sh https://xxxxx.execute-api.eu-central-1.amazonaws.com/v1${RESET}"
    exit 1
  }
fi

# ---------- resolve security ID ----------
if [[ -n "${2:-}" ]]; then
  SECURITY_ID="$2"
else
  echo -e "${CYAN}Fetching first security ID from ${API_BASE_URL}/securities …${RESET}"
  SECURITY_ID=$(curl -sf "${API_BASE_URL}/securities" | python3 -c "import sys,json; print(json.load(sys.stdin)['securities'][0])" 2>/dev/null) || {
    echo -e "${RED}ERROR: Could not fetch a security ID. Pass one as second argument.${RESET}"
    exit 1
  }
fi

ENDPOINT="${API_BASE_URL}/securities/${SECURITY_ID}/scores"
REQUESTS=5
PAUSE=0.3          # seconds between consecutive requests

echo ""
echo -e "${BOLD}=============================================${RESET}"
echo -e "${BOLD}  API Gateway Cache Test${RESET}"
echo -e "${BOLD}=============================================${RESET}"
echo -e "  Endpoint   : ${ENDPOINT}"
echo -e "  Requests   : ${REQUESTS}"
echo -e "  Cache TTL  : 300 s (configured in Terraform)"
echo -e "${BOLD}=============================================${RESET}"
echo ""

# ---------- Step 1: Flush the cache (cold start) ----------
echo -e "${YELLOW}▶ Step 1 — Invalidating cache (Cache-Control: max-age=0) …${RESET}"
curl -sf -H "Cache-Control: max-age=0" -o /dev/null "$ENDPOINT" || true
sleep 1
echo -e "  Cache flushed.\n"

# ---------- Step 2: First request (expected MISS) ----------
echo -e "${YELLOW}▶ Step 2 — First request (expected cache MISS) …${RESET}"
TMPFILE=$(mktemp)
HTTP_CODE=$(curl -s -o "$TMPFILE" -D - -w "%{http_code}" "$ENDPOINT")

MISS_TIME=$(curl -s -o /dev/null -w "%{time_total}" "$ENDPOINT" -H "Cache-Control: max-age=0")
echo -e "  HTTP status : ${HTTP_CODE: -3}"
echo -e "  Latency     : ${MISS_TIME} s"

# Check X-Cache header
XCACHE=$(grep -i "^x-cache:" "$TMPFILE" 2>/dev/null | tr -d '\r' || echo "")
if [[ -n "$XCACHE" ]]; then
  echo -e "  ${XCACHE}"
fi
rm -f "$TMPFILE"
echo ""

sleep 1

# ---------- Step 3: Warm request to populate cache ----------
echo -e "${YELLOW}▶ Step 3 — Populating cache …${RESET}"
curl -sf -o /dev/null "$ENDPOINT"
sleep 1
echo -e "  Done.\n"

# ---------- Step 4: Repeated requests (expected HITs) ----------
echo -e "${YELLOW}▶ Step 4 — Sending ${REQUESTS} requests (expecting cache HITs) …${RESET}"
echo ""
printf "  ${BOLD}%-6s  %-12s  %-10s  %s${RESET}\n" "#" "Latency (s)" "HTTP" "X-Cache"
printf "  %-6s  %-12s  %-10s  %s\n" "-----" "----------" "--------" "------------------------------"

declare -a TIMES=()
for i in $(seq 1 "$REQUESTS"); do
  TMPHEADERS=$(mktemp)
  TIME=$(curl -s -o /dev/null -D "$TMPHEADERS" -w "%{time_total}" "$ENDPOINT")
  CODE=$(tail -1 "$TMPHEADERS" 2>/dev/null || echo "")
  XCACHE=$(grep -i "^x-cache:" "$TMPHEADERS" 2>/dev/null | sed 's/[Xx]-[Cc]ache: //' | tr -d '\r' || echo "(not present)")
  HTTP=$(grep -m1 "^HTTP/" "$TMPHEADERS" | awk '{print $2}' || echo "?")
  rm -f "$TMPHEADERS"

  printf "  %-6s  %-12s  %-10s  %s\n" "$i" "$TIME" "$HTTP" "$XCACHE"
  TIMES+=("$TIME")
  sleep "$PAUSE"
done

echo ""

# ---------- Step 5: Compare cold vs. warm latencies ----------
echo -e "${YELLOW}▶ Step 5 — Latency comparison${RESET}"

# Calculate average of cached requests
AVG=$(printf '%s\n' "${TIMES[@]}" | awk '{ sum += $1; n++ } END { if (n>0) printf "%.4f", sum/n }')

echo -e "  Cold (cache miss) : ${RED}${MISS_TIME} s${RESET}"
echo -e "  Warm average      : ${GREEN}${AVG} s${RESET}"

SPEEDUP=$(awk "BEGIN { if ($AVG > 0) printf \"%.1f\", $MISS_TIME / $AVG; else print \"N/A\" }")
echo -e "  Speedup           : ${BOLD}~${SPEEDUP}x${RESET}"
echo ""

# ---------- Step 6: CloudWatch metrics hint ----------
echo -e "${YELLOW}▶ Step 6 — CloudWatch metrics (run manually)${RESET}"
echo ""
echo "  To see CacheHitCount / CacheMissCount in the last hour:"
echo ""
echo "    aws cloudwatch get-metric-statistics \\"
echo "      --namespace AWS/ApiGateway \\"
echo "      --metric-name CacheHitCount \\"
echo "      --dimensions Name=ApiName,Value=clarity-api Name=Stage,Value=v1 \\"
echo "      --start-time \"\$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)\" \\"
echo "      --end-time \"\$(date -u +%Y-%m-%dT%H:%M:%S)\" \\"
echo "      --period 300 --statistics Sum \\"
echo "      --profile clarity --region eu-central-1"
echo ""
echo -e "${BOLD}=============================================${RESET}"
echo -e "${GREEN}  Cache test complete ✓${RESET}"
echo -e "${BOLD}=============================================${RESET}"
