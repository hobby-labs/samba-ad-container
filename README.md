# samba-ad-container

# Prerequisite
## Create macvlan network
Create macvlan network that your organization's computers in your network to be able to communicate seamlessly with the primary DC container.
For example, your container's host is in the network `192.168.1.0/24`, you can create a macvlan network like below.

```
docker network create -d macvlan \
    --subnet=192.168.1.0/24 \
    --gateway=192.168.1.1 \
    -o parent=eth0 office_network
```

This command will create macvlan network named `office_network` on the interface `eth0` that belong to the network address `192.168.1.0/24`.
Containers that attaches this network will be able to communicate other hosts that located in the same network `192.168.1.0/24` by their mac address directly.
Containers do not need NAT interface like docker0.

# How to run a primary DC
## Run primary DC
Run a primary DC like below.

```
docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PARIMARY_DC" \
    -e CONTAINER_IP=192.168.1.71 \
    -e DOMAIN_FQDN="corp.mysite.example.com" \
    -e DOMAIN="CORP" \
    -e ADMIN_PASSWORD="p@ssword0" \
    -e DNS_FORWARDER="192.168.1.1" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    -d hobbylabs/samba-ad-container
```

You should specify IP of the `--dns` as same as the value of `--ip`.
This prevent the DNS update error after running Samba.

## Environment variables
| Name of variable | Required | Devault value | Note |
| ---------------- | -------- | ------------- | ---- |
| DC_TYPE          | Yes      | -             | This parameter requires "PARIMARY_DC" or "SECONDARY_DC" or "RESTORED_DC". "PARIMARY_DC" will build a Samba as a primary DC. "SECONDARY_DC" will build a Samba as a secondary DC. "RESTORED_DC" will build a Samba that restored from backup-data. "RESTORED_DC" is useful as the temporary DC if you want to restore Samba that has a same host name that had been running previously. |
| CONTAINER_IP     | No       | Interface IP of the docker | It is recommended to specify container IP if you have multiple IPs except loopback address. This parameter will be used as a listen IP of the Samba daemon. |
| DOMAIN_FQDN | No | mysite.example.com | Samba domain FQDN. It is not required but recommended to specify it that will be used your own site. |
| DOMAIN | No | (Upper case of the first element of DOMAIN_FQDN that splitted by ".") | Domain name of your DC. For example, if you do not specify it and you specified DOMAIN_FQDN=corp.mysite.example.com, "CORP" will be used. |
| ADMIN_PASSWORD | No | p@ssword0 | Password of the Administrator. You can change it after running Samba with samba-tool command. |
| DNS_FORWARDER | No | 8.8.8.8 | DNS forwarder for the Samba. This value will be written as the "dns forwarder" in /etc/samba/smb.conf |
