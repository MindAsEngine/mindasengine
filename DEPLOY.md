# Развёртывание mindasengine

## Схема

```text
              :80 / :443
                  |
             [  nginx  ]  <- TLS, единственный порт наружу
              /        \
   /  /static/*      /api/, /moderator/, /images/, /news, /projects
        |                          |
[ frontend :3000 ]        [ backend :1337 ]
 (serve -s build)          (Spring Boot)
                                   |
                          [ postgres :5432 ]

              [ certbot ]  <- продление сертификатов, общий том с nginx
```

Наружу открыты только 80 и 443. Порты 3000 / 1337 / 5432 доступны
только внутри compose-сети `default` по именам сервисов.

## Первый запуск

1. Настроить окружение:

   ```sh
   cp .env.example .env                       # DOMAIN, CERTBOT_EMAIL, TZ
   cp environment.env.example environment.env # пароли БД, JWT-секрет
   ```

   В `environment.env` поле `ALLOWED.ORIGINS` должно совпадать с доменом из `.env`.

2. Проверить, что DNS-запись домена (`DOMAIN` и `www.DOMAIN`) указывает на этот
   сервер и порт 80 открыт в фаерволе — без этого Let's Encrypt не выпустит сертификат.

3. Собрать и поднять:

   ```sh
   docker compose up -d --build
   ```

   На этом шаге nginx стартует с **самоподписанной** заглушкой — сайт уже
   работает, но браузер ругается на сертификат.

4. Выпустить боевой сертификат:

   ```sh
   ./nginx/scripts/init-letsencrypt.sh
   ```

   Сначала можно прогнать тестовый выпуск, чтобы не сжечь лимиты Let's Encrypt
   (5 неудачных попыток на домен в час):

   ```sh
   STAGING=1 ./nginx/scripts/init-letsencrypt.sh
   ```

   После успешного staging-прогона удалить тестовый сертификат и выпустить боевой:

   ```sh
   docker compose run --rm --entrypoint certbot certbot delete --cert-name "$DOMAIN"
   ./nginx/scripts/init-letsencrypt.sh
   ```

## Автопродление

Контейнер `certbot` каждые 12 часов выполняет `certbot renew`. Сертификат
обновляется, когда до истечения остаётся меньше 30 дней — то есть примерно раз
в 60 дней, никаких cron-задач на хосте не нужно.

Контейнер `nginx` раз в 6 часов перечитывает пути к сертификатам и делает
`nginx -s reload`, поэтому обновлённый сертификат подхватывается без даунтайма.

Проверить состояние:

```sh
docker compose exec certbot certbot certificates
docker compose logs certbot
```

Ручное продление (для проверки, что всё работает):

```sh
docker compose run --rm --entrypoint certbot certbot renew --dry-run
```

## Проверка связности

```sh
# фронт -> nginx
curl -Ik https://$DOMAIN/

# nginx -> backend
curl -k https://$DOMAIN/news
curl -k https://$DOMAIN/projects

# backend -> база
docker compose exec mind-as-engine-database psql -U postgres -d mindasengine -c '\dt'

# статусы healthcheck'ов
docker compose ps
```

Если `docker compose ps` показывает `healthy` у всех четырёх сервисов —
цепочка nginx -> frontend / backend -> postgres рабочая.

## Локальная проверка без домена

```sh
# в .env
DOMAIN=localhost
```

```sh
docker compose up -d --build
curl -k https://localhost/news
```

Сертификат будет самоподписанный (`curl -k`, в браузере — предупреждение).
Выпускать Let's Encrypt для `localhost` нельзя.

## Куда ходит фронт

`frontend/src/axios.js` отдаёт `baseURL = process.env.REACT_APP_API_URL || ''`.
Пустая строка означает относительные пути (`/news`, `/api/auth/signin`,
`/images/<file>`), которые уходят на тот же origin и разруливаются nginx.
Абсолютный `http://домен:1337` использовать нельзя: на HTTPS-странице браузер
блокирует такой запрос как mixed content.

Значение вшивается в бандл на этапе сборки через build-arg `REACT_APP_API_URL`
в `compose.yml`. После его изменения нужен `docker compose build mind-as-engine-frontend`.
