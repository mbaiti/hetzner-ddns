⚠️ THIS PROJECT IS UNDER DEVELOPMENT ⚠️

# Hetzner Dynamic DNS Update via Cloud API

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker Pulls](https://img.shields.io/docker/pulls/mbaiti/hetzner-ddns.svg)](https://hub.docker.com/r/mbaiti/hetzner-ddns)

A slim Dynamic DNS Updater for Hetzner DNS entries, which uses the new Hetzner Cloud API. This tool monitors your public IP address and automatically updates a specific A-record in your Hetzner DNS zone if the IP address changes. Ideal for home servers or other dynamic IP environments.

This project is an adapted version of the original `filiparag/hetzner_ddns`, but has been completely optimized for operation in a Docker container with environment variables.

## Features

*   **Uses the new Hetzner Cloud API:** Compatible with current Hetzner DNS management.
*   **Containerized:** Runs reliably and isolated in a Docker container.
*   **Configuration via Environment Variables:** Simple and secure configuration with `docker-compose`.
*   **Automatic IP Detection:** Regularly checks the public IPv4 address.
*   **Minimalist:** Slim Alpine Linux-based image and pure shell script for low resource consumption.
*   **Reliable:** Updates the DNS entry only when the IP changes.

## Background on API Transition

Hetzner has integrated the management of its DNS zones into the Hetzner Cloud API. The old dedicated Hetzner DNS Console API is no longer the recommended method. This script was developed to support this new API structure. This requires using an API token from the Hetzner Cloud Console and adapted API endpoints for DNS management.

## Prerequisites

*   Docker and Docker Compose installed
*   A Hetzner Cloud account
*   A DNS zone migrated to the Hetzner Cloud Console (if it was originally created in the DNS Console).

## Setup

### Generate API Token

1.  Log in to your [Hetzner Cloud Console](https://console.hetzner.cloud/).
2.  Navigate to "Access" -> "API Tokens".
3.  Create a new API Token. Give it a descriptive name (e.g., "hetzner-dyndns").
4.  Ensure that the token has at least the permission to **read and write DNS records**.
5.  Copy the generated token. It will be needed for the `HETZNER_CLOUD_API_TOKEN` environment variable.

### Prepare DNS Zone and Record

1.  Ensure that the DNS zone you want to update is visible and manageable in the Hetzner Cloud Console. If not, you may need to migrate it manually.
2.  Create an A-record for the hostname you want to update (e.g., `myhome.example.com` or `@` for the domain itself), and provide a placeholder value (e.g., `127.0.0.1`). The script will overwrite this value later.

### Docker-Compose Example

```yaml
services:
  hetzner-ddns:
    image: mbaiti/hetzner-ddns:latest
    container_name: hetzner-ddns
    restart: unless-stopped
    environment:
      - HETZNER_CLOUD_API_TOKEN=your_hetzner_cloud_api_token
      - HETZNER_DNS_ZONE_NAME=your-domain.com #The name of your DNS zone (e.g., "example.com")
      - HETZNER_DNS_RECORD_NAME=subdomain_or_@ #e.g. "myhost" for myhost.your_domain.com or "@" for your_domain.com
      - CHECK_INTERVAL_SECONDS=300
```

### Logging
The script outputs logs with timestamps and the status of operations.

* **INFO:** For normal operations and successful updates.
* **DEBUG:** More detailed information (e.g., when no IP change is detected). Not used in the current version, but could be extended if needed.
* **WARNING:** For non-critical issues (e.g., IP detection failed).
* **ERROR:** For critical errors (e.g., API errors, missing configuration).
