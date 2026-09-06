## 1. Переименование репозитория на GitHub

- [x] 1.1 Пользователь переименовывает репозиторий `united-software-platform/ssd-developer-kit`
      в `united-software-platform/sdd-developer-kit` на GitHub — проверить: `gh repo view
      united-software-platform/sdd-developer-kit` возвращает репозиторий

## 2. Синхронизация локального remote

- [x] 2.1 Обновить `git remote set-url origin
      git@github.com:united-software-platform/sdd-developer-kit.git` в этой рабочей среде —
      проверить `git remote -v` показывает новый URL
- [x] 2.2 Проверить `git fetch` и `git push` с новым URL без ошибок аутентификации

## 3. Приведение упоминаний имени к канону

- [x] 3.1 Заменить в `README.md` заголовок и упоминания `SDD Workbench` на `SDD Developer Kit` —
      проверить `grep -ri "SDD Workbench" README.md` не находит совпадений
- [x] 3.2 Проверить `CLAUDE.md`, `AGENTS.md`, `.idea/*` на отсутствие устаревших названий
      (`ssd-developer-kit`, `SDD Workbench`, `ReqControl`) вне исторических записей версионирования —
      исторические записи в таблицах версионирования не трогать
