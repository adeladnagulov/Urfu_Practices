.PHONY: db-up
db-up:
	docker compose -f docker/docker-compose.yml up -d

.PHONY: db-down
db-down:
	docker compose -f docker/docker-compose.yml down