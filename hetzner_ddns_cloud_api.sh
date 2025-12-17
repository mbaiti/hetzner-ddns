#!/bin/bash
set -x

# Environment Variables
HETZNER_CLOUD_API_TOKEN=${HETZNER_CLOUD_API_TOKEN}
HETZNER_DNS_ZONE_NAME=${HETZNER_DNS_ZONE_NAME} # E.g., "example.com"
HETZNER_DNS_RECORD_NAME=${HETZNER_DNS_RECORD_NAME} # E.g., "myhost" or "@" for the zone itself
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL_SECONDS:-300}

# Logging
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Environment Variables check
if [ -z "$HETZNER_CLOUD_API_TOKEN" ] || [ -z "$HETZNER_DNS_ZONE_NAME" ] || [ -z "$HETZNER_DNS_RECORD_NAME" ]; then
  log "ERROR: ONE OR MORE NECESSARY ENVIRONMENT VARIABLES ARE MISSING!"
  log "ERROR: Please set HETZNER_CLOUD_API_TOKEN, HETZNER_DNS_ZONE_NAME, and HETZNER_DNS_RECORD_NAME."
  exit 1
fi

log "Hetzner Dynamic DNS Updater started."
log "Check interval: $CHECK_INTERVAL_SECONDS Seconds."
log "DNS Zone Name: $HETZNER_DNS_ZONE_NAME"
log "DNS Record Name: $HETZNER_DNS_RECORD_NAME"

# Check Zone ID
get_zone_id() {
  ZONE_INFO=$(curl -s -X GET \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones?name=$HETZNER_DNS_ZONE_NAME")

  ZONE_ID=$(echo "$ZONE_INFO" | jq -r '.zones[] | select(.name == "'"$HETZNER_DNS_ZONE_NAME"'") | .id')

  if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    log "ERROR: DNS zone ‘$HETZNER_DNS_ZONE_NAME’ could not be found or API request failed: $ZONE_INFO"
    return 1
  fi
  echo "$ZONE_ID"
}

# Get Record ID
get_record_id() {
  local ZONE_ID=$1
  RECORD_INFO=$(curl -s -X GET \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones/$ZONE_ID/rrsets")

  RECORD_NAME_TO_MATCH="$HETZNER_DNS_RECORD_NAME"
  if [ "$HETZNER_DNS_RECORD_NAME" == "@" ]; then
    RECORD_NAME_TO_MATCH="@"
  fi

  RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.rrsets[] | select(.name == "'"$RECORD_NAME_TO_MATCH"'") | select(.type == "A") | .id')

  if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    log "ERROR: DNS record ‘$HETZNER_DNS_RECORD_NAME’ (A-Record) in zone ‘$HETZNER_DNS_ZONE_NAME’ could not be found or API request failed: $RECORD_INFO"
    return 1
  fi
  echo "$RECORD_ID"
}

# Update record
update_record() {
  local ZONE_ID=$1
  local RECORD_ID=$2
  local IP_ADDRESS=$3

  log "INFO: Attempting to update record ‘$HETZNER_DNS_RECORD_NAME’ to $IP_ADDRESS in zone '$HETZNER_DNS_ZONE_NAME'."

  RR_NAME=$(echo "$RECORD_ID" | cut -d'/' -f1)
  RR_TYPE=$(echo "$RECORD_ID" | cut -d'/' -f2)

  RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "records": [
            { "value": "'"$IP_ADDRESS"'" }
          ]
        }' \
    "https://api.hetzner.cloud/v1/zones/$ZONE_ID/rrsets/$RR_NAME/$RR_TYPE/actions/set_records")

  if echo "$RESPONSE" | grep -q '"action"'; then 
    ACTION_STATUS=$(echo "$RESPONSE" | jq -r '.action.status')
    if [ "$ACTION_STATUS" == "running" ] || [ "$ACTION_STATUS" == "success" ]; then
      log "INFO: DNS entry for $HETZNER_DNS_RECORD_NAME successfully updated to $IP_ADDRESS. Action Status: $ACTION_STATUS"
      return 0
    else
      log "ERROR: DNS update action failed. Response: $RESPONSE"
      return 1
    fi
  else
    log "ERROR: Failed to update DNS record. Unexpected API response: $RESPONSE"
    return 1
  fi
}

LAST_KNOWN_PUBLIC_IP=""

# Get Zone ID
ZONE_ID=$(get_zone_id)
if [ $? -ne 0 ]; then exit 1; fi
log "INFO: DNS Zone ID for '$HETZNER_DNS_ZONE_NAME': $ZONE_ID"

# Get Record ID
RECORD_ID=$(get_record_id "$ZONE_ID")
if [ $? -ne 0 ]; then exit 1; fi
log "INFO: Found DNS Record ID for '$HETZNER_DNS_RECORD_NAME': $RECORD_ID"

while true; do
  PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com)

  if [ -z "$PUBLIC_IP" ]; then
    log "WARNING: Could not determine public IP address. Retrying."
  elif [ "$PUBLIC_IP" != "$LAST_KNOWN_PUBLIC_IP" ]; then
    log "INFO: Public IP address has changed from $LAST_KNOWN_PUBLIC_IP to $PUBLIC_IP."
    if update_record "$ZONE_ID" "$RECORD_ID" "$PUBLIC_IP"; then
      LAST_KNOWN_PUBLIC_IP="$PUBLIC_IP"
    else
      log "ERROR: Failed to update DNS record. Will retry at the next interval."
    fi
  else
    log "DEBUG: Public IP address is $PUBLIC_IP, no change since last check."
  fi

  sleep "$CHECK_INTERVAL_SECONDS"
done
