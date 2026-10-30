# Maintenance & Update Policy

Server: `hardening-server` (Ubuntu Server 24.04 LTS)

---

## 1. Patch Management

### Types of updates

- **Security patches** fix known vulnerabilities (Ubuntu's `noble-security` source). They are installed automatically and quickly.
- **Regular package updates** are bug fixes and new versions (`noble-updates`). They are tested first and installed on a schedule.
- **Major OS upgrades** move to a new Ubuntu release (for example 24.04 to 26.04). They are planned, backed up and tested on a copy first.

### How often updates are checked and installed

- **Development / test:** security patches daily (automatic), regular updates weekly
- **Staging:** security patches daily (automatic), regular updates weekly, before production
- **Production:** security patches daily (automatic), regular updates monthly, after staging looks fine

### Unattended security updates settings

- `/etc/apt/apt.conf.d/20auto-upgrades`
  - `APT::Periodic::Update-Package-Lists "1";` refreshes the package list daily
  - `APT::Periodic::Unattended-Upgrade "1";` installs allowed updates daily
- `/etc/apt/apt.conf.d/50unattended-upgrades` (default file): `Allowed-Origins` contains `noble`, `noble-security` and the ESM security sources, so only security updates install on their own
- `/etc/apt/apt.conf.d/52unattended-upgrades-local` (my file, read after the default one)
  - `Unattended-Upgrade::Remove-Unused-Dependencies "true";` removes packages that are no longer needed
  - `Unattended-Upgrade::Automatic-Reboot "false";` the server never reboots by itself, so I choose the time
- The updates run from the timers `apt-daily.timer` and `apt-daily-upgrade.timer`.

### Handling a critical security patch

1. Find out about it (Ubuntu security notice, or `apt list --upgradable`).
2. Run `sudo /usr/local/sbin/maintenance.sh` to make a fresh config backup.
3. Install it right away instead of waiting for the daily timer: `sudo apt update && sudo apt install --only-upgrade <package>`.
4. If `/var/run/reboot-required` exists, reboot at a safe time.
5. Check that services are running (`systemctl --failed`), SSH still works and the firewall is active. If something broke, follow the rollback steps in section 3.

---

## 2. Preventive Maintenance

### Daily

- The maintenance script runs automatically at 12:30 and saves a report.
- I read the report: updates, disk, memory, load and service status.

### Weekly

- Check SSH logins and Fail2Ban bans: `sudo journalctl -u ssh --since "7 days ago"` and `sudo grep -E 'Ban|Unban' /var/log/fail2ban.log`
- Check whether a reboot is waiting: `ls /var/run/reboot-required`
- Install regular updates on test and staging: `sudo apt update && sudo apt upgrade`

### Monthly

- Install regular updates on production
- Test restoring one config file from backup
- Review users, SSH keys (`cat ~/.ssh/authorized_keys`) and open ports (`sudo ss -tulpn`)

### Checks

- **Disk usage:** `df -h`
- **CPU:** `uptime` (load average) or `top`
- **Memory:** `free -h`
- **Service status:** `systemctl is-active ssh fail2ban ufw cron unattended-upgrades`
- **System logs:** `sudo journalctl -p err -b` (errors since the last boot)

### Detecting failed services

- `systemctl --failed` lists failed services. The daily report prints it, and `none` means everything is fine.
- `systemctl status <service>` shows the state and the last log lines.
- `journalctl -u <service> -n 50 --no-pager` shows the recent log.

### Detecting abnormal resource use

- **CPU:** the load average stays higher than the number of CPU cores. Run `top` to find the process.
- **Memory:** very little free memory or swap in use. Run `free -h` and `ps aux --sort=-%mem | head`.
- **Disk:** `/` above about 80 percent. Run `df -h`, then `sudo du -xh /var | sort -h | tail` to find what is big.

### Log retention and cleanup

- **systemd journal:** capped at 200 MB and 1 month (`/etc/systemd/journald.conf.d/retention.conf`)
- **System logs in `/var/log`:** rotated weekly, 4 copies kept (Ubuntu's default logrotate)
- **`/var/log/maintenance/cron.log`:** rotated weekly, 4 compressed copies (`/etc/logrotate.d/maintenance`)
- **Daily reports in `/var/log/maintenance/`:** deleted after 30 days (same logrotate file)
- **Automatic config backups:** deleted after 14 days (done by the script)

---

## 3. Backup & Recovery

### Backup strategy

- The maintenance script makes `auto-config-<date>.tar.gz` in `/var/backups/config/` every day and keeps 14 days.
- It contains `/etc/ssh`, `/etc/fail2ban/jail.local`, `/etc/ufw` and the two unattended-upgrades files.
- The folder is root-only (`700`) and the archives are `600`, because `/etc/ssh` contains the server's private host keys.

### Rollback if an update or change causes problems

1. Keep one working SSH session open before changing anything risky.
2. **Config change broke something:** restore that file from the latest backup (see below), test it (`sudo sshd -t`, `sudo fail2ban-client -t`, `sudo ufw status`), then reload the service.
3. **Update broke something:** check what changed with `grep ' upgrade ' /var/log/dpkg.log | tail`, install the old version with `sudo apt install <package>=<old-version>`, and hold it with `sudo apt-mark hold <package>`.

### Restoring a config file from backup

```bash
sudo tar xzf /var/backups/config/config-2026-10-29.tar.gz -C / etc/apt/apt.conf.d/52unattended-upgrades-local
```

On 2026-10-29 I overwrote `52unattended-upgrades-local` with the text `THIS FILE IS BROKEN`, restored it with this command, and the checksum of the restored file matched the copy inside the backup. The output is in `evidence/00-before-states.txt`, section 9.

---

## Responsibilities

- **Administrator (`devops`):** reads the reports, installs regular updates, tests restores, handles critical patches.
- **Automation:** daily security updates, the daily maintenance script, log rotation and cleanup.
- **Second person, if there is a team:** approves major OS upgrades and changes to SSH or firewall rules.
