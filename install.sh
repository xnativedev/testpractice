#!/usr/bin/env bash
set -e

BLYNK_USER="blynk"
INSTALL_DIR="/opt/blynk"
DATA_DIR="/var/lib/blynk"
PORT="8080"

export DEBIAN_FRONTEND=noninteractive

echo "== Set Timezone =="
timedatectl set-timezone Asia/Bangkok

echo "== System update & upgrade =="
apt update -y
apt upgrade -y

echo "== Install deps =="
apt install -y curl jq openjdk-11-jre-headless ufw

echo "== Create user =="
id "$BLYNK_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin "$BLYNK_USER"

mkdir -p "$INSTALL_DIR" "$DATA_DIR"
chown -R "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR"

echo "== Download Blynk server =="
JSON=$(curl -s https://api.github.com/repos/Peterkn2001/blynk-server/releases/latest)
JAR_URL=$(echo "$JSON" | jq -r '.assets[] | select(.name|endswith(".jar")) | .browser_download_url' | head -n1)

if [ -z "$JAR_URL" ] || [ "$JAR_URL" = "null" ]; then
  echo "ERROR: Cannot find .jar in latest release assets."
  exit 1
fi

curl -L "$JAR_URL" -o "$INSTALL_DIR/server.jar"
chmod 644 "$INSTALL_DIR/server.jar"

echo "== Create server.properties =="
cat > "$DATA_DIR/server.properties" <<EOF
http.port=$PORT
# ถ้าต้องการให้ฟังทุก interface (ส่วนใหญ่ default ก็เป็นอยู่แล้ว)
# http.address=0.0.0.0
EOF
chown "$BLYNK_USER:$BLYNK_USER" "$DATA_DIR/server.properties"
chmod 644 "$DATA_DIR/server.properties"

echo "== Configure firewall (UFW) =="
ufw allow ssh
ufw allow $PORT/tcp
ufw --force enable

echo "== Create systemd service =="
cat > /etc/systemd/system/blynk.service <<EOF
[Unit]
Description=Blynk Local Server
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
systemctl status blynk --no-pager

echo "== DONE =="
echo "Open:  http://<SERVER_IP>:$PORT"
echo "Admin: http://<SERVER_IP>:$PORT/admin"
