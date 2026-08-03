#!/bin/sh
# Первичный выпуск сертификата Let's Encrypt.
#
# Запускать ОДИН раз на сервере, где домен из .env реально указывает
# A/AAAA-записью на этот хост и порт 80 доступен из интернета.
# Дальнейшее продление делает контейнер certbot автоматически.
#
#   ./nginx/scripts/init-letsencrypt.sh            # боевой сертификат
#   STAGING=1 ./nginx/scripts/init-letsencrypt.sh  # тестовый (без лимитов Let's Encrypt)
set -eu

cd "$(dirname "$0")/../.."

if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
fi

DOMAIN="${DOMAIN:?DOMAIN не задан - создайте .env из .env.example}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL не задан - создайте .env из .env.example}"
STAGING="${STAGING:-0}"

STAGING_ARG=""
if [ "${STAGING}" != "0" ]; then
    STAGING_ARG="--staging"
    echo ">> STAGING-режим: сертификат будет невалидным для браузера, но не тратит лимиты."
fi

echo ">> Домен: ${DOMAIN} (+ www.${DOMAIN}), email: ${CERTBOT_EMAIL}"

echo ">> Поднимаю nginx (нужен для ACME http-01 challenge)..."
docker compose up -d nginx

echo ">> Жду, пока nginx начнёт отвечать..."
i=0
while [ "$i" -lt 30 ]; do
    if docker compose exec -T nginx wget -q -O /dev/null http://127.0.0.1/healthz 2>/dev/null; then
        break
    fi
    i=$((i + 1))
    sleep 2
done

echo ">> Запрашиваю сертификат..."
docker compose run --rm --entrypoint certbot certbot \
    certonly --webroot -w /var/www/certbot \
    ${STAGING_ARG} \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email \
    --non-interactive \
    -d "${DOMAIN}" -d "www.${DOMAIN}"

echo ">> Перезапускаю nginx, чтобы он подхватил боевой сертификат..."
docker compose restart nginx

echo ">> Готово. Проверка: curl -I https://${DOMAIN}"
