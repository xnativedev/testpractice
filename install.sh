#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
BLYNK_USER="blynk"
INSTALL_DIR="/opt/blynk"
DATA_DIR="/var/lib/blynk"
HTTP_PORT="8080"
HTTPS_PORT="9443"

export DEBIAN_FRONTEND=noninteractive

# =========================
# PRE-FLIGHT
# =========================
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Please run as root (sudo)."
  exit 1
fi

echo "== Set Timezone =="
timedatectl set-timezone Asia/Bangkok || true

# =========================
# SYSTEM UPDATE
# =========================
echo "== System update & upgrade =="
apt update -y
apt upgrade -y

# =========================
# INSTALL DEPS
# =========================
echo "== Install dependencies =="
apt install -y curl jq openjdk-11-jre-headless ufw

# =========================
# USER & DIRS
# =========================
echo "== Create blynk user =="
id "$BLYNK_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin "$BLYNK_USER"

echo "== Create directories =="
mkdir -p "$INSTALL_DIR" "$DATA_DIR"

# สำคัญมาก: Blynk แตก static ลง WorkingDirectory
chown -R "$BLYNK_USER:$BLYNK_USER" "$INSTALL_DIR"
chown -R "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR"

# =========================
# DOWNLOAD BLYNK SERVER
# =========================
echo "== Download Blynk Server JAR =="
JSON="$(curl -s https://api.github.com/repos/Peterkn2001/blynk-server/releases/latest)"
JAR_URL="$(echo "$JSON" | jq -r '.assets[] | select(.name|endswith(".jar")) | .browser_download_url' | head -n1)"

if [ -z "$JAR_URL" ] || [ "$JAR_URL" = "null" ]; then
  echo "ERROR: Cannot find server.jar in GitHub release."
  exit 1
fi

curl -L "$JAR_URL" -o "$INSTALL_DIR/server.jar"
chmod 644 "$INSTALL_DIR/server.jar"
chown "$BLYNK_USER:$BLYNK_USER" "$INSTALL_DIR/server.jar"

# =========================
# SERVER CONFIG
# =========================
echo "== Write server.properties =="
cat > "$DATA_DIR/server.properties" <<EOF
# -------- Blynk Server Ports --------
http.port=$HTTP_PORT
https.port=$HTTPS_PORT

# -------- Optional (default OK) -----
# http.address=0.0.0.0
# https.address=0.0.0.0

# -------- Admin Security --------
# comma separated list of administrator IPs
# 0.0.0.0/0 = allow all IPv4
# ::/0      = allow all IPv6
allowed.administrator.ips=0.0.0.0/0,::/0

# -------- Default Admin (first start only) --------
admin.email=admin@blynk.cc
admin.pass=admin
EOF

chmod 644 "$DATA_DIR/server.properties"
chown "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR/server.properties"

# =========================
# FIREWALL
# =========================
echo "== Configure firewall (UFW) =="
ufw allow ssh || true
ufw allow "$HTTP_PORT"/tcp
ufw allow "$HTTPS_PORT"/tcp
ufw --force enable
ufw reload || true

# =========================
# SYSTEMD SERVICE
# =========================
echo "== Create systemd service =="
cat > /etc/systemd/system/blynk.service <<EOF
[Unit]
Description=Blynk Local Server (HTTP + HTTPS)
After=network.target

[Service]
User=$BLYNK_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/java -jar $INSTALL_DIR/server.jar \\
  -dataFolder $DATA_DIR \\
  -serverConfig $DATA_DIR/server.properties
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now blynk

# =========================
# STATUS
# =========================
echo "== Service Status =="
systemctl status blynk --no-pager || true

echo "== Listening Ports =="
ss -tulnp | grep -E "(:$HTTP_PORT|:$HTTPS_PORT)" || true

# =========================
# DONE
# =========================
echo "======================================"
echo "Blynk Server is READY"
echo "--------------------------------------"
echo "Blynk App (HTTP):  $HTTP_PORT  (SSL OFF)"
echo "Admin Web (HTTPS): $HTTPS_PORT (SSL ON)"
echo ""
echo "Admin URL:"
echo "https://<SERVER_IP>:$HTTPS_PORT/admin"
echo ""
echo "Blynk App Settings:"
echo "Server = <SERVER_IP>"
echo "Port   = $HTTP_PORT"
echo "SSL    = OFF"
echo "Mode   = CUSTOM"
echo "======================================"

