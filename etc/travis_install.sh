#!/bin/bash

set -ex

# Install base deps
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install -y -qq jq socat python3.7

# Install pachctl
pachyderm_version=$(jq -r .pachctl < version.json)
curl -o /tmp/pachctl.deb -L https://github.com/pachyderm/pachyderm/releases/download/v${pachyderm_version}/pachctl_${pachyderm_version}_amd64.deb  && \
sudo dpkg -i /tmp/pachctl.deb

# Pull & retag images for dev deployment
docker pull pachyderm/pachd:${pachyderm_version}
docker tag pachyderm/pachd:${pachyderm_version} pachyderm/pachd:local
docker pull pachyderm/worker:${pachyderm_version}
docker tag pachyderm/worker:${pachyderm_version} pachyderm/worker:local

# Install kubectl
# To get the latest kubectl version:
# curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt
if [ ! -f ~/cached-deps/kubectl ] ; then
    kubectl_version=v1.13.0
    curl -L -o kubectl https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kubectl && \
        chmod +x ./kubectl && \
        mv ./kubectl ~/cached-deps/kubectl
fi

# Install minikube
# To get the latest minikube version:
# curl https://api.github.com/repos/kubernetes/minikube/releases | jq -r .[].tag_name | sort | tail -n1
if [ ! -f ~/cached-deps/minikube ] ; then
    minikube_version=v0.31.0
    curl -L -o minikube https://storage.googleapis.com/minikube/releases/${minikube_version}/minikube-linux-amd64 && \
        chmod +x ./minikube && \
        mv ./minikube ~/cached-deps/minikube
fi

# Install selenium-related stuff
if [ ! -d ~/cached-deps/geckodriver ] ; then
    geckodriver_version=v0.26.0
    pushd ~/cached-deps
        wget https://github.com/mozilla/geckodriver/releases/download/${geckodriver_version}/geckodriver-${geckodriver_version}-linux64.tar.gz
        mkdir geckodriver
        tar -xzf geckodriver-${geckodriver_version}-linux64.tar.gz -C geckodriver
    popd
fi
/etc/init.d/xvfb start || true

# Setup virtualenv
if [ ! -d ~/cached-deps/venv ] ; then
    virtualenv -p python3.7 ~/cached-deps/venv
    source ~/cached-deps/venv/bin/activate
    pip3 install selenium==3.141.0
fi

# Variant-specific installations
function install_helm {
    if [ ! -f ~/cached-deps/helm ] ; then
        wget https://get.helm.sh/helm-v3.1.2-linux-amd64.tar.gz
        tar -zxvf helm-v3.1.2-linux-amd64.tar.gz
        mv linux-amd64/helm ~/cached-deps/helm
    fi
}

case "${VARIANT}" in
    native)
        # Installs pachctl with native support
        # TODO: remove once native jupyterhub deployments are stable
        pushd ~
            git clone --single-branch --branch native-jupyterhub --depth 1 https://github.com/pachyderm/pachyderm.git
            pushd pachyderm
                make install
            popd
        popd
        ;;
    python)
        install_helm
        ;;
    existing)
        install_helm
        helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
        helm repo update
        ;;
    *)
        echo "Unknown testing variant"
        exit 1
        ;;
esac
