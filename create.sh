#!/usr/bin/env bash
set -e

# SETTINGS
CTID=120
HOSTNAME=osic-tools
STORAGE=local-lvm
TEMPLATE=ubuntu-22.04-standard_22.04-1_amd64.tar.zst
TEMPLATE_CACHE="/var/lib/vz/template/cache"
DISK=80
RAM=8192
CORES=4
BRIDGE=vmbr0

# --- Ensure we're on a Proxmox host ---
if ! command -v pct &>/dev/null; then
  echo "Error: pct not found. Run this script on a Proxmox host." >&2
  exit 1
fi

# --- Don't create if container already exists ---
if pct status "$CTID" &>/dev/null; then
  echo "Error: Container $CTID already exists. Choose another CTID or destroy it first (pct destroy $CTID)." >&2
  exit 1
fi

# --- Download Ubuntu template if missing ---
TEMPLATE_PATH="$TEMPLATE_CACHE/$TEMPLATE"
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "Ubuntu template not found at $TEMPLATE_PATH. Downloading..."
  pveam update
  pveam download local "$TEMPLATE"
fi
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "Error: Template still missing at $TEMPLATE_PATH. Check 'pveam available' and storage." >&2
  exit 1
fi

echo "Creating LXC container..."

pct create $CTID "$TEMPLATE_PATH" \
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
CONTAINER_IP=$(pct exec $CTID -- ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
if [ -n "$CONTAINER_IP" ]; then
  echo "Access the interface:"
  echo "  http://$CONTAINER_IP"
  echo "  (password: abc123)"
else
  echo "Access the interface:"
  echo "  http://<container-ip>"
  echo "Get container IP with: pct exec $CTID ip a"
fi
echo ""
