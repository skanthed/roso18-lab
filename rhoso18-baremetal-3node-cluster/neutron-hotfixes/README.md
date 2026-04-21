## Neutron Control Plane Hotfix Guide


This document provides a detailed, step-by-step procedure to apply a hotfix to the Neutron control plane container in a Red Hat OpenStack Services on OpenShift environment.

The hotfix process includes:
- Identifying the current running Neutron container image
- Building a custom container image with updated RPMs
- Pushing the image to the OpenShift internal registry
- Updating the OpenStack control plane to use the new image
- Verifying that the hotfix is successfully applied
This approach enables applying patches without redeploying the entire OpenStack environment.


#### 1. Get current State of Neutron pod and Show current container images

```bash
oc get pods -n openstack -l service=neutron

oc get pod -n openstack neutron-5748b6f967-lgh76 -o json | jq -r '.spec.containers[] | "\(.name) \(.image)"'
oc get pod -n openstack neutron-5748b6f967-lgh76 -o jsonpath='{.spec.containers[*].name}'; echo

# The container image below is the base image to patch
registry.redhat.io/rhoso/openstack-neutron-server-rhel9@sha256:5d2db308bd0568888abae1
```
---

#### 2. Verify container user and exit

```bash
# If the container user is not 'root', switch to root and back to neutron user in Dockerfile
oc rsh -n openstack neutron-5748b6f967-lgh76 whoami
exit
```

---

#### 3. Setup Hot Fix environment

```bash
mkdir -p hotfix
cd hotfix

# Copy all hotfix RPMs into hotfix directory
ls hotfix/
python3-networking-generic-switch-7.1.1-18.739.1de4b6e.el9osttrunk.noarch.rpm

# Create Dockerfile in hotfix directory using base image
Reference file: neutron-hotfixes/Dockerfile

# Create hotfix.yaml defining ImageStream and BuildConfig
Reference file:neutron-hotfixes/neutron-hotfix.yaml

# Apply hotfix.yaml to create build environment
oc apply -f neutron-hotfix.yaml

oc get is -n openstack neutron-hotfix
oc get bc -n openstack neutron-hotfix -o yaml
imagestream.image.openshift.io/neutron-hotfix created
buildconfig.build.openshift.io/neutron-hotfix created
```
---

#### 4. Configure image registry storage if required

```bash
oc apply -f image-registry-pvc.yaml -n openshift-image-registry 

# Verify registry configuration
oc get image.config.openshift.io/cluster -o yaml
oc get co image-registry
oc get pods -n openshift-image-registry -w
oc get configs.imageregistry.operator.openshift.io cluster -o yaml

# If registry storage is not configured, patch to use emptyDir
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
```
---

#### 5.  Start binary build using local RPMs and Dockerfile

```bash
oc start-build -n openstack neutron-hotfix --from-dir=. --follow

# Expected output at end of build
Successfully pushed image-registry.openshift-image-registry.svc:5000/openstack/neutron-hotfix@sha256:5e4651eaa9bbad0ca12
Push successful

# Update OpenStackVersion CR to use hotfix image
Reference file:neutron-hotfixes/openstackversionpatch.yaml

oc patch openstackversion openstack-control-plane --type=merge --patch-file openstackversionpatch.yaml
```

---


#### 6.  Verify pod is running hotfix image

```bash
oc get pods -n openstack -l service=neutron
oc get pod -n openstack neutron-8497cc899f-llk45 -o json | jq -r '.spec.containers[] | "\(.name) \(.image)"'

# Expected updated image
neutron-api image-registry.openshift-image-registry.svc:5000/openstack/neutron-hotfix@sha256:5e4651eaa9bbad0ca12
neutron-httpd image-registry.openshift-image-registry.svc:5000/openstack/neutron-hotfix@sha256:5e4651eaa9bbad0ca12

# Verify installed RPM inside container
oc rsh -n openstack -c neutron-api neutron-8497cc899f-llk45 rpm -qa | grep networking-generic-switch

# Expected output
python3-networking-generic-switch-7.1.1-18.739.1de4b6e.el9osttrunk.noarch.rpm

# Verify logs for errors
oc logs -n openstack neutron-8497cc899f-llk45 -c neutron-api --tail=100
```

---

#### 7.  References

- [Red Hat Knowledgebase: RHOSO18 Control Plane Hotfix (Cinder Example)](https://access.redhat.com/solutions/7133065)

- [OpenShift Documentation: Configuring Image Registry Storage (Bare Metal)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/registry/setting-up-and-configuring-the-registry#installation-registry-storage-config_configuring-registry-storage-baremetal)
