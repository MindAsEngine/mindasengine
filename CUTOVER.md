# Переход на nginx + TLS на живом сервере

Одноразовый runbook. Штатная эксплуатация — [DEPLOY.md](DEPLOY.md).

Исходное состояние сервера: ветка `deploy` @ `b5ce3c8`, незавершённый merge
(`compose.yml` в состоянии `both modified`), незакоммиченная правка
`frontend/src/axios.js`. Порт 80 занят контейнером фронта напрямую, nginx нет,
TLS нет.

## Состояние репозиториев

Сервер и локальная разработка смотрят в **разные** GitHub-репозитории, истории
не имеют общего предка:

| где | remote | master | актуальная ветка |
| --- | --- | --- | --- |
| сервер | `github.com/ProdamGaraj/mindasengine` | `c9ace25` (2024-04-30) | `deploy` @ `b5ce3c8` (2024-04-30) |
| локально | `github.com/MindAsEngine/mindasengine` | `bcb7899` «mindasengine rebirth» (2024-01-21) | — |

Локальный `master` создан заново в январе и по содержимому **старше** боевого
`deploy`. Различий в коде оказалось всего 8 файлов, из них 4 — правки, которые
живут только на сервере и были бы молча откачены при деплое с `master`:

| файл | что было потеряно |
| --- | --- |
| `NewsRepository.java`, `NewsService.java` | `findByPublicationLessThanEqualOrderByPublicationDesc` — сортировка новостей по дате убыванию |
| `frontend/public/index.html` | meta description компании вместо заглушки «Web site created using create-react-app» |
| `frontend/src/component/footer/footer.scss` | `height: 20px` у футера |
| `frontend/src/component/project/projects.scss` | `border-radius: 15px` у картинок проектов |

Все четыре восстановлены в рабочем дереве командой
`git checkout server/deploy -- <файлы>`. После этого разница с `deploy`
состоит только из осознанных правок (nginx, TLS, Dockerfile'ы, compose,
axios.js, `frontend/.gitignore`).

Незакоммиченная правка `axios.js` на сервере — `http://72.56.32.151:1337`
(бэкенд по голому IP). Переносить не нужно: её заменяет относительный baseURL.

Восстановить состояние сервера локально:

```sh
git fetch СЕРВЕР/mae-deploy.bundle 'refs/heads/*:refs/remotes/server/*'
git diff server/deploy HEAD
```

---

## 0. Бэкап (до любых действий)

Ничего не останавливает, сайт продолжает работать.

```sh
cd <каталог проекта на сервере>
STAMP=$(date +%F-%H%M)

# 1. База
docker exec mind-as-engine-database pg_dump -U postgres mindasengine > ~/mae-db-$STAMP.sql

# 2. Загруженные картинки
tar czf ~/mae-images-$STAMP.tar.gz -C /home/mindasengine res

# 3. Каталог проекта целиком, вместе с .git, конфликтом и env-файлами
tar czf ~/mae-project-$STAMP.tar.gz .

# 4. Отдельно - то, чего нет в коммитах
git diff            > ~/mae-worktree-$STAMP.diff
git diff --cached   > ~/mae-staged-$STAMP.diff
cp environment.env    ~/mae-environment-$STAMP.env

# 5. Точка отката для compose. ВАЖНО: снимать здесь, до смены веток, и класть
#    под ОТДЕЛЬНЫМ именем. Работающий compose.yml не совпадает с git-версией,
#    а после переключения ветки на его месте будет уже новый файл.
cp compose.yml ~/mae-compose-running-$STAMP.yml
cp compose.yml compose.rollback.yml
grep -E "80:3000|twg-proxy" compose.rollback.yml   # ждём '80:3000', twg-proxy быть не должно
```

`compose.rollback.yml` дальше не трогать и поверх `compose.yml` **не
копировать** — иначе новый конфиг затрётся старым.

## 1. Доставка кода на сервер

Правки лежат в ветке `deploy-nginx-tls` в **том же** репозитории, где живёт
сервер — `github.com/ProdamGaraj/mindasengine`. Ветка стоит прямо на `b5ce3c8`,
то есть на боевом коммите, поэтому история непрерывна и никакие бандлы не
нужны. `deploy` и `master` не тронуты.

На сервере:

```sh
git fetch origin deploy-nginx-tls
git log --oneline -5 origin/deploy-nginx-tls
```

Ожидаемые заголовки, снизу вверх:

```text
description add                                                  <- b5ce3c8, боевой коммит
Fix frontend-backend-database wiring
Add nginx reverse proxy with TLS and automatic certificate renewal
Add deployment and cutover documentation
Correct the cutover runbook: bundle the nginx-tls branch, not master
Align ignore rules with the nginx-tls branch
```

Если `git fetch` не проходит по правам — та же ветка отдаётся инкрементальным
бандлом `mae-nginx-tls-incr.bundle` (77 КБ, требует уже имеющийся `b5ce3c8`):

```sh
git fetch ~/mae-nginx-tls-incr.bundle \
  'refs/heads/deploy-nginx-tls:refs/remotes/origin/deploy-nginx-tls'
```

Само переключение рабочего дерева делать **после** бэкапа и пометки образов
(шаги 0 и 4), непосредственно перед сборкой:

```sh
git switch -C release origin/deploy-nginx-tls
```

Заглавная `-C` вместо `-c`: команда идемпотентна и переставляет ветку, если та
уже создана прошлым заходом. Строчная `-c` на существующей ветке падает с
`fatal: a branch named 'release' already exists` и при этом **не переключается** —
легко решить, что переключение прошло, если до этого уже стоял на `release`.

Обязательно проверить, что в рабочем дереве оказался новый код, а не старый:

```sh
git rev-parse release origin/deploy-nginx-tls   # два одинаковых хеша
ls nginx/templates/                             # должен быть default.conf.template
grep -cE 'nginx|certbot' compose.yml            # > 0
grep -n 'context: \.$' compose.yml              # пусто
```

Точка в шаблоне обязана быть привязана к концу строки (`\.$`). Без якоря
`context: \.` совпадает и с нормальными `context: ./nginx`, `./frontend`,
`./backend` — это контексты сборки nginx, фронта и бэка, они должны быть.
Искать надо ровно `context: .` у сервиса базы.

Если `compose.yml` содержит `build:` у сервиса базы, а каталога `nginx/` нет —
приехал старый коммит, шаг 5 упадёт на сборке базы.

Ветка `deploy` @ `b5ce3c8` при этом остаётся на месте и служит точкой отката.

## 2. Снять фактическую конфигурацию работающих контейнеров

Файл `compose.yml` на диске содержит конфликт-маркеры и не отражает то, что
реально запущено. Источник истины — сами контейнеры:

```sh
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
for c in mind-as-engine-frontend mind-as-engine-backend mind-as-engine-database; do
  echo "=== $c ==="
  docker inspect $c --format '{{.Config.Image}} | {{json .NetworkSettings.Ports}}'
  docker inspect $c --format '{{range .Config.Env}}{{println .}}{{end}}'
  docker inspect $c --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
done
docker network ls
```

## 3. Разобрать git

> **compose.yml в git не совпадает с тем, чем работает сайт.** В `b5ce3c8`
> лежит версия с `twg-proxy` (`valian/docker-nginx-auto-ssl`) на портах 80 и
> 443, фронтом на `3000:3000` и сетями `proxy`/`frontend`/`backend`. Реально
> запущена вручную отредактированная версия: фронт на `80:3000`, сеть
> `default`, без `twg-proxy`. `git checkout -- compose.yml` подменяет рабочий
> файл на нерабочий, а `docker compose up -d` после этого положит сайт.
> Рабочую версию брать из бэкапа `~/mae-compose-conflicted-<STAMP>.yml`.

`git status` показывает `compose.yml` как `both modified`, но `MERGE_HEAD` нет —
`git merge --abort` выдаст `fatal: There is no merge to abort`. Такое состояние
остаётся после конфликтного `git stash pop` (в репозитории есть `refs/stash`
`23160c9 WIP on master`). Снимается индексом, а не merge-командами:

```sh
git reset                  # снять пометку unmerged, рабочее дерево не трогается
git status                 # compose.yml станет обычным "modified"
```

Рабочий `compose.yml` при этом остаётся на диске как есть — он нужен как точка
отката (шаг 4). Файл заменится сам при `git switch -C release origin/deploy-nginx-tls`.

Правку `frontend/src/axios.js` (`http://72.56.32.151:1337`) переносить не надо,
её заменяет относительный baseURL. Сохранена в `~/mae-worktree.diff`.

Сведение веток уже сделано локально: правки, жившие только в `deploy`,
восстановлены (см. таблицу в начале).

Файлы, которые в git не входят и должны остаться на сервере:
`environment.env` (дополнить по шагу 3a) и новый `.env` с `DOMAIN` /
`CERTBOT_EMAIL` — скопировать из `.env.example`.

## 3a. Дополнить environment.env

`environment.env` в git не входит и через bundle не приедет. На сервере
дописать/поправить руками:

```sh
SERVER.FORWARD-HEADERS-STRATEGY=FRAMEWORK
SPRING.SERVLET.MULTIPART.MAX-FILE-SIZE=25MB
SPRING.SERVLET.MULTIPART.MAX-REQUEST-SIZE=100MB
ALLOWED.ORIGINS=https://mindasengine.uz,https://www.mindasengine.uz
```

Последняя строка заменяет старую с IP. Пробелы вокруг `=` не ставить.
`POSTGRES_PASSWORD` не трогать: на уже инициализированном `pgdata` переменная
не применяется, смена пароля делается через `ALTER USER` в psql.

## 4. Защитить откат

`docker compose build` перезапишет теги `mind-as-engine-*:latest`, и откатиться
будет уже не на что. Поэтому сначала пометить работающие образы:

```sh
docker tag mind-as-engine-frontend:latest mind-as-engine-frontend:rollback
docker tag mind-as-engine-backend:latest  mind-as-engine-backend:rollback
```

`compose.rollback.yml` уже снят в шаге 0 — повторно копировать `compose.yml`
сюда нельзя, после смены ветки это уже новый файл.

Если файл потерялся или в него по ошибке лёг новый конфиг — восстановить из
бэкапа:

```sh
cp ~/mae-compose-running-<STAMP>.yml compose.rollback.yml
grep -E "80:3000|twg-proxy" compose.rollback.yml
```

## 5. Собрать новые образы

Сборка не трогает работающие контейнеры — они держат старый image ID.

Выполнять **только после** `git switch -C release origin/deploy-nginx-tls` из шага 1.
На старом `compose.yml` команда падает:

```text
target mind-as-engine-database: failed to solve: failed to read dockerfile:
open Dockerfile: no such file or directory
```

Причина — у сервиса базы стоял `build: context: .` рядом с
`image: postgres:14-alpine3.18`. Своего Dockerfile у базы нет, в корне
репозитория его тоже нет; блок был копипастой. `docker compose up -d` этого не
замечал (брал готовый образ), а `docker compose build` идёт по всем сервисам с
ключом `build:`. В новом `compose.yml` блок удалён.

```sh
docker compose build
```

## 6. Обкатка nginx на 18080/18443 (простоя нет)

nginx поднимается на временных портах и проксирует на уже работающие
контейнеры. Порт 80 остаётся за старым фронтом.

Предусловия:

```sh
docker compose version                     # нужна 2.24.0+, иначе не работает !override
ss -lnt | grep -E ':(18080|18443)'         # должно быть пусто
```

```sh
docker compose -f compose.yml -f compose.canary.yml up -d --no-deps nginx
docker ps --filter name=nginx --format '{{.Names}} | {{.Status}} | {{.Ports}}'
```

В выводе должно быть ровно `0.0.0.0:18080->80/tcp, 0.0.0.0:18443->443/tcp`.
Если контейнер не поднялся — смотреть шапку про `!override` ниже.

```sh
curl -k  https://127.0.0.1:18443/news      # nginx -> backend -> база
curl -k  https://127.0.0.1:18443/projects
curl -kI https://127.0.0.1:18443/          # nginx -> старый frontend
curl -I  http://127.0.0.1/                 # старый сайт на :80 живой, HTTP 200
```

> **`ports` в оверлее нужен тег `!override`.** Compose склеивает списки, а не
> заменяет их: без тега у nginx окажется 80 + 443 + 18080 + 18443, порт 80
> занят старым фронтом, контейнер падает при старте, и канареечный порт
> молчит — `curl: (7) Failed to connect`. В `compose.canary.yml` тег уже стоит;
> проверить результат слияния можно так:
>
> ```sh
> docker compose -f compose.yml -f compose.canary.yml config | grep -A 12 'ports:'
> ```
>
> Должны быть только 18080 и 18443.

Мелочь, чтобы не сбивала: `curl -I http://127.0.0.1:18080/` отдаёт
`301 -> https://127.0.0.1/` без порта. Так и задумано — `$host` не содержит
порт, и на боевых 80/443 редирект правильный. Канарейку проверять сразу по
HTTPS на 18443.

Старый фронт отдаёт старый бандл с абсолютным `http://mindasengine.uz:1337` —
на этом этапе так и должно быть, он заменится на шаге 7.

## 7. Переключение (единственный разрыв: 2–5 секунд на порту 80)

Порт 80 на хосте может держать только один контейнер, поэтому мгновенная
передача владения невозможна. Команды выполнять подряд, без пауз:

```sh
docker compose -f compose.yml -f compose.canary.yml stop nginx
docker stop mind-as-engine-frontend        # освобождает :80
docker compose up -d --no-deps nginx       # занимает :80 и :443
```

С этого момента сайт отвечает через nginx: API работает, на `/` — 502, пока не
поднимется новый фронт.

```sh
docker compose up -d --no-deps mind-as-engine-frontend   # ~10 c, 502 на / уходит
```

Итог: ~5 секунд полного отказа + ~10 секунд 502 на главной. API (`/news`,
`/projects`, `/images/*`) недоступен только в первые ~5 секунд.

## 8. Боевой сертификат

nginx уже на :80, ACME-webroot работает.

```sh
STAGING=1 ./nginx/scripts/init-letsencrypt.sh    # проверка без расхода лимитов
docker compose run --rm --entrypoint certbot certbot delete --cert-name "$DOMAIN"
./nginx/scripts/init-letsencrypt.sh              # боевой
```

До этого шага HTTPS работает на самоподписанном сертификате — браузер ругается,
но сайт доступен. HTTP отдаёт 301 на HTTPS.

Предусловия: A-записи `DOMAIN` и `www.DOMAIN` смотрят на этот сервер,
порты 80 и 443 открыты в фаерволе.

## 9. Довести остальные сервисы

Приводит backend и базу к новым определениям (healthcheck'и, порты 1337/5432
больше не торчат наружу).

```sh
docker compose up -d
```

Backend перезапускается ~15 c — на это время API отдаёт 502, оболочка сайта
продолжает открываться. Делать в низкий трафик.

## 10. Открытая регистрация — решить до публикации HTTPS

Обнаружено при сквозной проверке, к переходу на nginx отношения не имеет,
но касается того же кода.

`WebSecurityConfig` разрешает `/api/auth/**` всем, а `/moderator/**` требует
только `authenticated()` — ролей в проекте нет. То есть любой человек из
интернета может зарегистрироваться и получить полный доступ к управлению контентом.
Воспроизведено на тестовом стенде: два запроса без какой-либо авторизации —
и загрузка новости проходит с HTTP 200.

```sh
curl -X POST -H 'Content-Type: application/json' \
     -d '{"username":"probe","password":"probe12345"}' https://$DOMAIN/api/auth/signup
# {"message":"User registered successfully!"}
curl -X POST -H 'Content-Type: application/json' \
     -d '{"username":"probe","password":"probe12345"}' https://$DOMAIN/api/auth/signin
# {"token":"...","type":"Bearer",...}
curl -X POST -H "Authorization: Bearer <token>" -F name=... -F multipartFiles=@x.jpg \
     https://$DOMAIN/moderator/upload/news
# Upload news
```

Варианты (менять код — отдельная задача, в текущие правки не входит):

1. Закрыть `/api/auth/signup` — убрать из `permitAll`, оставить только
   `/api/auth/signin`. Аккаунты заводить вручную в базе. Минимальная правка.
2. Ввести роли и требовать `hasRole('MODERATOR')` на `/moderator/**`.

Пока не закрыто — проверить, кто уже зарегистрирован:

```sh
docker compose exec mind-as-engine-database psql -U postgres -d mindasengine \
  -c 'select id, username from users;'
```

## 11. Проверка

```sh
docker compose ps                       # все пять сервисов healthy
curl -I  http://$DOMAIN/                # 301
curl -I  https://$DOMAIN/               # 200, валидный сертификат (без -k)
curl -s  https://$DOMAIN/news
docker compose run --rm --entrypoint certbot certbot renew --dry-run
ss -lntp | grep -E ':(1337|5432|3000)'  # должно быть пусто
```

---

## Откат

```sh
docker stop nginx certbot
docker compose -f compose.rollback.yml up -d
```

Если новые образы уже подменили теги — вернуть помеченные на шаге 4:

```sh
docker tag mind-as-engine-frontend:rollback mind-as-engine-frontend:latest
docker tag mind-as-engine-backend:rollback  mind-as-engine-backend:latest
```

База и картинки лежат в bind-mount'ах `/home/mindasengine/*` и переключением
не затрагиваются.
