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
export LC_NUMERIC=C

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
  printf "%b\n" "${CYAN}Resolving API URL from Terraform outputs …${RESET}"
  API_BASE_URL=$(cd terraform && terraform output -raw api_base_url 2>/dev/null) || {
    printf "%b\n" "${RED}ERROR: Could not read api_base_url from Terraform outputs."
    printf "%b\n" "Pass the URL as argument: ./scripts/test_cache.sh https://xxxxx.execute-api.eu-central-1.amazonaws.com/v1${RESET}"
    exit 1
  }
fi

# ---------- resolve security ID ----------
if [[ -n "${2:-}" ]]; then
  SECURITY_ID="$2"
else
  printf "%b\n" "${CYAN}Fetching first security ID from ${API_BASE_URL}/securities …${RESET}"
  SECURITY_ID=$(curl -sf "${API_BASE_URL}/securities" | python3 -c "import sys,json; print(json.load(sys.stdin)['securities'][0])" 2>/dev/null) || {
    printf "%b\n" "${RED}ERROR: Could not fetch a security ID. Pass one as second argument.${RESET}"
    exit 1
  }
fi

ENDPOINT="${API_BASE_URL}/securities/${SECURITY_ID}/scores"
REQUESTS=5
PAUSE=0.3          # seconds between consecutive requests

echo ""
printf "%b\n" "${BOLD}=============================================${RESET}"
printf "%b\n" "${BOLD}  API Gateway Cache Test${RESET}"
printf "%b\n" "${BOLD}=============================================${RESET}"
printf "%b\n" "  Endpoint   : ${ENDPOINT}"
printf "%b\n" "  Requests   : ${REQUESTS}"
printf "%b\n" "  Cache TTL  : 300 s (configured in Terraform)"
printf "%b\n" "${BOLD}=============================================${RESET}"
echo ""

# Helper: extract server-side processing time (time_starttransfer - time_pretransfer).
# This isolates API Gateway + Lambda time, stripping DNS/TCP/TLS overhead.
server_time() {
  curl -s -o /dev/null -D "${1:--}" -w "%{time_pretransfer} %{time_starttransfer}" "$ENDPOINT" "${@:2}"
}

# Helper: detect cache HIT via x-amzn-trace-id.
# Lambda-invoked responses include Parent/Sampled; cached responses have only Root.
is_cache_hit() {
  local headers_file="$1"
  local trace
  trace=$(grep -i "^x-amzn-trace-id:" "$headers_file" 2>/dev/null || echo "")
  if [[ -z "$trace" ]]; then
    echo "unknown"
  elif echo "$trace" | grep -qi "Parent="; then
    echo "MISS"
  else
    echo "HIT"
  fi
}

# ---------- Step 1: Flush the cache ----------
printf "%b\n" "${YELLOW}▶ Step 1 — Invalidating cache via AWS API …${RESET}"
# Extract REST API ID from the URL (e.g. mykr5uo3u6 from https://mykr5uo3u6.execute-api...)
REST_API_ID=$(echo "$API_BASE_URL" | sed 's|https://||' | cut -d. -f1)
STAGE_NAME=$(echo "$API_BASE_URL" | sed 's|.*/||')  # last path segment, e.g. "v1"
AWS_REGION=$(echo "$API_BASE_URL" | sed 's|.*execute-api\.\([^.]*\)\..*|\1|')

aws apigateway flush-stage-cache \
  --rest-api-id "$REST_API_ID" \
  --stage-name "$STAGE_NAME" \
  --region "$AWS_REGION" \
  --profile "${AWS_PROFILE:-clarity}" 2>/dev/null || {
    printf "%b\n" "  ${YELLOW}Could not flush via API (missing permissions?). Falling back to header.${RESET}"
    curl -sf -H "Cache-Control: max-age=0" -o /dev/null "$ENDPOINT" || true
  }
sleep 2
printf "%b\n\n" "  Cache flushed."

# ---------- Step 2: First request (expected MISS) ----------
printf "%b\n" "${YELLOW}▶ Step 2 — First request (expected cache MISS) …${RESET}"
MISS_HEADERS=$(mktemp)
read -r PRE START <<< "$(server_time "$MISS_HEADERS")"
MISS_SERVER=$(awk "BEGIN { printf \"%.4f\", $START - $PRE }")
MISS_CACHE=$(is_cache_hit "$MISS_HEADERS")
HTTP_MISS=$(grep -m1 "^HTTP/" "$MISS_HEADERS" | awk '{print $2}' || echo "?")
rm -f "$MISS_HEADERS"
printf "%b\n" "  HTTP status     : ${HTTP_MISS}"
printf "%b\n" "  Server time     : ${MISS_SERVER} s  (excl. network overhead)"
printf "%b\n" "  Cache           : ${MISS_CACHE}"
echo ""

sleep 1

# ---------- Step 3: Warm request to populate cache ----------
printf "%b\n" "${YELLOW}▶ Step 3 — Populating cache …${RESET}"
curl -sf -o /dev/null "$ENDPOINT"
sleep 1
printf "%b\n\n" "  Done."

# ---------- Step 4: Repeated requests (expected HITs) ----------
printf "%b\n" "${YELLOW}▶ Step 4 — Sending ${REQUESTS} requests (expecting cache HITs) …${RESET}"
echo ""
printf "  ${BOLD}%-6s  %-14s  %-10s  %s${RESET}\n" "#" "Server (s)" "HTTP" "Cache"
printf "  %-6s  %-14s  %-10s  %s\n" "-----" "------------" "--------" "----------"

declare -a STIMES=()
HITS=0
for i in $(seq 1 "$REQUESTS"); do
  TMPHEADERS=$(mktemp)
  read -r PRE START <<< "$(server_time "$TMPHEADERS")"
  STIME=$(awk "BEGIN { printf \"%.4f\", $START - $PRE }")
  HTTP=$(grep -m1 "^HTTP/" "$TMPHEADERS" | awk '{print $2}' || echo "?")
  CACHE=$(is_cache_hit "$TMPHEADERS")
  rm -f "$TMPHEADERS"

  if [[ "$CACHE" == "HIT" ]]; then
    HITS=$((HITS + 1))
    printf "  %-6s  %-14s  %-10s  ${GREEN}%s${RESET}\n" "$i" "$STIME" "$HTTP" "$CACHE"
  else
    printf "  %-6s  %-14s  %-10s  ${RED}%s${RESET}\n" "$i" "$STIME" "$HTTP" "$CACHE"
  fi
  STIMES+=("$STIME")
  sleep "$PAUSE"
done

echo ""

# ---------- Step 5: Compare cold vs. warm latencies ----------
printf "%b\n" "${YELLOW}▶ Step 5 — Results${RESET}"

AVG=$(printf '%s\n' "${STIMES[@]}" | awk '{ sum += $1; n++ } END { if (n>0) printf "%.4f", sum/n }')

printf "%b\n" "  Cold server time  : ${RED}${MISS_SERVER} s${RESET}"
printf "%b\n" "  Warm avg server   : ${GREEN}${AVG} s${RESET}"

SPEEDUP=$(awk "BEGIN { if ($AVG > 0) printf \"%.1f\", $MISS_SERVER / $AVG; else print \"N/A\" }")
printf "%b\n" "  Speedup           : ${BOLD}~${SPEEDUP}x${RESET}"
printf "%b\n" "  Cache HITs        : ${BOLD}${HITS}/${REQUESTS}${RESET}"

if [[ "$HITS" -eq "$REQUESTS" ]]; then
  printf "%b\n" "  ${GREEN}✓ All requests served from cache${RESET}"
elif [[ "$HITS" -gt 0 ]]; then
  printf "%b\n" "  ${YELLOW}~ Partial cache hits (${HITS}/${REQUESTS})${RESET}"
else
  printf "%b\n" "  ${RED}✗ No cache hits detected${RESET}"
  printf "%b\n" "  ${YELLOW}  Hints:${RESET}"
  printf "%b\n" "  ${YELLOW}  - Cache cluster may still be provisioning (~4 min after terraform apply)${RESET}"
  printf "%b\n" "  ${YELLOW}  - Verify cache_key_parameters includes method.request.path.proxy${RESET}"
  printf "%b\n" "  ${YELLOW}  - Run: aws apigateway get-integration --rest-api-id <id> --resource-id <id> --http-method ANY${RESET}"
fi
echo ""

# ---------- Step 6: Lambda invocation verification via CloudWatch Logs ----------
printf "%b\n" "${YELLOW}▶ Step 6 — Lambda invocation check (CloudWatch Logs)${RESET}"
echo ""
LOG_GROUP="/aws/lambda/clarity-api"
# Wait for CloudWatch Logs to propagate (can take up to 15s)
printf "  Waiting 15s for CloudWatch Logs to propagate …"
sleep 15
echo ""

LOG_OUTPUT=$(aws logs tail "$LOG_GROUP" --since 90s \
  --region "$AWS_REGION" \
  --profile "${AWS_PROFILE:-clarity}" \
  --no-cli-pager 2>/dev/null || echo "")

INVOCATIONS=$(echo "$LOG_OUTPUT" | grep -c "START RequestId" || true)
SCORE_CALLS=$(echo "$LOG_OUTPUT" | grep -c "LAMBDA_INVOKED" || true)

printf "%b\n" "  Lambda invocations (last 90s): ${BOLD}${INVOCATIONS}${RESET}"
printf "%b\n" "  /scores handler calls        : ${BOLD}${SCORE_CALLS}${RESET}"
echo ""

# Show relevant log lines
printf "%b\n" "  ${CYAN}--- Lambda log excerpt ---${RESET}"
echo "$LOG_OUTPUT" | grep -E "(START RequestId|LAMBDA_INVOKED)" | while IFS= read -r line; do
  if echo "$line" | grep -q "LAMBDA_INVOKED"; then
    printf "  %b\n" "${YELLOW}${line}${RESET}"
  else
    printf "  %b\n" "${CYAN}${line}${RESET}"
  fi
done
printf "%b\n" "  ${CYAN}--- end ---${RESET}"
echo ""

# We expect: flush(0-1) + cold miss(1) + populate(1) = 2-3 score calls.
# If cache works, Step 4 adds 0 more. Without cache it adds REQUESTS more.
EXPECTED_MAX=3  # flush + cold miss + populate
if [[ "$SCORE_CALLS" -le "$EXPECTED_MAX" ]]; then
  printf "%b\n" "  ${GREEN}✓ Lambda was NOT invoked for cached requests${RESET}"
  printf "%b\n" "  ${GREEN}  (${SCORE_CALLS} /scores calls = flush + miss + populate, 0 from Step 4)${RESET}"
else
  CACHED_INVOCATIONS=$((SCORE_CALLS - EXPECTED_MAX))
  printf "%b\n" "  ${RED}✗ Lambda was invoked ${CACHED_INVOCATIONS} extra time(s) during cached requests${RESET}"
fi
echo ""
printf "%b\n" "${BOLD}=============================================${RESET}"
printf "%b\n" "${GREEN}  Cache test complete ✓${RESET}"
printf "%b\n" "${BOLD}=============================================${RESET}"
