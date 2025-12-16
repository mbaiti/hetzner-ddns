#!/bin/bash

# Konfiguration über Umgebungsvariablen
HETZNER_CLOUD_API_TOKEN=${HETZNER_CLOUD_API_TOKEN} # Startet mit hcloud_
HETZNER_DNS_ZONE_NAME=${HETZNER_DNS_ZONE_NAME} # Z.B. "example.com"
HETZNER_DNS_RECORD_NAME=${HETZNER_DNS_RECORD_NAME} # Z.B. "myhost" oder "@" für die Zone selbst
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL_SECONDS:-300}

# Logging-Funktion
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Überprüfen, ob alle notwendigen Umgebungsvariablen gesetzt sind
if [ -z "$HETZNER_CLOUD_API_TOKEN" ] || [ -z "$HETZNER_DNS_ZONE_NAME" ] || [ -z "$HETZNER_DNS_RECORD_NAME" ]; then
  log "ERROR: EINE ODER MEHRERE NOTWENDIGE UMWELTVARIABLEN FEHLEN!"
  log "ERROR: Bitte HETZNER_CLOUD_API_TOKEN, HETZNER_DNS_ZONE_NAME und HETZNER_DNS_RECORD_NAME setzen."
  exit 1
fi

log "Hetzner DynDNS Updater gestartet."
log "Prüfintervall: $CHECK_INTERVAL_SECONDS Sekunden."
log "DNS Zone Name: $HETZNER_DNS_ZONE_NAME"
log "DNS Record Name: $HETZNER_DNS_RECORD_NAME"

# Funktion zum Abrufen der Zone ID
get_zone_id() {
  ZONE_INFO=$(curl -s -X GET \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    "https://api.hetzner.cloud/v1/dns_zones?name=$HETZNER_DNS_ZONE_NAME")

  ZONE_ID=$(echo "$ZONE_INFO" | jq -r '.dns_zones[] | select(.name == "'"$HETZNER_DNS_ZONE_NAME"'") | .id')

  if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    log "ERROR: DNS Zone '$HETZNER_DNS_ZONE_NAME' konnte nicht gefunden werden oder API-Anfrage fehlgeschlagen: $ZONE_INFO"
    return 1
  fi
  echo "$ZONE_ID"
}

# Funktion zum Abrufen der Record ID
get_record_id() {
  local ZONE_ID=$1
  RECORD_INFO=$(curl -s -X GET \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    "https://api.hetzner.cloud/v1/dns_records?zone_id=$ZONE_ID")

  # Konstruiere den vollen Hostnamen, wie er im API-Response erscheinen sollte
  # Wenn HETZNER_DNS_RECORD_NAME "@" ist, ist der Name der Zone der vollständige Hostname.
  # Andernfalls ist es "RECORD_NAME.ZONE_NAME".
  FULL_HOSTNAME="$HETZNER_DNS_RECORD_NAME"
  if [ "$HETZNER_DNS_RECORD_NAME" != "@" ]; then
    FULL_HOSTNAME="$HETZNER_DNS_RECORD_NAME.$HETZNER_DNS_ZONE_NAME"
  fi

  RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.dns_records[] | select(.name == "'"$FULL_HOSTNAME"'") | select(.type == "A") | .id')

  if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    log "ERROR: DNS Record '$HETZNER_DNS_RECORD_NAME' (A-Record) in Zone '$HETZNER_DNS_ZONE_NAME' konnte nicht gefunden werden oder API-Anfrage fehlgeschlagen: $RECORD_INFO"
    return 1
  fi
  echo "$RECORD_ID"
}

# Funktion zum Aktualisieren des Records
update_record() {
  local ZONE_ID=$1
  local RECORD_ID=$2
  local IP_ADDRESS=$3

  log "INFO: Aktualisiere Record '$HETZNER_DNS_RECORD_NAME' auf $IP_ADDRESS in Zone '$HETZNER_DNS_ZONE_NAME'."

  RESPONSE=$(curl -s -X PUT \
    -H "Authorization: Bearer $HETZNER_CLOUD_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "zone_id": '$ZONE_ID',
          "type": "A",
          "name": "'"$HETZNER_DNS_RECORD_NAME"'",
          "value": "'"$IP_ADDRESS"'",
          "ttl": 300
        }' \
    "https://api.hetzner.cloud/v1/dns_records/$RECORD_ID")

  if echo "$RESPONSE" | grep -q '"dns_record"'; then
    log "INFO: DNS-Eintrag für $HETZNER_DNS_RECORD_NAME erfolgreich auf $IP_ADDRESS aktualisiert."
    return 0
  else
    log "ERROR: Fehler beim Aktualisieren des DNS-Eintrags: $RESPONSE"
    return 1
  fi
}

LAST_KNOWN_PUBLIC_IP=""

# Initialisierung: Zone und Record IDs abrufen
ZONE_ID=$(get_zone_id)
if [ $? -ne 0 ]; then exit 1; fi # Skript beenden, wenn Zone nicht gefunden
log "INFO: DNS Zone ID für '$HETZNER_DNS_ZONE_NAME': $ZONE_ID"

RECORD_ID=$(get_record_id "$ZONE_ID")
if [ $? -ne 0 ]; then exit 1; fi # Skript beenden, wenn Record nicht gefunden
log "INFO: DNS Record ID für '$HETZNER_DNS_RECORD_NAME': $RECORD_ID"

while true; do
  PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com)

  if [ -z "$PUBLIC_IP" ]; then
    log "WARNING: Konnte öffentliche IP-Adresse nicht ermitteln. Wiederhole den Versuch."
  elif [ "$PUBLIC_IP" != "$LAST_KNOWN_PUBLIC_IP" ]; then
    log "INFO: Öffentliche IP-Adresse hat sich geändert von $LAST_KNOWN_PUBLIC_IP zu $PUBLIC_IP."
    if update_record "$ZONE_ID" "$RECORD_ID" "$PUBLIC_IP"; then
      LAST_KNOWN_PUBLIC_IP="$PUBLIC_IP"
    else
      log "ERROR: Aktualisierung des DNS-Records fehlgeschlagen. Versuche es beim nächsten Intervall erneut."
    fi
  else
    log "DEBUG: Öffentliche IP-Adresse ist $PUBLIC_IP, keine Änderung seit letzter Prüfung."
  fi

  sleep "$CHECK_INTERVAL_SECONDS"
done
