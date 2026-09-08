#!/bin/sh
#
# Установка SDD Developer Kit в текущий проект.
#
#   curl -fsSL https://raw.githubusercontent.com/united-software-platform/sdd-developer-kit/main/install.sh | sh
#
# Клонировать репозиторий не требуется: скрипт сам скачивает архив kit'а во временный
# каталог и раскладывает состав поставки в текущий каталог.
#
# Установка выполняется в два прохода: первый строит план и ничего не пишет, второй
# записывает файлы после подтверждения. Без этого нельзя одновременно выполнить
# «ни один файл не записан до подтверждения» и «отказ не изменяет проект».

set -eu

KIT_REPO="${SDD_KIT_REPO:-united-software-platform/sdd-developer-kit}"
KIT_REF="${SDD_KIT_REF:-main}"
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
SDD-KIT.md
rules
.claude/skills
.claude/commands
openspec/config.yaml
tools/host-runner"

DRY_RUN=0
ASSUME_YES=0
SOURCE_DIR=""

usage() {
    cat <<'USAGE'
Использование: install.sh [ОПЦИИ]

Разворачивает SDD Developer Kit в текущем каталоге.

Опции:
  -n, --dry-run       показать план установки и завершиться, ничего не записав
  -y, --yes           не спрашивать подтверждения перезаписи
      --ref <REF>     ветка, тег или коммит kit'а (по умолчанию main)
      --source <DIR>  взять состав поставки из локального каталога вместо загрузки
  -h, --help          показать эту справку

При запуске через конвейер опции передаются так:
  curl -fsSL <URL>/install.sh | sh -s -- --dry-run
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
        --ref)        [ $# -ge 2 ] || die "ключ --ref требует значения"; KIT_REF="$2"; shift ;;
        --ref=*)      KIT_REF="${1#--ref=}" ;;
        --source)     [ $# -ge 2 ] || die "ключ --source требует значения"; SOURCE_DIR="$2"; shift ;;
        --source=*)   SOURCE_DIR="${1#--source=}" ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        *)            usage >&2; die "неизвестный аргумент: $1" ;;
    esac
    shift
done

[ $# -eq 0 ] || { usage >&2; die "лишние аргументы: $*"; }

# --- Внешние утилиты ---------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
    checksum() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "не найдена утилита вычисления контрольной суммы (sha256sum или shasum)"
fi

# Команда установки предполагает curl, но сам скрипт после запуска работает в
# произвольной системе: проверка дешевле невнятного сбоя в середине установки.
if [ -n "$SOURCE_DIR" ]; then
    fetch() { die "загрузка не требуется при указанном --source"; }
elif command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -O "$2" "$1"; }
else
    die "не найден ни curl, ни wget — установите один из них и повторите"
fi

# tar распаковывает gzip внешней утилитой, поэтому нужны обе.
command -v tar  >/dev/null 2>&1 || die "не найдена утилита tar"
command -v gzip >/dev/null 2>&1 || die "не найдена утилита gzip"

# --- Проверка текущего каталога до любых изменений ---------------------------

TARGET=$(pwd)
[ -w "$TARGET" ] || die "текущий каталог недоступен на запись: $TARGET"

MANIFEST_PATH="$TARGET/$MANIFEST_NAME"

# --- Рабочие файлы -----------------------------------------------------------

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
trap 'rm -rf "$WORK_DIR"; exit 130' INT
trap 'rm -rf "$WORK_DIR"; exit 143' TERM

FILES="$WORK_DIR/files"
PLAN="$WORK_DIR/plan"
MANIFEST_IDX="$WORK_DIR/manifest.idx"

# --- Получение состава поставки ----------------------------------------------

if [ -n "$SOURCE_DIR" ]; then
    [ -d "$SOURCE_DIR" ] || die "каталог источника не существует: $SOURCE_DIR"
    SRC=$(CDPATH= cd -- "$SOURCE_DIR" && pwd)
    [ "$SRC" != "$TARGET" ] || die "каталог источника совпадает с текущим каталогом"
    printf 'Источник:       %s\n' "$SRC"
else
    SRC="$WORK_DIR/kit"
    mkdir -p "$SRC"
    ARCHIVE_URL="https://codeload.github.com/$KIT_REPO/tar.gz/$KIT_REF"
    printf 'Загрузка %s (%s)...\n' "$KIT_REPO" "$KIT_REF"
    # Архив — одна атомарная единица загрузки: либо распаковался целиком,
    # либо установка прерывается до записи в проект.
    fetch "$ARCHIVE_URL" "$WORK_DIR/kit.tar.gz" \
        || die "не удалось загрузить $ARCHIVE_URL — проверьте сеть и значение --ref"
    tar -xzf "$WORK_DIR/kit.tar.gz" -C "$SRC" --strip-components=1 \
        || die "не удалось распаковать архив kit'а"
fi

VERSION_FILE="$SRC/VERSION"
# Версия читается из файла, а не из git: архив приходит без истории.
[ -f "$VERSION_FILE" ] || die "в составе kit'а нет файла версии VERSION"
KIT_VERSION=$(head -n 1 "$VERSION_FILE" | tr -d ' \011\015\012')
[ -n "$KIT_VERSION" ] || die "файл версии kit'а пуст"

# --- Первый проход: разворачивание списка поставки ---------------------------

: > "$FILES"
OLD_IFS=$IFS
IFS='
'
for payload_path in $PAYLOAD_PATHS; do
    IFS=$OLD_IFS
    src_path="$SRC/$payload_path"
    # Отсутствующий путь прерывает установку: молчаливый пропуск сделал бы состав
    # поставки зависящим от того, что попало в архив.
    [ -e "$src_path" ] || die "путь поставки отсутствует в составе kit'а: $payload_path"
    if [ -d "$src_path" ]; then
        find "$src_path" -type f -print | sed "s|^$SRC/||" >> "$FILES"
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
    dst="$TARGET/$rel"
    if [ ! -e "$dst" ]; then
        printf 'CREATE %s\n' "$rel" >> "$PLAN"
    elif [ ! -f "$dst" ]; then
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

plan_list()  { grep "^$1 " "$PLAN" | cut -d' ' -f2- || true; }
plan_count() { grep -c "^$1 " "$PLAN" || true; }

N_CREATE=$(plan_count CREATE)
N_UPDATE=$(plan_count UPDATE)
N_CONFLICT=$(plan_count CONFLICT)

# --- Отчёт по плану ----------------------------------------------------------

printf 'Версия kit'"'"'а: %s\n' "$KIT_VERSION"
printf 'Проект:         %s\n\n' "$TARGET"

if [ "$N_CREATE" -gt 0 ]; then
    printf 'Будет создано (%s):\n' "$N_CREATE"
    plan_list CREATE | sed 's/^/  + /'
    printf '\n'
fi

if [ "$N_UPDATE" -gt 0 ]; then
    printf 'Будет обновлено без потери правок (%s) — установлено kit'"'"'ом и не менялось:\n' "$N_UPDATE"
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
# При запуске через конвейер стандартный ввод занят телом скрипта, поэтому вопрос
# задаётся управляющему терминалу сеанса.

if [ "$N_CONFLICT" -gt 0 ]; then
    printf 'Внимание: перечисленные файлы будут перезаписаны, их содержимое будет потеряно.\n'
    if [ "$ASSUME_YES" -eq 1 ]; then
        printf 'Перезапись разрешена ключом --yes.\n\n'
    elif (exec < /dev/tty) 2>/dev/null; then
        printf 'Перезаписать эти файлы? [y/N]: ' > /dev/tty
        read -r answer < /dev/tty || answer=""
        case "$answer" in
            y|Y|yes|YES|да|ДА|Да) printf '\n' ;;
            *) printf 'Установка отменена, файлы не изменены.\n'; exit 1 ;;
        esac
    else
        die "обнаружены конфликты, а спросить некого: нет управляющего терминала — повторите с --yes"
    fi
fi

# --- Второй проход: запись ---------------------------------------------------

while IFS= read -r rel; do
    dst="$TARGET/$rel"
    dst_dir=$(dirname -- "$dst")
    [ -d "$dst_dir" ] || mkdir -p -- "$dst_dir"
    if [ -d "$dst" ]; then
        rm -rf -- "$dst"
    fi
    cp -p -- "$SRC/$rel" "$dst"
done < "$FILES"

# --- Манифест пишется последним ----------------------------------------------
# Его отсутствие или неполнота — признак незавершённой установки.

{
    printf '{\n'
    printf '  "kit_version": "%s",\n' "$KIT_VERSION"
    printf '  "kit_ref": "%s",\n' "$KIT_REF"
    printf '  "installed_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "files": [\n'
    manifest_first=1
    while IFS= read -r rel; do
        sha=$(checksum "$TARGET/$rel")
        if [ "$manifest_first" -eq 1 ]; then
            manifest_first=0
        else
            printf ',\n'
        fi
        printf '    {"path": "%s", "sha256": "%s"}' "$rel" "$sha"
    done < "$FILES"
    printf '\n  ]\n}\n'
} > "$MANIFEST_PATH"

printf 'Установлено: создано %s, обновлено %s, перезаписано %s.\n' \
    "$N_CREATE" "$N_UPDATE" "$N_CONFLICT"
printf '\nДальше по шагам — см. SDD-KIT.md. Следующий шаг: make init\n'
