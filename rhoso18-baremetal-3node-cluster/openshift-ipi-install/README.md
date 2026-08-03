# OpenShift 4.18 Bare-Metal IPI Installation

Scripts and configuration for deploying a compact (3-master, 0-worker) OpenShift 4.18 cluster on bare metal using the IPI (Installer-Provisioned Infrastructure) method with Redfish virtual media provisioning.

---

## Prerequisites

Before running the installation:

### 1. Download and extract the OpenShift client

Download `openshift-client-linux-<version>.tar.gz` from the [Red Hat Hybrid Cloud Console](https://console.redhat.com/openshift/downloads).

Extract `oc` and `kubectl`, then either:

- Install them globally (for example, `/usr/local/bin`), **or**
- Place them in the repository's `bin/` directory (this repository assumes `bin/`).

```bash
tar -xzf openshift-client-linux-<version>.tar.gz -C bin/ oc kubectl
chmod +x bin/oc bin/kubectl
```

### 2. Download your pull secret

Download your pull secret from the [Red Hat Hybrid Cloud Console](https://console.redhat.com/openshift/downloads) under **Downloads → Pull Secret** and save it as:

```
assets/pull_secret.json
```

### 3. Configure the install-config template

Update `assets/install-config-template.yaml` with your environment-specific configuration, including:

- Cluster name
- Base domain
- Network configuration
- API & Ingress VIPs
- BMC/iDRAC information
- Node IP addresses
- Pull Secret
- SSH Public Key

---

## Installation

```
00. Complete all prerequisites above
01. ./01_extract_installer.sh       # Pulls openshift-baremetal-install from the release image
02. ./02_run_installation.sh        # Runs the full cluster installation (~45–90 min)
03. ./cleanup.sh                    # Run only if you need to tear down the cluster
```

After a successful install, cluster credentials are written to:

```
<CLUSTER_NAME>/auth/kubeconfig
<CLUSTER_NAME>/auth/kubeadmin-password
```

Export the kubeconfig to start using the cluster:

```bash
export KUBECONFIG=$(pwd)/<CLUSTER_NAME>/auth/kubeconfig
```

Verify the cluster:

```bash
oc get nodes
oc get clusteroperators
```

---

## MachineConfigs

The `assets/MC/` directory contains optional MachineConfig resources for customizing the networking configuration of the control-plane nodes.

Apply the required MachineConfigs after the cluster installation, depending on your environment and deployment requirements.

```bash
oc apply -f assets/MC/
```

---

## Notes

* `<CLUSTER_NAME>/` is created automatically during installation and contains cluster state, credentials, certificates, and logs.
* `assets/install-config.yaml` is generated from `assets/install-config-template.yaml` before each installation.
* `assets/pull_secret.json` contains registry credentials and must never be committed to Git.
* `cleanup.sh` removes the generated installation artifacts and powers off the configured bare-metal nodes.
