### RHOSO18: OpenStack on OpenShift Deployment using ESI

#### Overview
This documentation provides a **step-by-step reference** for installing OpenStack on OpenShift using the **Elastic Secure Infrastructure (ESI)** and the assisted installer method on a 3-node cluster. It includes setup commands, network configurations, and OpenShift integration.

#### 1. Create ESI-Compatible Networks

```bash
openstack network create ctrlplane-network

openstack subnet create ctrlplane-subnet \
  --network ctrlplane-network \
  --subnet-range 192.168.122.0/24 \
  --allocation-pool start=192.168.122.10,end=192.168.122.20 \
  --no-dhcp

openstack network create internalapi
openstack network create tenant
openstack network create ironic

openstack subnet create \
  --network internalapi \
  --subnet-range 172.17.0.0/24 \
  --allocation-pool start=172.17.0.10,end=172.17.0.20 \
  --no-dhcp \
  internalapi-subnet

openstack subnet create \
  --network tenant \
  --subnet-range 172.19.0.0/24 \
  --allocation-pool start=172.19.0.10,end=172.19.0.20 \
  --no-dhcp \
  tenant-subnet

openstack subnet create \
  --network ironic \
  --subnet-range 172.20.1.0/24 \
  --allocation-pool start=172.20.1.10,end=172.20.1.20 \
  --no-dhcp \
  ironic-subnet
```

---

#### 2. Create ESI Trunks

```bash
#openstack esi trunk create --native-network <accessible network> <trunk name>
openstack esi trunk create --native-network ctrlplane-network nncp-trunk-1
#openstack esi trunk add network --tagged-networks <private network> <trunk name>
openstack esi trunk add network --tagged-networks internalapi nncp-trunk-1
openstack esi trunk add network --tagged-networks ironic nncp-trunk-1
openstack esi trunk add network --tagged-networks tenant nncp-trunk-1
openstack esi trunk add network --tagged-networks moc-obm-mgmt nncp-trunk-1

# Attach trunk to nodes
openstack esi node network attach --trunk nncp-trunk-1 <node1>
openstack esi node network attach --trunk nncp-trunk-2 <node2>
openstack esi node network attach --trunk nncp-trunk-3 <node3>
```

---

#### 3. Apply Required Operator Manifests

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

#### 4. Secrets and Service Setup

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

#### 5. Node Network Config Policies (NNCP)

```bash

Add DHCP Shim for OBM VLAN Access

To allow the OBM VLAN interface (`moc-obm-mgmt`) to receive an IP via DHCP, add the following `additionalNetworks` configuration to the cluster network operator: See control-plane/networking/dhcp-shim-additional-network.yaml for reference.

# For each worker node
oc get nodes -l node-role.kubernetes.io/worker -o jsonpath="{.items[*].metadata.name}"

# Apply NNCP config
rhoso18-openstack-on-openshif-esi/control-plane/networking/
#oc apply node network configuration policy according to your network
oc apply -f control-plane/networking/nncp-host-192-168-60-181.yaml
oc apply -f control-plane/networking/nncp-host-192-168-60-178.yaml
oc apply -f control-plane/networking/nncp-host-192-168-60-54.yaml

oc get nncp -w
```

---

#### 6. Apply MetalLB, NAD & IP Pools

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

#### 7.  Configure LVM Storage

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

#### 8.  Deploy OpenStack Control Plane

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

#### 9. (Post-Install) Create Ironic-Provisioning Network & Subnet in OpenStack pod

```bash

oc rsh -n openstack openstackclient

# Create a shared provider network for Ironic provisioning and cleaning traffic
openstack network create \
  --provider-network-type vlan \
  --provider-segment 596 \
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


####  Summary
This captures the essential commands for deploying OpenStack on OpenShift using ESI with MetalLB, NMState, and LVM integration. 

