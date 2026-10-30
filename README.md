# Linux Server Hardening & Maintenance

Practical assessment: set up, secure and maintain an Ubuntu Server 24.04 LTS virtual machine.

## Environment

- OS: Ubuntu Server 24.04.5 LTS, running as a local VM in GNOME Boxes on Pop!_OS
- Hostname: `hardening-server`
- Timezone: `Asia/Kolkata` (IST)
- Admin user: `devops` (has sudo, logs in with an SSH key only)
- Network: default QEMU NAT, IP `10.0.2.15` on `enp1s0` (DHCP)
- I connect from my own computer with `ssh -p 2222 devops@127.0.0.1` (a port forward, see issue 1)

No paid cloud services were used.

## What is in this repository

```
README.md                this file
MAINTENANCE_POLICY.md    update, maintenance, backup and rollback policy
scripts/maintenance.sh   the Bash maintenance script
configs/                 config files I created or changed on the server
evidence/                command outputs that prove each task
```

Files in `evidence/`:

- `00-before-states.txt`: outputs from during the build (before and after, and one-time events)
- `01-final-state.txt`: final settings and status of the server
- `02-sample-report.log`: report from the scheduled run
- `03-host-ssh-tests.txt`: key login works, password login refused
- `04-vm-backup.txt`: check of the VM disk backup

## How to review

1. Read `MAINTENANCE_POLICY.md`.
2. Check `evidence/` for the proof of each task.
3. Read `scripts/maintenance.sh`.

## Maintenance script

`scripts/maintenance.sh` is installed on the server at `/usr/local/sbin/maintenance.sh`. It does four things and saves a report to `/var/log/maintenance/report-<date>.log`:

1. Checks for available updates and whether a reboot is needed
2. Shows disk and memory usage
3. Checks that ssh, fail2ban, ufw, cron and unattended-upgrades are running
4. Backs up the important config files to `/var/backups/config/`

**Run it:**

```bash
sudo cp scripts/maintenance.sh /usr/local/sbin/maintenance.sh
sudo chmod 750 /usr/local/sbin/maintenance.sh
sudo /usr/local/sbin/maintenance.sh
```

**Schedule it:** cron runs it every day at 12:30 (`configs/cron-maintenance`).

```bash
sudo cp configs/cron-maintenance /etc/cron.d/maintenance
```

**Check it ran:**

```bash
sudo journalctl -u cron --since "2 days ago" --no-pager | grep maintenance.sh
sudo ls -l /var/log/maintenance/
```

You should see a `CMD (/usr/local/sbin/maintenance.sh ...)` line at 12:30 and a new report file for that day. This happened on 2026-10-30 at 12:30:01 (see `evidence/00-before-states.txt`).

## Service and port audit

I listed open ports with `sudo ss -tulpn` and running services with `systemctl list-units --type=service --state=running`.

- **Kept:** SSH (port 22), the local DNS resolver (port 53, only reachable inside the VM) and the DHCP client (port 68).
- **Disabled or removed:**
  - `avahi-daemon`: network auto-discovery, listening on all interfaces, not needed on a server
  - `ModemManager`: the VM has no modem
  - `spice-webdavd`: a leftover from a shared-folder attempt that opened port 9843
- **Looked at but left alone:** `snapd`, `multipathd`, `open-iscsi`, `open-vm-tools`, `fwupd`, `udisks2`, `upower`, `thermald`. None of them listen on the network, and some touch storage or boot, so I did not risk breaking the VM.

After this, only SSH, local DNS and the DHCP client are listening. The full outputs are in `evidence/00-before-states.txt`.

## Issues I ran into and how I fixed them

1. **I could not SSH into the VM from my computer.** `ssh`, `nc` and `ssh-copy-id` all timed out. I checked the VM's network with `virsh` and saw it uses QEMU "user" mode, a private NAT my computer can't reach. **Fix:** a port forward, `hostfwd_add tcp:127.0.0.1:2222-:22`, sent to the running VM with `virsh qemu-monitor-command`. **Limitation:** the forward disappears when the VM is fully powered off, so I add it again each time.
2. **The shared folder for copying my public key did not work.** I installed `spice-webdavd` and rebooted, but `/mnt` stayed empty. **Fix:** I dropped that idea and used `ssh-copy-id` through the port forward. I removed the package later.
3. **The VM snapshot failed.** The Boxes button gave no reason, so I ran `virsh snapshot-create-as`, which said internal snapshots are not supported for a VM with UEFI (pflash) firmware. **Fix:** I shut the VM down, copied the disk image, and checked the copy with `qemu-img check` (no errors).
4. **Password login stayed on even after I planned to turn it off.** `sshd -T` showed `passwordauthentication yes`, and `/etc/ssh/sshd_config.d/50-cloud-init.conf` contained `PasswordAuthentication yes`. SSH uses the first value it finds and reads those files in alphabetical order. **Fix:** I created `01-hardening.conf` and `02-hardening.conf`, which are read first. A forced password attempt now gives `Permission denied (publickey)`.
5. **Fail2Ban counted no failed logins.** With password login off, failed attempts show up in the log as "Connection closed ... [preauth]", which the default filter ignores. `fail2ban-regex` matched 0 lines with the default filter and 4 with `mode = aggressive`. **Fix:** I added `mode = aggressive` to `jail.local`.
6. **My own Fail2Ban test locked me out.** Every connection from my computer looks like `10.0.2.2` (the QEMU gateway) inside the VM, so one ban blocked all my logins, and Boxes froze. **Fix:** I waited 5 minutes. The log shows `Ban 10.0.2.2` and then `Unban 10.0.2.2`.
7. **After a restart SSH timed out again.** The VM was running but the port forward was gone (`info usernet` showed it empty). **Fix:** I added the forward again. All the hardening settings were still in place.
8. **My first config backup could be read by any user and contains the server's private SSH host keys.** **Fix:** folder set to `700`, archive set to `600`, and backups are not in this repo.
9. **The VM clock was in UTC.** **Fix:** `sudo timedatectl set-timezone Asia/Kolkata`, then I set the cron time in IST.

## Notes

- No private keys, passwords or backup archives are in this repository.
- Only the server's own config files I wrote are included. I left out `50-cloud-init.conf` and `/etc/ssh` host keys.
