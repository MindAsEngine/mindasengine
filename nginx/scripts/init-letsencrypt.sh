#!/bin/sh
# Первичный выпуск сертификата Let's Encrypt.
#
# Запускать ОДИН раз на сервере, где домен из .env реально указывает
# A/AAAA-записью на этот хост и порт 80 доступен из интернета.
# Дальнейшее продление делает контейнер certbot автоматически.
#
#   ./nginx/scripts/init-letsencrypt.sh            # боевой сертификат
#   STAGING=1 ./nginx/scripts/init-letsencrypt.sh  # тестовый (без лимитов Let's Encrypt)
#
# Поддомен www включается в запрос, только если у него есть DNS-запись:
# Let's Encrypt валидирует все имена разом, и NXDOMAIN по одному отменяет
# выпуск целиком. Принудительно управлять можно переменной WITH_WWW=1|0.
set -eu

cd "$(dirname "$0")/../.."

if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
fi

DOMAIN="${DOMAIN:?DOMAIN не задан - создайте .env из .env.example}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL не задан - создайте .env из .env.example}"
STAGING="${STAGING:-0}"

# Есть ли у имени A/AAAA-запись. Без getent проверить не можем - тогда пробуем как есть.
resolves() {
    if command -v getent >/dev/null 2>&1; then
        getent ahosts "$1" >/dev/null 2>&1
    else
        return 0
    fi
}

if ! resolves "${DOMAIN}"; then
    echo "!! ${DOMAIN} не резолвится. Проверьте A-запись домена, без неё выпуск невозможен." >&2
    exit 1
fi

DOMAIN_ARGS="-d ${DOMAIN}"
WWW_NOTE=""
case "${WITH_WWW:-auto}" in
    1)
        DOMAIN_ARGS="${DOMAIN_ARGS} -d www.${DOMAIN}"
        ;;
    0)
        WWW_NOTE=" (www исключён явно: WITH_WWW=0)"
        ;;
    *)
        if resolves "www.${DOMAIN}"; then
            DOMAIN_ARGS="${DOMAIN_ARGS} -d www.${DOMAIN}"
        else
            WWW_NOTE=" (www пропущен: нет DNS-записи)"
            echo ">> www.${DOMAIN} не резолвится - исключаю из запроса."
            echo ">> Если поддомен нужен, заведите A-запись www и перевыпустите сертификат."
        fi
        ;;
esac

STAGING_ARG=""
if [ "${STAGING}" != "0" ]; then
    STAGING_ARG="--staging"
    echo ">> STAGING-режим: сертификат будет невалидным для браузера, но не тратит лимиты."
else
    echo ">> БОЕВОЙ режим. Лимит Let's Encrypt: 5 неудачных проверок на домен в час."
    echo ">> Если не уверены в DNS или доступности порта 80 - сначала STAGING=1."
fi

echo ">> Домен: ${DOMAIN}${WWW_NOTE}, email: ${CERTBOT_EMAIL}"

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
# shellcheck disable=SC2086
docker compose run --rm --entrypoint certbot certbot \
    certonly --webroot -w /var/www/certbot \
    ${STAGING_ARG} \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email \
    --non-interactive \
    ${DOMAIN_ARGS}

echo ">> Перезапускаю nginx, чтобы он подхватил боевой сертификат..."
docker compose restart nginx

echo ">> Готово. Проверка: curl -I https://${DOMAIN}"
