#!/usr/bin/env bash
# avahi-daemon 이 죽으면 다시 띄우고, 메모리가 바닥날 때 OOM killer 가 먼저 죽이지 않게 한다.
# <호스트>.local 이름은 avahi 가 알린다 — OOM 으로 죽은 뒤 재시작 설정이 없어 12일 동안 이름이 안 풀린 적이 있다.
#   sudo bash setup/avahi-restart.sh      (setup/ubuntu.sh 가 부른다, 다시 돌려도 안전)
set -euo pipefail
systemctl list-unit-files avahi-daemon.service >/dev/null 2>&1 || { echo "avahi-daemon 없음 — 건너뜀"; exit 0; }
mkdir -p /etc/systemd/system/avahi-daemon.service.d
printf '[Service]\nRestart=always\nRestartSec=5\nOOMScoreAdjust=-500\n' > /etc/systemd/system/avahi-daemon.service.d/restart.conf
systemctl daemon-reload
systemctl restart avahi-daemon
echo "avahi-daemon: Restart=always, OOMScoreAdjust=-500"
