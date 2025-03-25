-include .env

REGISTRY_USERNAME ?= your_redhat_user@whatever.com
REGISTRY_PASSWORD ?= your_secret_registry_password
AAP_HOSTNAME ?= aap-bootc.javipolo.redhat.com
AAP_VERSION=2.5-10.1

IMAGE_NAME ?= quay.io/jpolo/ansible-automation-platform-bootc:${IMAGE_TAG}
IMAGE_TAG ?= latest

AAP_PG_ADMIN_USER ?= postgres
AAP_PG_ADMIN_PASSWORD ?= redhat
AAP_CONTROLLER_ADMIN_PASSWORD ?= redhat
AAP_CONTROLLER_PG_PASSWORD ?= redhat
AAP_HUB_ADMIN_PASSWORD ?= redhat
AAP_HUB_PG_PASSWORD ?= redhat
AAP_EDA_ADMIN_PASSWORD ?= redhat
AAP_EDA_PG_PASSWORD ?= redhat
AAP_GATEWAY_ADMIN_PASSWORD ?= redhat
AAP_GATEWAY_PG_PASSWORD ?= redhat
ANSIBLE_USER ?= core
ANSIBLE_USER_PASSWORD ?= redhat
ANSIBLE_USER_SSHKEY ?= $(shell cat ~/.ssh/id_rsa.pub)

AAP_FULL_NAME=ansible-automation-platform-containerized-setup-bundle-${AAP_VERSION}-x86_64

LIBVIRT_POOL ?= default
DISK_TYPE ?= qcow2
DISK_SIZE=200G
CPUS=8
MEMORY=32768
VM_NAME ?= aap-bootc
VM_MAC ?= fa:ba:da:ba:fa:da

IMAGE_BUILDER_CONFIG=$(abspath .)/tmp/config.toml
BOOTC_IMAGE_BUILDER ?= quay.io/centos-bootc/bootc-image-builder
GRAPH_ROOT=$(shell podman info --format '{{ .Store.GraphRoot }}')
DISK_UID ?= $(shell id -u)
DISK_GID ?= $(shell id -g)

LIBVIRT_POOL_PATH ?= $(shell virsh pool-dumpxml ${LIBVIRT_POOL} --xpath "/pool/target/path/text()")

.PHONY: default
default: help

.PHONY: all
all: image disk vm-delete vm-create unpack-aap ansible

.PHONY: image
image: ## Build container image
	podman build -t ${IMAGE_NAME} -f Containerfile .

.PHONY: disk
disk: tmp/config.toml ## Build disk image
	mkdir -p tmp/build/store tmp/build/output
	podman run \
	  --rm \
	  -ti \
	  --privileged \
	  --pull newer \
	  -v ${GRAPH_ROOT}:/var/lib/containers/storage \
	  -v ./tmp/build/store:/store \
	  -v ./tmp/build/output:/output \
	  $(IMAGE_BUILDER_CONFIG:%=-v %:/config$(suffix ${IMAGE_BUILDER_CONFIG})) \
	  ${CONTAINER_TOOL_EXTRA_ARGS} \
	  ${BOOTC_IMAGE_BUILDER} \
	    $(IMAGE_BUILDER_CONFIG:%=--config /config$(suffix ${IMAGE_BUILDER_CONFIG})) \
	    ${IMAGE_BUILDER_EXTRA_ARGS} \
	    --chown ${DISK_UID}:${DISK_GID} \
	    --local \
	    --type ${DISK_TYPE} \
	    ${IMAGE_NAME}

.PHONY: vm
vm: vm-delete vm-create ## Create VM

.PHONY: vm-create
vm-create:
	sudo cp tmp/build/output/qcow2/disk.qcow2 ${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2
	sudo qemu-img resize ${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2 ${DISK_SIZE}
	sudo virt-install \
		--name ${VM_NAME} \
		--memory ${MEMORY} \
		--vcpus ${CPUS} \
		--disk path=${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2,bus=virtio \
		--network=network:default,mac="${VM_MAC}" \
		--os-variant=rhel9.3 \
		--import \
		--noautoconsole \
		--graphics=vnc

.PHONY: vm-delete
vm-delete:
	-sudo virsh destroy ${VM_NAME}
	-sudo virsh undefine ${VM_NAME} --remove-all-storage

.PHONY: tmp/config.toml
tmp/config.toml:
	@ANSIBLE_USER=${ANSIBLE_USER} \
	ANSIBLE_USER_PASSWORD=${ANSIBLE_USER_PASSWORD} \
	ANSIBLE_USER_SSHKEY="${ANSIBLE_USER_SSHKEY}" \
		envsubst < templates/config.toml.template > $@
	chmod 600 $@

.PHONY: tmp/inventory
tmp/inventory:
	@AAP_HOSTNAME=${AAP_HOSTNAME} \
	AAP_PG_ADMIN_USER=${AAP_PG_ADMIN_USER} \
	AAP_PG_ADMIN_PASSWORD=${AAP_PG_ADMIN_PASSWORD} \
	AAP_CONTROLLER_ADMIN_PASSWORD=${AAP_CONTROLLER_ADMIN_PASSWORD} \
	AAP_CONTROLLER_PG_PASSWORD=${AAP_CONTROLLER_PG_PASSWORD} \
	AAP_HUB_ADMIN_PASSWORD=${AAP_HUB_ADMIN_PASSWORD} \
	AAP_HUB_PG_PASSWORD=${AAP_HUB_PG_PASSWORD} \
	AAP_EDA_ADMIN_PASSWORD=${AAP_EDA_ADMIN_PASSWORD} \
	AAP_EDA_PG_PASSWORD=${AAP_EDA_PG_PASSWORD} \
	AAP_GATEWAY_ADMIN_PASSWORD=${AAP_GATEWAY_ADMIN_PASSWORD} \
	AAP_GATEWAY_PG_PASSWORD=${AAP_GATEWAY_PG_PASSWORD} \
	ANSIBLE_USER=${ANSIBLE_USER} \
	ANSIBLE_USER_PASSWORD=${ANSIBLE_USER_PASSWORD} \
	REGISTRY_USERNAME=${REGISTRY_USERNAME} \
	REGISTRY_PASSWORD=${REGISTRY_PASSWORD} \
		envsubst < templates/inventory.template > $@
	chmod 600 $@

unpack-aap: tmp/collections

tmp/collections:
	@if [ ! -f tmp/${AAP_FULL_NAME}.tar.gz ]; then \
		echo Please download ${AAP_FULL_NAME}.tar.gz and place it in $(abspath .)/tmp; \
		exit 1; \
	fi
	tar xzf tmp/${AAP_FULL_NAME}.tar.gz -C tmp
	mv tmp/${AAP_FULL_NAME}/collections $@

.PHONY: ansible
ansible: tmp/collections tmp/inventory ## Run ansible in the VM
	ansible all -m wait_for_connection --timeout 60
	ansible-playbook -i tmp/inventory ansible.containerized_installer.install

.PHONY: help
help:
	@gawk -vG=$$(tput setaf 6) -vR=$$(tput sgr0) ' \
		match($$0,"^(([^:]*[^ :]) *:)?([^#]*)## (.*)",a) { \
			if (a[2]!="") {printf "%s%-30s%s %s\n",G,a[2],R,a[4];next}\
			if (a[3]=="") {print a[4];next}\
			printf "\n%-30s %s\n","",a[4]\
		}\
	' ${MAKEFILE_LIST}
