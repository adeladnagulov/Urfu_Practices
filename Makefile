GO ?= go
BINARY ?= bin/trip-service

include .env
export $(shell grep -v '^#' .env | cut -d= -f1)

.PHONY: db-up
db-up:
	docker compose up -d

.PHONY: db-down
db-down:
	docker compose down

migrate: ## Накатить миграции на базу данных
	$(GO) tool goose -dir migrations postgres "$(DATABASE_URL)" up

migrate-down: ## Откатить последнюю миграцию
	$(GO) tool goose -dir migrations postgres "$(DATABASE_URL)" down

run: ## Запустить го бекенд локально
	cd backend-main && $(GO) run ./cmd/api