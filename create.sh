#!/bin/bash

# SETTINGS
CTID=120
HOSTNAME=osic-tools
STORAGE=local-lvm
TEMPLATE=ubuntu-22.04-standard_22.04-1_amd64.tar.zst
DISK=80
RAM=8192
CORES=4
BRIDGE=vmbr0

echo "Creating LXC container..."

pct create $CTID /var/lib/vz/template/cache/$TEMPLATE \
  --hostname $HOSTNAME \
  --cores $CORES \
  --memory $RAM \
  --swap 1024 \
  --rootfs $STORAGE:$DISK \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --onboot 1

echo "Starting container..."
pct start $CTID

sleep 10

echo "Installing Docker..."

pct exec $CTID -- bash -c "
apt update
apt install -y docker.io docker-compose git
systemctl enable docker
systemctl start docker
"

echo "Pulling IIC-OSIC-TOOLS container..."

pct exec $CTID -- docker pull hpretl/iic-osic-tools:latest

echo "Creating design directory..."

pct exec $CTID -- mkdir -p /root/osic/designs

echo "Starting OSIC container..."

pct exec $CTID -- docker run -d \
  --name osic \
  --restart unless-stopped \
  -p 80:80 \
  -p 5901:5901 \
  -p 8888:8888 \
  -v /root/osic/designs:/foss/designs \
  hpretl/iic-osic-tools:latest

echo "Done!"
echo ""
echo "Access the interface:"
echo "http://<container-ip>"
echo ""
echo "Get container IP with:"
echo "pct exec $CTID ip a"
