#!/usr/bin/env bash
# Клиент раннера для контейнера агента: запрашивает одну цель make и печатает её вывод.
# Параметры подключения берутся из окружения (заполняются из .env через env_file).
#
# Использование:
#   call.sh <цель>                                  цель без параметров
#   call.sh <цель> ПЕРЕМЕННАЯ=значение [...]        цель с параметрами
#
# Пример:
#   call.sh scan REPO=/путь/к/проекту AUTHOR='Иванов Иван'
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Использование: $(basename "$0") <цель make> [ПЕРЕМЕННАЯ=значение ...]" >&2
  exit 2
fi
shift

URL="${AGENT_RUNNER_URL:-}"
TOKEN="${AGENT_RUNNER_TOKEN:-}"
if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
  echo "Не заданы AGENT_RUNNER_URL и/или AGENT_RUNNER_TOKEN" >&2
  exit 2
fi

# Присваивания уходят одной строкой url-safe base64: значения содержат пробелы и кириллицу,
# а процентное кодирование в bash пришлось бы писать вручную и посимвольно.
QUERY=""
if [ "$#" -gt 0 ]; then
  for assignment in "$@"; do
    case "$assignment" in
      *=*) ;;
      *) echo "Параметр должен иметь вид ПЕРЕМЕННАЯ=значение, получено: $assignment" >&2; exit 2 ;;
    esac
  done
  encoded=$(printf '%s\n' "$@" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  QUERY="?args=${encoded}"
fi

# --content-on-error печатает тело и при статусе 4xx: отказ раннера — это не недоступность,
# поэтому код возврата wget сам по себе о доставке запроса не говорит
set +e
response=$(wget -q -O - --content-on-error \
  --header="X-Runner-Token: ${TOKEN}" \
  --tries=1 --connect-timeout=10 \
  --read-timeout="${AGENT_RUNNER_TIMEOUT:-900}" \
  "${URL}/run/${TARGET}${QUERY}")
wget_status=$?
set -e

if [ -z "$response" ]; then
  echo "Раннер недоступен по ${URL} (wget: ${wget_status})" >&2
  exit 1
fi

echo "$response"

# Ответ цели начинается со строки `exit: N`; иначе это отказ раннера (белый список, токен, путь)
case "$(printf '%s\n' "$response" | head -n 1)" in
  "exit: 0") exit 0 ;;
  *) exit 1 ;;
esac
