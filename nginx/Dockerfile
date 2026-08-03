FROM nginx:1.27-alpine

# openssl нужен для самоподписанной заглушки до выпуска боевого сертификата.
RUN apk add --no-cache openssl tzdata

# Шаблон конфига (обрабатывается штатным 20-envsubst-on-templates.sh)
COPY templates/ /etc/nginx/templates/

# Сниппет с proxy_set_header для всех upstream'ов.
COPY conf/proxy_backend.conf /etc/nginx/proxy_backend.conf

# Статика, отдаваемая самим nginx (favicon/логотип для страниц ошибок).
COPY static/ /usr/share/nginx/html/static/

# Стоковый конфиг из базового образа не нужен - его целиком заменяет шаблон.
RUN rm -f /etc/nginx/conf.d/default.conf

# Скрипты штатного entrypoint'а nginx:
#   05 - выбор сертификата (боевой или самоподписанная заглушка) до старта nginx;
#   40 - фоновый цикл перечитывания сертификатов.
# ВАЖНО: не задавать command:/CMD вида "sh -c ...", иначе /docker-entrypoint.sh
# не увидит первым аргументом "nginx" и пропустит эти скрипты вместе с envsubst.
COPY entrypoint/05-tls-bootstrap.sh /docker-entrypoint.d/05-tls-bootstrap.sh
COPY entrypoint/40-cert-reload-loop.sh /docker-entrypoint.d/40-cert-reload-loop.sh
RUN chmod +x /docker-entrypoint.d/05-tls-bootstrap.sh \
             /docker-entrypoint.d/40-cert-reload-loop.sh

EXPOSE 80 443

STOPSIGNAL SIGQUIT
