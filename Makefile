.PHONY: help init build up down shell

.DEFAULT_GOAL := help

# Список целей собирается из комментариев вида '## описание' в самом Makefile:
# описание живёт рядом с целью, поэтомуновая цель попадает в вывод без правки в двух местах.
help: ## Список команд с описаниями
	@printf 'Команды окружения SDD Developer Kit:\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sed 's/:.*## /|/' \
		| awk -F'|' '{printf "  make %-8s %s\n", $$1, $$2}'
	@printf '\nПорядок установки и переменные окружения — в README.md проекта kit'"'"'а.\n'

# Подготовка проекта к запуску: файл секретов, каталоги ключей и профилей,
# записи в .gitignore. Существующий .env не перезаписывается — он содержит секреты.
init: ## Подготовка проекта: .env, каталоги ключей и профилей, записи в .gitignore
	@if [ -f .env ]; then \
		echo "  .env уже существует — оставлен без изменений"; \
	else \
		cp .env.example .env; \
		echo "  создан .env из .env.example"; \
	fi
	@mkdir -p .ssh .claude-accounts
	@chmod 700 .ssh
	@touch .gitignore
	@if [ -s .gitignore ] && [ -n "$$(tail -c 1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
	@for entry in .env .ssh/ .claude-accounts/; do \
		grep -qxF "$$entry" .gitignore >/dev/null 2>&1 \
			|| { printf '%s\n' "$$entry" >> .gitignore; echo "  в .gitignore добавлено: $$entry"; }; \
	done
	@echo "Готово. Дальше: заполнить .env (GIT_HOST, CLAUDE_PROFILE) и положить SSH-ключ в .ssh/"

build: ## Сборка образа claude-openspec:local
	docker compose --profile claude build claude

up: ## Запуск контейнера агента
	docker compose --profile claude up -d --force-recreate claude

down: ## Остановка контейнера
	docker compose --profile claude down

# Вход в контейнер агента. Профиль берётся из окружения или из .env: без него
# контейнер смонтировал бы несуществующий каталог и остался без доступа к аккаунту.
shell: ## Вход в контейнер агента
	@profile="$${CLAUDE_PROFILE:-$$(sed -n 's/^CLAUDE_PROFILE=//p' .env 2>/dev/null | tail -n 1)}"; \
	accounts="$${CLAUDE_ACCOUNTS_DIR:-$$(sed -n 's/^CLAUDE_ACCOUNTS_DIR=//p' .env 2>/dev/null | tail -n 1)}"; \
	accounts="$${accounts:-.claude-accounts}"; \
	if [ -z "$$profile" ]; then \
		echo "Ошибка: не задан CLAUDE_PROFILE — укажите профиль аккаунта в .env или в окружении" >&2; \
		exit 1; \
	fi; \
	if [ ! -d "$$accounts/$$profile" ]; then \
		echo "Ошибка: каталог профиля не найден: $$accounts/$$profile" >&2; \
		exit 1; \
	fi; \
	docker compose --profile claude exec claude bash
