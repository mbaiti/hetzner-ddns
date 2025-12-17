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
  # KORREKTUR HIER: Endpunkt geändert zu /v1/zones/$ZONE_ID/rrsets
  RECORD_INFO=$(curl -s -X GET \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    "https://api.hetzner.cloud/v1/zones/$ZONE_ID/rrsets") # <<< Hier ist die Änderung

  # Build full hostname for matching in API response.
  # For Apex record ('@'), Hetzner API's 'name' field is the zone name itself.
  FULL_HOSTNAME_FOR_MATCH="$HETZNER_DNS_RECORD_NAME"
  if [ "$HETZNER_DNS_RECORD_NAME" == "@" ]; then
    FULL_HOSTNAME_FOR_MATCH="$HETZNER_DNS_ZONE_NAME"
  else
    FULL_HOSTNAME_FOR_MATCH="$HETZNER_DNS_RECORD_NAME.$HETZNER_DNS_ZONE_NAME"
  fi

  RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.rrsets[] | select(.name == "'"$FULL_HOSTNAME_FOR_MATCH"'") | select(.type == "A") | .id')

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

  log "INFO: Update record ‘$HETZNER_DNS_RECORD_NAME’ to $IP_ADDRESS in zone '$HETZNER_DNS_ZONE_NAME'."

  # Build full hostname for the 'name' parameter in the PATCH request body
  FULL_HOSTNAME_FOR_PATCH="$HETZNER_DNS_RECORD_NAME"
  if [ "$HETZNER_DNS_RECORD_NAME" == "@" ]; then
    FULL_HOSTNAME_FOR_PATCH="$HETZNER_DNS_ZONE_NAME"
  else
    FULL_HOSTNAME_FOR_PATCH="$HETZNER_DNS_RECORD_NAME.$HETZNER_DNS_ZONE_NAME"
  fi

  # KORREKTUR HIER: Endpunkt geändert zu /v1/zones/$ZONE_ID/rrsets/$RECORD_ID
  RESPONSE=$(curl -s -X PATCH \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "name": "'"$FULL_HOSTNAME_FOR_PATCH"'",
          "type": "A",
          "records": [
            { "value": "'"$IP_ADDRESS"'" }
          ],
          "ttl": 300
        }' \
    "https://api.hetzner.cloud/v1/zones/$ZONE_ID/rrsets/$RECORD_ID") # <<< Hier ist die Änderung

  if echo "$RESPONSE" | grep -q '"rrset"'; then
    log "INFO: DNS entry for $HETZNER_DNS_RECORD_NAME successfully updated to $IP_ADDRESS."
    return 0
  else
    log "ERROR: Error updating DNS record: $RESPONSE"
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
log "INFO: DNS Record ID for '$HETZNER_DNS_RECORD_NAME': $RECORD_ID"

while true; do
  PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com)

  if [ -z "$PUBLIC_IP" ]; then
    log "WARNING: Could not determine public IP address. Please try again."
  elif [ "$PUBLIC_IP" != "$LAST_KNOWN_PUBLIC_IP" ]; then
    log "INFO: Public IP address has changed from $LAST_KNOWN_PUBLIC_IP to $PUBLIC_IP."
    if update_record "$ZONE_ID" "$RECORD_ID" "$PUBLIC_IP"; then
      LAST_KNOWN_PUBLIC_IP="$PUBLIC_IP"
    else
      log "ERROR: Failed to update DNS record. Try again at the next interval."
    fi
  else
    log "DEBUG: Public IP address is $PUBLIC_IP, no change since last check."
  fi

  sleep "$CHECK_INTERVAL_SECONDS"
done
