# Media Server (Docker Compose + Jellyfin + Arr Stacks)

**An automated media stack running on Arch Linux (CachyOS).**

This repo documents the journey of building a self-hosted media server. It features a **"Split-Network" architecture** that balances VPN isolation for downloads with direct access for streaming, protected by security layers.

Hope it will help the future-me when and if i need to redeploy this to another machine/dedicated server. And of course, if it helps others to make sense of things and deploy something similar, it would be awesome too! :)

-----

## 🖥️ System Specs

  * **Host:** CachyOS (Arch Linux)
  * **Hardware:** AMD 7600x, 32GB RAM, AQC113C 10GbE NIC, Radeon 5600xt
  * **Storage:** 2 x 1TB NVMEs in an LVM (`vg_pool01`) mounted at `/mnt/pool01`
  * **Network:** Custom Bridge (`dockerapps-net`) with IPv6 + Reverse Proxy (Caddy)

-----

## 🏗️ Architecture Overview

### The "Two-Zone" Network Model

We separate services into two distinct network zones.

  * **Zone 1: Trusted Apps (`dockerapps-net`)**
      * *Services:* Jellyfin, Jellyseerr, Caddy, Radarr, Sonarr, Bazarr, Homepage etc..
      * *Behavior:* Uses host internet for metadata & streaming. Accessible via Reverse Proxy.

  * **Zone 2: The VPN Bubble (`service:gluetun`)**
      * *Services:* qBittorrent, Transmission, FlareSolverr.
      * *Behavior:* These containers have **NO** IP address. They use `gluetun`'s network stack to force 100% of traffic through the AirVPN WireGuard tunnel.
      * *Paid Service:* Airvpn Subscription

### The Security Stack

  * **Ingress:** **Caddy** (Ports 80/443) with Cloudflare DNS validation.
  * **Defense:**
      * **CrowdSec:** IPS reading Caddy logs to ban malicious IPs.
      * **GeoIP:** Blocks all non-Singaporean traffic at the proxy level.
      * **Socket Proxy:** Read-only gateway for docker.sock, preventing container breakout.
  * **Firewall:** Host-level `firewalld` rules preventing Docker containers from scanning the home LAN.

-----

## Final Look: Static IP Allocation Table

| IP Address | Service | Stack | Port | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `172.20.0.1` | **Gateway** | - | - | Docker Host Gateway |
| `172.20.0.10` | **Jellyfin** | `jellyfin` | 8096 | Media Server |
| `172.20.0.11` | **Gluetun** | `vpn-arr` | - | **VPN Gateway** |
| `172.20.0.12` | **Jellyseerr** | `jellyfin` | 5055 | Request Manager |
| `172.20.0.13` | **Radarr** | `vpn-arr` | 7878 | Movies |
| `172.20.0.14` | **Sonarr** | `vpn-arr` | 8989 | TV Shows |
| `172.20.0.15` | **Bazarr** | `vpn-arr-stack` | 6767 | Subtitles |
| `172.20.0.16` | **Gotify** | `gotify` | 80 | Notifications |
| `172.20.0.17` | **Portainer** | `utilities` | 9443 | Docker UI (via Proxy) |
| `172.20.0.19` | **Profilarr** | `vpn-arr-stack` | 5000 | Quality Settings & Formats |
| `172.20.0.20` | **Prowlarr** | `vpn-arr` | 9696 | Indexer Manager |
| `172.20.0.21` | **FlareSolverr** | `vpn-arr-stack` | 8191 | Captcha Solver |
| `172.20.0.22` | **Jackett** | `vpn-arr-stack` | 9117 | Indexer Fallback |
| `172.20.0.23` | **Caddy** | `caddy` | 80/443 | **Reverse Proxy** |
| `172.20.0.24` | **CrowdSec** | `crowdsec` | 8080 | Security Brain |
| `172.20.0.25` | **Homepage** | `utilities` | 3000 | Dashboard |
| `172.20.0.26` | **Dozzle** | `utilities` | 8080 | Log Viewer |
| `172.20.0.27` | **WUD** | `utilities` | 3001 | Update Notifier |
| `172.20.0.28` | **Socket Proxy** | `utilities` | 2375 | **Docker-Socket Proxy** |

---
## Final Look: Homepage

![homepage dashboard](/assets/homepage-dashboard1.png)
-----

If I were to clone this repo to a brand-new machine right now and ran `start-stacks.sh`, **it would fail immediately.**

### **The "Invisible" Gaps (Why it would fail)**

This repo contains the *application* logic, but it is missing the **Host-Level Dependencies** that I configured manually in the terminal along the way.

1.  **The Network Error:** Docker will complain that `dockerapps-net` does not exist. The `compose` files expect it to be `external`, so they won't create it for us.
2.  **The "Connection Refused" Error:** Without the specific `/etc/docker/daemon.json` IPv6/DNS fix I applied, containers might fail to talk to each other.
3.  **The "Missing File" Error:** Caddy will crash because `GeoLite2-Country.mmdb` is excluded from the repo (correctly), but it doesn't exist on the new host.
4.  **The "Missing Secrets" Error:** The `.env` files are git-ignored. A fresh clone has no API keys, so containers will start with empty variables and crash.
5.  **The Firewall:** `firewalld` won't be installed or configured, so even if Caddy starts, no one can reach it.
6.  **Homepage-Crowdsec API Error:** `crowdsec` will generate a new Machine ID (because the database is fresh) and utilities/homepage/config/services.yaml will still contain the old username/password for the CrowdSec widget.

To make this truly reproducible, I try to document the **"One-Time Setup"** steps below that *must* happen before the scripts can run.

*I would also need to refer to the [docs/](docs/) folder for granular details on specific services.*

## 🚀 Deployment Guide (Zero-to-Hero)

### Phase 1: Host Preparation

*Configure the OS before touching Docker.*

1.  **Install Dependencies:**

    ```bash
    sudo pacman -S docker docker-compose git firewalld
    sudo systemctl enable --now docker firewalld
    ```

2.  **Configure Docker Daemon (for IPv6 & DNS):**

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

3.  **Create the Network Infrastructure:**

      * Creates the `dockerapps-net` custom network with its own isolated IPv6 subnet (`abc2`).

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

4.  **Configure Firewall (Security & Access):**

      * **Allow:** Web (80/443) and Local Direct Play (8096).
      * **Block:** Prevents Docker containers (`172.20...`) from initiating connections to our Home LAN (`192.168...`), effectively creating a "Software VLAN."

         ```bash
         # 1. Open Required Ports
         sudo firewall-cmd --add-service=http --permanent
         sudo firewall-cmd --add-service=https --permanent
         sudo firewall-cmd --add-port=8096/tcp --permanent

         # 2. Create DOCKER-USER Chain (Prevents errors if Docker hasn't started yet)
         sudo firewall-cmd --permanent --direct --add-chain ipv4 filter DOCKER-USER

         # 3. Add Isolation Rule (Block Docker -> LAN)
         sudo firewall-cmd --permanent --direct --add-rule ipv4 filter DOCKER-USER 0 -s 172.20.0.0/24 -d 192.168.0.0/24 -m conntrack --ctstate NEW -j DROP

         # 4. Apply
         sudo firewall-cmd --reload
         ```

5.  **Identify Host IDs (For .env):**

      * Homepage and \*Arr apps need to know our user/group IDs.

         ```bash
         echo "PUID=$(id -u)"
         echo "PGID=$(id -g)"
         echo "DOCKER_GID=$(getent group docker | cut -d: -f3)"
         ```
    *(Save these numbers for our `.env` file in Phase 2).*

### **Why these matter:**

  * **Port 8096:** Ensures my phone can cast/play media without going through the reverse proxy loopback.
  * **Step 5:** Solves the "Permission Denied" error I faced with Homepage and the Widgets part, so I am doing this to get that DOCKER_GID before I even install Homepage\!

-----

### Phase 2: Repository & Structure

1.  **Clone Repo:**

    ```bash
    git clone git@github.com:sheikhfarhan/docker-jellyfin-arr-automated.git /mnt/pool01/dockerapps
    ```

2.  **Reconstruct Directories:**
    Run the script in ![docs/folder-structure.md](docs/folder-structure.md) to create the empty config folders (e.g., `utilities/homepage/config`, `vpn-arr-stack/gluetun/auth`). 

    The idea is that the folders config/data/store within each of the main sub-folders for each of the services should be created by me/user so that docker root would not create on our behalf, coz if they do, that folder witll have root:root ownership.

3.  **Restore "Ignored" Assets:**

      * **GeoIP Database:** Required for Caddy.

        ```bash
        cd caddy #make sure we are in caddy dir
        wget "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
        sudo chown 1000:1000 GeoLite2-Country.mmdb
        cd ..
        ```

4.  **Create .env files (`.env`):**

      * **Critical:** We must create the `.env` file in **every** service folder that requires one. Refer to .env.example in each of the subfolder for each services/containers.
      
      
-----

### Phase 3: Initialization & Launch

1.  **Bootstrap CrowdSec (Generate Keys):**

      Before starting the full stack, start CrowdSec to generate the keys Caddy and Homepage need.

         ```bash
         # Start just CrowdSec when at crowdsec folder
         docker compose up -d 

         # 1. Generate Caddy Bouncer Key
         docker exec crowdsec cscli bouncers add caddy-bouncer
         # -> Paste this key into caddy/.env for CROWDSEC_API_KEY=

         # 2. Get Homepage Credentials
         # Run this still from /mnt/pool01/dockerapps/crowdsec
         cat config/local_api_credentials.yaml
         # Update HOMEPAGE_VAR_CROWDSEC_USER and _PASS in utilities/.env
         ```

2.  **Run the Startup Script:**

    ```bash
    ./scripts/start-stacks.sh
    ```

3.  **Configure Jellyfin Networking (CRITICAL for Mobile):**

      *Dashboard \> Networking:*
       * **LAN Networks:** `192.168.0.0/24, 172.20.0.0/24` (Enables local playback).
       * **Known Proxies:** `172.20.0.23` (Trusts Caddy).
       * **Published Server URIs:** `all=https://jellyfin.mydomain.xyz` (Fixes Android app connection).

4.  **Configure Portainer:**

      Add Environment -\> Docker Standalone -\> API.
      **URL:** `tcp://172.20.0.28:2375` (Connects via Socket Proxy).

5.  **Continue with Secrets** (`utilities/.env`, `vpn-arr-stack/.env` where needed). eg:

       ```bash
       nano utilities/.env
       # Add: API Keys for Radarr, Sonarr, Jellyfin (now that we have the other services up)
       # Add: Gotify Token
       # Add: Gluetun keys
       # ... 
       ```

    *Refer to .env.example in each of the sub-folder.*

    *I would also need to refer to the [docs/](docs/) folder for granular details on specific services.*

### **Verification**

1.  **Check Caddy:**
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
* **[Firewalld](docs/security-firewall.md):** Firewalld "Software VLAN"
* **[Utilities](docs/utilities.md):** Management stack & Socket Proxy.

