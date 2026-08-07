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
oc apply -f control-plane/networking/nncp-master-0.yaml
oc apply -f control-plane/networking/nncp-master-1.yaml
oc apply -f control-plane/networking/nncp-master-2.yaml

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
  --provider-network-type <network_type> \
  --provider-segment <vlan_id> \
  --provider-physical-network <provider_physical_network> \
  --share <network_name>

# Create the Ironic provisioning subnet with DHCP enabled for baremetal PXE and cleaning workflows
openstack subnet create \
  --network <network_name> \
  --subnet-range <network_cidr> \
  --ip-version 4 \
  --gateway <gateway_ip> \
  --allocation-pool start=<start_ip>,end=<end_ip> \
  --dhcp <subnet_name>
  --dns-nameserver <dns_ip>

# Create a router and attach the Ironic provisioning subnet to the router
openstack router create provisioning-router
openstack router add subnet provisioning-router ironic-provisioning-subnet

# Reapply control plane (after ironic provisioning network exists)
Update the Ironic network configuration in openstack_control_plane.yaml by replacing all instances of <ironic_network_uuid>.

oc apply -f control-plane/openstack_control_plane.yaml -n openstack
```

---

#### References

- [Planning your deployment](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/pdf/planning_your_deployment/Red_Hat_OpenStack_Services_on_OpenShift-18.0-Planning_your_deployment-en-US.pdf)
- [Deploying Red Hat OpenStack Services on OpenShift](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/html/deploying_red_hat_openstack_services_on_openshift/index)
- [Configuring the Bare Metal Provisioning Service](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/html/configuring_the_bare_metal_provisioning_service/index)
- [Configuring Networking Services](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/html/configuring_networking_services/index)