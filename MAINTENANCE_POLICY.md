# Maintenance & Update Policy

Server: `hardening-server` (Ubuntu Server 24.04 LTS).

Things already set up on my VM are marked **[done]**. Everything else is the plan I would follow on real servers.

---

## 1. Patch management

### The three kinds of updates

- **Security patches** fix known vulnerabilities. They come from Ubuntu's `noble-security` source. They should be installed quickly and automatically. **[done]**
- **Regular package updates** are bug fixes and new versions from `noble-updates`. They are not urgent, so I test them first and install them on a schedule.
- **Major OS upgrades** move to a new Ubuntu release (for example 24.04 to 26.04). This is a big change, so it needs a plan, a backup and a test on a copy first. The server says 26.04.1 is available. I did not upgrade.

### How often updates are checked and installed

| Environment | Security patches | Regular updates |
|---|---|---|
| Development / test | Automatically, every day | Weekly |
| Staging | Automatically, every day | Weekly, before production |
| Production | Automatically, every day | Monthly, after staging looks fine |

My lab VM is a single machine, so only the daily security updates are actually configured.

### Unattended security updates **[done]**

- `/etc/apt/apt.conf.d/20auto-upgrades`
  - `APT::Periodic::Update-Package-Lists "1";` refreshes the package list daily
  - `APT::Periodic::Unattended-Upgrade "1";` installs allowed updates daily
- `/etc/apt/apt.conf.d/50unattended-upgrades` (default file): `Allowed-Origins` lists `noble`, `noble-security` and the ESM security sources, so only security updates install on their own
- `/etc/apt/apt.conf.d/52unattended-upgrades-local` (my file, read after the default one):
  - `Unattended-Upgrade::Remove-Unused-Dependencies "true";` cleans up packages no longer needed
  - `Unattended-Upgrade::Automatic-Reboot "false";` the server never reboots by itself, so I choose the time
- The updates run from the timers `apt-daily.timer` and `apt-daily-upgrade.timer`
- Test with `sudo unattended-upgrade --dry-run --debug`

### Handling a critical security patch

1. Find out about it (Ubuntu security notice, or `apt list --upgradable`).
2. Check whether the affected package is installed and exposed to the network.
3. Take a backup first: run `sudo /usr/local/sbin/maintenance.sh` and copy the VM disk if the change is big.
4. Install it right away instead of waiting for the daily timer: `sudo apt update && sudo apt install --only-upgrade <package>`.
5. If `/var/run/reboot-required` exists, reboot at a safe time with the console open.
6. Check that services are running (`systemctl --failed`), SSH still works and the firewall is active.
7. If something broke, follow the rollback steps in section 3.

---

## 2. Preventive maintenance

### Daily

- The maintenance script runs by itself at 12:30 and saves a report. **[done]**
- Security updates install by themselves. **[done]**
- I read the latest report: `tail -n 40 /var/log/maintenance/report-$(date +%F).log`

### Weekly

- Look at SSH logins and Fail2Ban bans: `sudo journalctl -u ssh --since "7 days ago"` and `sudo grep -E 'Ban|Unban' /var/log/fail2ban.log`
- Check whether a reboot is waiting: `ls /var/run/reboot-required`
- Install regular updates on test/staging: `sudo apt update && sudo apt upgrade`

### Monthly

- Install regular updates on production and reboot if needed
- Test restoring one config file from backup
- Review users and SSH keys (`cat ~/.ssh/authorized_keys`), open ports (`sudo ss -tulpn`) and enabled services
- Check disk space and log sizes

### What to check and how

| Check | Command |
|---|---|
| Disk usage | `df -h` |
| CPU | `uptime` (load average) or `top` |
| Memory | `free -h` |
| Service status | `systemctl is-active ssh fail2ban ufw cron unattended-upgrades` |
| System logs | `sudo journalctl -p err -b` (errors since last boot) |

The maintenance script already does the disk, memory, load and service checks every day.

### Detecting failed services

- `systemctl --failed` lists failed services. The daily report prints this, and `none` is the healthy answer.
- `systemctl status <service>` shows the state and the last log lines.
- `journalctl -u <service> -n 50 --no-pager` shows the recent log.
- A service showing `inactive` or `failed` in the report gets fixed the same day.

### Detecting abnormal resource use

- **CPU:** load average higher than the number of CPU cores for a long time. Run `top` to find the process.
- **Memory:** very little free memory or swap being used. Run `free -h` and `ps aux --sort=-%mem | head`.
- **Disk:** `/` above about 80 percent. Run `df -h`, then `sudo du -xh /var | sort -h | tail` to find what is big.
- **Attacks:** many bans in `sudo fail2ban-client status sshd`.

Normal on my VM: disk 28 percent used, about 475 MiB of 2.8 GiB memory used, load average 0.00.

### Log retention and cleanup **[done]**

- **systemd journal:** capped at 200 MB and 1 month (`/etc/systemd/journald.conf.d/retention.conf`)
- **System logs in `/var/log`:** rotated weekly, 4 copies kept (Ubuntu's default logrotate)
- **`/var/log/maintenance/cron.log`:** rotated weekly, 4 compressed copies (`/etc/logrotate.d/maintenance`)
- **Daily reports in `/var/log/maintenance/`:** deleted after 30 days (same logrotate file)
- **Automatic config backups:** deleted after 14 days (done by the script)

---

## 3. Backup and recovery

### What I back up

- **Config files:** the script makes `auto-config-<date>.tar.gz` in `/var/backups/config/` every day and keeps 14 days. **[done]** It contains `/etc/ssh`, `/etc/fail2ban/jail.local`, `/etc/ufw` and the two unattended-upgrades files.
- **The whole VM disk:** I copied the disk image before the big changes. **[done]** A normal snapshot did not work (see README issue 3).
- **Plan:** copy the config backup off the VM every week.

The backup folder is root-only (`700`) and the archives are `600`, because `/etc/ssh` contains the server's private host keys.

### Rollback if an update or change breaks something

1. Keep one working SSH session open before changing anything risky.
2. **Config change broke something:** restore that one file from the latest backup (below), test it (`sudo sshd -t`, `sudo fail2ban-client -t`, `sudo ufw status`), then reload the service.
3. **Update broke something:** see what changed with `grep ' upgrade ' /var/log/dpkg.log | tail`, install the old version with `sudo apt install <package>=<old-version>`, and hold it with `sudo apt-mark hold <package>`.
4. **Everything is broken:** shut the VM down, copy the disk backup back over the VM image, start the VM, and add the port forward again.

### Restore demo **[done]**

Restore one file from the backup:

```bash
sudo tar xzf /var/backups/config/config-2026-10-29.tar.gz -C / etc/apt/apt.conf.d/52unattended-upgrades-local
```

What I did on 2026-10-29: I overwrote `52unattended-upgrades-local` with the text `THIS FILE IS BROKEN` (checksum `b26b8779...`), restored it with the command above, and the checksum of the restored file (`89eba8f7...`) matched the copy inside the archive. The output is in `evidence/00-before-states.txt`, section 9.

---

## Responsibilities

- **Administrator (`devops`):** reads the reports, installs regular updates, tests restores, handles critical patches.
- **Automation:** daily security updates, the daily maintenance script, log rotation and cleanup.
- **Second person, if there is a team:** approves major OS upgrades and changes to SSH or firewall rules.
