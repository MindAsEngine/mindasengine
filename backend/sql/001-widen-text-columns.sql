-- Расширение текстовых колонок.
--
-- Зачем: в моделях Project и News поле description было объявлено как обычный
-- String без длины, Hibernate маппил его в varchar(255). Любое описание длиннее
-- 255 символов роняло вставку:
--
--   SQLState 22001
--   ERROR: value too long for type character varying(255)
--   insert into project (description,name) values (?,?)
--
-- В моделях тип исправлен, но spring.jpa.hibernate.ddl-auto=update умеет только
-- добавлять таблицы и колонки - тип существующей колонки он не меняет. Поэтому
-- на уже развёрнутой базе миграцию нужно применить руками:
--
--   docker exec -i mind-as-engine-database psql -U postgres -d mindasengine \
--     < backend/sql/001-widen-text-columns.sql
--
-- Идемпотентна, повторный запуск безопасен. Данные не теряются: расширение
-- varchar до text и varchar(255) до varchar(500) выполняется без переписывания
-- значений.

BEGIN;

ALTER TABLE project ALTER COLUMN description TYPE text;
ALTER TABLE project ALTER COLUMN name        TYPE varchar(500);

ALTER TABLE news    ALTER COLUMN description TYPE text;
ALTER TABLE news    ALTER COLUMN name        TYPE varchar(500);

-- filename = UUID (36 символов) + "." + исходное имя файла
ALTER TABLE photo   ALTER COLUMN filename    TYPE varchar(512);

COMMIT;

\d project
\d news
\d photo
