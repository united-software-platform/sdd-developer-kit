#!/bin/sh
# Проверка версии репозитория SDD Developer Kit.
#
# Одна проверка: состав поставки изменён относительно базы сравнения, а VERSION не тронут —
# инкрементацию забыли. Изменения вне состава поставки требования не поднимают.
#
# Согласованность тега vX.Y.Z с содержимым VERSION здесь не проверяется: и файл, и коммит,
# и тег создаёт один запуск релизного сценария .github/workflows/release.yml, поэтому
# разойтись они не могут. Проверять гарантированное — сторожить пустое место.
#
# Перечень путей поставки читается из payload.txt — того же файла, что читает установщик.
# Собственной копии перечня здесь нет: две копии со временем разошлись бы, и проверка молча
# перестала бы замечать часть поставки.
#
# Скрипт вызывается локально до отправки изменений и из пайплайна GitHub Actions —
# вердикт в обоих случаях один и тот же. В состав поставки скрипт не входит.

set -eu

SELF=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BASE=""

usage() {
    cat <<'USAGE'
Использование: check.sh [ОПЦИИ]

Проверяет, что изменение состава поставки сопровождается инкрементацией VERSION.

Опции:
      --base <REF>    база сравнения. По умолчанию — предыдущее состояние ветки (HEAD~1).
                      Сравнение трёхточечное: для ветки берётся точка её ветвления от базы
      --repo <ПУТЬ>   корень репозитория (по умолчанию — на два уровня выше скрипта)
  -h, --help          эта справка

Коды возврата: 0 — проверка пройдена, 1 — нарушение, 2 — ошибка вызова или окружения.
USAGE
}

die() {
    printf '%s: %s\n' "$SELF" "$1" >&2
    exit "${2:-2}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --base)
            [ $# -ge 2 ] || die "ключ --base требует значения"
            BASE=$2; shift ;;
        --repo)
            [ $# -ge 2 ] || die "ключ --repo требует значения"
            ROOT=$2; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "неизвестный аргумент: $1 (см. $SELF --help)" ;;
    esac
    shift
done

[ -d "$ROOT" ] || die "каталог репозитория не найден: $ROOT"
ROOT=$(cd "$ROOT" && pwd)

command -v git >/dev/null 2>&1 || die "не найдена утилита git"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "каталог не является git-репозиторием: $ROOT"

PAYLOAD_LIST="$ROOT/payload.txt"
[ -f "$PAYLOAD_LIST" ] || die "не найден $PAYLOAD_LIST — из него читается состав поставки"
PAYLOAD=$(grep -v '^[[:space:]]*$' "$PAYLOAD_LIST" || true)
[ -n "$PAYLOAD" ] || die "перечень путей поставки пуст: $PAYLOAD_LIST"

version_at() {
    # Содержимое VERSION в указанной ревизии; пустая строка, если файла там нет.
    git -C "$ROOT" show "$1:VERSION" 2>/dev/null | head -n 1 | tr -d ' \011\015\012' || true
}

BASE=${BASE:-HEAD~1}

if ! git -C "$ROOT" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    printf '%s: база сравнения не найдена: %s\n' "$SELF" "$BASE" >&2
    printf 'Углубите историю (fetch-depth) или задайте --base.\n' >&2
    exit 2
fi

changed=$(git -C "$ROOT" diff --name-only "$BASE...HEAD")
if [ -z "$changed" ]; then
    printf 'Поставка: изменений относительно %s нет.\n' "$BASE"
    exit 0
fi

# Изменённый путь относится к поставке, если совпадает с записью перечня или лежит под ней.
changed_payload=$(printf '%s\n' "$changed" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf '%s\n' "$PAYLOAD" | while IFS= read -r prefix; do
        [ -n "$prefix" ] || continue
        case "$file" in
            "$prefix"|"$prefix"/*) printf '%s\n' "$file" ;;
        esac
    done
done | sort -u)

if [ -z "$changed_payload" ]; then
    printf 'Поставка: изменения есть, но состава поставки не касаются — инкрементация не нужна.\n'
    exit 0
fi

base_version=$(version_at "$BASE")
head_version=$(version_at HEAD)

if [ "$base_version" = "$head_version" ]; then
    printf '%s: состав поставки изменён, а VERSION остался %s\n' "$SELF" "$head_version" >&2
    printf 'Изменённые пути поставки:\n' >&2
    printf '%s\n' "$changed_payload" | sed 's|^|  - |' >&2
    printf 'Выпустите версию: запустите workflow «release» с разрядом major, minor или patch.\n' >&2
    exit 1
fi

printf 'Поставка: изменена, версия повышена %s -> %s.\n' "$base_version" "$head_version"
printf 'Проверка версии пройдена.\n'
