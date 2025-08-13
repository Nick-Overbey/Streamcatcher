#!/bin/bash

# Script: ABR Network Baseline Tester
# Description: Runs ABR network readiness tests on all UP interfaces except enp7s0
# Output: Timestamped log with test results

read -p "Enter site name (e.g. customer name or location): " SITE_NAME
SITE_CLEAN=$(echo "$SITE_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_')

read -p "Enter iperf3 server IP (leave blank to skip iperf tests): " IPERF_SERVER
read -p "Enter ABR stream URL (manifest or segment): " TEST_URL
CDN_HOST=$(echo "$TEST_URL" | awk -F/ '{print $3}')

# Always log to ~/scripts, create directory if needed
LOGDIR="$HOME/scripts"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/abr_test_${SITE_CLEAN}_$(date +%Y-%m-%d_%H%M%S).log"

echo "ABR Network Test Log - $(date)" | tee "$LOGFILE"
echo "Site: $SITE_NAME" | tee -a "$LOGFILE"
echo "iperf3 Server: ${IPERF_SERVER:-[skipped]}" | tee -a "$LOGFILE"
echo "ABR Stream URL: $TEST_URL" | tee -a "$LOGFILE"
echo "CDN Host Extracted: $CDN_HOST" | tee -a "$LOGFILE"
echo "=========================================" | tee -a "$LOGFILE"

# Get all UP interfaces, excluding lo and enp7s0
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | while read -r iface; do
  if [[ "$iface" != "lo" && "$iface" != "enp7s0" ]] && ip link show "$iface" | grep -q "state UP"; then
    echo "$iface"
  fi
done)

if [[ -z "$interfaces" ]]; then
  echo "❌ No valid UP interfaces found (excluding enp7s0 and lo). Exiting." | tee -a "$LOGFILE"
  exit 1
fi

for iface in $interfaces; do
  echo -e "\n=========================================" | tee -a "$LOGFILE"
  echo "--- Testing interface: $iface ---" | tee -a "$LOGFILE"
  echo "=========================================" | tee -a "$LOGFILE"

  if [[ -n "$IPERF_SERVER" ]]; then
    echo -e "\n>>> Bandwidth Test with iperf3 (measures upload and download throughput to test server)" | tee -a "$LOGFILE"
    echo "Running download test (client to server)..." | tee -a "$LOGFILE"
    iperf3 -c "$IPERF_SERVER" -t 10 -B "$(ip -4 -o addr show $iface | awk '{print $4}' | cut -d/ -f1)" >> "$LOGFILE" 2>&1

    echo "Running upload test (server to client)..." | tee -a "$LOGFILE"
    iperf3 -c "$IPERF_SERVER" -t 10 -R -B "$(ip -4 -o addr show $iface | awk '{print $4}' | cut -d/ -f1)" >> "$LOGFILE" 2>&1
  fi

  echo -e "\n>>> Latency and Jitter Test with mtr to Google DNS (measures packet loss and timing consistency)" | tee -a "$LOGFILE"
  MTR_OUTPUT_GOOGLE=$(mktemp)
  sudo mtr -rwzbc 50 8.8.8.8 -i 0.2 -4 -T -o "LSD NB J W" > "$MTR_OUTPUT_GOOGLE" 2>&1
  cat "$MTR_OUTPUT_GOOGLE" | tee -a "$LOGFILE"

  JITTER=$(awk '/8\.8\.8\.8/ {print $(NF-1)}' "$MTR_OUTPUT_GOOGLE")
  echo -e "\n>>> Jitter Analysis (Google DNS)" | tee -a "$LOGFILE"
  printf "%-15s %-15s\n" "Category" "Range (ms)" | tee -a "$LOGFILE"
  printf "%-15s %-15s\n" "Excellent" "0–10" | tee -a "$LOGFILE"
  printf "%-15s %-15s\n" "Good" "11–20" | tee -a "$LOGFILE"
  printf "%-15s %-15s\n" "Marginal" "21–50" | tee -a "$LOGFILE"
  printf "%-15s %-15s\n" "Poor" ">50" | tee -a "$LOGFILE"

  jitter_value=${JITTER%.*}
  if [[ -n "$jitter_value" ]]; then
    if [[ $jitter_value -le 10 ]]; then
      echo "Jitter test result: ✅ Excellent (${JITTER} ms)" | tee -a "$LOGFILE"
    elif [[ $jitter_value -le 20 ]]; then
      echo "Jitter test result: ✅ Good (${JITTER} ms)" | tee -a "$LOGFILE"
    elif [[ $jitter_value -le 50 ]]; then
      echo "Jitter test result: ⚠️ Marginal (${JITTER} ms)" | tee -a "$LOGFILE"
    else
      echo "Jitter test result: ❌ Poor (${JITTER} ms)" | tee -a "$LOGFILE"
    fi
  else
    echo "Jitter test result: ⚠️ Could not parse jitter from MTR output." | tee -a "$LOGFILE"
  fi
  rm "$MTR_OUTPUT_GOOGLE"

  if [[ -n "$TEST_URL" ]]; then
    echo -e "\n>>> Latency Test with mtr to CDN (${CDN_HOST})" | tee -a "$LOGFILE"
    MTR_OUTPUT_CDN=$(mktemp)
    sudo mtr -rwzbc 50 "$CDN_HOST" -i 0.2 -4 -T -o "LSD NB J W" > "$MTR_OUTPUT_CDN" 2>&1
    cat "$MTR_OUTPUT_CDN" | tee -a "$LOGFILE"

    JITTER_CDN=$(awk 'NF > 0 && $(NF-1) ~ /^[0-9.]+$/ {jitter=$(NF-1)} END {print jitter}' "$MTR_OUTPUT_CDN")
    echo -e "\n>>> Jitter Analysis (CDN)" | tee -a "$LOGFILE"
    printf "%-15s %-15s\n" "Category" "Range (ms)" | tee -a "$LOGFILE"
    printf "%-15s %-15s\n" "Excellent" "0–10" | tee -a "$LOGFILE"
    printf "%-15s %-15s\n" "Good" "11–20" | tee -a "$LOGFILE"
    printf "%-15s %-15s\n" "Marginal" "21–50" | tee -a "$LOGFILE"
    printf "%-15s %-15s\n" "Poor" ">50" | tee -a "$LOGFILE"

    jitter_value_cdn=${JITTER_CDN%.*}
    if [[ -n "$jitter_value_cdn" ]]; then
      if [[ $jitter_value_cdn -le 10 ]]; then
        echo "Jitter test result: ✅ Excellent (${JITTER_CDN} ms)" | tee -a "$LOGFILE"
      elif [[ $jitter_value_cdn -le 20 ]]; then
        echo "Jitter test result: ✅ Good (${JITTER_CDN} ms)" | tee -a "$LOGFILE"
      elif [[ $jitter_value_cdn -le 50 ]]; then
        echo "Jitter test result: ⚠️ Marginal (${JITTER_CDN} ms)" | tee -a "$LOGFILE"
      else
        echo "Jitter test result: ❌ Poor (${JITTER_CDN} ms)" | tee -a "$LOGFILE"
      fi
    else
      echo "Jitter test result: ⚠️ Could not parse jitter from CDN MTR output." | tee -a "$LOGFILE"
    fi
    rm "$MTR_OUTPUT_CDN"

    if [[ "$TEST_URL" == https:* ]]; then
      echo -e "\n>>> Skipping HTTP latency test due to HTTPS: httping doesn't support SSL well" | tee -a "$LOGFILE"
    else
      echo -e "\n>>> HTTP Latency Test with httping (simulates ABR client latency fetching manifest/segments)" | tee -a "$LOGFILE"
      httping -c 20 -i 0.5 -G "$TEST_URL" >> "$LOGFILE" 2>&1
    fi

    echo -e "\n>>> Segment Fetch Test with curl (measures ABR segment fetch times)" | tee -a "$LOGFILE"
    printf "%-20s %-10s\n" "Response Time (ms)" "HTTP Status" | tee -a "$LOGFILE"
    PASS_COUNT=0
    for i in {1..10}; do
      curl_output=$(curl -s -w "%{time_total} %{http_code}" -o /dev/null "$TEST_URL")
      response_time=$(echo "$curl_output" | awk '{printf "%.0f", $1 * 1000}')
      http_code=$(echo "$curl_output" | awk '{print $2}')
      printf "%-20s %-10s\n" "$response_time" "$http_code" | tee -a "$LOGFILE"
      if [[ "$http_code" == "200" ]] && [[ "$response_time" -lt 500 ]]; then
        ((PASS_COUNT++))
      fi
    done

    if [[ $PASS_COUNT -ge 8 ]]; then
      echo "Segment fetch test: ✅ PASS ($PASS_COUNT/10 within threshold)" | tee -a "$LOGFILE"
    else
      echo "Segment fetch test: ❌ FAIL ($PASS_COUNT/10 met threshold)" | tee -a "$LOGFILE"
    fi
  fi

  echo -e "\n>>> Bandwidth Snapshot with ifstat (monitors real-time throughput)" | tee -a "$LOGFILE"
  ifstat -i "$iface" 0.5 5 >> "$LOGFILE" 2>&1
done

echo -e "\n=========================================" | tee -a "$LOGFILE"
echo "✅ All tests completed. Review results above for each interface." | tee -a "$LOGFILE"
echo "Log saved to $LOGFILE" | tee -a "$LOGFILE"
exit 0
