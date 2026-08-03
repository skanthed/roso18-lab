#!/bin/bash
set -euo pipefail

CLUSTER="<CLUSTER_NAME>"

: "${BMC_USERNAME:?Set BMC_USERNAME before running this script}"
: "${IPMI_PASSWORD:?Set IPMI_PASSWORD before running this script}"

read -rp "Are you sure? Delete: ${CLUSTER} [y/n]: " DELETE

if [[ "${DELETE}" != "y" && "${DELETE}" != "Y" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

BOOTSTRAP=$(virsh list | grep "${CLUSTER}-.*bootstrap" | awk '{print $2}' | tr -d " " || true)
if [[ "${BOOTSTRAP}" != "" ]]; then
  virsh destroy  "${BOOTSTRAP}"
  virsh undefine "${BOOTSTRAP}" --remove-all-storage
  rm -rf "/var/lib/libvirt/openshift-images/${CLUSTER}"*
fi

rm -rf "${CLUSTER}/"

ipmitool -I lanplus -H "<BMC_IP_MASTER_0>" -U "${BMC_USERNAME}" -E chassis power off
ipmitool -I lanplus -H "<BMC_IP_MASTER_1>" -U "${BMC_USERNAME}" -E chassis power off
ipmitool -I lanplus -H "<BMC_IP_MASTER_2>" -U "${BMC_USERNAME}" -E chassis power off
#ssh master-0 'sudo shutdown -h now'
#ssh master-1 'sudo shutdown -h now'
#ssh master-2 'sudo shutdown -h now'