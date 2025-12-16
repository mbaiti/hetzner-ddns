# Basis-Image: Ein kleines Image mit Bash und curl
FROM alpine:latest

# Arbeitsverzeichnis im Container setzen
WORKDIR /app

# Installiere curl, bash und jq
RUN apk add --no-cache curl bash jq

# Das angepasste Skript in den Container kopieren
COPY hetzner_ddns_cloud_api.sh .

# Das Skript ausführbar machen
RUN chmod +x hetzner_ddns_cloud_api.sh

# Den Befehl definieren, der beim Start des Containers ausgeführt werden soll
CMD ["/app/hetzner_ddns_cloud_api.sh"]
