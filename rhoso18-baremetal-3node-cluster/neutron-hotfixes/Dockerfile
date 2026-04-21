FROM registry.redhat.io/rhoso/openstack-neutron-server-rhel9@sha256:5d2db308bd0568888abae1
USER root
COPY *.rpm /tmp/
RUN dnf update -y --nobest /tmp/*.rpm
RUN dnf clean all
RUN rm -f /tmp/*.rpm
USER neutron
