# 🔍 Service: Indexer Management (Prowlarr & Jackett)

**Stack:** `vpn-arr-stack` \
**Network:** `dockerapps-net` (Zone 1 - Trusted) \

This document details the "Hybrid" indexer strategy. While **Prowlarr** is the primary manager, we utilize **Jackett** as a fallback backend for specific trackers that have difficult Cloudflare protections. Both services rely on **FlareSolverr** to bypass CAPTCHAs.

-----

## 1\. Architecture & Logic

### **The "Bad Neighbor" Fix**

Prowlarr, Jackett, and FlareSolverr run **outside** the VPN on the `dockerapps-net`.

  * **Reasoning:** Trackers often rate-limit or block shared VPN IPs ("Bad Neighbors"). By running these apps on the host's residential IP, we avoid CAPTCHAs and connection blocks.
  * **Privacy:** These apps only download metadata (small `.torrent` files), not the actual media content, minimizing ISP visibility risks.

### **The DNS Override**

Because these containers are not using the VPN's internal DNS, they are explicitly configured with public DNS servers to bypass any potential host-level DNS filtering or "Stub Resolver" issues.

  * **DNS Servers:** `1.1.1.1` (Cloudflare), `8.8.8.8` (Google).

### **Dependency Chain (Startup Order)**

To prevent connection errors on startup, a dependency chain is enforced via Healthchecks:

1.  **FlareSolverr** starts and passes its healthcheck (`curl localhost:8191`).
2.  **Prowlarr** and **Jackett** wait for `flaresolverr` to be `service_healthy` before starting.

-----

## 2\. Service Configuration

### **A. FlareSolverr (The Solver)**

  * **Role:** Solves Cloudflare challenges for Prowlarr/Jackett.
  * **Static IP:** `172.20.0.21`
  * **Healthcheck:** Critical for dependent services.
  * **Logging:** Configured to write to `/config/flaresolverr.log` for easier debugging.

### **B. Prowlarr (The Manager)**

  * **Role:** Primary indexer manager. Syncs trackers to Radarr/Sonarr.
  * **Static IP:** `172.20.0.20`
  * **DNS:** Hardcoded to bypass host issues.
  * **Dependency:** Waits for FlareSolverr.

### **C. Jackett (The Specialist)**

  * **Role:** Handles problematic indexers (e.g., `ExtraTorrent.st`, `Kickass`).
  * **Static IP:** `172.20.0.22`
  * **DNS:** Hardcoded to bypass host issues.
  * **Healthcheck:** Added to ensure stability.
  * **Volumes:** Includes a `/downloads` mount for `.torrent` file caching (good practice).

**File:** [`compose`](/vpn-arr-stack/compose.yml)

-----

## 3\. Configuration Guide (UI)

### **Step 1: FlareSolverr Integration**

  * **In Prowlarr:** Settings \> Indexers \> Add Proxy \> FlareSolverr.
      * **Host:** `http://flaresolverr:8191`
      * **Tags:** `cloudflare` (this same tag will be within indexers selected that require them)
  * **In Jackett:** Scroll to bottom of dashboard.
      * **FlareSolverr API URL:** `http://flaresolverr:8191`
      * Click **Apply Server Settings**.

### **Step 2: Linking Jackett to Prowlarr**

We do **not** add Jackett as an "App" in Prowlarr. We add it as a **Generic Torznab Indexer**.

1.  **Get the Feed URL:**
      * In Jackett, click **"Copy Torznab Feed"** (Blue button).
      * *Example:* `http://172.20.0.22:9117/api/v2.0/indexers/all/results/torznab/`
2.  **Add to Prowlarr:**
      * Prowlarr \> Indexers \> Add Indexer \> Search "Torznab" (Generic).
      * **URL:** Paste the long Jackett URL.
      * **API Key:** Paste the API Key from Jackett (top-right).
      * **Categories:** Map standard categories (2000, 5000, etc.).
