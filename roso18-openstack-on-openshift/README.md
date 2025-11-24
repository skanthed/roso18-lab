### ROSO18: OpenStack on OpenShift Deployment using ESI

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

# Attach trunk to nodes
openstack esi node network attach --trunk nncp-trunk-1 <node1>
openstack esi node network attach --trunk nncp-trunk-2 <node2>
openstack esi node network attach --trunk nncp-trunk-3 <node3>
```

---

#### 3. Apply Required Operator Manifests

```bash
oc new-project openstack
oc label ns openstack security.openshift.io/scc.podSecurityLabelSync=false --overwrite
oc label ns openstack pod-security.kubernetes.io/enforce=privileged --overwrite

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
oc create -f openstack_service_secret.yaml -n openstack
oc describe secret osp-secret -n openstack
```

---

#### 5. Node Network Config Policies (NNCP)

```bash
# For each worker node
oc get nodes -l node-role.kubernetes.io/worker -o jsonpath="{.items[*].metadata.name}"

# Apply NNCP config
roso18-openstack-on-openshift/control-plane/networking/
#oc apply node network configuration policy according to your network
oc apply -f control-plane/networking/nncp-host-192-168-60-180.yaml
oc apply -f control-plane/networking/nncp-host-192-168-60-143.yaml
oc apply -f control-plane/networking/nncp-host-192-168-60-193.yaml

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

#oc apply control plane configuration
oc create -f control-plane/openstack_control_plane.yaml -n openstack
oc get openstackcontrolplane -n openstack
oc get openstackcontrolplanes -n openstack

oc get pods -n openstack | grep -i openstackclient
oc rsh -n openstack openstackclient

#oc apply DNS for baremetal ironic configuration
oc apply -f control-plane/dnsmasq-dns-ironic.yaml

# Inside pod
openstack endpoint list
openstack token issue
```

---


####  Summary
This captures the essential commands for deploying OpenStack on OpenShift using ESI with MetalLB, NMState, and LVM integration. 

