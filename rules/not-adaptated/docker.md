# Правила Docker и Docker Compose

Правила оформления `docker-compose.yaml`, именования сервисов и контейнеров, сети, портов и переменных окружения.

---

## Навигация

- [Таблица правил](#таблица-правил)
- [Имя файла конфигурации](#имя-файла-конфигурации-dock-011)
- [Префикс имён](#префикс-имён-dock-001002)
- [Сеть](#сеть-dock-003)
- [Переменные окружения](#переменные-окружения-dock-004-dock-009-dock-010)
- [Параметры сервиса](#параметры-сервиса-dock-005-dock-006-dock-007)
- [Сервис инициализации состояния](#сервис-инициализации-состояния-dock-014-dock-015)
- [Пользователь backend-контейнера](#пользователь-backend-контейнера-dock-012-dock-013)
- [Порты](#порты-dock-008)
- [Пример](#пример)
- [Версионирование](#версионирование)

---

## Таблица правил

| ID | Правило |
|----|---------|
| DOCK-001 | Имена сервисов — с префиксом проекта; префикс вычленяется из README (заголовок системы) или первичных требований |
| DOCK-002 | `container_name` совпадает с именем сервиса |
| DOCK-003 | Обязательно объявлять сеть в `networks` и подключать к ней все сервисы |
| DOCK-004 | Запрет атрибута `env_file` |
| DOCK-005 | `working_dir` указывается при необходимости (например, backend-контейнеры) |
| DOCK-006 | `healthcheck` добавляется при необходимости (например, контейнеры БД) |
| DOCK-007 | Политика перезапуска — `restart: unless-stopped` для всех долгоживущих сервисов; исключение — сервисы инициализации состояния (DOCK-014) |
| DOCK-008 | Порты по умолчанию не назначаются; публикуемый порт выбирается из диапазона `11000–12000`; по возможности проверяется, свободен ли порт |
| DOCK-009 | Все параметры `environment` берутся из `.env` (через интерполяцию `${VAR}`) |
| DOCK-010 | Рядом с `.env` создаётся `.env.example` — шаблон переменных окружения |
| DOCK-011 | Файл конфигурации Compose именуется `docker-compose.yaml` |
| DOCK-012 | Backend-контейнер запускается под пользователем и группой `www` |
| DOCK-013 | Рабочий каталог и все внутренние файлы backend-контейнера принадлежат пользователю и группе `www` |
| DOCK-014 | Состояние в томах, необходимое сервису для работы (модели, словари, расширения, схемы), наполняется одноразовым сервисом инициализации `{сервис}-init` с `restart: "no"`; ручное наполнение тома запрещено |
| DOCK-015 | Потребители инициализированного состояния ждут завершения init-сервиса через `depends_on` с `condition: service_completed_successfully`; сам init-сервис ждёт готовности целевого сервиса по `healthcheck` |

---

## Имя файла конфигурации [DOCK-011]

**[DOCK-011]** Файл конфигурации Docker Compose именуется строго `docker-compose.yaml` и располагается в корне проекта. Краткие формы (`compose.yaml`, `compose.yml`, `docker-compose.yml`) не используются.

---

## Префикс имён [DOCK-001..002]

**[DOCK-001]** Каждое имя сервиса начинается с префикса проекта. Префикс вычленяется из источника проекта в порядке приоритета:

1. Заголовок системы в корневом `README.md` (H1).
2. Первичные требования (название системы).

Префикс приводится к короткой форме в нижнем регистре (kebab-case). Пример: README `# RAG-система Lenvendo` → префикс **`rag`** → сервисы `rag-php`, `rag-postgres`, `rag-nginx`.

**[DOCK-002]** Имя контейнера (`container_name`) совпадает с именем сервиса. Это убирает автогенерируемый суффикс Compose (`<project>-<service>-1`) и делает имя предсказуемым.

```yaml
services:
  rag-postgres:
    container_name: rag-postgres
```

---

## Сеть [DOCK-003]

**[DOCK-003]** В `docker-compose.yaml` обязательно объявляется сеть в секции `networks`, и каждый сервис подключается к ней явно. Имя сети — с префиксом проекта.

```yaml
networks:
  rag-net:
    driver: bridge
```

---

## Переменные окружения [DOCK-004, DOCK-009, DOCK-010]

**[DOCK-004]** Атрибут `env_file` **запрещён**. Переменные передаются через секцию `environment` с интерполяцией.

**[DOCK-009]** Все значения секции `environment` берутся из файла `.env` через `${VAR}`. Compose автоматически читает `.env` из каталога проекта для подстановки значений — хардкод значений в `docker-compose.yaml` запрещён.

```yaml
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

**[DOCK-010]** Рядом с `.env` создаётся `.env.example` — коммитимый шаблон со всеми переменными и несекретными дефолтами. Сам `.env` игнорируется git.

> **Внимание:** `.env` содержит реальные значения и не коммитится; `.env.example` — единственный версионируемый файл переменных.

---

## Параметры сервиса [DOCK-005, DOCK-006, DOCK-007]

**[DOCK-005]** `working_dir` указывается там, где это осмысленно — прежде всего для backend-контейнеров (рабочий каталог приложения).

**[DOCK-006]** `healthcheck` добавляется там, где готовность сервиса критична для зависящих сервисов — прежде всего для контейнеров БД, очередей, хранилищ.

**[DOCK-007]** Для всех **долгоживущих** сервисов задаётся `restart: unless-stopped`. Единственное исключение — сервисы инициализации состояния (см. [DOCK-014](#сервис-инициализации-состояния-dock-014-dock-015)): они выполняют задачу и завершаются, поэтому политика перезапуска у них `restart: "no"`.

---

## Сервис инициализации состояния [DOCK-014, DOCK-015]

**[DOCK-014]** Если сервису для работы требуется **состояние внутри тома**, которого нет в образе — модели, словари, расширения, схемы, справочники, — это состояние наполняется **одноразовым сервисом инициализации** `{сервис}-init`. Наполнять том вручную (командами внутри работающего контейнера) запрещено: том — не декларация, ручное наполнение не воспроизводится и теряется при пересоздании тома.

Требования к init-сервису:

- имя — `{имя целевого сервиса}-init`, `container_name` совпадает с ним (DOCK-002);
- образ — тот же, что у целевого сервиса (в нём уже есть нужный клиент), либо минимальный образ с необходимым инструментом;
- монтирует тот же том, что и целевой сервис;
- источник значений — переменные `.env` (DOCK-009), а не литералы в команде;
- `restart: "no"` — исключение из DOCK-007: сервис обязан завершиться, а не перезапускаться;
- подключается к общей сети (DOCK-003), портов не публикует.

**[DOCK-015]** Порядок запуска задаётся `depends_on`:

- init-сервис ждёт готовности целевого сервиса — `condition: service_healthy` (целевому сервису при этом нужен `healthcheck`, DOCK-006);
- все потребители инициализированного состояния ждут **успешного завершения** init-сервиса — `condition: service_completed_successfully`.

Без `service_completed_successfully` потребитель стартует раньше, чем состояние наполнено, и падает на первом обращении либо молча работает на пустом хранилище.

```yaml
  rag-ollama:
    image: ${OLLAMA_IMAGE}
    container_name: rag-ollama
    restart: unless-stopped
    volumes:
      - rag-ollama-data:/root/.ollama
    healthcheck:                                  # нужен для service_healthy [DOCK-006]
      test: ["CMD-SHELL", "ollama list >/dev/null 2>&1"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - rag-net

  rag-ollama-init:                                # одноразовое наполнение тома [DOCK-014]
    image: ${OLLAMA_IMAGE}
    container_name: rag-ollama-init
    restart: "no"                                 # исключение из DOCK-007
    environment:
      OLLAMA_HOST: rag-ollama:11434
      CHAT_MODEL: ${OLLAMA_CHAT_MODEL}            # значения из .env [DOCK-009]
      EMBEDDING_MODEL: ${OLLAMA_EMBEDDING_MODEL}
    entrypoint: ["/bin/sh", "-c"]
    command: ['ollama pull "$$CHAT_MODEL" && ollama pull "$$EMBEDDING_MODEL"']
    depends_on:
      rag-ollama:
        condition: service_healthy                # ждёт готовности целевого сервиса [DOCK-015]
    networks:
      - rag-net

  rag-php:
    # ...
    depends_on:
      rag-ollama-init:
        condition: service_completed_successfully # ждёт наполнения состояния [DOCK-015]
```

> **Внимание:** в `command` переменные экранируются двойным `$$` — иначе Compose подставит их сам на этапе интерполяции и внутрь контейнера уйдёт уже раскрытое (или пустое) значение.

---

## Пользователь backend-контейнера [DOCK-012, DOCK-013]

**[DOCK-012]** Backend-контейнер запускается не от `root`, а под выделенным пользователем и группой `www`. Пользователь и группа создаются в `Dockerfile`, процесс приложения исполняется от их имени (`USER www` в `Dockerfile` и/или `user: www` в сервисе Compose).

**[DOCK-013]** Рабочий каталог (`working_dir`) и все внутренние файлы backend-контейнера принадлежат пользователю и группе `www`. Владелец задаётся при копировании кода (`COPY --chown=www:www`) и/или через `chown -R www:www` рабочего каталога. Файлы приложения не должны оставаться во владении `root`.

### Dockerfile backend-контейнера

```dockerfile
# docker/php/Dockerfile
FROM php:8.4-fpm

# Выделенные пользователь и группа www [DOCK-012]
RUN groupadd -g 1000 www \
    && useradd -u 1000 -g www -m -s /bin/bash www

WORKDIR /var/www/html

# Все внутренние файлы принадлежат www:www [DOCK-013]
COPY --chown=www:www . /var/www/html
RUN chown -R www:www /var/www/html

# Процесс приложения исполняется от www [DOCK-012]
USER www
```

---

## Порты [DOCK-008]

**[DOCK-008]** Порты, опубликованные на хост, **не назначаются по умолчанию** (`5432:5432`, `80:80` и т.п.). Хостовый порт выбирается из диапазона `11000–12000`. По возможности перед назначением проверяется, свободен ли порт.

Внутренний порт контейнера остаётся штатным; меняется только хостовая (левая) часть маппинга:

```yaml
    ports:
      - "11432:5432"   # postgres: хостовый 11432 из диапазона, контейнерный штатный
```

Проверка свободности портов на хосте:

```bash
for p in 11080 11432 11672; do
  ss -ltn | grep -q ":$p " && echo "$p занят" || echo "$p свободен"
done
```

---

## Пример

`.env.example` (рядом — `.env` с реальными значениями, игнорируется git):

```bash
POSTGRES_DB=app
POSTGRES_USER=app
POSTGRES_PASSWORD=change_me
APP_HTTP_PORT=11080
DB_HTTP_PORT=11432
```

`docker-compose.yaml`:

```yaml
services:
  rag-php:
    build:
      context: .
      dockerfile: docker/php/Dockerfile
    container_name: rag-php
    working_dir: /var/www/html
    user: www
    restart: unless-stopped
    environment:
      DATABASE_URL: ${DATABASE_URL}
    depends_on:
      rag-postgres:
        condition: service_healthy
    networks:
      - rag-net

  rag-postgres:
    image: postgres:18.3
    container_name: rag-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "${DB_HTTP_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - rag-net

  rag-nginx:
    image: nginx:1.30
    container_name: rag-nginx
    restart: unless-stopped
    depends_on:
      - rag-php
    ports:
      - "${APP_HTTP_PORT}:80"
    networks:
      - rag-net

networks:
  rag-net:
    driver: bridge
```

---

## Версионирование

| Версия | Дата | Задача | Агент | Модель | Описание изменений |
|--------|------|--------|-------|--------|--------------------|
| 1.0 | 2026-06-17 | Правила Docker/Docker Compose | claude | opus-4.8 | Начальное создание: DOCK-001..010 — префикс имён сервисов из README/первичных требований, `container_name` = имя сервиса, обязательная сеть, запрет `env_file`, `working_dir`/`healthcheck` по необходимости, `restart: unless-stopped`, порты из диапазона 11000–12000, `environment` из `.env`, обязательный `.env.example` |
| 1.1 | 2026-06-23 | Имя файла Compose и пользователь backend | claude | opus-4.8 | Добавлены DOCK-011 (файл конфигурации именуется `docker-compose.yaml`), DOCK-012 (backend-контейнер под пользователем и группой `www`), DOCK-013 (рабочий каталог и внутренние файлы backend во владении `www:www`); добавлены разделы «Имя файла конфигурации» и «Пользователь backend-контейнера» с `Dockerfile`; упоминания `compose.yaml` заменены на `docker-compose.yaml`; в пример добавлен `user: www` |
| 1.2 | 2026-07-28 | RAG-021: потеря моделей Ollama при пересоздании тома | claude | opus-5 | Добавлены DOCK-014 (состояние в томах — модели, словари, расширения, схемы — наполняется одноразовым сервисом `{сервис}-init` с `restart: "no"`; ручное наполнение тома запрещено) и DOCK-015 (порядок запуска: init ждёт `service_healthy` целевого сервиса, потребители ждут `service_completed_successfully` init-сервиса). DOCK-007 уточнён: `restart: unless-stopped` — для долгоживущих сервисов, init-сервисы — явное исключение. Добавлен раздел «Сервис инициализации состояния» с примером `rag-ollama-init` и предупреждением об экранировании `$$` в `command`; обновлены таблица правил и навигация |
