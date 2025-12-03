# 🔔 Service: Gotify (Notification Hub)

**Location:** `/mnt/pool01/dockerapps/gotify` \
**Network:** `dockerapps-net` (Static IP: `172.20.0.16`) \
**URL:** `https://gotify.mydomain.xyz` (Public) / `http://172.20.0.16:80` (Internal) \

Gotify acts as the central nervous system for the server. It receives alerts from all automation apps and pushes them instantly to our mobile devices via WebSocket.

## 1\. Docker Configuration

The service is lightweight, running on the official image with minimal configuration.

**File:** [`compose.yml`](/gotify/compose.yml)

## 2\. Integration Map (Tokens)

Gotify uses two types of tokens. It is critical to use the correct one for each task.

### **A. Application Tokens (Starts with `A...`)**

*Used by services to **SEND** messages.*

| Service | Integration Method | Notes |
| :--- | :--- | :--- |
| **Jellyfin** | **Webhook Plugin** | Uses custom JSON templates for rich notifications. |
| **Radarr** | Native (Connect -\> Gotify) | "On Grab", "On Import", "On Upgrade". |
| **Sonarr** | Native (Connect -\> Gotify) | "On Grab", "On Import", "On Upgrade". |
| **Jellyseerr** | Native (Notifications) | "Request Pending", "Request Approved". |
| **WUD** | Native (Triggers) | "New Image Available". |

### **B. Client Tokens (Starts with `C...`)**

*Used by devices to **RECEIVE** messages.*

| Client | Usage |
| :--- | :--- |
| **Android App** | Real-time push notifications on your phone. |
| **Homepage** | Displays unread message count on the dashboard widget. |

-----

## 3\. Jellyfin Webhook Configuration (The "Deep Dive")

Jellyfin does not have native Gotify support. We use the **"Webhook"** plugin to bridge the gap.

### **Step 1: Install Plugin**

  * **Jellyfin Dashboard** -\> **Plugins** -\> **Catalog** -\> Install **Webhook**.
  * Restart Jellyfin.

### **Step 2: Configure Destination**

  * **Navigate:** Dashboard -\> Plugins -\> Webhook.
  * **Add Destination:** Select **"Gotify"**.
  * **Webhook Url:** `http://172.20.0.16:80/message?token=<YOUR_APP_TOKEN>`
      * *Note: Uses the internal static IP to bypass routing issues.*

### **Step 3: Configure Templates (The Logic)**

This is where we define *what* the notification looks like. We use the official templates from the [Jellyfin Webhook Repository](https://github.com/jellyfin/jellyfin-plugin-webhook/tree/master/Jellyfin.Plugin.Webhook/Templates/Gotify).

**Why Templates?**
Raw webhooks are ugly JSON blobs. Templates format them into readable text like:

> **Playback Started**
> *User: name*
> *Item: Inception (2010)*
> *Device: Android TV*

**Configuration:**

1.  **Playback Start:**
      * **Item Type:** `Movies`, `Episodes`
      * **Template:** (Copy from `Templates/Gotify/PlaybackStart.handlebars`)
2.  **Playback Stop:**
      * **Item Type:** `Movies`, `Episodes`
      * **Template:** (Copy from `Templates/Gotify/PlaybackStop.handlebars`)

-----

## 4\. Security & Access

  * **Ingress:** Accessed via **Caddy Reverse Proxy** (`https://gotify.mydomain.xyz`).
  * **Protection:** Secured by **CrowdSec** and **GeoIP (Singapore Only)**.
  * **WebSocket:** Caddy automatically upgrades the connection to WebSocket (`wss://`), allowing real-time pushes without polling.

## 5\. Maintenance

  * **Database:** `gotify.db` (SQLite) is stored in `./data`. It is included in the weekly `rclone` backup.
  * **Image Storage:** Uploaded images (for app icons) are also stored in `./data/images`.
  * **Troubleshooting:** If notifications stop, check the **App Token** in the sending service (e.g., Radarr) and ensure it matches the one in Gotify.
