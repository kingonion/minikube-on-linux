#!/bin/bash
#


set -e


# define the home directory of minikube
# if not set, this value will be the current directory 
MINIKUBE_HOME=/opt/minikube

# version of kubernetes
# if not set, this value will be the latest stable version
KUBE_VERSION=v1.13.4

# version of minikube
# default value is latest, you can specify a version, like v0.35.0, v0.34.0
MINIKUBE_VERSION=latest

# the registry where to pull the kubernetes related images
# if not set, this value will be k8s.gcr.io
# in China, because of the GFW, this value can be registry.cn-hangzhou.aliyuncs.com/google_containers
REGISTRY_MIRROR=registry.cn-hangzhou.aliyuncs.com/google_containers

BASE_DIR=$(cd $(dirname "$BASH_SOURCE[0]"); pwd)

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

function logger_error() {
    local time=$(date +'%F %T')
    printf "${RED}${time} - ERROR - %s${RESET}\n" "$@"
    echo "${time} - ERROR - $@" >> ${BASE_DIR}/logs/setup.log
}

function logger_info() {
    local time=$(date +'%F %T')
    printf "${GREEN}${time} - INFO - %s${RESET}\n" "$@"
    echo "${time} - INFO - $@" >> ${BASE_DIR}/logs/setup.log
}

function logger_warn() {
    local time=$(date +'%F %T')
    printf "${YELLOW}${time} - WARN - %s${RESET}\n" "$@"
    echo "${time} - WARN - $@" >> ${BASE_DIR}/logs/setup.log
}

# check docker is started or not
function check_requirement() {
    if [[ ! $(docker info 2>/dev/null) ]] 
    then 
        logger_error "docker is not running, please start it first."
        exit 1
    fi
}

function make_dirs() {
    [[ -d "${BASE_DIR}/.cache/${MINIKUBE_VERSION}" ]] || mkdir -p "${BASE_DIR}/.cache/${MINIKUBE_VERSION}"
    [[ -d "${BASE_DIR}/.cache/${KUBE_VERSION}" ]] || mkdir -p "${BASE_DIR}/.cache/${KUBE_VERSION}"
    [[ -d "${BASE_DIR}/.cache/images" ]] || mkdir -p "${BASE_DIR}/.cache/images"
    [[ -d "${BASE_DIR}/logs" ]] || mkdir -p "${BASE_DIR}/logs"
}

function get_host_os() {
    local host_os=""
    case "$(uname -s)" in
        Darwin)
            host_os=darwin
            ;;
        Linux)
            host_os=linux
            ;;
        *)
            logger_error "Unsupported host OS. Must be Linux or Mac OS X."
            exit 1
            ;;
    esac
    echo "${host_os}"
}

function get_host_arch() {
    local host_arch=""
    case "$(uname -m)" in
        x86_64*|i?86_64*|amd64*|aarch64*|arm64*)
            host_arch=amd64
            ;;
        arm*)
            host_arch=arm
            ;;
        i?86*)
            host_arch=x86
            ;;
        s390x*)
            host_arch=s390x
            ;;
        ppc64le*)
            host_arch=ppc64le
            ;;
        *)
            logger_error "Unsupported host arch. Must be x86_64, 386, arm, arm64, s390x or ppc64le."
            exit 1
            ;;
    esac
    echo "${host_arch}"
}

function get_kube_version() {
    if [ "x${KUBE_VERSION}" = "x" ] 
    then 
        cd /tmp &>/dev/null
        logger_info "start to get kubernetes version."
        download "${STORAGE_HOST}/kubernetes-release/release/stable.txt" stable.txt
        KUBE_VERSION=$(cat stable.txt | awk 'NR == 1 { print }')
        cd - &>/dev/null
    fi
}

# download minikube and kubelet
function download_binaries() {
    local host_os=$(get_host_os)
    local host_arch=$(get_host_arch)
    STORAGE_HOST="${STORAGE_HOST:-https://storage.googleapis.com}"
    cd "${BASE_DIR}/.cache/${MINIKUBE_VERSION}" &>/dev/null
    # main process
    if [ ! -f minikube ] 
    then 
        logger_info "start to download minikube."
        download "${STORAGE_HOST}/minikube/releases/${MINIKUBE_VERSION}/minikube-${host_os}-${host_arch}" minikube
    fi
    cd - &>/dev/null
    cd "${BASE_DIR}/.cache/${KUBE_VERSION}" &>/dev/null
    # kubernetes client tool
    if [ ! -f kubectl ] 
    then 
        logger_info "start to download kubectl."
        download "${STORAGE_HOST}/kubernetes-release/release/${KUBE_VERSION}/bin/${host_os}/${host_arch}/kubectl" kubectl
    fi
    # pkg/minikube/bootstrapper/kubeadm/kubeadm.go UpdateCluster
    if [ ! -f kubelet ] 
    then 
        logger_info "start to download kubelet."
        download "${STORAGE_HOST}/kubernetes-release/release/${KUBE_VERSION}/bin/${host_os}/${host_arch}/kubelet" kubelet
    fi
    if [ ! -f kubeadm ] 
    then 
        logger_info "start to download kubeadm."
        download "${STORAGE_HOST}/kubernetes-release/release/${KUBE_VERSION}/bin/${host_os}/${host_arch}/kubeadm" kubeadm
    fi
    cd - &>/dev/null
}

# download file from remote host
# ${1} file url
# ${2} file name
function download() {
    local file_url="${1}"
    local file_name="${2}"
    if [[ $(which curl) ]]
    then 
        curl -fsSL "${file_url}" -o "${file_name}"
    elif [[ $(which wget) ]] 
    then
        wget -q "${file_url}" -O "${file_name}"
    else 
        logger_error "Couldn't find curl or wget, please install one at least."
        exit 1
    fi 
}

function set_envs() {
    [[ -f ~/.bash_profile ]] || touch ~/.bash_profile
    if [ "x${MINIKUBE_HOME}" = "x" ] 
    then 
        MINIKUBE_HOME="${BASE_DIR}"
    fi 
    export MINIKUBE_HOME="${MINIKUBE_HOME}"
    export PATH=$MINIKUBE_HOME/bin:$PATH
    export MINIKUBE_WANTUPDATENOTIFICATION=false
    export MINIKUBE_WANTREPORTERRORPROMPT=false
    append_text_to_file "export MINIKUBE_HOME=${MINIKUBE_HOME}" ~/.bash_profile
    append_text_to_file 'export PATH=$MINIKUBE_HOME/bin:$PATH' ~/.bash_profile
    append_text_to_file 'export MINIKUBE_WANTUPDATENOTIFICATION=false' ~/.bash_profile
    append_text_to_file 'export MINIKUBE_WANTREPORTERRORPROMPT=false' ~/.bash_profile
}

function install() {
    [[ -d "${MINIKUBE_HOME}/bin" ]] || mkdir -p "${MINIKUBE_HOME}/bin"
    if [[ ! -f "${MINIKUBE_HOME}/bin/minikube" ]]
    then 
        logger_info "start to install minikube."
        cp -f "${BASE_DIR}/.cache/${MINIKUBE_VERSION}/minikube" "${MINIKUBE_HOME}/bin/minikube"
        chmod a+rx "${MINIKUBE_HOME}/bin/minikube"
        logger_info "end to install minikube."
    fi
    if [[ ! -f "${MINIKUBE_HOME}/bin/kubectl" ]]
    then
        logger_info "start to install kubectl."
        cp -f "${BASE_DIR}/.cache/${KUBE_VERSION}/kubectl" "${MINIKUBE_HOME}/bin/kubectl"
        chmod a+rx "${MINIKUBE_HOME}/bin/kubectl"
        logger_info "end to install kubectl."
    fi
    [[ -d "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}" ]] || mkdir -p "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}"
    if [[ ! -f "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}/kubelet" ]] 
    then 
        logger_info "start to cache kubelet."
        cp -f "${BASE_DIR}/.cache/${KUBE_VERSION}/kubelet" "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}/kubelet"
    fi 
    if [[ ! -f "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}/kubeadm" ]]
    then
        logger_info "start to cache kubeadm."
        cp -f "${BASE_DIR}/.cache/${KUBE_VERSION}/kubeadm" "${MINIKUBE_HOME}/.minikube/cache/${KUBE_VERSION}/kubeadm"
    fi 
}

# ${1} text
# ${2} file
function append_text_to_file() {
    local text="${1}"
    local file="${2}"
    if [ -f "${file}" ] 
    then 
        if [[ ! $(cat "${file}" | grep -F "${text}" | grep -v grep) ]] 
        then 
            logger_info "append text[${text}] to file[file]"
            echo "${text}" | tee -a "${file}"
        else 
            logger_warn "text[${text}] is found in file[${file}], skip append."
        fi
    else 
        logger_warn "file[${file}] not exists."
    fi 
}

function pull_images() {
    REGISTRY_MIRROR="${REGISTRY_MIRROR:-k8s.gcr.io}"
    # images are defined in pkg/minikube/constants/constants.go
    pull_and_save_image "${REGISTRY_MIRROR}/kube-proxy-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-proxy-amd64:${KUBE_VERSION}"
    docker tag "k8s.gcr.io/kube-proxy-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-proxy:${KUBE_VERSION}"
    pull_and_save_image "${REGISTRY_MIRROR}/kube-scheduler-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-scheduler-amd64:${KUBE_VERSION}"
    docker tag "k8s.gcr.io/kube-scheduler-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-scheduler:${KUBE_VERSION}"
    pull_and_save_image "${REGISTRY_MIRROR}/kube-controller-manager-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-controller-manager-amd64:${KUBE_VERSION}"
    docker tag "k8s.gcr.io/kube-controller-manager-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-controller-manager:${KUBE_VERSION}"
    pull_and_save_image "${REGISTRY_MIRROR}/kube-apiserver-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-apiserver-amd64:${KUBE_VERSION}"
    docker tag "k8s.gcr.io/kube-apiserver-amd64:${KUBE_VERSION}" "k8s.gcr.io/kube-apiserver:${KUBE_VERSION}"
    if [[ "${KUBE_VERSION}" > "v1.13.0" ]] || [ "${KUBE_VERSION}" = "v1.13.0" ]
    then 
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.1" "k8s.gcr.io/pause-amd64:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/pause:3.1" "k8s.gcr.io/pause:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.8" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.8" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.8" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.2.24" "k8s.gcr.io/etcd-amd64:3.2.24"
        docker tag "k8s.gcr.io/etcd-amd64:3.2.24" "k8s.gcr.io/etcd:3.2.24"
        pull_and_save_image "${REGISTRY_MIRROR}/coredns:1.2.6" "k8s.gcr.io/coredns:1.2.6"
    elif [[ "${KUBE_VERSION}" > "v1.12.0" ]] || [ "${KUBE_VERSION}" = "v1.12.0" ]
    then
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.1" "k8s.gcr.io/pause-amd64:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/pause:3.1" "k8s.gcr.io/pause:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.8" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.8" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.8" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.2.24" "k8s.gcr.io/etcd-amd64:3.2.24"
        pull_and_save_image "${REGISTRY_MIRROR}/coredns:1.2.2" "k8s.gcr.io/coredns:1.2.2"
    elif [[ "${KUBE_VERSION}" > "v1.11.0" ]] || [ "${KUBE_VERSION}" = "v1.11.0" ]
    then
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.1" "k8s.gcr.io/pause-amd64:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/pause:3.1" "k8s.gcr.io/pause:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.8" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.8" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.8" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.2.18" "k8s.gcr.io/etcd-amd64:3.2.18"
        pull_and_save_image "${REGISTRY_MIRROR}/coredns:1.1.3" "k8s.gcr.io/coredns:1.1.3"
    elif [[ "${KUBE_VERSION}" > "v1.10.0" ]] || [ "${KUBE_VERSION}" = "v1.10.0" ]
    then
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.1" "k8s.gcr.io/pause-amd64:3.1"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.8" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.8" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.8" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.8"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.1.12" "k8s.gcr.io/etcd-amd64:3.1.12"
    elif [[ "${KUBE_VERSION}" > "v1.9.0" ]] || [ "${KUBE_VERSION}" = "v1.9.0" ]
    then
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.0" "k8s.gcr.io/pause-amd64:3.0"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.7" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.7"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.7" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.7"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.7" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.7"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.1.10" "k8s.gcr.io/etcd-amd64:3.1.10"
    elif [[ "${KUBE_VERSION}" > "v1.8.0" ]] || [ "${KUBE_VERSION}" = "v1.8.0" ]
    then
        pull_and_save_image "${REGISTRY_MIRROR}/pause-amd64:3.0" "k8s.gcr.io/pause-amd64:3.0"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-kube-dns-amd64:1.14.5" "k8s.gcr.io/k8s-dns-kube-dns-amd64:1.14.5"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-dnsmasq-nanny-amd64:1.14.5" "k8s.gcr.io/k8s-dns-dnsmasq-nanny-amd64:1.14.5"
        pull_and_save_image "${REGISTRY_MIRROR}/k8s-dns-sidecar-amd64:1.14.5" "k8s.gcr.io/k8s-dns-sidecar-amd64:1.14.5"
        pull_and_save_image "${REGISTRY_MIRROR}/etcd-amd64:3.0.17" "k8s.gcr.io/etcd-amd64:3.0.17"
    fi 
    pull_and_save_image "${REGISTRY_MIRROR}/kubernetes-dashboard-amd64:v1.10.1" "k8s.gcr.io/kubernetes-dashboard-amd64:v1.10.1"
    pull_and_save_image "${REGISTRY_MIRROR}/kube-addon-manager:v8.6" "k8s.gcr.io/kube-addon-manager:v8.6"
    if [[ $(echo "${REGISTRY_MIRROR}" | grep "^gcr.io" | grep -v grep) ]] 
    then 
        pull_and_save_image "gcr.io/k8s-minikube/storage-provisioner:v1.8.1" "gcr.io/k8s-minikube/storage-provisioner:v1.8.1"
    else 
        pull_and_save_image "${REGISTRY_MIRROR}/storage-provisioner:v1.8.1" "gcr.io/k8s-minikube/storage-provisioner:v1.8.1"
    fi 
}

# ${1} image
# ${2} new_image
function pull_and_save_image() {
    local image="${1}"
    local new_image="${2}"
    local file=$(echo "${new_image}" | awk -F '/' '{ print $NF }' | awk -F ':' '{ printf "%s_%s.tar", $1, $2}')
    if [[ ! $(docker images | awk '{ printf "%s:%s\n", $1, $2 }' | grep "${new_image}" | grep -v grep) ]] 
    then
        if [ -f "${BASE_DIR}/.cache/images/${file}" ] 
        then 
            docker load -i "${BASE_DIR}/.cache/images/${file}"
        else
            docker pull "${image}"
            if [[ ! $(echo "${image}" | grep "^k8s.gcr.io" | grep -v grep) ]]
            then 
                docker tag "${image}" "${new_image}"
            fi
        fi
    fi 
    if [ ! -f "${BASE_DIR}/.cache/images/${file}" ] 
    then 
        docker save -o "${BASE_DIR}/.cache/images/${file}" "${new_image}"
    fi 
}

function start() {
    set +e
    . ~/.bash_profile
    set -e
    local cgroup_driver=$(docker info 2>/dev/null | grep 'Cgroup Driver' | awk -F ':' '{ print $2 }' | tr -d '[:blank:]')
    [[ ! -z "${cgroup_driver}" ]] || cgroup_driver=systemd
    minikube start --vm-driver none --kubernetes-version "${KUBE_VERSION}" --extra-config kubelet.cgroup-driver="${cgroup_driver}"
}

function package() {
    cd "${BASE_DIR}/.." &>/dev/null
    tar -czf minikube-autoinstall.tar.gz ./.cache setup.sh
    cd - &>/dev/null
}

make_dirs

check_requirement

get_kube_version

download_binaries

set_envs

install

pull_images

start