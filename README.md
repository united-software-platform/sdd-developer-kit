# SDD Developer Kit

[![базовый образ Claude из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=FROM%20%28ghcr%5C.io%2F%5CS%2B%2Fclaude%3A%5CS%2B%29&replace=%241&label=claude%20image&color=2496ED&logo=docker)](https://github.com/orgs/united-software-platform/packages/container/package/claude)
[![версия Python из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20PYTHON_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=python&color=3776AB&logo=python)](./Dockerfile)
[![версия OpenSpec из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20OPENSPEC_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=openspec&color=5B4FCF)](./Dockerfile)
[![версия uv из Dockerfile](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FDockerfile&search=ARG%20UV_VERSION%3D%28%5B%5Cd.%5D%2B%29&replace=%241&label=uv&color=DE5FE9)](./Dockerfile)
[![версия kit'а из файла VERSION](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Funited-software-platform%2Fsdd-developer-kit%2Fmain%2FVERSION&search=%28%5B%5Cd.%5D%2B%29&replace=%241&label=version&color=007EC6)](./VERSION)
[![лицензия MIT](https://img.shields.io/badge/license-MIT-007EC6)](./LICENSE)
Изолированное окружение разработки для Spec-Driven Development (SDD): контейнер с Claude Code
и предустановленным OpenSpec, правила репозитория и инструменты SDD — разворачиваются в любом
проекте одной командой.

---

## Навигация

- [Установка](#установка)
- [Что попадает в проект](#что-попадает-в-проект)
- [Команды](#команды)
- [Разработка самого kit'а](#разработка-самого-kitа)
- [Лицензия](#лицензия)
- [Версионирование](#версионирование)

---

## Установка

В корне своего проекта:

```bash
curl -fsSL https://raw.githubusercontent.com/united-software-platform/sdd-developer-kit/main/install.sh | sh
```

Дальше — по шагам из [`SDD-KIT.md`](./SDD-KIT.md): подготовка проекта, заполнение `.env`,
сборка образа, запуск контейнера. Инструкция ставится в проект вместе с инструментами, поэтому
после установки она всегда под рукой.

Если запускать чужой скрипт из сети не хочется, его можно сначала прочитать:

```bash
curl -fsSL -O https://raw.githubusercontent.com/united-software-platform/sdd-developer-kit/main/install.sh
less install.sh
sh install.sh
```

Установщик не пишет ничего, пока не покажет план: файлы к созданию, к обновлению и к перезаписи.
Перезапись существующих файлов требует подтверждения.

---

## Что попадает в проект

| Компонент | Расположение |
|-----------|--------------|
| Окружение агента | `Dockerfile`, `docker-compose.yml`, `Makefile`, `.env.example` |
| Правила репозитория | `rules/`, `CLAUDE.md`, `AGENTS.md` |
| Инструменты SDD | `.claude/skills/`, `.claude/commands/`, `openspec/config.yaml` |
| Раннер целей сборки | `tools/host-runner/` |
| Инструкция | `SDD-KIT.md` |

---

## Команды

| Команда | Действие |
|---------|----------|
| `make init` | Подготовка проекта: `.env`, каталоги ключей и профилей, записи в `.gitignore` |
| `make build` | Сборка образа |
| `make up` | Запуск контейнера агента |
| `make shell` | Вход в контейнер |
| `make down` | Остановка контейнера |

Подробности по каждому шагу — в [`SDD-KIT.md`](./SDD-KIT.md).

---

## Разработка самого kit'а

Репозиторий kit'а сам развёрнут теми же инструментами: правила лежат в [`rules/`](./rules),
процесс ведётся через OpenSpec в [`openspec/`](./openspec), установщик — [`install.sh`](./install.sh).
Правила работы с репозиторием описаны в [`CLAUDE.md`](./CLAUDE.md) и [`AGENTS.md`](./AGENTS.md).

---

## Лицензия

[MIT](./LICENSE).

---

## Версионирование

| Версия | Дата | Задача | Агент | Модель | Описание изменений |
|--------|------|--------|-------|--------|--------------------|
| 1.0.0 | 2026-09-06 | OpenSpec change `repo-bootstrap-process` | Claude Code | Claude Sonnet 5 | Начальное создание: формализован бутстрап-процесс — предусловия (`.env`, SSH-ключ, профиль аккаунта), сборка образа, запуск контейнера, готовность к рабочей сессии, опциональный host-runner, таблица переменных окружения |
| 1.0.1 | 2026-09-08 | OpenSpec change `install-kit-into-project` | Claude Code | Claude Opus 5 | Добавлен раздел «Установка kit'а в целевой проект» со ссылками на установочный скрипт и документ окружения; соответствующий пункт добавлен в навигацию |
| 1.0.2 | 2026-09-08 | OpenSpec change `add-readme-badges` | Claude Code | Claude Opus 5 | Добавлен блок бейджей между заголовком и назначением по исключению [DOC-015](./rules/documentation-rules.md#ссылки-doc-015): базовый Claude-образ, Python, OpenSpec, uv, версия kit'а и лицензия. Пять бейджей динамические — значения читаются из `Dockerfile` и `VERSION` через `shields.io`, ручных копий версий в документе нет. Добавлен раздел «Бейджи» с таблицей «бейдж ↔ источник» и ограничениями, добавлен пункт навигации |
| 1.1.0 | 2026-09-08 | OpenSpec change `install-kit-into-project` | Claude Code | Claude Opus 5 | Кардинальная переработка: файл переведён из описания бутстрапа клона в витрину продукта — установка одной удалённой командой, состав поставки, таблица команд `make`, раздел о разработке самого kit'а. Порядок шагов перенесён в единственную инструкцию `SDD-KIT.md` и здесь не дублируется; описание окружения из `docs/sdd-kit.md` и документация установщика из `tools/install/README.md` объединены там же |
