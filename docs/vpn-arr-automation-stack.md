# 🤖 Service: Automation Stack (`vpn-arr-stack`)

**Location:** `/mnt/pool01/dockerapps/vpn-arr-stack/` \
**Network:** `dockerapps-net` (Management) & `service:gluetun` (Downloads) \

This stack is the engine of the media server. It handles finding, downloading, renaming, and organizing content. It relies on a "Two-Zone" network architecture to ensure no piracy traffic leaks outside the VPN.

-----

**File:** [`compose`](/vpn-arr-stack/compose.yml)

## 1\. The VPN Gateway (Zone 2)

These services are **inside the VPN bubble**. They do not have their own IP addresses; they share the network stack of the `gluetun` container.

### **A. Gluetun (The Gateway)**

  * **Role:** VPN Tunnel & Firewall. All download traffic MUST go through here.
  * **Static IP:** `172.20.0.11`
  * **Provider:** AirVPN (WireGuard).
  * **Ports Open:**
      * `8080` (qBittorrent Web UI)
      * `9091` (Transmission Web UI)
      * *Note: These ports are mapped on the Gluetun container, but forward traffic to the services "attached" to it.*
  * **Critical Config:**
      * `devices: /dev/net/tun` (Required for VPN).
      * `sysctls: net.ipv6.conf.all.disable_ipv6=0` (Enables IPv6 inside the tunnel).
      * **Healthcheck:** The container has a built-in healthcheck. Dependent services (`depends_on`) will NOT start until the VPN tunnel is fully established.

### **B. qBittorrent (Primary Downloader)**

  * **Role:** Torrent client.
  * **Network Mode:** `service:gluetun` (No IP).
  * **Web UI:** Accessed via `http://172.20.0.11:8080`.
  * **Storage:** Maps `/mnt/pool01/media:/media` to allow atomic moves to the library.
  * **Port Forwarding:** Configured/Added in AirVpn's Client Area Settings and double check that the specified AirVpn's Port number shows up in Qbit's settings under "Connection"->"Port used for incoming connections").

### **C. Transmission (Secondary Downloader)**

  * **Role:** Backup/Alternative client.
  * **Network Mode:** `service:gluetun` (No IP).
  * **Web UI:** Accessed via `http://172.20.0.11:9091`.
  * **Storage:** Maps `/mnt/pool01/media:/media`.
  * **Port Forwarding:** Uses AirVPN Port `<RESERVED_PORT>`.

-----

## 2\. The Managers (Zone 1)

These services are **outside the VPN** on the standard `dockerapps-net`. They manage the library and talk to the download clients via the local gateway.

### **A. Radarr (Movies)**

  * **Static IP:** `172.20.0.13`
  * **Port:** `7878`
  * **Role:** Managing Movie collection.
  * **Critical Settings:**
      * **Root Folders:** `/media/movies` (Standard) and `/media/anime-movies` (Anime).
      * **Remote Path Mapping:** Maps Host `172.20.0.1` Path `/media` to Local Path `/media`.
      * **Tags:** Auto-tags "Animation" genre with `anime`.

### **B. Sonarr (TV Shows)**

  * **Static IP:** `172.20.0.14`
  * **Port:** `8989`
  * **Role:** Managing TV Series.
  * **Critical Settings:**
      * **Root Folders:** `/media/shows` (Standard) and `/media/anime-shows` (Anime).
      * **Remote Path Mapping:** Maps Host `172.20.0.1` Path `/media` to Local Path `/media`.
      * **Tags:** Auto-tags "Anime" series type with `anime`.

### **C. Bazarr (Subtitles)**

  * **Static IP:** `172.20.0.15`
  * **Port:** `6767`
  * **Role:** Downloads subtitles for existing media.
  * **Connection:** Connects to Radarr/Sonarr to see what files need subtitles.

-----

## 3\. The Indexers & Utilities

### **A. Prowlarr (Indexer Manager)**

  * **Static IP:** `172.20.0.20`
  * **Port:** `9696`
  * **Role:** Manages torrent trackers and syncs them to Radarr/Sonarr.
  * **DNS Fix:** Configured with `dns: [1.1.1.1, 8.8.8.8]` to bypass host DNS issues.
  * **Proxy:** Uses `flaresolverr` to bypass Cloudflare protections on trackers.

### **B. FlareSolverr (Captcha Solver)**

  * **Static IP:** `172.20.0.21`
  * **Port:** `8191`
  * **Role:** Solves Cloudflare challenges for Prowlarr/Jackett.

### **C. Jackett (Useful Proxy)**

  * **Static IP:** `172.20.0.22`
  * **Port:** `9117`
  * **Role:** Used *only* for specific trackers that Prowlarr struggles with.
  * **Integration:** Added to Prowlarr as a "Generic Torznab" indexer.

### **D. Profilarr (Quality Settings & Custom Formats)**

  * **Static IP:** `172.20.0.19`
  * **Port:** `5000`
  * **Role:** Automatically syncs optimal quality profiles and custom formats to Radarr/Sonarr.

-----

## 4\. Maintenance

### **Dependencies & Startup**

The `compose.yml` defines strict dependencies:

1.  **Gluetun** starts first.
2.  **Download Clients** wait for `service_healthy` from Gluetun.
3.  **Managers (Radarr/Sonarr)** wait for Download Clients.
4.  **Profilarr** waits for Radarr/Sonarr.

**To Update the Entire Stack:**

```bash
cd /mnt/pool01/dockerapps/vpn-arr-stack
docker compose pull
docker compose up -d --force-recreate
```

*(This will briefly interrupt downloads and the VPN connection).*

## 5\. .env for vpn-arr-stack (saved alongside the compose file)

The `.env` elements that are align with what we have in our stack can be found in ![.env-example](/vpn-arr-stack/.env.example)