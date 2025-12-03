# 🔧 Troubleshooting & Diagnostics Playbook

This document records the specific commands and logic used to diagnose complex issues in this stack. I try to document when things doesn't work as I intended them to and to identify *why* before trying to fix it.

-----

## 1. High CPU / Resource Usage

### **Symptom**
System fans spin up, load average spikes, or UI becomes unresponsive.

### **Investigation Command**
Use `docker stats` to instantly identify the offending container. The `--no-stream` flag gives a clean snapshot instead of a jumping live feed.

```bash
docker stats --no-stream
````

### **Case Study A: The "Log Flood" (CrowdSec)**

  * **Observation:** CrowdSec using 400% CPU. Logs show rapid processing of internal IP addresses.
  * **Diagnosis:** Caddy was logging internal health checks (from Homepage), flooding the parser.
  * **The Fix:** Configure Caddy to **skip logging** for internal IPs.
      * *Code:* `log_skip @internal` in `Caddyfile`.

### **Case Study B: The "Engine Bottleneck" (CrowdSec)**

  * **Observation:** Logs are quiet (no flood), but CrowdSec CPU is still high (\~500%).
  * **Diagnosis:** Default CrowdSec config is single-threaded. On my CPU (Ryzen 7600X), this creates a queue backlog.
  * **The Fix:**
    1.  **Parallelization:** Edit `crowdsec/config/config.yaml` to increase `parser_routines` to `6` (matching CPU cores).
    2.  **Polling Frequency:** Edit `Caddyfile` to increase `ticker_interval` to `60s` (reduces how often Caddy asks the Agent for updates).

-----

## 2\. Connection Refused / Service Down

### **Symptom**

A service (like Portainer or WUD) cannot connect to another service (like Socket Proxy), showing `ECONNREFUSED` or `ENOTFOUND`.

### **Investigation Command**

Investigate if the target is actually listening on the expected port from *inside* the network.

```bash
# 1. Check if the target is running
docker ps | grep socket-proxy

# 2. Check container logs for startup errors
docker logs socket-proxy

# 3. Verify Internal DNS resolution (from another container)
docker exec -it wud ping socket-proxy
```

### **Case Study: WUD & Portainer vs. Socket Proxy**

  * **Observation:** WUD logs showed `getaddrinfo ENOTFOUND socket-proxy`.
  * **Diagnosis:** Docker's internal DNS sometimes fails to resolve container names immediately on boot.
  * **The Fix:** Switch from **Hostname** (`socket-proxy`) to **Static IP** (`172.20.0.28`).
      * *Config:* `WUD_WATCHER_LOCAL_HOST=172.20.0.28`

-----

## 3\. Storage / Disk Missing in Dashboard

### **Symptom**

Homepage reports `Drive not found for target: /mnt/dockerapps_disk`.

### **Investigation Command**

Verify what the container *actually* sees mounted.

```bash
docker exec homepage df -h
```

### **Case Study: The "Ghost" Mount**

  * **Observation:** `df -h` inside the container did NOT show the mount, even though `compose` had it.
  * **Diagnosis:** **Startup Race Condition.** Docker started *before* the OS finished mounting the LVM drive.
  * **The Fix:** Point the widget to `/app/config` (internal path) instead of an external `/mnt` path.

-----

## 4\. External Access Fails (Mobile Only)

### **Symptom**

Jellyfin works on LAN (Wi-Fi) and Desktop Browser (4G), but **fails on Android App (4G)**.

### **Investigation Tool**

**SSL Labs Server Test** (ssllabs.com).

### **Case Study: The IPv6 Trap**

  * **Observation:** SSL Labs showed IPv6 test failing.
  * **Diagnosis:** 4G Mobile networks prioritize **IPv6**. Cloudflare was publishing an AAAA record, but our host wasn't routing IPv6 ingress correctly.
  * **The Fix:** **Deleted AAAA records** in Cloudflare to force IPv4.

-----

## 5\. Security Verification (Lateral Movement)

### **Symptom**

Need to verify that a compromised container cannot "talk" to the Home LAN.

### **Investigation Command**

The "Hack Test." Try to ping our router from *inside* a container.

```bash
docker exec -it jellyfin ping 192.168.0.1
```

### **Case Study: The Software VLAN**

  * **Observation:** Ping succeeded (`time=0.4ms`).
  * **The Fix:** Applied a **Firewalld Direct Rule** to `DOCKER-USER` chain to DROP packets from `172.20.0.0/24` to `192.168.0.0/24`.
  * Refer: [docs](/docs/security-firewall.md)

-----

## 6\. Homepage Issues

### **Issue 1: "API Error" on Storage Widgets**

  * **Fix:** Ensure volume is mounted (`- /mnt/pool01/media:/mnt/media_disk:ro`).

### **Issue 2: "Host validation failed"**

  * **Fix:** Set `HOMEPAGE_ALLOWED_HOSTS=*` in `compose`.

### **Issue 3: CrowdSec Widget Error**

  * **Fix:** If DB was wiped, update `.env` with new credentials from `crowdsec/config/local_api_credentials.yaml`.

-----

## 7\. WUD (What's Up Docker) Issues

### **Issue 1: Duplicate Containers / "Ghosts"**

  * **Symptom:** WUD shows 2 entries for every container (one "Local", one "Proxy").
  * **Cause:** Defining `WUD_WATCHER_PROXY_...` creates a second watcher, while the default `local` watcher still tries to run.
  * **Fix:** "Hijack" the local watcher by setting `WUD_WATCHER_LOCAL_HOST=172.20.0.28` and removing all Proxy variables.

### **Issue 2: Updates not showing**

  * **Fix:** WUD scans on a CRON schedule. Restart the container (`docker restart wud`) to force an immediate re-scan.

-----

## 8\. Shutdown Timeouts (Exit Code 137)

### **Symptom**

Host shutdown takes a long time, or databases/WUD state files get corrupted.

### **Investigation Command**

Check how long a container takes to stop.

```bash
time docker stop wud
```

### **Case Study: WUD Corruption**

  * **Observation:** WUD took `10.2s` to stop and showed Exit Code `137` (SIGKILL).
  * **Diagnosis:** The application processes data slowly on shutdown. Docker's default timeout is 10s, after which it kills the process aggressively.
  * **The Fix:**
    1.  **Global:** Add `"shutdown-timeout": 30` to `/etc/docker/daemon.json`.
    2.  **Local:** Add `stop_grace_period: 30s` to the service in `compose`.

-----

## 9\. General "Rule of Thumb" Workflow

1.  **Check State:** `docker ps -a` (Is it restarting? Exited?)
2.  **Check Logs:** `docker logs <container_name> --tail 50` (Read the actual error)
3.  **Check Resources:** `docker stats --no-stream` (Is CPU/RAM spiked?)
4.  **Check Connections:** `curl -v http://<ip>:<port>` (Is the port actually open?)

