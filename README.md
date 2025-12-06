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

To make this truly reproducible, I try to document the [**"One-Time Setup"**](/docs/from-zero.md) steps below that *must* happen before the scripts can run.

*I would also need to refer to the rest of the [docs/](docs/) folder for granular details on specific services.*

-----

## 📚 Documentation Index

This project is documented in modular "Deep Dives". Click the links below for detailed configurations and logic.

### Deployment Guide - [One-Time Setup](/docs/from-zero.md)

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
* **[Utilities](docs/utilities.md):** Management stack & Socket Proxy

