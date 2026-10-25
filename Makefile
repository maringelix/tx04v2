# Optional convenience only. Make is never required; every target delegates to
# the Docker-only launcher and installs nothing on the host.
NODES ?= 100

.PHONY: help build up up-cilium down gpu scheduling serving networking observability kwok scale smoke

help:
	@./lab.sh help
build:
	@./lab.sh build
up:
	@./lab.sh up
up-cilium:
	@./lab.sh up-cilium
down:
	@./lab.sh down
gpu:
	@./lab.sh gpu
scheduling:
	@./lab.sh scheduling
serving:
	@./lab.sh serving
networking:
	@./lab.sh networking
observability:
	@./lab.sh observability
kwok:
	@./lab.sh kwok $(NODES)
scale:
	@./lab.sh scale
smoke:
	@./lab.sh up
	@./lab.sh kubectl wait --for=condition=Ready nodes --all --timeout=180s
	@./lab.sh kubectl get nodes -o wide
