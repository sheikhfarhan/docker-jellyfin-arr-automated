# Media Server (Docker Compose + Jellyfin + Arr Stacks) on a PC

**An automated media stack running on Arch Linux (CachyOS).**

This repo documents my journey and adventure for a self-hosted media server. It features a **"Split-Network" architecture** that balances VPN isolation for downloads with direct access for streaming, protected by basic security layers. \
Hope it will help the future-me when and if i need to redeploy this to another machine/dedicated server. And of course, if it helps others to make sense of things and deploy something similar, it would be awesome too! :)

---

**Host System:** CachyOS (Arch Linux) \
**PC Specs:** X870 Mobo (AsRock RS), AMD 7600x, 32GB Ram, AQC113C Marvell 10gbe NIC, 5600xt GPU \
**Architecture:** Docker Compose (Split-Network Model) \
**Storage:** LVM (`vg_pool01`) mounted at `/mnt/pool01` \
**Network Strategy:** Custom Bridge with IPv6 + Reverse Proxy (Caddy).

-----

### **Static IP Allocation Table**

| IP Address | Service | Stack | Port (Internal) | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `172.20.0.1` | **Gateway** | - | - | Host Gateway |
| `172.20.0.10` | **Jellyfin** | `jellyfin` | 8096 | Media Server |
| `172.20.0.11` | **Gluetun** | `vpn-arr-stack` | - | **VPN Gateway** |
| `172.20.0.11` | **qBittorrent** | `vpn-arr-stack` | 8080 | Via VPN (Gluetun) |
| `172.20.0.11` | **Transmission** | `vpn-arr-stack` | 9091 | Via VPN (Gluetun) |
| `172.20.0.12` | **Jellyseerr** | `jellyfin` | 5055 | Request Manager |
| `172.20.0.13` | **Radarr** | `vpn-arr-stack` | 7878 | Movies |
| `172.20.0.14` | **Sonarr** | `vpn-arr-stack` | 8989 | TV Shows |
| `172.20.0.15` | **Bazarr** | `vpn-arr-stack` | 6767 | Subtitles |
| `172.20.0.16` | **Gotify** | `gotify` | 80 | Notifications |
| `172.20.0.17` | **Portainer** | `portainer` | 9443 | Admin UI |
| `172.20.0.19` | **Profilarr** | `vpn-arr-stack` | 5000 | Trash Guides |
| `172.20.0.20` | **Prowlarr** | `vpn-arr-stack` | 9696 | Indexers |
| `172.20.0.21` | **FlareSolverr** | `vpn-arr-stack` | 8191 | Captcha Solver |
| `172.20.0.22` | **Jackett** | `vpn-arr-stack` | 9117 | Indexer Fallback |
| `172.20.0.23` | **Caddy** | `caddy` | 80/443 | **Public Ingress** |
| `172.20.0.24` | **CrowdSec** | `crowdsec` | 8080 | Security Brain |
| `172.20.0.25` | **Homepage** | `homepage` | 3000 | Dashboard |
| `172.20.0.26` | **Dozzle** | `dozzle` | 8080 | Log Viewer |
| `172.20.0.27` | **WUD** | `wud` | 3001 | Update Notifier |

---
![homepage dashboard](/assets/homepage-dashboard1.png)

---

## Highlights

1.  **Two-Zone Networking:** Complete isolation between "Trusted" apps (Management/Streaming) and "Untrusted" apps (Downloads/VPN).
2.  **Performance First:** Uses **Caddy** as a reverse proxy for direct streaming (vs using Cloudflare Tunnel, which works flawlessly btw).
3.  **Zero-Copy Storage:** Utilizes **Hardlinks (Atomic Moves)** to manage media files instantly without using double disk space.
4.  **Basic Security:** Protected by **CrowdSec** (Intrusion Detection) and **GeoIP Blocking** (Singapore-Only whitelist).

-----

## 📚 Documentation Index

This project is documented in modular "Deep Dives". Click the links below for detailed configurations and logic.

### Infrastructure & Storage

* **[Storage Architecture](docs/storage.md):** How LVM is used to pool my currently humble 2 x 1TB NVMe drives in my mobo and manage volumes (`/mnt/pool01`).
* **[Folder Structure & Hardlinks](docs/folder-structure.md):** The directory layout, **including a full "Golden Tree" map**, which enables atomic moves and automated anime routing.
* **[Network Architecture](docs/networking.md):** The "Two-Zone" Docker network, Static IP map, and `daemon.json` configuration.

### Services & Stacks

* **[Media Core (Jellyfin & Jellyseerr)](docs/jellyfin-stack.md):** The streaming server and request management hub, with GPU Passthrough configurations.
* **[Automation Engine (VPN & *Arr Stack)](docs/vpn-arr-automation-stack.md):** The "Engine Room." Covers Gluetun VPN, Radarr, Sonarr, Bazarr, Prowlarr and Download Clients.
* **[Indexer Management](docs/indexers.md):** The "Hybrid" strategy using Prowlarr and Jackett with FlareSolverr to bypass CAPTCHAs.
* **[Notification Hub](docs/gotify.md):** Centralized alerts for all services via Gotify and Webhooks.
* **[Dashboard (Homepage)](docs/homepage.md):** The "Single Pane of Glass" monitoring all services, resources, and security alerts.

### Security & Ingress

* **[Caddy Reverse Proxy](docs/caddy.md):** The "Front Door." Handles SSL, DDNS, and mobile app compatibility.
* **[CrowdSec IDS](docs/crowdsec.md):** The "Brain." Reads logs and bans malicious IPs before they touch the application.
* **[Cloudflare Configuration](docs/cloudflare-setup.md):** Setup for API Tokens, DNS Records, and Permissions.

-----

## Architecture Overview

### The "Two-Zone" Model

We separate services into two distinct network zones.

1.  **Zone 1: The App Network (`dockerapps-net`)**
      * *Contains:* Jellyfin, Jellyseerr, Caddy, Radarr, Sonarr, Portainer.
      * *Behavior:* Uses the host's internet connection for media management, remote requests and serving the streams.
2.  **Zone 2: The VPN Bubble (`service:gluetun`)**
      * *Contains:* qBittorrent, Transmission.
      * *Behavior:* These containers have **NO** IP address of their own. They are network-attached to `gluetun` and force 100% of traffic through the AirVPN WireGuard tunnel.
      * *Paid Service:* Airvpn Subscription

### The Security Stack

Instead of relying on Cloudflare Tunnel (which works flawlessly before I decided to use Caddy), we use a **Caddy** instance exposed on ports 80/443.

  * **Layer 1 (GeoIP):** Caddy immediately drops any connection not originating from **Singapore**.
  * **Layer 2 (CrowdSec):** Caddy checks the client IP against a local CrowdSec blocklist. If the IP is malicious, it is banned (403 Forbidden).
  * **Layer 3 (HTTPS):** Fully encrypted via Let's Encrypt.

-----

## Deployment Guide

### Prerequisites

If I were to clone this repo to a brand-new CachyOS machine right now and ran `start-stacks.sh`, **it would fail immediately.**

### **The "Invisible" Gaps (Why it would fail)**

This repo contains the *application* logic, but it is missing the **Host-Level Dependencies** that I configured manually in the terminal along the way.

1.  **The Network Error:** Docker will complain that `dockerapps-net` does not exist. The `compose.yml` files expect it to be `external`, so they won't create it for us.
2.  **The "Connection Refused" Error:** Without the specific `/etc/docker/daemon.json` IPv6/DNS fix I applied, containers might fail to talk to each other.
3.  **The "Missing File" Error:** Caddy will crash because `GeoLite2-Country.mmdb` is excluded from the repo (correctly), but it doesn't exist on the new host.
4.  **The "Missing Secrets" Error:** The `.env` files are git-ignored. A fresh clone has no API keys, so containers will start with empty variables and crash.
5.  **The Firewall:** `firewalld` won't be installed or configured, so even if Caddy starts, no one can reach it.
6.  **Homepage-Crowdsec API Error:** `crowdsec` will generate a new Machine ID (because the database is fresh) and homepage/config/services.yaml will still contain the old username/password for the CrowdSec widget.

To make this truly reproducible, I try to document the **"One-Time Setup"** steps below that *must* happen before the scripts can run.

*I would also need to refer to the [docs/](docs/) folder for granular details on specific services.*


-----

### **The "Zero-to-Hero" Workflow**

#### **Phase 1: Host Preparation (The "Invisible" Foundation)**

These steps configure the OS to support the stack.

1.  **Install System Dependencies:**

    ```bash
    sudo pacman -S docker docker-compose git firewalld
    sudo systemctl enable --now docker firewalld
    ```

2.  **Configure Docker Daemon (Critical for IPv6 & DNS):**

      * **Why:** Enables IPv6 support. I use the subnet `2001:db8:abc1::/64` here for the **Default Bridge** (system-wide), which must be different from our custom network later.
      * **Action:** Create `/etc/docker/daemon.json`:

         ```json
         {
           "ipv6": true,
           "fixed-cidr-v6": "2001:db8:abc1::/64",
           "experimental": true,
           "ip6tables": true,
           "dns": ["1.1.1.1", "8.8.8.8"]
         }
         ```
      * **Apply:** `sudo systemctl restart docker`

4.  **Create the Network Infrastructure:**

      * **Why:** Creates the `dockerapps-net` custom network with its own isolated IPv6 subnet (`abc2`).

         ```bash
         docker network create \
           --driver=bridge \
           --ipv6 \
           --subnet=172.20.0.0/24 \
           --gateway=172.20.0.1 \
           --subnet=2001:db8:abc2::/64 \
           --gateway=2001:db8:abc2::1 \
           dockerapps-net
         ```

5.  **Configure Firewall (Ports):**

      * **80/443:** For Caddy (Public Internet).
      * **8096:** For Jellyfin (Local LAN Direct Play).

         ```bash
         sudo firewall-cmd --add-service=http --permanent
         sudo firewall-cmd --add-service=https --permanent
         sudo firewall-cmd --add-port=8096/tcp --permanent
         sudo firewall-cmd --reload
         ```

6.  **Identify Host IDs (For .env):**

      * **Why:** Homepage and \*Arr apps need to know our user/group IDs to read files and sockets.

         ```bash
         echo "PUID=$(id -u)"
         echo "PGID=$(id -g)"
         echo "DOCKER_GID=$(getent group docker | cut -d: -f3)"
         ```
    *(Save these numbers for our `.env` file in Phase 2).*

### **Why these matter:**

  * **Port 8096:** Ensures my phone can cast/play media without going through the reverse proxy loopback.
  * **Step 5:** Solves the "Permission Denied" error I faced with Homepage and the Widgets part, so I am doing this before I even install it\!

-----

#### **Phase 2: Repository & File Setup**

1.  **Clone the Repo:**

    ```bash
    # Clone into the correct LVM mount point
    git clone git@github.com:sheikhfarhan/docker-jellyfin-arr-automated.git /mnt/pool01/dockerapps
    cd /mnt/pool01/dockerapps
    ```

2.  **Reconstruct Directory Tree (Permissions Fix):**

      * **Critical:** We must create them manually to ensure correct permissions (`1000:1000`), otherwise Docker will create them as `root` and break the stack.
      * **Action:** Run the reconstruction commands found in [Folder Structure Docs](docs/folder-structure.md).

3.  **Restore "Ignored" Assets:**

      * **GeoIP Database:** Required for Caddy.

        ```bash
        cd caddy
        wget "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
        sudo chown 1000:1000 GeoLite2-Country.mmdb
        cd ..
        ```

4.  **Configure Secrets (`.env`):**

      * **Critical:** We must create the `.env` file in **every** service folder that requires one.
      * **Step A: Caddy Secrets** (`caddy/.env`)

        ```bash
        nano caddy/.env
        # Add: PUID, PGID, TZ
        # Add: CLOUDFLARE_API_TOKEN=...
        # Add: ROOT_DOMAIN=mydomain.xyz
        # Note: Leave CROWDSEC_API_KEY blank for now (we generate it in Phase 3)
        ```
      * **Step B: VPN Secrets** (`vpn-arr-stack/.env`)

        ```bash
        nano vpn-arr-stack/.env
        # Add: WireGuard Keys, VPN Provider config
        # Add: HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE='{"auth":"apikey"..."}'
        ```
      * **Step C: Homepage Secrets** (`homepage/.env`)

        ```bash
        nano homepage/.env
        # Add: API Keys for Radarr, Sonarr, Jellyfin (retrieve these later from apps)
        # Note: Leave Gluetun/CrowdSec keys blank for now (generated in Phase 3)
        ```

-----

#### **Phase 3: Initialization & Launch**

1.  **Bootstrap CrowdSec (Generate Keys):**

      * Before starting the full stack, start CrowdSec to generate the keys Caddy and Homepage need.

         ```bash
         # Start just CrowdSec
         docker compose -f vpn-arr-stack/compose.yml up -d crowdsec

         # 1. Generate Caddy Bouncer Key
         docker exec crowdsec cscli bouncers add caddy-bouncer
         # -> Paste this key into caddy/.env

         # 2. Get Homepage Credentials
         cat vpn-arr-stack/gluetun/config/local_api_credentials.yaml
         # -> Paste 'login' and 'password' into homepage/.env
         ```

2.  **Run the Startup Script:**

    ```bash
    ./scripts/start-stacks.sh
    ```

3.  **Connect Homepage to CrowdSec:**

      * Since this is a fresh install, CrowdSec generates a unique Machine ID/Password on every fresh install. We must manually provide these to Homepage so the widget works.
    * **Action:**
        1.  Retrieve the new credentials:

            ```bash
            # Run this from /mnt/pool01/dockerapps
            cat crowdsec/config/local_api_credentials.yaml
            ```
        3.  Copy the `login` and `password` values.
        4.  Update Homepage secrets file:
            ```bash
            nano homepage/.env
            # Update HOMEPAGE_VAR_CROWDSEC_USER and _PASS
            ```
        5.  Restart Homepage to apply:
            ```bash
            docker restart homepage
            ```
*I would also need to refer to the [docs/](docs/) folder for granular details on specific services.*

### **Verification**

1.  **Check Caddy (Ingress):**
    ```bash
    docker logs caddy
    ```
    * *Success:* Look for "certificate obtained" and "GeoIP loaded".

2.  **Check VPN (Security):**
    ```bash
    docker logs gluetun
    ```
    * *Success:* Look for "Public IP address is xxx.xxx.xxx.xxx" (Should show a VPN IP/Location, e.g., Netherlands).

3.  **Check External Access (Mobile):**
    * Disconnect phone from Wi-Fi (use 4G/5G).
    * Visit `https://jellyfin.mydomain.xyz`.
    * *Success:* The Jellyfin login page should load securely.



