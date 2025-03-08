# Disk Monitor Script

This script is designed to monitor disk and RAM usage on Debian-based servers and send email notifications if predefined thresholds are exceeded.

📌 **[Türkçe İçin Tıklayın](README-tr.md)**

## 🚀 Installation

Run the following command to download and start the installation:

```bash
curl -fsSL https://raw.githubusercontent.com/KaraKunT/DiskMonitor/main/disk-monitor.sh -o /usr/local/bin/disk-monitor.sh && chmod +x /usr/local/bin/disk-monitor.sh && /usr/local/bin/disk-monitor.sh --init
```

or

```bash
wget -qO /usr/local/bin/disk-monitor.sh https://raw.githubusercontent.com/KaraKunT/DiskMonitor/main/disk-monitor.sh && chmod +x /usr/local/bin/disk-monitor.sh && /usr/local/bin/disk-monitor.sh --init
```

## 📌 Features

- 📊 Monitors disk usage and alerts when thresholds are exceeded.
- 💾 Checks RAM usage and notifies if free space is below the threshold.
- 📧 Email notifications via SMTP.
- 🛠 Interactive setup wizard for easy configuration.
- 🔄 Automatically adds a crontab entry for periodic checks.

## 📖 Usage

Run the script using:

```bash
/usr/local/bin/disk-monitor.sh
```

When first run, an interactive setup wizard will guide you through disk selection, RAM threshold, and email notification settings.

### 🛠 Updating Configuration

To reconfigure the settings, run:

```bash
/usr/local/bin/disk-monitor.sh --init
```

This will update your existing configuration without deleting previous settings.

## 📜 Configuration File

The script stores its settings in `/etc/disk-monitor.conf`. You can manually edit this file:

```bash
# Disk Monitoring Configuration
/dev/sda1 10
/dev/sdb2 15

# RAM Threshold%
RAM 25

# Email Settings
EMAIL_TO=example@example.com
EMAIL_FROM=noreply@example.com
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
SMTP_USER=username
SMTP_PASS=password
```

## 📅 Crontab for Automatic Execution

The script is automatically added to `crontab` during installation and runs every 5 minutes by default. To modify the interval:

```bash
crontab -e
```

Edit the line to change the frequency:

```bash
*/5 * * * * /usr/local/bin/disk-monitor.sh
```

For a 10-minute interval:

```bash
*/10 * * * * /usr/local/bin/disk-monitor.sh
```

## 📩 Email Notifications

If a monitored disk or RAM usage exceeds the set threshold, an alert email will be sent to the specified address.

### 🔎 Viewing Logs

The script logs its activity in `/var/log/disk-monitor.log`. To view logs:

```bash
tail -f /var/log/disk-monitor.log
```

## 🛠 Dependencies

The script requires `curl`. If not installed, you can install it using:

```bash
apt update && apt install -y curl
```

## 📌 Supported Operating Systems

- Debian 10+ (Buster, Bullseye, Bookworm)
- Ubuntu 20.04+

## 🤝 Contributing

Contributions are welcome! Feel free to submit pull requests

---

📌 **GitHub:** [KaraKunT/DiskMonitor](https://github.com/KaraKunT/DiskMonitor)
