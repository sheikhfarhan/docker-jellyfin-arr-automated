# 🛡️ Service: CrowdSec (Intrusion Detection)

**Role:** Security "Brain" (IDS) \
**Location:** `/mnt/pool01/dockerapps/crowdsec` \
**Network:** `dockerapps-net` (Static IP: `172.20.0.24`) \

CrowdSec acts as the intelligence hub for the server. It reads logs, detects attacks (brute force, scanners, botnets), and issues "Ban" decisions. It does **not** block traffic itself; it instructs **Caddy** (the "Bouncer") to do the blocking.

## 1\. Docker Compose Configuration

The container is configured to persist its database locally (for backups) and read Caddy's logs in Read-Only mode.

**File:** [`compose`](/crowdsec/compose.yml)

## 2\. Acquisition Configuration (`acquis.yaml`)

This file tells CrowdSec specifically which files to tail and how to interpret them. Without this, CrowdSec runs blind.

**File:** `acquis.yaml`

```yaml
# Watch the Caddy JSON access log
filenames:
  - /var/log/caddy/access.log
# Tell CrowdSec to use the Caddy parser for these lines
labels:
  type: caddy
```

## 3\. Integration Workflow (Connecting to Caddy)

CrowdSec requires a "Bouncer" API key to allow Caddy to check IP reputations.

### **How to Generate a New Key (If Re-deploying)**

If we rebuild the server, the old API key in Caddy's `.env` will be invalid. We must generate a new one:

1.  **Start CrowdSec:**
2.  **Run the Registration Command:**
    ```bash
    docker exec crowdsec cscli bouncers add caddy-bouncer
    ```
3.  **Copy the Key:** The output will be `Api key for 'caddy-bouncer': <KEY>`
4.  **Update Caddy:** Paste this key into `/mnt/pool01/dockerapps/caddy/.env` as `CROWDSEC_API_KEY`.
5.  **Restart Caddy:** `docker compose restart caddy`

## 4\. Operational Commands (Cheatsheet)

**Check Status:**
See if CrowdSec is successfully reading logs and parsing them.

```bash
docker exec crowdsec cscli metrics
```

  * *Look for:* `Acquisition Metrics` (Lines read) and `Parser Metrics` (Parseds).

**List Active Bans:**
See who is currently blocked.

```bash
docker exec crowdsec cscli decisions list
```

**Manually Ban an IP:**
Useful for testing or blocking a persistent pest.

```bash
docker exec crowdsec cscli decisions add --ip <IP_ADDRESS> --duration 24h --reason "manual ban"
```

**Unban an IP:**

```bash
docker exec crowdsec cscli decisions delete --ip <IP_ADDRESS>
```

**Update Collections:**
Update the threat intelligence rules.

```bash
docker exec crowdsec cscli hub update
docker exec crowdsec cscli hub upgrade
```
