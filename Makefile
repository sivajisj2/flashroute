.PHONY: up down check logs smoke deploy backup
up:
	./scripts/up.sh
down:
	./scripts/down.sh
check:
	./scripts/check.sh
logs:
	docker compose logs -f --tail=100
smoke:
	./scripts/smoke.sh
deploy:
	./scripts/deploy-vps.sh
backup:
	./scripts/backup.sh
