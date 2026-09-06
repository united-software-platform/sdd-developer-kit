# Образ агента Claude Code с предустановленными утилитой OpenSpec и Python.
#
# Базовый образ — готовая мультиарх-сборка из GHCR; здесь она только дополняется
# инструментами, которые иначе пришлось бы ставить в каждый новый контейнер заново:
# глобальные пакеты npm и интерпретатор Python живут в слое образа, а домашний
# каталог пользователя монтируется томом и переустановку не переживает.
#
# Сборка: docker build -t claude-openspec:local .

# Версия uv объявлена до FROM: в имя образа стадии подставляется только глобальный ARG.
ARG UV_VERSION=0.12.7

# uv приезжает готовым бинарником из официального образа — не нужны ни curl,
# ни установочный скрипт, а тег образа фиксирует версию инструмента.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ghcr.io/united-software-platform/claude:latest

# Версия закреплена явно: latest в базовом образе сделал бы сборку невоспроизводимой,
# а несовместимая мажорная версия ломает скиллы openspec-* из .claude/skills.
ARG OPENSPEC_VERSION=1.11.0

# Версия Python закреплена по той же причине. Интерпретатор берётся не из apt:
# в Debian 12 (bookworm) штатный python3 — 3.11, а pyproject.toml проекта требует
# requires-python >=3.12. uv ставит нужную сборку CPython сам и работает на обеих
# архитектурах базового образа.
ARG PYTHON_VERSION=3.12

# Установка выполняется от root: префикс npm в базовом образе — /usr/local,
# он принадлежит root, и пользователю claude запись туда запрещена.
USER root

RUN npm install -g "@fission-ai/openspec@${OPENSPEC_VERSION}" \
    && npm cache clean --force \
    && openspec --version

COPY --from=uv /uv /uvx /usr/local/bin/

# Интерпретатор кладётся в /opt/python, а не в домашний каталог: домашний каталог
# монтируется томом, и содержимое слоя образа в нём не видно. Переменная сохраняется
# в окружении образа, иначе uv в рантайме искал бы установленный Python не там.
ENV UV_PYTHON_INSTALL_DIR=/opt/python

# Симлинки python3/python выводят интерпретатор на PATH: без них он доступен
# только через uv run, и обычные вызовы python3 из скриптов и инструментов падают.
# chmod открывает каталог непривилегированному пользователю claude: установка идёт
# от root, а запускать интерпретатор будет он.
RUN uv python install "${PYTHON_VERSION}" \
    && ln -s "$(uv python find "${PYTHON_VERSION}")" /usr/local/bin/python3 \
    && ln -s /usr/local/bin/python3 /usr/local/bin/python \
    && chmod -R a+rX /opt/python \
    && python3 --version \
    && uv --version

# Возврат к непривилегированному пользователю базового образа (uid/gid 1000):
# рабочее дерево проекта монтируется с правами хозяина каталога.
USER claude
