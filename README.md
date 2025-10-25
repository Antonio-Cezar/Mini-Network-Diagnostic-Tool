# Mini Network Diagnostic Tool

A simple yet robust Bash script that automatically runs **ping**, **traceroute** (or `tracepath`), and **nslookup** (or `dig`) to check network connectivity.  
All results are logged to a file, and the terminal displays clear status feedback for each test.

---

## Features

- Automatically runs ping, traceroute, and DNS lookups  
- Logs results to `~/.local/var/netdiag/`  
- Displays status in the terminal (OK / FAIL / WARNING)  
- Uses color-coded and well-formatted output  
- Includes per-step timeout handling  
- Falls back to `tracepath` and `dig` if `traceroute` or `nslookup` are unavailable  
- Returns exit code `0` (OK) or `1` (Error) – suitable for automation, cron jobs, or CI/CD  

---

## Requirements

Runs out of the box on **Ubuntu**, **WSL (Windows Subsystem for Linux)**, and other **Debian-based systems**.

Install dependencies if missing:

```bash
sudo apt update
sudo apt install -y traceroute dnsutils iputils-ping coreutils
```

## Examples
![outpuy](/images/1.jpg)