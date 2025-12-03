# 🛡️ Service: Caddy (Secure Reverse Proxy)

**Location:** `/mnt/pool01/dockerapps/caddy/` \
**Network:** `dockerapps-net` (Static IP: `172.20.0.23`) \
**Ports:** `80` & `443` (Directly exposed to Host) \

This service is the **"Front Door"** of the server. It handles all incoming traffic from the public internet, secures it with SSL, filters it through security layers (GeoIP + CrowdSec), and routes it to the correct internal service.

-----

## 1\. The Custom Build Strategy (`Dockerfile`)

Unlike other services where we pull a standard image, Caddy requires a **custom build**. This is because the standard Caddy image does not include the specific plugins we need for our security and automation logic.

**The Build Recipe:**

```dockerfile
FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \       # For SSL DNS Challenges & DDNS
    --with github.com/mholt/caddy-dynamicdns \     # For updating home IP (DDNS)
    --with github.com/hslatman/caddy-crowdsec-bouncer \ # For IP Reputation Blocking
    --with github.com/porech/caddy-maxmind-geolocation  # For Geo-Blocking

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

**File:** [`Dockerfile`](/caddy/Dockerfile)

  * **Why:** This compiles a single binary that has native, high-performance access to Cloudflare's API and the MaxMind database without needing external scripts or sidecars.

-----

## 2\. Container Configuration (`compose.yml`)

The Compose file orchestrates the build and runtime environment.

**Key Configuration Points:**

  * **Network:** Uses `dockerapps-net` with a Static IP (`.23`) so other containers can trust it as a known proxy.
  * **Ports:** Maps `80:80` and `443:443` directly to the host to handle incoming web traffic.
  * **Volumes:**
      * **`./logs`**: Critical for CrowdSec (the "Brain") to read the access logs generated here.
      * **`./GeoLite2-Country.mmdb`**: Critical for the GeoIP plugin to function.

**File:** [`compose`](/caddy/compose.yml)

-----

## 2\. Configuration Logic (`Caddyfile`)

The `Caddyfile` is the brain of the proxy. It uses a "Global Options" block for server-wide settings and "Site Blocks" for specific domainn.

### **A. Global Options**

  * **Dynamic DNS:** Automatically updates the A-records for `mydomain.xyz`, `jellyfin`, `requests`, and `gotify` to match the home IP.
  * **CrowdSec:** Connects to the CrowdSec "Brain" container (`http://crowdsec:8080`) to fetch ban lists.
  * **Logging:** Writes internal Caddy system logs to `caddy.log`.

### **B. Site Logic (Repeated for each subdomain)**

Each domain (e.g., `jellyfin.mydomain.xyz`) follows these pipeline:

1.  **SSL Termination (`tls`):**

      * Uses the `dns cloudflare` plugin to solve the Let's Encrypt challenge. This allows us to get certificates even though we are behind a residential IP.

2.  **Geo-Blocking (Layer 1 Security):**

      * **Matcher:** `@geo_sg` checks if the incoming IP is from **Singapore (SG)** using the local MaxMind database.
      * **Filter:** Traffic entering the `handle @geo_sg` block is allowed.
      * **Block:** Any traffic *not* matching this group falls through to the final `handle` block, which responds with **403 Access Denied**.

3.  **CrowdSec Check (Layer 2 Security):**

      * Inside the allowed block, the `route { crowdsec }` directive checks the IP against CrowdSec's database. If the IP is malicious (even if it's from Singapore), the connection is dropped.

4.  **Reverse Proxy (Routing):**

      * Forwards valid traffic to the internal static IP (e.g., `http://jellyfin:8096`).
      * **Header Fixes:**
          * `header_up X-Real-IP {remote_host}`: Tells Jellyfin the user's real IP.

5.  **Optimization (Log Filtering)**
    
     * To prevent **CrowdSec** from burning CPU by analyzing internal traffic (e.g., Homepage widgets checking status every second), we explicitly skip logging for local networks.
     * Configuration Logic:
         * **Define Internal Subnets:** We create a matcher `@internal` for `172.20.0.0/24` (Docker) and `192.168.0.0/16` (LAN).
         * **Skip Logging:** The directive `log_skip @internal` ensures these requests never hit the `access.log` file.

**Caddyfile Snippet:**
```caddy
jellyfin.{env.ROOT_DOMAIN} {
    # ... tls ...

    # Define Internal Traffic
    @internal {
        remote_ip 172.20.0.0/24 192.168.0.0/16 127.0.0.1
    }

    # Disable Logging for Internal (Saves CPU)
    log_skip @internal

    # Log everything else for CrowdSec
    log {
        output file /var/log/caddy/access.log {
            roll_size 10mb
            roll_keep 5
        }
        format json {
            time_local
        }
    }
    
    # ... rest of config ...
}
```

**File:** [`Caddyfile`](/caddy/Caddyfile)

-----

## 3\. Environment & Secrets (`.env`)

Sensitive keys and Variables are passed into the container at runtime, keeping the config files safe for version control.

  * **`CLOUDFLARE_API_TOKEN`:** Used for DDNS updates and SSL challenges.
  * **`CROWDSEC_API_KEY`:** Generated from the CrowdSec container to authorize the bouncer.
  * **`ROOT_DOMAIN`:** Used to replace the root domain.
  
**File:** [`.env.example`](/caddy/.env.example)

----

## 4\. Maintenance Commands

**To Rebuild (Required if adding plugins):**

```bash
cd /mnt/pool01/dockerapps/caddy
docker compose build
docker compose up -d --force-recreate
```

**To Reload Config (Zero Downtime):**

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**To View Access Logs:**

```bash
tail -f /mnt/pool01/dockerapps/caddy/logs/access.log
```
