## 1. Makefile репозитория

- [x] 1.1 Создать `Makefile` в корне репозитория с целями `build`, `up`, `down`, вызывающими
      команды `docker compose --profile claude build/up/down claude` из корневого `README.md`, и
      проверить, что `make build`, `CLAUDE_PROFILE=<профиль> make up`, `make down` завершаются
      успешно на хосте
- [x] 1.2 Проверить, что `runner.py` при старте находит `Makefile` (`WORKDIR / "Makefile"`) без
      правки `AGENT_RUNNER_WORKDIR`

## 2. Сокращение белого списка runner.py

- [x] 2.1 Сократить `ALLOWED_TARGETS` до `{"build", "up", "down"}`, убрать `init`, `restart`,
      `logs`, `authors`, `scan`
- [x] 2.2 Удалить `TARGET_PARAMETERS`, `PARAMETER_PATTERNS`, функцию `parse_assignments` и разбор
      `args` из query-строки в `_dispatch`/`_run` — целям параметры больше не передаются
- [x] 2.3 Проверить вручную (`tools/host-runner/call.sh build`, `up`, `down`) и через отклонённую
      цель (`tools/host-runner/call.sh authors` → код возврата не ноль, тело ответа `400` с
      перечнем `build, down, up`)

## 3. Упрощение call.sh

- [x] 3.1 Убрать в `call.sh` разбор позиционных присваиваний `ПЕРЕМЕННАЯ=значение` и сборку `args`
      в base64 — клиент передаёт только имя цели
- [x] 3.2 Проверить `tools/host-runner/call.sh up` без параметров: код возврата совпадает с
      `exit:` в ответе раннера

## 4. Документация host-runner

- [x] 4.1 Переписать `tools/host-runner/README.md` заново по шаблону `DOC-014`: убрать
      дублирование и обрыв текста, обновить разделы «Как это устроено», «Использование агентом»,
      «Границы доступа» под белый список `build`/`up`/`down` без параметров и без пунктов про
      `authors`/`scan`, `REPO`, `SNAPSHOT_DIR`
- [x] 4.2 Добавить в таблицу версий `tools/host-runner/README.md` запись об этом изменении
      следующим номером после `1.3.1`
- [x] 4.3 Проверить корневой `README.md` (раздел «Опционально: host-runner на хосте») и
      `.env.example` на отсутствие ссылок на `init`/`restart`/`logs`/`authors`/`scan` или их
      параметры; при отсутствии таких ссылок — оставить без изменений
