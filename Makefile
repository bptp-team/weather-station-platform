.PHONY: dev down

dev:
	docker compose -f compose/docker-compose.yaml up -d

down:
	docker compose -f compose/docker-compose.yaml down
