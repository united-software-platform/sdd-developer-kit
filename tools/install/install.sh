#!/bin/sh
#
# Установка SDD Developer Kit в каталог целевого проекта.
#
# Запускается из клона kit'а: ./tools/install/install.sh [ОПЦИИ] <каталог-проекта>
# Источником файлов служит сам клон, поэтому состав поставки всегда соответствует
# версии kit'а, из которой запущен скрипт.
#
# Установка выполняется в два прохода: первый строит план и ничего не пишет,
# второй записывает файлы после подтверждения. Без этого требования «ни один файл
# не записан до подтверждения» и «отказ не изменяет проект» невыполнимы.

set -eu

MANIFEST_NAME=".sdd-kit-manifest.json"

# Явный список путей поставки; каталоги разворачиваются рекурсивно.
# Список задан явно, а не выведен из .gitignore: граница поставки не совпадает с границей
# версионирования — openspec/changes и openspec/specs версионируются, но остаются
# рабочими артефактами самого kit'а и в чужой проект не переносятся.
PAYLOAD_PATHS="Dockerfile
docker-compose.yml
Makefile
.env.example
CLAUDE.md
AGENTS.md
rules
.claude/skills
.claude/commands
openspec/config.yaml
tools/host-runner
docs/sdd-kit.md"

DRY_RUN=0
ASSUME_YES=0
TARGET=""

usage() {
    cat <<'USAGE'
Использование: install.sh [ОПЦИИ] <каталог-проекта>

Разворачивает SDD Developer Kit в каталоге целевого проекта.

Опции:
  -n, --dry-run   показать план установки и завершиться, ничего не записав
  -y, --yes       неинтерактивный режим: перезапись разрешена заранее
  -h, --help      показать эту справку

Целевой каталог должен существовать и быть доступен на запись.
USAGE
}

die() {
    printf 'Ошибка: %s\n' "$1" >&2
    exit 1
}

# --- Разбор аргументов -------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes)     ASSUME_YES=1 ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           usage >&2; die "неизвестная опция: $1" ;;
        *)
            [ -z "$TARGET" ] || { usage >&2; die "целевой каталог указан более одного раза"; }
            TARGET="$1"
            ;;
    esac
    shift
done

while [ $# -gt 0 ]; do
    [ -z "$TARGET" ] || { usage >&2; die "целевой каталог указан более одного раза"; }
    TARGET="$1"
    shift
done

[ -n "$TARGET" ] || { usage >&2; die "не указан каталог целевого проекта"; }

# --- Контрольные суммы -------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
    checksum() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "не найдена утилита вычисления контрольной суммы (sha256sum или shasum)"
fi

# --- Корень kit'а и версия ---------------------------------------------------

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

VERSION_FILE="$KIT_ROOT/VERSION"
# Версия читается из файла, а не из git: клон может быть получен архивом без истории.
[ -f "$VERSION_FILE" ] || die "не найден файл версии kit'а: $VERSION_FILE"
KIT_VERSION=$(head -n 1 "$VERSION_FILE" | tr -d ' \011\015\012')
[ -n "$KIT_VERSION" ] || die "файл версии kit'а пуст: $VERSION_FILE"

# --- Проверка целевого каталога до любых изменений ---------------------------

[ -e "$TARGET" ] || die "каталог целевого проекта не существует: $TARGET"
[ -d "$TARGET" ] || die "путь целевого проекта не является каталогом: $TARGET"
[ -w "$TARGET" ] || die "каталог целевого проекта недоступен на запись: $TARGET"

TARGET_ABS=$(CDPATH= cd -- "$TARGET" && pwd)
[ "$TARGET_ABS" != "$KIT_ROOT" ] || die "целевой каталог совпадает с каталогом kit'а"

MANIFEST_PATH="$TARGET_ABS/$MANIFEST_NAME"

# --- Рабочие файлы -----------------------------------------------------------

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
trap 'rm -rf "$WORK_DIR"; exit 130' INT
trap 'rm -rf "$WORK_DIR"; exit 143' TERM

FILES="$WORK_DIR/files"
PLAN="$WORK_DIR/plan"
MANIFEST_IDX="$WORK_DIR/manifest.idx"

# --- Первый проход: разворачивание списка поставки ---------------------------

: > "$FILES"
OLD_IFS=$IFS
IFS='
'
for payload_path in $PAYLOAD_PATHS; do
    IFS=$OLD_IFS
    src="$KIT_ROOT/$payload_path"
    # Отсутствующий путь прерывает установку: молчаливый пропуск сделал бы состав
    # поставки зависящим от состояния клона.
    [ -e "$src" ] || die "путь поставки отсутствует в kit'е: $payload_path"
    if [ -d "$src" ]; then
        find "$src" -type f -print | sed "s|^$KIT_ROOT/||" >> "$FILES"
    else
        printf '%s\n' "$payload_path" >> "$FILES"
    fi
    IFS='
'
done
IFS=$OLD_IFS

sort -o "$FILES" "$FILES"
[ -s "$FILES" ] || die "состав поставки пуст"

# --- Первый проход: индекс манифеста предыдущей установки --------------------

: > "$MANIFEST_IDX"
if [ -f "$MANIFEST_PATH" ]; then
    sed -n 's/^[ 	]*{"path": "\(.*\)", "sha256": "\([0-9a-f]*\)"}.*$/\1 \2/p' \
        "$MANIFEST_PATH" > "$MANIFEST_IDX"
fi

manifest_sha() {
    awk -v p="$1" '$1 == p { print $2; exit }' "$MANIFEST_IDX"
}

# --- Первый проход: построение плана -----------------------------------------

: > "$PLAN"
while IFS= read -r rel; do
    dst="$TARGET_ABS/$rel"
    if [ ! -e "$dst" ]; then
        printf 'CREATE %s\n' "$rel" >> "$PLAN"
    elif [ ! -f "$dst" ]; then
        # По пути файла поставки лежит каталог или иной объект — разрешает пользователь.
        printf 'CONFLICT %s\n' "$rel" >> "$PLAN"
    else
        recorded=$(manifest_sha "$rel")
        current=$(checksum "$dst")
        if [ -n "$recorded" ] && [ "$recorded" = "$current" ]; then
            # Файл установлен kit'ом и с тех пор не менялся — перезапись безопасна.
            printf 'UPDATE %s\n' "$rel" >> "$PLAN"
        else
            printf 'CONFLICT %s\n' "$rel" >> "$PLAN"
        fi
    fi
done < "$FILES"

plan_list() { grep "^$1 " "$PLAN" | cut -d' ' -f2- || true; }
plan_count() { grep -c "^$1 " "$PLAN" || true; }

N_CREATE=$(plan_count CREATE)
N_UPDATE=$(plan_count UPDATE)
N_CONFLICT=$(plan_count CONFLICT)

# --- Отчёт по плану ----------------------------------------------------------

printf 'Kit:             %s (версия %s)\n' "$KIT_ROOT" "$KIT_VERSION"
printf 'Целевой проект:  %s\n\n' "$TARGET_ABS"

if [ "$N_CREATE" -gt 0 ]; then
    printf 'Будет создано (%s):\n' "$N_CREATE"
    plan_list CREATE | sed 's/^/  + /'
    printf '\n'
fi

if [ "$N_UPDATE" -gt 0 ]; then
    printf 'Будет обновлено без потери правок (%s) — файлы установлены kit'"'"'ом и не менялись:\n' "$N_UPDATE"
    plan_list UPDATE | sed 's/^/  ~ /'
    printf '\n'
fi

if [ "$N_CONFLICT" -gt 0 ]; then
    printf 'Будет ПЕРЕЗАПИСАНО с потерей текущего содержимого (%s):\n' "$N_CONFLICT"
    plan_list CONFLICT | sed 's/^/  ! /'
    printf '\n'
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Режим предварительного просмотра: ничего не записано.\n'
    exit 0
fi

# --- Подтверждение перезаписи ------------------------------------------------

if [ "$N_CONFLICT" -gt 0 ]; then
    printf 'Внимание: перечисленные файлы будут перезаписаны, их текущее содержимое будет потеряно.\n'
    if [ "$ASSUME_YES" -eq 1 ]; then
        printf 'Перезапись разрешена ключом --yes.\n\n'
    elif [ -t 0 ]; then
        printf 'Перезаписать эти файлы? [y/N]: '
        read -r answer || answer=""
        case "$answer" in
            y|Y|yes|YES|да|ДА|Да) printf '\n' ;;
            *) printf 'Установка отменена, файлы не изменены.\n'; exit 1 ;;
        esac
    else
        die "обнаружены конфликты, а запросить подтверждение невозможно: запустите с --yes или в интерактивном режиме"
    fi
fi

# --- Второй проход: запись ---------------------------------------------------

while IFS= read -r rel; do
    dst="$TARGET_ABS/$rel"
    dst_dir=$(dirname -- "$dst")
    [ -d "$dst_dir" ] || mkdir -p -- "$dst_dir"
    if [ -d "$dst" ]; then
        rm -rf -- "$dst"
    fi
    cp -p -- "$KIT_ROOT/$rel" "$dst"
done < "$FILES"

# --- Манифест пишется последним ----------------------------------------------
# Его отсутствие или неполнота — признак незавершённой установки.

{
    printf '{\n'
    printf '  "kit_version": "%s",\n' "$KIT_VERSION"
    printf '  "installed_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "files": [\n'
    manifest_first=1
    while IFS= read -r rel; do
        sha=$(checksum "$TARGET_ABS/$rel")
        if [ "$manifest_first" -eq 1 ]; then
            manifest_first=0
        else
            printf ',\n'
        fi
        printf '    {"path": "%s", "sha256": "%s"}' "$rel" "$sha"
    done < "$FILES"
    printf '\n  ]\n}\n'
} > "$MANIFEST_PATH"

printf 'Установка завершена: создано %s, обновлено %s, перезаписано %s.\n' \
    "$N_CREATE" "$N_UPDATE" "$N_CONFLICT"
printf 'Манифест: %s\n' "$MANIFEST_PATH"
printf 'Следующие шаги — см. %s\n' "$TARGET_ABS/docs/sdd-kit.md"
