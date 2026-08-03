#!/bin/sh
# Фоновый цикл: раз в 6 часов пересобирает /etc/nginx/tls-cert.conf и делает
# graceful reload. Нужен, чтобы nginx без даунтайма подхватил:
#   * первый боевой сертификат вместо самоподписанной заглушки;
#   * продлённый certbot'ом сертификат.
#
# Запускается штатным /docker-entrypoint.sh ДО exec nginx, поэтому уходит в фон
# и переживает подмену процесса на nginx.
set -eu

(
    while :; do
        sleep 6h
        /docker-entrypoint.d/05-tls-bootstrap.sh || true
        nginx -s reload || true
    done
) &

echo "40-cert-reload-loop: certificate reload loop started (every 6h)"
