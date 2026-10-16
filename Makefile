.PHONY: check test tf-check helm-check hooks-test plugin

check: test tf-check helm-check hooks-test

test:
	cd app && pytest -q

tf-check:
	terraform fmt -check -recursive terraform/
	terraform -chdir=terraform/envs/dev init -backend=false -input=false >/dev/null
	terraform -chdir=terraform/envs/dev validate

helm-check:
	helm lint charts/orders-api
	helm template orders-api charts/orders-api -f charts/orders-api/values-dev.yaml > /tmp/orders-dev.yaml
	kubeconform -strict -summary /tmp/orders-dev.yaml
	bash .claude/skills/k8s-manifest-review/scripts/check-manifests.sh /tmp/orders-dev.yaml

hooks-test:
	bash tests/test_hooks.sh

plugin:
	bash scripts/build-plugin.sh
