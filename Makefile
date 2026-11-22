.PHONY: db-up
db-up:
	docker compose up -d

.PHONY: db-down
db-down:
	docker compose down