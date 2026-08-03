#!/bin/sh
# Выбирает, какой сертификат подключить в nginx:
#   * боевой Let's Encrypt, если он уже выпущен;
#   * иначе - самоподписанную заглушку, чтобы nginx вообще смог стартовать
#     (без неё директива ssl_certificate указывает на несуществующий файл и nginx падает).
set -eu

DOMAIN="${DOMAIN:-localhost}"
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"
DUMMY_DIR="/etc/nginx/dummy-certs"
OUT="/etc/nginx/tls-cert.conf"

if [ -f "${LIVE_DIR}/fullchain.pem" ] && [ -f "${LIVE_DIR}/privkey.pem" ]; then
    CERT="${LIVE_DIR}/fullchain.pem"
    KEY="${LIVE_DIR}/privkey.pem"
    echo "05-tls-bootstrap: using Let's Encrypt certificate for ${DOMAIN}"
else
    CERT="${DUMMY_DIR}/fullchain.pem"
    KEY="${DUMMY_DIR}/privkey.pem"
    if [ ! -f "${CERT}" ] || [ ! -f "${KEY}" ]; then
        mkdir -p "${DUMMY_DIR}"
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout "${KEY}" -out "${CERT}" \
            -subj "/CN=${DOMAIN}" \
            -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN}" >/dev/null 2>&1
        chmod 600 "${KEY}"
    fi
    echo "05-tls-bootstrap: WARNING - no Let's Encrypt cert for ${DOMAIN}, serving self-signed placeholder."
    echo "05-tls-bootstrap: run ./nginx/scripts/init-letsencrypt.sh to issue a real certificate."
fi

cat > "${OUT}" <<EOF
ssl_certificate     ${CERT};
ssl_certificate_key ${KEY};
EOF
