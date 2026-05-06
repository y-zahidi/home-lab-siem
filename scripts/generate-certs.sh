#!/usr/bin/env bash
# Generate Wazuh self-signed certs for the home-lab-siem stack.
# Wraps the official Wazuh certs-tool so we don't have to think about it.
#
# Usage: ./scripts/generate-certs.sh
#
# Output: config/wazuh_indexer_ssl_certs/* (gitignored)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${ROOT_DIR}/config/wazuh_indexer_ssl_certs"
TOOL_VERSION="4.7.4"

mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

if [[ -f "root-ca.pem" ]]; then
  echo "[*] Certificates already exist in ${CERT_DIR}. Refusing to overwrite."
  echo "    Delete the directory first if you want to regenerate."
  exit 0
fi

echo "[*] Downloading Wazuh certs-tool ${TOOL_VERSION}..."
curl -sSL -o wazuh-certs-tool.sh \
  "https://packages.wazuh.com/${TOOL_VERSION%.*}/wazuh-certs-tool.sh"
curl -sSL -o config.yml \
  "https://packages.wazuh.com/${TOOL_VERSION%.*}/config.yml"

chmod +x wazuh-certs-tool.sh

echo "[*] Generating certs..."
./wazuh-certs-tool.sh -A

echo "[*] Moving certs to expected layout..."
mv wazuh-certificates/* .
rm -rf wazuh-certificates wazuh-certificates.tar wazuh-certs-tool.sh config.yml

echo "[+] Done. Certs are in: ${CERT_DIR}"
echo "    Now run: docker compose up -d"
