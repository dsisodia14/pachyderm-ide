#!/bin/bash

set -ex

# Deploys pachyderm and activates enterprise+auth
function deploy_pachyderm {
    pachctl deploy local -d
    wait_for pachd
    pachctl version

    pachctl enterprise activate "${PACH_ENTERPRISE_CODE}"
    echo admin | pachctl auth activate
    pachctl auth whoami
}

# Waits for a given app to be ready
function wait_for {
    until timeout 1s ./etc/ci/check_ready.sh app=$1; do sleep 1; done
}

# Executes a test run
function test_run {
    wait_for jupyterhub
    # TODO: run through testing the login process via selenium/firefox
}

./etc/ci/start_minikube.sh

pushd images/hub
    make docker-build
popd

pushd images/user
    make docker-build
popd

image_version=$(jq -r .jupyterhub_pachyderm < version.json)
./etc/ci/push-to-minikube.sh pachyderm/jupyterhub-pachyderm-hub:${image_version}
./etc/ci/push-to-minikube.sh pachyderm/jupyterhub-pachyderm-user:${image_version}

case "${VARIANT}" in
    native)
        # Deploy pachyderm
        deploy_pachyderm

        # Deploy jupyterhub
        ${GOPATH}/bin/pachctl deploy jupyterhub \
            --user-image pachyderm/jupyterhub-pachyderm-user:${image_version} \
            --hub-image pachyderm/jupyterhub-pachyderm-hub:${image_version}
        test_run

        # Upgrade jupyterhub
        ${GOPATH}/bin/pachctl deploy jupyterhub \
            --user-image pachyderm/jupyterhub-pachyderm-user:${image_version} \
            --hub-image pachyderm/jupyterhub-pachyderm-hub:${image_version}
        test_run

        # Undeploy
        echo yes | ${GOPATH}/bin/pachctl undeploy --jupyterhub --metadata

        # Reset minikube
        minikube delete
        ./etc/ci/start_minikube.sh

        # Re-deploy pachyderm
        deploy_pachyderm

        # Re-deploy jupyterhub
        ${GOPATH}/bin/pachctl deploy jupyterhub \
            --user-image pachyderm/jupyterhub-pachyderm-user:${image_version} \
            --hub-image pachyderm/jupyterhub-pachyderm-hub:${image_version}
        test_run
        ;;
    python)
        # Deploy pachyderm
        deploy_pachyderm

        # Deploy jupyterhub
        python3.7 init.py
        test_run

        # Upgrade jupyterhub
        python3.7 init.py
        test_run

        # Undeploy
        ./delete.sh

        # Reset minikube and hostpaths
        minikube delete
        sudo rm -rf /var/pachyderm
        ./etc/ci/start_minikube.sh

        # Re-deploy pachyderm
        deploy_pachyderm

        # Re-deploy jupyterhub
        python3.7 init.py
        test_run
        ;;
    existing)
        # Create a base deployment of jupyterhub
        python3 ./etc/ci/existing_config.py base \
            | helm upgrade --install jhub jupyterhub/jupyterhub --version 0.8.2 --values -
        wait_for jupyterhub

        # Patch in the user image
        python3 ./etc/ci/existing_config.py patch \
            | helm upgrade jhub jupyterhub/jupyterhub --version 0.8.2 --values -
        test_run

        # Undeploy
        ./delete.sh
        ;;
    *)
        echo "Unknown testing variant"
        exit 1
        ;;
esac
