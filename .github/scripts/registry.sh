#!/bin/sh
# Чтение метаданных образа из реестра без docker.
#
# Пайплайну нужны две вещи до сборки: конкретный выпуск, скрытый за подвижным тегом базового
# образа, и состав уже опубликованного образа — чтобы не пересобирать неизменное. Обе читаются
# из манифеста и конфигурации образа, то есть до и без его загрузки: загружать мультиарх-образ
# ради пары строк метаданных дороже самой сборки.
#
# Обращения анонимные: образы организации публичны, а токен рабочего процесса даёт права
# на запись, которые заданию параметров не нужны.
#
# Использование:
#   sh .github/scripts/registry.sh digest <репозиторий> <ссылка>
#   sh .github/scripts/registry.sh labels <репозиторий> <ссылка>
#   sh .github/scripts/registry.sh label  <репозиторий> <ссылка> <имя метки>
#
# Коды возврата: 0 — прочитано, 4 — образа с такой ссылкой в реестре нет,
# 1 — ошибка обращения к реестру или разбора ответа.
set -eu

REGISTRY=ghcr.io

# Медиатипы перечислены оба поколения: индекс мультиарх-образа приходит как OCI-индекс,
# а образ одной архитектуры — как манифест; без Accept реестр отдаёт устаревшую схему.
ACCEPT='application/vnd.oci.image.index.v1+json,
application/vnd.docker.distribution.manifest.list.v2+json,
application/vnd.oci.image.manifest.v1+json,
application/vnd.docker.distribution.manifest.v2+json'
ACCEPT=$(printf '%s' "$ACCEPT" | tr -d '\012')

die() { echo "registry.sh: $*" >&2; exit 1; }

token() {
    curl -fsSL "https://$REGISTRY/token?service=$REGISTRY&scope=repository:$1:pull" \
        | jq -er '.token' 2>/dev/null \
        || die "не удалось получить токен чтения репозитория $1"
}

# Тело манифеста по ссылке. Отсутствие образа отделено от ошибки обращения: первое —
# штатное состояние (образ ещё не публиковался), второе — повод остановить прогон.
manifest() {
    _repo=$1; _ref=$2; _token=$3
    _body=$(mktemp)
    _status=$(curl -sSL -o "$_body" -w '%{http_code}' \
        -H "Authorization: Bearer $_token" -H "Accept: $ACCEPT" \
        "https://$REGISTRY/v2/$_repo/manifests/$_ref") || die "реестр недоступен: $_repo:$_ref"
    case "$_status" in
        200) cat "$_body"; rm -f "$_body" ;;
        404) rm -f "$_body"; return 4 ;;
        *)   rm -f "$_body"; die "реестр ответил $_status на запрос манифеста $_repo:$_ref" ;;
    esac
}

cmd_digest() {
    _repo=$1; _ref=$2
    _token=$(token "$_repo")
    _headers=$(mktemp)
    _status=$(curl -sSL -o /dev/null -D "$_headers" -w '%{http_code}' \
        -H "Authorization: Bearer $_token" -H "Accept: $ACCEPT" \
        "https://$REGISTRY/v2/$_repo/manifests/$_ref") || die "реестр недоступен: $_repo:$_ref"
    [ "$_status" = "404" ] && { rm -f "$_headers"; return 4; }
    [ "$_status" = "200" ] || { rm -f "$_headers"; die "реестр ответил $_status на запрос $_repo:$_ref"; }
    _digest=$(tr -d '\015' < "$_headers" | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p' | tail -n 1)
    rm -f "$_headers"
    [ -n "$_digest" ] || die "реестр не вернул digest манифеста $_repo:$_ref"
    printf '%s\n' "$_digest"
}

# Метки лежат в конфигурации образа, а не в манифесте, поэтому чтение трёхшаговое:
# индекс -> манифест архитектуры -> блоб конфигурации. Для мультиарх-образа берётся amd64:
# метки состава от архитектуры не зависят, а разбирать обе — удваивать обращения впустую.
cmd_labels() {
    _repo=$1; _ref=$2
    _token=$(token "$_repo")
    _manifest=$(manifest "$_repo" "$_ref" "$_token") || return $?

    if printf '%s' "$_manifest" | jq -e '.manifests' >/dev/null 2>&1; then
        _arch_digest=$(printf '%s' "$_manifest" \
            | jq -er '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' \
            | head -n 1) || die "в индексе $_repo:$_ref нет манифеста linux/amd64"
        _manifest=$(manifest "$_repo" "$_arch_digest" "$_token") || return $?
    fi

    _config=$(printf '%s' "$_manifest" | jq -er '.config.digest') \
        || die "манифест $_repo:$_ref не называет конфигурацию образа"
    curl -fsSL -H "Authorization: Bearer $_token" \
        "https://$REGISTRY/v2/$_repo/blobs/$_config" \
        | jq -er '.config.Labels // {}' \
        || die "не удалось прочитать метки образа $_repo:$_ref"
}

cmd_label() {
    cmd_labels "$1" "$2" | jq -r --arg name "$3" '.[$name] // ""'
}

case "${1:-}" in
    digest) [ $# -eq 3 ] || die "использование: digest <репозиторий> <ссылка>"; cmd_digest "$2" "$3" ;;
    labels) [ $# -eq 3 ] || die "использование: labels <репозиторий> <ссылка>"; cmd_labels "$2" "$3" ;;
    label)  [ $# -eq 4 ] || die "использование: label <репозиторий> <ссылка> <метка>"; cmd_label "$2" "$3" "$4" ;;
    *)      die "неизвестная команда «${1:-}»; доступны digest, labels, label" ;;
esac
