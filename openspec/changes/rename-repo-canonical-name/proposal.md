## Why

Название проекта расходится между подсистемами: репозиторий на GitHub называется
`ssd-developer-kit` (опечатка — «ssd» вместо «sdd», хотя проект про Spec-Driven Development),
IDE-проект называется `SDD Developer Kit` (орфография верная), а часть документации ссылалась на
третье название — `SDD Workbench`. Пользователь зафиксировал каноническое имя — `SDD Developer Kit`.
Нужно привести репозиторий и связанные ссылки к этому имени.

## What Changes

- **BREAKING**: репозиторий на GitHub переименован из `ssd-developer-kit` в `sdd-developer-kit`.
  GitHub автоматически редиректит старый URL на новый, но `git remote` во всех локальных клонах
  (включая эту рабочую среду) должен быть обновлён на новый URL.
- В `README.md` заголовок и упоминания названия проекта приведены к `SDD Developer Kit` вместо
  `SDD Workbench`.
- Проверены прочие ссылки на имя проекта (`.idea/*`, `CLAUDE.md`, `AGENTS.md`) на соответствие
  канону; исторические упоминания прежних названий (`ReqControl`, `experience-graph`) в
  версионировании `tools/host-runner/README.md` не меняются — это история изменений, а не текущее
  состояние.

## Capabilities

Поведение системы не меняется — только имя репозитория и упоминания в документации.
`skip_specs: true` зафиксирован в `.openspec.yaml` этого change.

## Impact

- GitHub: переименование репозитория `united-software-platform/ssd-developer-kit` →
  `united-software-platform/sdd-developer-kit`. Существующие форки, локальные клоны и CI-конфиги
  со старым URL продолжат работать через редирект GitHub, но их стоит обновить.
- Локально в этой рабочей среде: `git remote set-url origin` на новый URL.
- `README.md`: заголовок и упоминания названия проекта.
