# samba-ad-container

# Prerequisite of primary/secondary DC
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
You can run a primary DC like below.

```
docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    -e DOMAIN_FQDN="corp.mysite.example.com" \
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
| DC_TYPE          | Yes      | -             | This parameter requires "**PRIMARY_DC**" or "**SECONDARY_DC**" or "**RESTORED_DC**". "PRIMARY_DC" will build a Samba as a primary DC. "SECONDARY_DC" will build a Samba as a secondary DC. "RESTORED_DC" will build a Samba that restored from backup-data. "RESTORED_DC" is useful as the temporary DC if you want to restore Samba that has a same host name that had been running previously. |
| CONTAINER_IP     | No       | Interface IP of the docker | It is recommended to specify container IP if you have multiple IPs except loopback address. This parameter will be used as a listen IP of the Samba daemon. |
| DOMAIN_FQDN | No | mysite.example.com | Samba domain FQDN. It is not required but recommended to specify it that will be used your own site. |
| DOMAIN | No | (Upper case of the first element of DOMAIN_FQDN that splitted by ".") | Domain name of your DC. For example, if you do not specify it and you specified DOMAIN_FQDN=corp.mysite.example.com, "CORP" will be used. |
| ADMIN_PASSWORD | No | p@ssword0 | Password of the Administrator. You can change it after running Samba with samba-tool command. |
| DNS_FORWARDER | No | 8.8.8.8 | DNS forwarder for the Samba. This value will be written as the "dns forwarder" in /etc/samba/smb.conf |

## Use users smb.conf
Mount /etc/samba directory that contains smb.conf if you want to use smb.conf as user's own.

```
docker run --name pdc01 --hostname pdc01 \
   ...
   --volume /var/data/pdc01/etc/samba:/etc/samba
   ...
    -d hobbylabs/samba-ad-container
```

smb.conf you mounted will be used in the Samba process.
And do not specify the ro(Read only) option.
This cause errors during provisioning process.

## Backup PDC
You can use samba-tool to backup Samba data.

```
# docker exec -ti pdc01 samba-tool domain backup online --targetdir=/var/tmp --server=127.0.0.1 -UAdministrator%secret
# docker cp pdc01 /var/tmp/samba-backup-* .
# docker exec pdc01 rm -f /var/tmp/samba-backup-*
# ls -l ./samba-backup-*
-> samba-backup-corp.mysite.example.com-YYYY-MM-DDThh-mm-ss.SSSSSS.tar.bz2
```

Then you should save `samba-backup-corp.mysite.example.com-YYYY-MM-DDThh-mm-ss.SSSSSS.tar.bz2` to more safely place like NAS or cloud storage not to missing it.

## Backup PDC (Unofficial way)
You can run the container mounting `/etc/samba` and `/var/lib/samba` on the container like below.

```
# docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    --volume /data/pdc01/etc/samba:/etc/samba \
    --volume /data/pdc01/var/lib/samba:/var/lib/samba \
    -d hobbylabs/samba-ad-container
```

Then you should save data `/data/pdc01/etc/samba` and `/data/pdc01/var/lib/samba` to more safely place like NAS or cloud storage not to missing it.

## Restore PDC
TODO:
This program will add a feature to restore data like this journal.

https://github.com/hobby-labs/samba-ad-container/wiki/Strategies-of-backup-and-restore-AD#restore-strategies

## Restore PDC (Unofficial way)
Restore data `/etc/samba` and `/var/lib/samba` to the directory on the host.
For example, they were restored to `/data/pdc01/etc/samba` and `/data/pdc01/var/lib/samba`.
Then you can just run the container with mounting them like below.

```
# docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    --volume /data/pdc01/etc/samba:/etc/samba \
    --volume /data/pdc01/var/lib/samba:/var/lib/samba \
    -d hobbylabs/samba-ad-container
```

# How to run a secondary DC
## Prerequisite of secondary DC
Secondary DC requires primary DC.
Instructions here assumes that host name of the secondary DC is `bdc01` and it has an IP `192.168.1.72` and its primary DC has been running with an IP `192.168.1.71`.

## Run secondary DC
You can run a secondary DC like below.

```
docker run --name bdc01 --hostname bdc01 \
    -e DC_TYPE="SECONDARY_DC" \
    --network office_network \
    --privileged \
    --ip 192.168.1.72 \
    --dns 192.168.1.71 \
    -d hobbylabs/samba-ad-container
```
Specify the IP of the primary DC to `--dns 192.168.1.71`.
Otherwise `samba-tool domain join` as secondary DC will be fail.

## Use users smb.conf
You can also use your smb.conf similar to the primary DC.

```
docker run --name bdc01 --hostname bdc01 \
   ...
   --volume /var/data/bdc01/etc/samba:/etc/samba
   ...
    -d hobbylabs/samba-ad-container
```
