## 🎬 Service: Media Core - Jellyfin with Jellyseerr

This stack runs the primary media server (Jellyfin) and the request management frontend (Jellyseerr). They are grouped together because they share the same network context and startup logic.

## 1\. Jellyfin
**Role:** Media streaming, transcoding, and library management \
**URL:** `https://jellyfin.mydomain.xyz` (Public) / `http://172.20.0.10:8096` (Internal) \
**Location:** `/mnt/pool01/dockerapps/jellyfin`

## 2\. Docker Compose Configuration

This configuration relies on the `media-stack` (or `dockerapps-net`) network and a specific `group_add` permission for the AMD GPU.

**File:** [`compose`](/jellyfin/compose.yml)

## 3\. Hardware Acceleration (AMD GPU)

This system has two GPUs. We must explicitly force Jellyfin to use the **Dedicated RX 5600 XT** instead of the integrated CPU graphics.

  * **Integrated GPU:** `/dev/dri/renderD129` (Ignored)
  * **Dedicated GPU:** `/dev/dri/renderD128` (Passed to container)

### **Application Settings**

These settings must be configured inside the Jellyfin Web UI (**Dashboard \> Playback \> Transcoding**).

  * **Hardware Acceleration:** `VAAPI`
  * **VA-API Device:** `/dev/dri/renderD128`
  * **Enable Hardware Decoding:**
      * [x] H.264 / AVC
      * [x] HEVC / H.265
      * [x] MPEG2
      * [x] VC1
      * [x] VP9
      * [x] AV1 (If supported by card)

## 4\. Networking & Security

These settings **must** be configured inside the Jellyfin Web UI (**Dashboard > Networking**) to ensure mobile apps connect correctly and the reverse proxy is trusted.

### **A. LAN Networks**
* **Value:** `192.168.0.0/24, 172.20.0.0/24`
* **Why:** Tells Jellyfin which IPs are "Local."
    * `192.168.0.0/24`: Our home Wi-Fi network (allows Direct Play on phones).
    * `172.20.0.0/24`: The Docker network (allows internal containers to talk).
* **Effect:** Prevents local devices from being treated as "Remote" (which triggers bandwidth limits and transcoding).

### **B. Known Proxies**
* **Value:** `172.20.0.23` (Caddy's Static IP)
* **Why:** Tells Jellyfin to trust traffic from Caddy.
* **Effect:** Jellyfin reads the `X-Real-IP` header from Caddy to see the *actual* user's IP address. Without this, all logs show `172.20.0.23`, and IP-based security fails.

### **C. Published Server URIs & Allow Remote**
* **Value:** `all=https://jellyfin.mydomain.xyz`
* **Why:** Explicitly tells clients (especially Android Apps) what the official public URL is.
* **Effect:** Fixes "Connection Cannot be Established" errors on mobile networks (4G/5G). The `all=` prefix forces this URL for all clients, preventing them from trying to connect to unreachable internal IPs.
* **Allow Remote Connections:** [x] Checked.

## 5\. Storage & Folder Structure

Jellyfin "sees" the media files at `/media`.

  * **Movies:** `/media/movies`
  * **TV Shows:** `/media/shows`
  * **Anime Movies:** `/media/anime-movies`
  * **Anime Shows:** `/media/anime-shows`

*(Note: Because of the `/mnt/pool01/media:/media` volume mapping, these files are hardlinked from the downloads folder, consuming no extra space.)*

-----

## 6\. Jellyseerr (The Requester)

  * **Role:** User interface for requesting Movies and TV Shows. Automatically sends requests to Radarr/Sonarr.
  * **Internal URL:** `http://172.20.0.12:5055`
  * **Public URL:** `https://requests.mydomain.xyz` (via Caddy)
  * **Location:** `/mnt/pool01/dockerapps/jellyfin`

### **Configuration Logic**

  * **Dependencies:**
      * `depends_on: jellyfin` (Ensures media server is up before requests UI starts).
  * **Networking:**
      * **Static IP:** `172.20.0.12`
      * **Port:** `5055`
  * **Environment:**
      * `LOG_LEVEL=debug` (Add this if needed for troubleshooting connection issues).
  * **Volumes:**
      * `./jellyseerr-config:/app/config` (Stores user database and request history).

-----

## 7\. Integrated Workflow

### **The "Request" Pipeline**

1.  **User** logs into **Jellyseerr** (`requests.mydomain.xyz`) using their **Jellyfin Credentials** (Single Sign-On).
2.  **User** requests a movie (e.g., *Inception*).
3.  **Jellyseerr** sends the request to **Radarr** (at `172.20.0.13:7878`).
      * *Note:* Requires Radarr API Key in Jellyseerr settings.
4.  **Radarr** downloads the movie via **qBittorrent**.
5.  **Jellyfin** scans the library and makes the movie available.
6.  **Jellyseerr** detects the new content and sends a notification (via **Gotify**) to the user.

### **Caddy Reverse Proxy Integration**

Both services are proxied by Caddy using their internal Static IPs.

  * **Jellyfin:**
      * **Source:** `https://jellyfin.mydomain.xyz`
      * **Destination:** `http://172.20.0.10:8096`
      * **Security:** GeoIP (SG Only) + CrowdSec.
        
  * **Jellyseerr:**
      * **Source:** `https://requests.mydomain.xyz`
      * **Destination:** `http://172.20.0.12:5055`
      * **Security:** GeoIP (SG Only) + CrowdSec.

### **Startup Order**

The `compose.yml` defines a startup sequence to prevent database locks or connection timeouts.

1.  **Jellyfin** starts first (`ipv4_address: 172.20.0.10`).
2.  **Jellyseerr** starts second, waiting for `service_started` signal from Jellyfin.

### Maintenance Commands

**Update Both Services:**

```bash
cd /mnt/pool01/dockerapps/jellyfin
docker compose pull
docker compose up -d --force-recreate
```

**View Logs:**

```bash
# Jellyfin Logs
docker logs -f jellyfin

# Jellyseerr Logs
docker logs -f jellyseerr
```

