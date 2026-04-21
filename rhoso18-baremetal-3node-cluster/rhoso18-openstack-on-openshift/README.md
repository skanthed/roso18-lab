## RHOSO18 OpenStack on OpenShift Deployment Guide


This document provides a comprehensive, step-by-step implementation guide for deploying Red Hat OpenStack Services on OpenShift (RHOSO18) within an OpenShift cluster environment.

It captures the exact sequence of actions, configurations, and validation steps followed during the deployment. The objective is to establish a repeatable and standardized deployment process for us.


#### 1. Apply Required Operator Manifests

```bash
# Apply operator files

oc apply -f operators/cert-manager-install.yaml
oc apply -f operators/cluster-observability-install.yaml
oc apply -f operators/metallb-install.yaml
oc apply -f operators/metallb-instance.yaml
oc apply -f operators/nmstate-install.yaml
oc apply -f operators/nmstate-instance.yaml
```

##### Verify:
```bash
oc get pods -A | grep -E 'cert-manager|nmstate|metallb|observability'
```

---

#### 2. Secrets and Service Setup

```bash
Install OpenStack Operator and create an instance of the Operator initialization resource. The OpenStack Operator is ready to use when the Status of the openstack instance is Conditions: Ready.

oc new-project openstack
oc get namespace openstack -ojsonpath='{.metadata.labels}' | jq
oc label ns openstack security.openshift.io/scc.podSecurityLabelSync=false --overwrite
oc label ns openstack pod-security.kubernetes.io/enforce=privileged --overwrite

oc project openstack

oc create -f openstack_service_secret.yaml -n openstack
oc describe secret osp-secret -n openstack
```

---


#### 3. Node Network Config Policies (NNCP)

```bash

# For each worker node
oc get nodes -l node-role.kubernetes.io/worker -o jsonpath="{.items[*].metadata.name}"

# Apply NNCP config
rhoso18-openstack-on-openshift/control-plane/networking/
#oc apply node network configuration policy according to your network
oc apply -f control-plane/networking/nncp-2c-ea-7f-90-42-d3.yaml
oc apply -f control-plane/networking/nncp-b4-96-91-4c-b7-ac.yaml
oc apply -f control-plane/networking/nncp-b4-96-91-4c-c7-b0.yaml

oc get nncp -w
```

---

#### 4. Apply MetalLB, NAD & IP Pools

```bash
#oc apply network attach definition based on your netwok
oc apply -f control-plane/networking/openstack-net-attach-def.yaml
oc get net-attach-def -n openstack

oc apply -f control-plane/networking/openstack-ipaddresspools.yaml
oc get ipaddresspool -n metallb-system
oc describe ipaddresspool -n metallb-system

oc apply -f control-plane/networking/openstack-l2advertisement.yaml
oc get L2Advertisement -n metallb-system
```

###### Enable Global IP Forwarding (if using OVNKubernetes)

```bash
oc get network.operator cluster --output=jsonpath='{.spec.defaultNetwork.type}'

oc patch network.operator cluster -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"gatewayConfig":{"ipForwarding": "Global"}}}}}' --type=merge
```

---

#### 5.  Configure LVM Storage

```bash

oc apply -f storage/lvms-install.yaml
oc get csv -n openshift-storage -o custom-columns=Name:.metadata.name,Phase:.status.phase

oc apply -f storage/node_labels.yaml
oc get nodes --show-labels

# Apply LVM config per node
oc apply -f storage/lvmclusterCR.yaml
oc get lvmcluster -n openshift-storage

oc get pods -n openshift-storage -o wide | grep vg-manager
```

---


#### 6.  Deploy OpenStack Control Plane

```bash
#oc apply switch configuration for network generic switch
oc apply -f control-plane/ngs/ngs_config.yaml

#Commands to view the OpenStackControlPlane CRD definition and specification
oc describe crd openstackcontrolplane
oc explain openstackcontrolplane.spec

#oc apply control plane configuration
oc create -f control-plane/openstack_control_plane.yaml -n openstack
oc get openstackcontrolplanes -n openstack

#oc apply DNS for baremetal ironic configuration
oc apply -f control-plane/dnsmasq-dns-ironic.yaml

oc get pods -n openstack | grep -i openstackclient
oc rsh -n openstack openstackclient

# Inside pod
openstack endpoint list
openstack token issue
```

---

#### 7. (Post-Install) Create an Ironic-Provisioning Network & Subnet in OpenStack pod

```bash

oc rsh -n openstack openstackclient

# Create a shared provider network for Ironic provisioning and cleaning traffic
openstack network create \
  --provider-network-type vlan \
  --provider-physical-network bmnet \
  --share ironic-provisioning

# Create the Ironic provisioning subnet with DHCP enabled for baremetal PXE and cleaning workflows
openstack subnet create \
  --network ironic-provisioning \
  --subnet-range 172.20.1.0/24 \
  --ip-version 4 \
  --gateway 172.20.1.100 \
  --allocation-pool start=172.20.1.150,end=172.20.1.200 \
  --dns-nameserver 172.20.1.80 \
  --dhcp ironic-provisioning-subnet

# Create a router and attach the Ironic provisioning subnet to the router
openstack router create provisioning-router
openstack router add subnet provisioning-router ironic-provisioning-subnet

# Reapply control plane (after ironic provisioning network exists)
Update the Ironic network configuration in openstack_control_plane.yaml by replacing all instances of <ironic_network_uuid>.

oc apply -f control-plane/openstack_control_plane.yaml -n openstack
```


---

#### 8. Networking Generic Switch (NGS) Validation

```bash
# Create VLAN-backed networks for testing switch integration
openstack network create test_net_dell \
  --provider-network-type vlan \
  --provider-physical-network bmnet \
  --provider-segment 60 \
  --disable-port-security

openstack network create test_net_cumulus \
  --provider-network-type vlan \
  --provider-physical-network bmnet \
  --provider-segment 61 \
  --disable-port-security

# Create baremetal ports mapped to switch interfaces
openstack port create --network test_net_dell dell_eth1_13 --vnic-type baremetal
openstack port create --network test_net_cumulus cumulus_swp9 --vnic-type baremetal

# Bind ports to physical switch interfaces using local link information
openstack port set --host test-host \
  --binding-profile '{"local_link_information": [{"switch_info": "dell-switch", "port_id": "TenGigabitEthernet 1/13"}]}' \
  dell_eth1_13

openstack port set --host test-host \
  --binding-profile '{"local_link_information": [{"switch_info": "MOC-DEV-SW1", "port_id": "swp9"}]}' \
  cumulus_swp9

# Verify port binding status
openstack port show dell_eth1_13
openstack port show cumulus_swp9
```
---

#### 9. Switch Side Validation

```bash
# Dell Switch - Verify interface configuration
show running-config interface TenGigabitEthernet 1/13

# Cumulus Switch - Verify VLAN and interface mapping
net show bridge vlan
nv show interface
```
Verified that switch interfaces are in Layer 2 mode and VLANs (60, 61) are correctly configured and mapped to the respective ports.

---