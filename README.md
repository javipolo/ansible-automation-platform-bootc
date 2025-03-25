# Ansible Automation Platform running on RHEL image mode

This repo showcases how the containerized version of Ansible Automation Platform is deployed in a RHEL Image Mode immutable operating system

## Prerequisites

- libvirt
- Add the new `AAP_HOSTNAME` to DNS
- Download the `Containerized Setup Bundle` from the [Ansible Download Page](https://developers.redhat.com/products/ansible/download) in the `tmp` directory

## Customize your environment

Check and edit the variables on top of the `Makefile` file to suit your case

> * **Note:** You can specify the variables in a `.env` file that will override the Makefile settings

## Steps

We can just run `make all` to perform all steps in order

Or we can go manually over each one:

1. Create a custom rhel-bootc image installing the required packages
```
make image
```

2. Create a qcow2 disk image using `bootc-image-builder`
```
make disk
```

3. Create a libvirt VM using the qcow2 disk image
```
make vm
```

4. Provision Ansible Automation Platform using the ansible installer
```
make ansible
```
