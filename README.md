# samba-ad-container

<!--ts-->
   * [Prerequisite of primary/secondary DC](#prerequisite-of-primarysecondary-dc)
      * [Create macvlan network](#create-macvlan-network)
   * [How to run a primary DC](#how-to-run-a-primary-dc)
      * [Run primary DC](#run-primary-dc)
      * [Use user specified smb.conf](#use-user-specified-smbconf)
      * [Environment variables](#environment-variables)
      * [Backup PDC](#backup-pdc)
      * [Backup PDC (Unofficial way)](#backup-pdc-unofficial-way)
      * [Restore PDC](#restore-pdc)
         * [Remitations of restoring PDC](#remitations-of-restoring-pdc)
         * [Restore temporary PDC first](#restore-temporary-pdc-first)
         * [Restore PDC with that same name that running previously with joining a domain from restored PDC](#restore-pdc-with-that-same-name-that-running-previously-with-joining-a-domain-from-restored-pdc)
         * [Remove rpdc](#remove-rpdc)
      * [Restore PDC (Unofficial way)](#restore-pdc-unofficial-way)
   * [How to run a secondary DC](#how-to-run-a-secondary-dc)
      * [Prerequisite of secondary DC](#prerequisite-of-secondary-dc)
      * [Run secondary DC](#run-secondary-dc)
      * [Use users smb.conf on secondary DC](#use-users-smbconf-on-secondary-dc)
      * [Backup secondary DC](#backup-secondary-dc)
      * [Restore secondary DC](#restore-secondary-dc)

<!-- Added by: tsutomu, at: Mon Sep 21 12:19:41 PM JST 2020 -->

<!--te-->

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

## Use user specified smb.conf
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

## Environment variables
| Name of variable | Required | Devault value | Note |
| ---------------- | -------- | ------------- | ---- |
| DC_TYPE          | Yes      | -             | This parameter requires "**PRIMARY_DC**" or "**SECONDARY_DC**". "PRIMARY_DC" will build a Samba as a primary DC or restore from backups. "SECONDARY_DC" will build a Samba as a secondary DC. |
| CONTAINER_IP     | No       | Interface IP of the docker | It is recommended to specify container IP if you have multiple IPs except loopback address. This parameter will be used as a listen IP of the Samba daemon. |
| DOMAIN_FQDN | No | mysite.example.com | Samba domain FQDN. It is not required but recommended to specify it that will be used your own site. |
| DOMAIN | No | (Upper case of the first element of DOMAIN_FQDN that splitted by ".") | Domain name of your DC. For example, if you do not specify it and you specified DOMAIN_FQDN=corp.mysite.example.com, "CORP" will be used. |
| ADMIN_PASSWORD | No | p@ssword0 | Password of the Administrator. You can change it after running Samba with samba-tool command. |
| DNS_FORWARDER | No | 8.8.8.8 | DNS forwarder for the Samba. This value will be written as the "dns forwarder" in /etc/samba/smb.conf |
| RESTORE_FROM | No | (specify a type of method to restore) | Type of method to restore AD. There are 2 types of options like `BACKUP_FILE` and `JOINING_DOMAIN`. `BACKUP_FILE` will restore AD from a backup file that locatated in specific directory `/backup` on the container. This process requires its host name is `rpdc`. `JOINING_DOMAIN` will restore AD by joining a current domain. As a point of caution, `JOINING_DOMAIN` will transfer roles to new AD from current master AD. |

# Backup and restore

## Backup PDC
You can use samba-tool to backup Samba data.

```
# docker exec -ti pdc01 samba-tool domain backup online --targetdir=/var/tmp --server=127.0.0.1 -UAdministrator%secret
# docker cp pdc01 /var/tmp/samba-backup-* .
# docker exec pdc01 rm -f /var/tmp/samba-backup-*
# ls -l ./samba-backup-*
-> samba-backup-corp.mysite.example.com-YYYY-MM-DDThh-mm-ss.SSSSSS.tar.bz2
```

Then you should save `samba-backup-corp.mysite.example.com-YYYY-MM-DDThh-mm-ss.SSSSSS.tar.bz2` (file name will be different by your domain name) to more safely place like NAS or cloud storage not to missing it.

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

Then you can save data `/data/pdc01/etc/samba` and `/data/pdc01/var/lib/samba` to more safely place like NAS or cloud storage not to missing it.

## Restore PDC
### Remitations of restoring PDC
You will take a little complex strategy to restore PDC if you want to restore it with a same name of the PDC that running previously.
The reason why we have to do so is because there are no method to restore like this so far.
The strategy to restore PDC as a same name of the PDC that running previously is like the link below.

https://github.com/hobby-labs/samba-ad-container/wiki/Strategies-of-backup-and-restore-AD#restore-strategies

I will explain how to restore PDC as a same name in this section.

### Restore temporary PDC first
Prepare the directory that contains a backup file on your host.
In this explanation, it assumes that the directory is `/path/to/backup`.
Run the container with this conditions.

* Set environment variables `-e DC_TYPE="PRIMARY_DC"` and `-e RESTORE_FROM="BACKUP_FILE"`
* Mounting a volume `/path/to/backup` on the host to `/backup` on the container. It assumes that the name of backup file is `samba-backup-corp.yoursite.example.com-YYYY-MM-DDThh-mm-ss.SSSSSS.tar.bz2`
* Specify the name of a container differ from the PDC that running previously. Use `rpdc` in this section.

```
docker run --name rpdc --hostname rpdc \
    -e DC_TYPE="PRIMARY_DC" \
    -e RESTORE_FROM="BACKUP_FILE" \
    --network office_network \
    --privileged \
    --ip 192.168.1.73 \
    --dns 192.168.1.73 \
    --volume ${PWD}/example/backup:/backup \
    -ti hobbylabs/samba-ad-container
```

### Restore PDC with that same name that running previously with joining a domain from restored PDC
Restore new PDC named `pdc01` after `rpdc` launches properly.
Run the container with the option `RESTORE_FROM="JOINING_DOMAIN"`, your `DOMAIN_FQDN` and `ADMIN_PASSWORD`.
And you should specify `--dns 192.168.1.73` as your `rpdc`'IP.

```
docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    -e RESTORE_FROM="JOINING_DOMAIN" \
    -e DOMAIN_FQDN="corp.mysite.example.com" \
    -e ADMIN_PASSWORD="secret" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    --dns 192.168.1.73 \
    -ti hobbylabs/samba-ad-container
```

This instruction will restore new AD by joining domain from `rpdc` and demote `rpdc`.
It means new AD `pdc01` get the rights of primary AD from `rpdc` then remove them from it.

### Remove rpdc
After succeeded restoring new AD `pdc01`, you can delete `rpdc`.

```
docker stop rpdc
docker rm rpdc
```

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

## Use users smb.conf on secondary DC
You can also use your smb.conf similar to the primary DC.

```
docker run --name bdc01 --hostname bdc01 \
   ...
   --volume /var/data/bdc01/etc/samba:/etc/samba
   ...
    -d hobbylabs/samba-ad-container
```

## Backup secondary DC
You can backup secondary DC by copying config files.

```
docker exec -ti bdc01 cp /etc/samba/smb.conf
```

Additionally, backup other config files if smb.conf include them.
And you need not take any backup data because it will be restored from primary DC in restore process.

## Restore secondary DC
You can restore secondary DC by running samba-ad-container with smb.conf that backupped previously.

```
docker run --name bdc01 --hostname bdc01 \
    -e DC_TYPE="SECONDARY_DC" \
    ......
    -v /path/to/backup/smbconf:/etc/samba
    ......
    -d hobbylabs/samba-ad-container
```

# Persistence logs
## Use fluentd log driver
Run a fuluentd container with binding host's ports '24224'.
```
mkdir -p /var/docker/fluentd/data/log
sudo chmod -R 777 /var/docker/fluentd/data/log
sudo ln -s /var/docker/fluentd/data /fluentd
docker run -d -p 24224:24224 -p 24224:24224/udp \
    -v /var/docker/fluentd/data/log:/fluentd/log \
    -v /var/docker/fluentd/data/etc:/fluentd/etc \
    --hostname fluentd --name fluentd \
    fluentd
```

Run a samba container with a fuluentd's log driver

```
docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    -e DOMAIN_FQDN="corp.mysite.example.com" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    --log-driver=fluentd --log-opt fluentd-address=x.x.x.x:24224 --log-opt tag="docker.{{.Name}}" \
    -d hobbylabs/samba-ad-container
```

Logs will be save in `/var/docker/fluentd/data/log` on the host machine.

## Use syslog driver
First, prepare syslog server.
This repository contains an example config file for syslog-ng and you can use it.
```
docker run --rm -it -p 514:514/udp -p 601:601 \
    --name syslog-ng \
    --volume ${PWD}/container/syslog-ng/etc/syslog-ng/syslog-ng.conf:/etc/syslog-ng/syslog-ng.conf \
    balabit/syslog-ng
```

Secound, you can run the Samba container with logging driver syslog.

```
docker run --rm --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PRIMARY_DC" \
    -e DOMAIN_FQDN="corp.mysite.example.com" \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    --log-driver=syslog \
    --log-opt tag="pdc01" \
    --log-opt syslog-address=udp://x.x.x.x:514 \
    hobbylabs/samba-ad-container
```

Then you can see logs `/var/log/containers/pdc01/syslog.log` on the `syslog-ng` container.
