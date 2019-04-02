# minikube-on-linux
A simple shell that helps you boot up a local kubernetes cluster on linux host.

## Background
Booting up a local kubernetes cluster will take a few steps if you fellow the official documents. And it extremely depends on the network. It will be a little difficult if you want to try kubernetes in a private network. This script can help you make a offline installation package and boot up a local kubernetes cluster easily.

## Requirements
* Linux OS(tested under CentOS)
* Docker

## Usage
* *Start a local kubernetes cluster when network is available*
```sh
cd minikube-on-linux
bash setup.sh start
```

* *Start a local kubernetes cluster when network is unavailable*
```sh
# make a offline installation package when network is available
# package will be saved in target directory
cd minikube-on-linux
bash setup.sh package
```
```sh
# start a local kubernetes cluster in private network
tar -xzvf minikube-on-linux.tar.gz
cd minikube-on-linux
bash setup.sh start
```