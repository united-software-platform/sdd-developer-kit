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

# Значение переменной из .env: файл заполняется пользователем и на момент первого
# запуска init может быть неполным, поэтому пустое значение заменяется умолчанием
# из .env.example. Разбор построчный, а не через include: .env — файл секретов,
# и его содержимое не должно попадать в пространство имён переменных make.
env_value = $$(sed -n 's/^$(1)=//p' .env 2>/dev/null | tail -n 1)

# Подготовка проекта к запуску: файл секретов, каталоги ключей и профилей,
# записи в .gitignore, SSH-ключ проекта и конфигурация SSH для git-хоста.
# Существующие .env, ключ и конфигурация SSH не перезаписываются: первый содержит
# секреты, ключ может быть уже зарегистрирован в git-сервисе, конфигурация — правки
# пользователя.
init: ## Подготовка проекта: .env, каталоги, SSH-ключ и конфигурация SSH, записи в .gitignore
	@if [ -f .env ]; then \
		echo "  .env уже существует — оставлен без изменений"; \
	else \
		cp .env.example .env; \
		echo "  создан .env из .env.example"; \
	fi
	@mkdir -p .ssh .claude-accounts
	@chmod 700 .ssh
	@touch .gitignore
	@for entry in .env .ssh/ .claude-accounts/; do \
		grep -qxF "$$entry" .gitignore >/dev/null 2>&1 && continue; \
		[ -s .gitignore ] && [ -n "$$(tail -c 1 .gitignore)" ] && printf '\n' >> .gitignore; \
		printf '%s\n' "$$entry" >> .gitignore; \
		echo "  в .gitignore добавлено: $$entry"; \
	done
	@ssh_key="$(call env_value,SSH_KEY)"; ssh_key="$${ssh_key:-.ssh/id_ed25519}"; \
	ssh_config="$(call env_value,SSH_CONFIG)"; ssh_config="$${ssh_config:-.ssh/config}"; \
	git_host="$(call env_value,GIT_HOST)"; \
	git_user="$(call env_value,GIT_USER)"; git_user="$${git_user:-git}"; \
	container_ssh="$(call env_value,CONTAINER_SSH_DIR)"; container_ssh="$${container_ssh:-/home/claude/.ssh}"; \
	if ! command -v ssh-keygen >/dev/null 2>&1; then \
		echo "Ошибка: не найдена утилита ssh-keygen — установите пакет openssh-client" >&2; \
		exit 1; \
	fi; \
	mkdir -p "$$(dirname "$$ssh_key")" "$$(dirname "$$ssh_config")"; \
	if [ -f "$$ssh_key" ]; then \
		echo "  SSH-ключ $$ssh_key уже существует — оставлен без изменений"; \
	else \
		ssh-keygen -q -t ed25519 -f "$$ssh_key" -N "" -C "sdd-developer-kit@$$(basename "$$(pwd)")"; \
		chmod 600 "$$ssh_key"; \
		chmod 644 "$$ssh_key.pub"; \
		echo "  создан SSH-ключ $$ssh_key (ed25519, без passphrase)"; \
		echo ""; \
		echo "  Добавьте публичный ключ в git-сервис — без этого push из контейнера не пройдёт:"; \
		echo ""; \
		cat "$$ssh_key.pub"; \
		echo ""; \
	fi; \
	if [ -f "$$ssh_config" ]; then \
		echo "  $$ssh_config уже существует — оставлен без изменений"; \
	elif [ -z "$$git_host" ]; then \
		echo "  GIT_HOST не задан — $$ssh_config не создан;"; \
		echo "  заполните GIT_HOST в .env и выполните make init повторно"; \
	else \
		printf 'Host %s\n  HostName %s\n  User %s\n  IdentityFile %s/%s\n  IdentitiesOnly yes\n' \
			"$$git_host" "$$git_host" "$$git_user" "$$container_ssh" "$$(basename "$$ssh_key")" \
			> "$$ssh_config"; \
		chmod 644 "$$ssh_config"; \
		echo "  создан $$ssh_config: хост $$git_host, ключ $$container_ssh/$$(basename "$$ssh_key")"; \
	fi
	@echo "Готово. Дальше: заполнить .env (GIT_HOST, CLAUDE_PROFILE) и создать каталог профиля в .claude-accounts/"

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
