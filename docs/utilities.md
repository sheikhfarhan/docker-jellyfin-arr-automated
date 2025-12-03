# 🛠️ Utilities Stack (Management & Monitoring)

**Location:** `/mnt/pool01/dockerapps/utilities` \
**Network:** `dockerapps-net` (Zone 1 - Trusted)

This stack consolidates all management tools behind a **Socket Proxy**, ensuring no container has direct root access to the Docker socket.

## 1\. Architecture

  * **Socket Proxy:** The *only* container with `/var/run/docker.sock` mounted. It exposes a sanitized Docker API on TCP port `2375`.
  * **Dependent Services:** Homepage, Portainer, WUD, and Dozzle connect to `tcp://172.20.0.28:2375`.

## 2\. Services Configuration

### **A. Socket Proxy (The Gatekeeper)**

  * **IP:** `172.20.0.28`
  * **Port:** `2375` (Internal TCP)
  * **Security:**
      * `POST=0`: Blocks all state-changing commands (create/start/stop/delete).
      * `CONTAINERS=1`, `IMAGES=1`, `NETWORKS=1`: Allows read-only monitoring.

### **B. Homepage (Dashboard)**

  * **IP:** `172.20.0.25`
  * **Port:** `3000`
  * **Docker Connection:** `DOCKER_HOST=tcp://172.20.0.28:2375`
  * **Disk Monitoring:** Uses internal `/app/config` path to monitor the `dockerapps` volume without extra mounts.

### **C. WUD (Update Notifier)**

  * **IP:** `172.20.0.27`
  * **Port:** `3001`
  * **Watcher:** Custom `PROXY` watcher pointing to `172.20.0.28`.
  * **Registries:** GitHub/LSCR authenticated via `${GITHUB_TOKEN}` in `.env`.

### **D. Portainer (Management)**

  * **IP:** `172.20.0.17`
  * **Port:** `9443`
  * **Connection:** Must be manually connected in UI to `tcp://172.20.0.28:2375`.

### **E. Dozzle (Log Viewer)**

  * **IP:** `172.20.0.26`
  * **Port:** `9090` (Mapped to host 8080)
  * **Connection:** `DOCKER_HOST=tcp://172.20.0.28:2375`

**File:** [`compose`](/utilities/compose.yml)

-----

## 3\. Maintenance

**Update Command:**

```bash
cd /mnt/pool01/dockerapps/utilities
docker compose pull
docker compose up -d --force-recreate
```

**Troubleshooting:**

  * **"Connection Refused" on Portainer:** Ensure `socket-proxy` is running and `POST=0` is set (Read-Only).
  * **WUD "ENOENT" Error:** Ensure `WUD_WATCHER_LOCAL_SOCKET` is removed and `WUD_WATCHER_PROXY_HOST` is set.

## **Special Case: Homepage x CrowdSec**

Unlike other apps, the CrowdSec widget connects directly to the Local API (LAPI). It requires the **Machine Login/Password**, not an API key.

  * **Where to find credentials:** `/mnt/pool01/dockerapps/crowdsec/config/local_api_credentials.yaml` on the host.