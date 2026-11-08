FROM ubuntu:26.04
LABEL maintainer="Tsutomu Nakamura<tsuna.0x00@gmail.com>"

# Notes for Ubuntu 26.04:
# * AD DC components (/usr/sbin/samba, provisioning data) are shipped in "samba-ad-dc".
# * "dnsutils" has been replaced by "bind9-dnsutils" (provides the "host" command).
# * "iproute2" provides the "ip" command used by entrypoint.sh to detect the container IP.
# * "bsdextrautils" provides the "rev" command used by entrypoint.sh (it was in "util-linux" on 20.04).
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y pkg-config attr acl samba samba-ad-dc smbclient ldap-utils \
        winbind libnss-winbind libpam-winbind \
        supervisor openvpn inetutils-ping iproute2 \
        libpam-krb5 krb5-config krb5-user \
        vim git bind9-dnsutils net-tools ed bsdextrautils && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* && \
        rm -f /etc/samba/smb.conf /etc/krb5.conf

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod u+x /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
