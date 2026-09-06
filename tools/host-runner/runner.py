#!/usr/bin/env python3
"""Раннер целей сборки окружения на хосте.

Принимает по HTTP имя цели `make` из белого списка, выполняет её в корне репозитория
и возвращает вывод с кодом возврата. Ни shell, ни произвольные команды, ни доступ
к Docker-сокету из контейнера агента не задействованы: агент лишь просит выполнить
одну из заранее разрешённых целей.
"""

from __future__ import annotations

import base64
import binascii
import hmac
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

# Белый список: только эти цели могут быть запрошены. Список совпадает с целями
# Makefile репозитория — цель вне Makefile дала бы лишь ошибку make. Расширять осознанно.
ALLOWED_TARGETS = frozenset(
    {
        "init",
        "up",
        "down",
        "restart",
        # logs состояние не меняет — нужна агенту для диагностики упавших сервисов
        "logs",
        # authors и scan снимают слепок стороннего репозитория; путь к нему приходит
        # параметром, поэтому обе цели перечислены и в TARGET_PARAMETERS
        "authors",
        "scan",
    }
)

# Цели, принимающие параметры, и разрешённые имена переменных каждой. Цель, которой
# здесь нет, вызывается без параметров: присваивание для неё отклоняется, а не молча
# игнорируется — иначе опечатка в имени переменной выглядела бы как успешный прогон.
TARGET_PARAMETERS: dict[str, frozenset[str]] = {
    "authors": frozenset({"REPO", "IDENTITY", "IMAGE_TAG"}),
    "scan": frozenset({"REPO", "CODE_PATH", "IDENTITY", "AUTHOR", "IMAGE_TAG", "SNAPSHOT_DIR"}),
}

# Значение подставляется в рецепт make и попадает в порождаемый им shell, поэтому
# проверяется по разрешающему образцу, а не по перечню запрещённых символов: кавычка,
# `$`, обратная кавычка, `;` и перевод строки в классы ниже не входят и пройти не могут.
# \w покрывает кириллицу — имена участников пишутся как есть.
PARAMETER_PATTERNS: dict[str, re.Pattern[str]] = {
    "REPO": re.compile(r"^/[\w./\- ]{1,512}$"),
    "CODE_PATH": re.compile(r"^[\w./\-]{0,256}$"),
    "IDENTITY": re.compile(r"^[\w.@,=\- ]{1,512}$"),
    "AUTHOR": re.compile(r"^[\w.@\- ]{1,256}$"),
    "IMAGE_TAG": re.compile(r"^[\w.\-]{1,64}$"),
    "SNAPSHOT_DIR": re.compile(r"^[\w.\-/]{1,128}$"),
}

# Цели выполняются в корне репозитория: там лежит Makefile окружения
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORKDIR = REPOSITORY_ROOT

BIND = os.environ.get("AGENT_RUNNER_BIND", "0.0.0.0")
PORT = int(os.environ.get("AGENT_RUNNER_PORT", "11900"))
TOKEN = os.environ.get("AGENT_RUNNER_TOKEN", "")
WORKDIR = Path(os.environ.get("AGENT_RUNNER_WORKDIR", str(DEFAULT_WORKDIR)))
TIMEOUT = int(os.environ.get("AGENT_RUNNER_TIMEOUT", "900"))


class ParameterError(ValueError):
    """Присваивание не прошло проверку: имя вне списка, значение вне образца."""


def parse_assignments(encoded: str, target: str) -> list[str]:
    """Разобрать параметры цели из строки `args` и вернуть присваивания для make.

    Значения приезжают строками `ИМЯ=значение`, склеенными переводом строки и упакованными
    в url-safe base64: так через строку запроса проходят и пробелы, и кириллица, без
    процентного кодирования на стороне клиента.
    """
    padded = encoded + "=" * (-len(encoded) % 4)
    try:
        raw = base64.urlsafe_b64decode(padded).decode("utf-8")
    except (binascii.Error, UnicodeDecodeError) as error:
        raise ParameterError(f"параметры не разобраны: {error}") from None

    allowed = TARGET_PARAMETERS.get(target, frozenset())
    assignments: list[str] = []
    seen: set[str] = set()
    for line in raw.splitlines():
        if not line.strip():
            continue
        name, separator, value = line.partition("=")
        if not separator:
            raise ParameterError(f"ожидается «ИМЯ=значение», получено {line!r}")
        name = name.strip()
        if name not in allowed:
            permitted = ", ".join(sorted(allowed)) or "нет"
            raise ParameterError(
                f"переменная {name!r} для цели {target!r} не разрешена. Разрешены: {permitted}"
            )
        if name in seen:
            raise ParameterError(f"переменная {name!r} указана дважды")
        pattern = PARAMETER_PATTERNS[name]
        if not pattern.fullmatch(value):
            raise ParameterError(
                f"значение {name!r} не соответствует образцу {pattern.pattern}"
            )
        seen.add(name)
        assignments.append(f"{name}={value}")
    return assignments


class RunnerHandler(BaseHTTPRequestHandler):
    """Обрабатывает запросы вида `GET /run/{target}?args={base64}` с токеном в заголовке."""

    server_version = "host-runner/1.3"

    def do_GET(self) -> None:  # noqa: N802 — имя задано BaseHTTPRequestHandler
        # Ответ обязателен при любом исходе: без него клиент виснет до своего таймаута
        try:
            self._dispatch()
        except Exception as error:  # noqa: BLE001 — раннер не должен падать молча
            self._reply(500, f"Внутренняя ошибка раннера: {error!r}\n")

    def _dispatch(self) -> None:
        parts = urlsplit(self.path)

        if parts.path == "/healthz":
            self._reply(200, "ok\n")
            return

        if not parts.path.startswith("/run/"):
            self._reply(404, "Доступен только путь /run/{цель} и /healthz\n")
            return

        # Сравнение в байтах: compare_digest на строках с не-ASCII бросает TypeError
        supplied = self.headers.get("X-Runner-Token", "").encode("utf-8", "surrogateescape")
        if not hmac.compare_digest(supplied, TOKEN.encode("utf-8")):
            self._reply(403, "Неверный токен\n")
            return

        target = parts.path[len("/run/") :].strip("/")
        if target not in ALLOWED_TARGETS:
            allowed = ", ".join(sorted(ALLOWED_TARGETS))
            self._reply(400, f"Цель {target!r} не в белом списке.\nРазрешены: {allowed}\n")
            return

        encoded = parse_qs(parts.query).get("args", [""])[0]
        try:
            assignments = parse_assignments(encoded, target) if encoded else []
        except ParameterError as error:
            self._reply(400, f"{error}\n")
            return

        self._reply(200, self._run(target, assignments))

    def log_message(self, format: str, *args: object) -> None:
        """Каждый запрос виден в консоли раннера — что именно попросил агент."""
        sys.stderr.write(f"[host-runner] {self.address_string()} {format % args}\n")

    def _run(self, target: str, assignments: list[str]) -> str:
        command = ["make", target, *assignments]
        # Присваивания печатаются полностью: хозяин хоста должен видеть, какой каталог
        # агент попросил просканировать, а не только имя цели
        sys.stderr.write(f"[host-runner] выполняю: {' '.join(command)}\n")
        try:
            completed = subprocess.run(
                command,
                cwd=str(WORKDIR),
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return f"exit: timeout\nЦель {target} не уложилась в {TIMEOUT} с\n"
        except OSError as error:
            return f"exit: error\nНе удалось запустить make: {error}\n"

        return (
            f"exit: {completed.returncode}\n"
            f"--- stdout ---\n{completed.stdout}"
            f"--- stderr ---\n{completed.stderr}"
        )

    def _reply(self, status: int, body: str) -> None:
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    if not TOKEN:
        sys.stderr.write("Не задан AGENT_RUNNER_TOKEN — раннер без токена не запускается\n")
        return 1
    if not (WORKDIR / "Makefile").is_file():
        sys.stderr.write(f"В каталоге {WORKDIR} нет Makefile — проверьте AGENT_RUNNER_WORKDIR\n")
        return 1

    parametrised = ", ".join(sorted(TARGET_PARAMETERS))
    sys.stderr.write(
        f"[host-runner] каталог: {WORKDIR}\n"
        f"[host-runner] слушает: {BIND}:{PORT}\n"
        f"[host-runner] цели: {', '.join(sorted(ALLOWED_TARGETS))}\n"
        f"[host-runner] с параметрами: {parametrised}\n"
    )
    # Однопоточный сервер: цели выполняются строго по одной, параллельных make не будет
    HTTPServer((BIND, PORT), RunnerHandler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
