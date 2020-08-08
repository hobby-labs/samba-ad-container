FROM ubuntu:18.04
LABEL maintainer "Tsutomu Nakamura<tsuna.0x00@gmail.com>"

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y pkg-config attr acl samba smbclient ldap-utils \
        winbind libnss-winbind libpam-winbind \
        supervisor openvpn inetutils-ping \
        libpam-krb5 krb5-config krb5-user \
        vim git dnsutils net-tools && \
        apt-get clean

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

