#!/bin/bash

set -e

color_red='\033[0;31m'
color_none='\033[0m'

function print_section {
    echo -e "${color_red}${1}${color_none}"
}

# Use virtualenv
source ~/cached-deps/venv/bin/activate

# Deploys pachyderm and activates enterprise+auth
function deploy_pachyderm {
    /usr/bin/pachctl deploy local -d
    until timeout 1s ./etc/check_ready.sh app=pachd; do sleep 1; done
    /usr/bin/pachctl version

    /usr/bin/pachctl enterprise activate "${PACH_ENTERPRISE_CODE}"
    echo admin | /usr/bin/pachctl auth activate
    /usr/bin/pachctl auth whoami
}

# Waits for a jupyterhub to be ready
function wait_for_jupyterhub {
    ./etc/ide_url.py minikube --attempts=100
}

# Executes a test run with pachyderm auth
function test_run_with_auth {
    wait_for_jupyterhub
    url=$(./etc/ide_url.py minikube)
    python3 ./etc/test_e2e.py "${url}" "" "$(pachctl auth get-otp)" --headless
}

# Deletes and restarts minikube
function reset_minikube {
    minikube delete
    sudo rm -rf /var/pachyderm # delete the pachyderm hostpath
    ./etc/start_minikube.sh
}

# Make an initial deployment of pachyderm
print_section "Deploy pachyderm"
reset_minikube
deploy_pachyderm

case "${VARIANT}" in
    native)
        # Deploy IDE
        print_section "Deploy IDE"
        make deploy-local
        test_run_with_auth

        # Re-run IDE deployment, should act as an upgrade and not error
        # out
        print_section "Upgrade IDE"
        make deploy-local
        test_run_with_auth

        # Undeploy everything, including the IDE
        print_section "Undeploy"
        echo yes | ${GOPATH}/bin/pachctl undeploy --ide --metadata

        # Reset minikube fully and re-run the deployment/test cycle. This
        # ensures that jupyterhub doesn't mistakenly pull in its old PV.
        reset_minikube
        print_section "Re-deploy pachyderm"
        deploy_pachyderm
        print_section "Re-deploy IDE"
        make deploy-local
        test_run_with_auth
        ;;
    patch)
        # Create a vanilla jupyterhub deployment, which employs the default
        # (non-pachyderm) login mechanism
        print_section "Create a base deployment of jupyterhub"
        helm upgrade --install jhub jupyterhub/jupyterhub --version 0.8.2 --values ./etc/config/test_base.yaml
        wait_for_jupyterhub

        # Patch in our custom user image
        print_section "Patch in the user image"
        helm upgrade --install jhub jupyterhub/jupyterhub --version 0.8.2 --values ./etc/config/test_patch.yaml

        wait_for_jupyterhub
        url=$(./etc/ide_url.py minikube)
        python3 ./etc/test_e2e.py "${url}" "jovyan" "jupyter" --headless --no-auth-check
        ;;
    *)
        echo "Unknown testing variant"
        exit 1
        ;;
esac
