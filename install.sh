#!/usr/bin/env bash
set -euo pipefail

BLYNK_USER="blynk"
INSTALL_DIR="/opt/blynk"
DATA_DIR="/var/lib/blynk"
PORT="8080"

export DEBIAN_FRONTEND=noninteractive

echo "== Pre-flight check =="
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Please run as root (use sudo)."
  exit 1
fi

echo "== Set Timezone =="
timedatectl set-timezone Asia/Bangkok || true

echo "== System update & upgrade =="
apt update -y
apt upgrade -y

echo "== Install deps =="
apt install -y curl jq openjdk-11-jre-headless ufw

echo "== Create user =="
id "$BLYNK_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin "$BLYNK_USER"

echo "== Create dirs & permissions =="
mkdir -p "$INSTALL_DIR" "$DATA_DIR"
chown -R "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR"
# IMPORTANT: Blynk unpacks static files under WorkingDirectory (/opt/blynk/static)
chown -R "$BLYNK_USER:$BLYNK_USER" "$INSTALL_DIR"

echo "== Download Blynk server =="
JSON="$(curl -s https://api.github.com/repos/Peterkn2001/blynk-server/releases/latest)"
JAR_URL="$(echo "$JSON" | jq -r '.assets[] | select(.name|endswith(".jar")) | .browser_download_url' | head -n1)"

if [ -z "$JAR_URL" ] || [ "$JAR_URL" = "null" ]; then
  echo "ERROR: Cannot find .jar in latest release assets."
  exit 1
fi

curl -L "$JAR_URL" -o "$INSTALL_DIR/server.jar"
chmod 644 "$INSTALL_DIR/server.jar"
chown "$BLYNK_USER:$BLYNK_USER" "$INSTALL_DIR/server.jar"

echo "== Write server.properties (HTTP only) =="
cat > "$DATA_DIR/server.properties" <<EOF
http.port=$PORT
# NOTE: HTTPS disabled on purpose (no https.port here)
EOF
chmod 644 "$DATA_DIR/server.properties"
chown "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR/server.properties"

echo "== Configure firewall (UFW) =="
ufw allow ssh || true
ufw allow "$PORT"/tcp
ufw --force enable
ufw reload || true

echo "== Create systemd service =="
cat > /etc/systemd/system/blynk.service <<EOF
[Unit]
Description=Blynk Local Server (HTTP)
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

echo "== Status =="
systemctl status blynk --no-pager || true

echo "== Listening ports =="
ss -tulnp | grep -E "(:$PORT\\b)" || true

echo "== DONE =="
echo "HTTP:  http://<SERVER_IP>:$PORT"
echo "Tip: In Blynk App set CUSTOM server IP and Port=$PORT, and DISABLE SSL/HTTPS."
