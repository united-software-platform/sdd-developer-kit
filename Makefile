.PHONY: build up down

build:
	docker compose --profile claude build claude

up:
	docker compose --profile claude up -d --force-recreate claude

down:
	docker compose --profile claude down
