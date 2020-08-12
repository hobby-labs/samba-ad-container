# samba-ad-container

# How to run a primary DC

## Create macvlan network first
Create macvlan network that computers in your network to be able to communicate with the primary DC container first.
For example, your container's host machine is located in the network `192.168.1.0/24`, you can create a macvlan network like below.

```
docker network create -d macvlan \
    --subnet=192.168.1.0/24 \
    --gateway=192.168.1.1 \
    -o parent=eth0 office_network
```

This command will create macvlan network named `office_network` on the interface `eth0` that belong to the network address `192.168.1.0/24`.
Containers that attaches this network will be able to communicate other hosts that located in the same network `192.168.1.0/24` by their mac address directly.
Containers do not need NAT interface like docker0.

## Run primary DC
Run a primary DC like below.

```
docker run --name pdc01 --hostname pdc01 \
    -e DC_TYPE="PARIMARY_DC" \
    -e DNS_FORWARDER=192.168.1.1 \
    --network office_network \
    --privileged \
    --ip 192.168.1.71 \
    --dns 192.168.1.71 \
    -d hobbylabs/samba-ad-container
```



