#!/usr/bin/env bash
# maintenance.sh - updates, disk/memory, service status, config backup
set -u

REPORT_DIR=/var/log/maintenance
BACKUP_DIR=/var/backups/config
DATE=$(date +%F)
REPORT="$REPORT_DIR/report-$DATE.log"
SERVICES="ssh fail2ban ufw cron unattended-upgrades"
BACKUP_PATHS="etc/ssh etc/fail2ban/jail.local etc/ufw etc/apt/apt.conf.d/20auto-upgrades etc/apt/apt.conf.d/52unattended-upgrades-local"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

mkdir -p "$REPORT_DIR" "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

{
  echo "=== Maintenance report: $(date) on $(hostname) ==="

  echo
  echo "--- 1. Available updates ---"
  apt-get -s upgrade | grep -E '^[0-9]+ upgraded'
  [ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED" || echo "No reboot required"

  echo
  echo "--- 2. Disk and memory ---"
  df -h /
  free -h
  uptime

  echo
  echo "--- 3. Critical services ---"
  for svc in $SERVICES; do
    echo "$svc: $(systemctl is-active "$svc")"
  done
  echo "Failed units:"
  systemctl --failed --no-legend --no-pager | grep . || echo "  none"

  echo
  echo "--- 4. Config backup ---"
  BACKUP="$BACKUP_DIR/auto-config-$DATE.tar.gz"
  tar -C / -czf "$BACKUP" $BACKUP_PATHS && chmod 600 "$BACKUP" && echo "Created $BACKUP" || echo "BACKUP FAILED"
  find "$BACKUP_DIR" -name 'auto-config-*.tar.gz' -mtime +14 -delete
  ls -lh "$BACKUP_DIR"

  echo
  echo "=== End of report ==="
} 2>&1 | tee "$REPORT"
