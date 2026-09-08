# SDD Developer Kit

[![базовый образ Claude из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=FROM%20%28ghcr%5C.io%2F%5CS%2B%2Fclaude%3A%5CS%2B%29&replace=%241&label=claude%20image&color=2496ED&logo=docker)](https://github.com/orgs/united-software-platform/packages/container/package/claude)
[![версия Python из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20PYTHON_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=python&color=3776AB&logo=python)](./Dockerfile)
[![версия OpenSpec из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20OPENSPEC_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=openspec&color=5B4FCF)](./Dockerfile)
[![версия uv из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20UV_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=uv&color=DE5FE9)](./Dockerfile)
[![версия kit'а из файла VERSION](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FVERSION&search=%28%5B%5Cd.%5D%2B%29&replace=%241&label=version&color=007EC6)](./VERSION)
[![лицензия MIT](https://img.shields.io/badge/license-MIT-007EC6)](./LICENSE)

Изолированная облачная среда разработки для Spec-Driven Development (SDD): контейнер с Claude
Code и предустановленным OpenSpec. Этот файл описывает бутстрап — порядок подготовки окружения
от чистого клона репозитория до готового к работе контейнера.

---

## Навигация

- [Предусловия](#предусловия)
- [Сборка образа](#сборка-образа)
- [Запуск контейнера](#запуск-контейнера)
- [Готовность к рабочей сессии](#готовность-к-рабочей-сессии)
- [Установка kit'а в целевой проект](#установка-kita-в-целевой-проект)
- [Опционально: host-runner на хосте](#опционально-host-runner-на-хосте)
- [Переменные окружения](#переменные-окружения)
- [Бейджи](#бейджи)
- [Версионирование](#версионирование)

---

## Предусловия

Перед сборкой образа должны быть готовы:

- **Файл `.env`** — скопировать из [`.env.example`](./.env.example) и заполнить. Без `.env`
  или без обязательных переменных сборка и запуск контейнера завершаются ошибкой конфигурации.
- **SSH-ключ** в каталоге `${SSH_DIR:-.ssh}` — используется контейнером для доступа к
  git-репозиторию (push/pull), а не ключ, встроенный в образ.
- **Профиль аккаунта** — переменная `CLAUDE_PROFILE` должна указывать на существующий подкаталог
  в `${CLAUDE_ACCOUNTS_DIR:-.claude-accounts}`. Без неё путь монтирования схлопывается в
  несуществующий каталог, и контейнер не получает доступ ни к одному профилю — это осознанная
  защита от случайного доступа к чужому профилю. Проверка сделана в цели `make claude-shell`.

---

## Сборка образа

```bash
docker compose --profile claude build claude
```

Образ собирается локально (`claude-openspec:local`) — готового образа с этим тегом в реестре нет,
поэтому пересборка обязательна после любой правки `Dockerfile`.

---

## Запуск контейнера

```bash
CLAUDE_PROFILE=<профиль> docker compose --profile claude up -d --force-recreate claude
```

Контейнер монтирует рабочее дерево проекта, каталог выбранного профиля аккаунта и SSH-ключи.
Файл `.env` на хосте контейнеру не виден — секреты приходят через `env_file`, а сам `.env` внутри
контейнера замаскирован пустым файлом.

---

## Готовность к рабочей сессии

Образ уже содержит `openspec` и Python нужной версии (закреплены в `Dockerfile`) — после запуска
контейнера дополнительная установка инструментов не требуется. Разработчик или CI входят в
контейнер и продолжают работу с Claude Code и OpenSpec (`openspec status`, `/opsx:propose` и т.д.).

Порядок одинаков для разработчика и для CI: различается только среда выполнения команд
`docker compose`, а не сама последовательность шагов.

---

## Установка kit'а в целевой проект

Kit применяется не только к самому себе: его инструменты разворачиваются в каталоге любого другого
проекта установочным скриптом.

```bash
./tools/install/install.sh /path/to/project
```

Скрипт раскладывает состав поставки в корень целевого проекта, до записи показывает перечень файлов,
которые будут перезаписаны, и записывает манифест установки. Состав поставки, режимы запуска
(предварительный просмотр, неинтерактивный режим) и ограничения описаны в
[`tools/install/README.md`](./tools/install/README.md).

Описание окружения, которое получает целевой проект, — в [`docs/sdd-kit.md`](./docs/sdd-kit.md).
Этот же документ описывает окружение и для самого kit'а.

---

## Опционально: host-runner на хосте

Агенту внутри контейнера недоступны `make` и Docker-сокет. Если нужно, чтобы агент мог выполнять
цели `make` окружения (например, поднимать или останавливать сопутствующие сервисы), на хосте
отдельно запускается host-runner — подробности в
[`tools/host-runner/README.md`](./tools/host-runner/README.md).

Это необязательный шаг: без запущенного host-runner контейнер всё равно собирается и запускается,
а вызовы целей `make` из контейнера просто завершаются ошибкой соединения.

---

## Переменные окружения

Актуальный состав — в [`.env.example`](./.env.example). Кратко:

| Переменная | Назначение |
|------------|------------|
| `PROJECT_DIR` | Путь монтирования рабочего дерева проекта внутри контейнера |
| `CLAUDE_CONFIG_DIR` | Каталог конфигурации Claude Code внутри контейнера |
| `CLAUDE_ACCOUNTS_DIR` | Каталог на хосте, где лежат профили аккаунтов |
| `CONTAINER_SSH_DIR` | Каталог SSH внутри контейнера |
| `SSH_DIR` | Каталог SSH на хосте, монтируемый в контейнер |
| `SSH_KEY`, `SSH_CONFIG`, `SSH_KNOWN_HOSTS` | Пути к файлам SSH-конфигурации |
| `GIT_HOST`, `GIT_USER` | Параметры доступа к git-хосту |
| `USER_ID`, `GROUP_ID` | UID/GID пользователя контейнера |

`CLAUDE_PROFILE` задаётся отдельно от `.env.example` (см. [Предусловия](#предусловия)) — значение
специфично для каждого разработчика и не должно быть общим для всех, поэтому в пример не включено.

Переменные `AGENT_RUNNER_*` относятся к опциональному host-runner — их назначение и значения по
умолчанию описаны в [`tools/host-runner/README.md`](./tools/host-runner/README.md#запуск).

---

## Бейджи

Блок бейджей под заголовком файла не хранит значений: пять из шести бейджей вычисляются сервисом
`shields.io`, который читает файлы этого репозитория с ветки `main` и вынимает значение регулярным
выражением. Правка версии в источнике меняет бейдж без правки `README.md`.

| Бейдж | Файл-источник | Что извлекается |
|-------|---------------|-----------------|
| `claude image` | [`Dockerfile`](./Dockerfile) | строка `FROM` — имя базового образа вместе с тегом |
| `python` | [`Dockerfile`](./Dockerfile) | `ARG PYTHON_VERSION` |
| `openspec` | [`Dockerfile`](./Dockerfile) | `ARG OPENSPEC_VERSION` |
| `uv` | [`Dockerfile`](./Dockerfile) | `ARG UV_VERSION` |
| `version` | [`VERSION`](./VERSION) | содержимое файла |
| `license` | — | статическое значение `MIT`, ссылка ведёт на [`LICENSE`](./LICENSE) |

Ограничения:

- **Репозиторий должен быть доступен анонимно.** Значения читаются через
  `raw.githubusercontent.com`; для закрытого репозитория запрос вернёт `404`, и бейджи версий
  отрисуются как ошибка.
- **Значения берутся с ветки `main`.** На ветке с ещё не влитой правкой `Dockerfile` бейдж покажет
  прежнюю версию — он отражает то, что видит внешний читатель `main`, а не локальное состояние.
- **Бейдж ломается при переименовании источника.** Переименование или удаление `ARG`, как и смена
  формы строки `FROM`, оставляет бейдж без совпадения, и он показывает ошибку. Так и задумано:
  видимая ошибка честнее молча устаревшего значения. При правке `Dockerfile` сверяйтесь с таблицей
  выше.

> **Примечание:** описание блока живёт в `README.md`, а не в
> [`docs/sdd-kit.md`](./docs/sdd-kit.md): последний входит в состав поставки kit'а и
> устанавливается в целевые проекты, где бейджи этого репозитория не имеют смысла.

---

## Версионирование

| Версия | Дата | Задача | Агент | Модель | Описание изменений |
|--------|------|--------|-------|--------|--------------------|
| 1.0.0 | 2026-09-06 | OpenSpec change `repo-bootstrap-process` | Claude Code | Claude Sonnet 5 | Начальное создание: формализован бутстрап-процесс — предусловия (`.env`, SSH-ключ, профиль аккаунта), сборка образа, запуск контейнера, готовность к рабочей сессии, опциональный host-runner, таблица переменных окружения |
| 1.0.1 | 2026-09-08 | OpenSpec change `install-kit-into-project` | Claude Code | Claude Opus 5 | Добавлен раздел «Установка kit'а в целевой проект» со ссылками на установочный скрипт и документ окружения; соответствующий пункт добавлен в навигацию |
| 1.0.2 | 2026-09-08 | OpenSpec change `add-readme-badges` | Claude Code | Claude Opus 5 | Добавлен блок бейджей между заголовком и назначением по исключению [DOC-015](./rules/documentation-rules.md#ссылки-doc-015): базовый Claude-образ, Python, OpenSpec, uv, версия kit'а и лицензия. Пять бейджей динамические — значения читаются из `Dockerfile` и `VERSION` через `shields.io`, ручных копий версий в документе нет. Добавлен раздел «Бейджи» с таблицей «бейдж ↔ источник» и ограничениями, добавлен пункт навигации |
