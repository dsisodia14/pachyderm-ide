.PHONY: test-e2e docker-build-local deploy-local jupyterhub-dev

venv:
	virtualenv -p python3.7 venv
	. venv/bin/activate && pip3 install -r etc/test_requirements.txt

test-e2e: venv
	. venv/bin/activate && python3 ./etc/test_e2e.py \
		"$(shell ./etc/ide_url.py minikube)" \
        "" "$(shell pachctl auth get-otp)" --debug

docker-build-local:
	cd hub && VERSION=local make docker-build
	cd user && VERSION=local make docker-build

deploy-local:
	$(GOPATH)/bin/pachctl deploy ide \
        --user-image "pachyderm/ide-user:local" \
        --hub-image "pachyderm/ide-hub:local" \
        --jupyterhub-chart-version "$(shell jq -r .jupyterhub version.json)"

jupyterhub-dev:
	. venv/bin/activate && pip install jupyterhub
	sudo npm install -g configurable-http-proxy
	. venv/bin/activate && jupyterhub --config=etc/config/dev_jupyterhub.py
