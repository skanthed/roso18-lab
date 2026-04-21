## Baremetal OpenShift Lab – Environment Preparation (Pre-Installation)

### 1. Overview

This document describes the steps performed to prepare a baremetal environment for deploying OpenShift using the Assisted Installer.

Scope:
- Infrastructure setup and validation
- Network and VLAN verification
- Switch-level validation
- Node interface configuration
- DNS setup using dnsmasq on a dedicated jump host


### 2. Infrastructure Details

Baremetal Nodes
The environment consists of four physical nodes:

    10.5.1.16 - Cluster Node  
    10.5.1.17 - Jump Host + DNS  
    10.5.1.18 - Cluster Node  
    10.5.1.19 - Cluster Node  

A minimum of three nodes is required for OpenShift cluster deployment. The fourth node (10.5.1.17) is configured as a dedicated jump host to manage supporting services such as DNS and provide administrative access to the cluster.

Switches

    10.5.1.20 - Cumulus NVUE Switch  
    10.5.1.21 - Dell Force10 Switch  

These switches are used to validate Layer 2 connectivity, MAC address learning, and interface mapping between nodes.

### 3. Network Configuration

VLAN
- All nodes are connected to the same VLAN: VLAN 914. This ensures Layer 2 communication across all nodes, which is required for OpenShift installation.


Node Connectivity Validation
- From the jump host, verify connectivity to all cluster nodes: ping other nodes and successful responses confirm network reachability.


### 4. Switch Validation

On the Cumulus switch, validate connectivity:

    bridge link show
    net show mac

Validate
- Node MAC addresses are visible, Interfaces are mapped correctly, and Switch ports are active.


### 5. Jump Host Setup on Node - 10.5.1.17

Register System with Red Hat Subscription

The system was registered to enable package installation and updates
    
    sudo subscription-manager register

System Update and Install dnsmasq

    cat /etc/resolv.conf
    ip a
    sudo dnf update -y
    sudo dnf install -y dnsmasq

Configuration

Edit the dnsmasq configuration:

    sudo nano /etc/dnsmasq.conf

Add the following entries: Host-record defines the API endpoint, and the ingress IP address defines wildcard apps routing

    no-dhcp-interface=<interface-name>
    server=10.5.0.3
    host-record=api.osac.lab.massopen.cloud.com,<api-ip>
    address=/apps.osac.lab.massopen.cloud.com/<ingress-ip>

Restart services

    sudo systemctl restart dnsmasq
    sudo systemctl restart systemd-resolved

 Validate DNS

    dig api.osac.lab.massopen.cloud.com
    dig apps.osac.lab.massopen.cloud.com

### 6. Issue: Multiple NICs Active on all nodes

Problem:
- Multiple active interfaces on nodes cause routing conflicts
- This impacts node discovery in Assisted Installer

Fix (on each node):

    sudo nmcli device disconnect <secondary-interface-name>

Ensure only one active interface is present on all nodes.

### 7. Assisted Installer Preparation

Steps performed:
1. Open cloud.redhat.com
2. Create a bare-metal cluster
3. Provide the base domain and add the SSH key from the jump host
4. Generate discovery ISO, download, and mount the ISO using iDRAC virtual media
5. Boot all 3 cluster nodes simultaneously using the ISO


Accessing the Cluster

After installation, update your local system to resolve cluster endpoints.
Edit /etc/hosts on your local machine:

    sudo nano /etc/hosts

Add entries which might look like

    <api-ip> api.osac.lab.massopen.cloud.com
    <ingress-ip> console-openshift-console.apps.osac.lab.massopen.cloud.com
    <ingress-ip> oauth-openshift.apps.osac.lab.massopen.cloud.com

Alternatively, update resolv.conf to point to the jump host DNS if required.
After updating, access the cluster using:

    https://console-openshift-console.apps.osac.lab.massopen.cloud.com


### 8. References

[Red Hat Blog: Using the OpenShift Assisted Installer Service to Deploy an OpenShift Cluster on Metal and vSphere](https://www.redhat.com/en/blog/using-the-openshift-assisted-installer-service-to-deploy-an-openshift-cluster-on-metal-and-vsphere)
