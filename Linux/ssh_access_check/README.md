# SSH Access Checker

A Bash utility for testing SSH username/password access against a list of Linux hosts and exporting the results to CSV.

**Type:** Repository README  
**Version:** 1.2.0  
**Status:** Active  
**Last Updated:** 2026-09-14  
**Environment:** Linux  
**License:** <LICENSE>

## Overview

`ssh_access_check.sh` reads a list of IP addresses or hostnames, prompts for SSH credentials, tests targets with controlled parallel SSH workers, displays a live terminal dashboard, and writes the final results to a CSV file in the exact original input order.

The script is designed for system administrators who need to verify whether the same SSH account can authenticate to multiple Linux systems.

> Use this script only on systems you own or are explicitly authorized to administer.

## Features

- Reads targets from a plain-text file.
- Accepts IPv4 addresses, IPv6-compatible SSH host strings where supported, or DNS hostnames.
- Prompts interactively for:
  - SSH username
  - SSH password
  - SSH port
  - Connection timeout
  - Number of concurrent SSH workers
  - CSV output filename
- Hides the password while it is entered.
- Checks required dependencies before execution.
- Attempts to install missing dependencies automatically.
- Supports common Linux package managers:
  - `apt-get`
  - `dnf`
  - `yum`
  - `zypper`
  - `pacman`
  - `apk`
- Disables public-key authentication during the test so the supplied username/password is actually validated.
- Uses a temporary `known_hosts` file instead of modifying the user's normal SSH configuration.
- Shows a K9s-inspired live terminal dashboard with progress, worker count, elapsed time, and recent activity.
- Supports `--plain` mode for normal line-by-line output.
- Uses controlled parallel SSH workers to reduce total scan time.
- Preserves the exact original target order in the CSV even when workers finish out of order.
- Distinguishes common failure types such as:
  - Authentication failure
  - Connection refused
  - Host unreachable
  - Timeout
  - DNS failure
  - Host key error
  - Connection closed/reset
- Exports results to CSV.

## Repository Structure

```text
.
├── README.md
├── HOW-TO-USE.md
├── ssh_access_check.sh
└── ips.txt                 # Optional local target list; avoid committing sensitive inventories
```

## Requirements

The script requires the following commands:

- `bash`
- `ssh`
- `sshpass`
- `timeout`

Normally, the script checks these dependencies automatically and attempts to install missing packages.

Administrative privileges may be required when a package must be installed. The script uses `sudo` when it is not already running as `root`.

### Package Availability Note

Package availability depends on the Linux distribution and configured repositories. In particular, `sshpass` may not be available in the default repositories of some RHEL/CentOS-compatible systems. If automatic installation fails, install the required package manually from an approved repository before running the script again.

## Input File Format

Create a text file containing one target per line:

```text
192.168.10.10
192.168.10.11
192.168.20.15
server01.example.local
```

Blank lines are ignored.

Comments beginning with `#` are also supported:

```text
# Production servers
192.168.10.10
192.168.10.11

# Development servers
192.168.20.10
```

## Quick Start

Make the script executable:

```bash
chmod +x ssh_access_check.sh
```

Run it with a target file:

```bash
./ssh_access_check.sh ips.txt
```

Or run it without an argument and enter the file path interactively:

```bash
./ssh_access_check.sh
```

For the full procedure, see [`HOW-TO-USE.md`](HOW-TO-USE.md).

## Interactive Prompts

The script asks for values similar to the following:

```text
Enter the SSH username:
Enter the SSH password:
Enter the SSH port [22]:
Enter the connection timeout in seconds [8]:
Enter the number of concurrent SSH workers [5]:
Enter the output CSV filename [ssh_access_results_YYYYMMDD_HHMMSS.csv]:
```

The password is not displayed while typing.

## Example Terminal Output

The default mode uses a live dashboard similar to:

```text
SSH ACCESS CHECKER v1.2.0 | PARALLEL LIVE DASHBOARD
----------------------------------------------------------------------------------------------------
User: admin                  Port: 22    Timeout: 8s    Elapsed: 00:00:18
Workers: 5    Running: 5    CSV order: Input order
Input: ips.txt                            Output: ssh_access_results.csv
----------------------------------------------------------------------------------------------------
Progress: [####################----------------------------] 42% (42/100)
Accessible: 15     Failed: 27     Remaining: 58
----------------------------------------------------------------------------------------------------
RECENT ACTIVITY (completion order; CSV remains in input order)
#     TARGET                 RESULT                      DETAIL
----- ---------------------- --------------------------- -------------------------------
39    192.168.10.39          ACCESS_OK                   Login successful
42    192.168.10.42          TIMEOUT                     Connection or authentication...
40    192.168.10.40          AUTHENTICATION_FAILED       Password authentication rejected
```

The dashboard is periodically redrawn while the scan is running. This is expected behavior. Use `--plain` if a continuously redrawn terminal UI is not desired.

## CSV Output

The generated CSV contains the following columns:

```text
Target,Port,Username,Access,Result,TestedAt
```

Rows are written in the same order as the targets in the input file, even when parallel workers complete in a different order.

Example:

```csv
Target,Port,Username,Access,Result,TestedAt
"192.168.10.10","22","admin","YES","ACCESS_OK","2026-09-13 11:35:12 +0330"
"192.168.10.11","22","admin","NO","AUTHENTICATION_FAILED","2026-09-13 11:35:14 +0330"
"192.168.10.12","22","admin","NO","CONNECTION_REFUSED","2026-09-13 11:35:15 +0330"
"192.168.10.20","22","admin","NO","TIMEOUT","2026-09-13 11:35:28 +0330"
```

## Result Codes

| Result | Meaning |
| --- | --- |
| `ACCESS_OK` | Authentication succeeded and the remote command completed successfully. |
| `AUTHENTICATION_FAILED` | The supplied credentials were rejected. |
| `CONNECTION_REFUSED` | The host responded, but the SSH port refused the connection. |
| `HOST_UNREACHABLE` | No route to the host or network was available. |
| `TIMEOUT` | The SSH connection or authentication attempt exceeded the configured timeout. |
| `DNS_ERROR` | The supplied hostname could not be resolved. |
| `HOST_KEY_ERROR` | SSH host-key verification failed. |
| `CONNECTION_CLOSED` | The remote side closed or reset the SSH connection. |
| `SSH_NEGOTIATION_FAILED` | SSH algorithm negotiation failed. |
| `SSH_PROTOCOL_ERROR` | SSH handshake or protocol negotiation failed. |
| `SSH_CLIENT_ERROR` | The local SSH client reported a configuration or option error. |
| `SSHPASS_ERROR` | `sshpass` could not parse the SSH response. |
| `WORKER_ERROR` | A parallel worker terminated without producing a normal result. |
| `SSH_ERROR` | SSH failed for a reason that did not match one of the known classifications. |

## Security Considerations

### Credentials

The SSH password is entered interactively and is not written to the CSV file.

Do not:

- Hard-code passwords in the script.
- Put credentials in `ips.txt`.
- Commit credentials to Git.
- Store real credentials in documentation or shell history.

### Account Lockout Risk

If the same account is managed by LDAP, Active Directory, PAM, or another centralized authentication system, repeated failed authentication attempts can trigger an account lockout policy.

Verify the credentials on a known system before testing a large target list. Parallel workers can reach an account-lockout threshold faster than sequential execution, so start with the default value of `5` unless the authentication and security policies are known.

### Password Authentication

The script intentionally disables SSH public-key authentication during each test. This ensures that `ACCESS_OK` means the supplied username/password worked rather than an existing SSH key.

A target configured with password authentication disabled will therefore fail this test even if key-based SSH access is available.

### Host Keys

The script uses a temporary `known_hosts` file. New host keys can be accepted for the duration of the script without modifying the user's normal `~/.ssh/known_hosts` file.

## Limitations

- The script tests username/password SSH authentication only.
- It does not validate sudo privileges after login.
- It does not test SSH key authentication.
- It does not automatically discover hosts on a network.
- Package installation depends on the repositories configured on the local Linux system.
- Network firewalls, ACLs, IDS/IPS systems, rate limits, and SSH server policies can affect the result.
- High worker counts can increase transient failures or trigger rate limiting and account-lockout controls.
- The dashboard recent-activity list is shown in worker completion order; the CSV remains in original input order.

## Recommended Usage

The default value of `5` concurrent workers is the recommended starting point for small and medium inventories. It normally provides a meaningful speed improvement without creating aggressive connection pressure.

Increase concurrency carefully. Higher worker counts can trigger SSH rate limits, IDS/IPS controls, or centralized account-lockout policies, especially when credentials are invalid. Values above `10` should be used only when the environment and authentication policies are understood.

## Troubleshooting

If the script reports `AUTHENTICATION_FAILED`:

1. Verify the username and password manually on one known host.
2. Confirm that password authentication is enabled in the remote SSH server configuration.
3. Confirm that the account is not locked or expired.

If the script reports `CONNECTION_REFUSED`:

1. Verify that `sshd` is running on the remote host.
2. Confirm the SSH port.
3. Check host firewall rules.

If the script reports `TIMEOUT` or `HOST_UNREACHABLE`:

1. Check routing and network connectivity.
2. Verify firewall and ACL rules.
3. Confirm that the target address is correct.

If dependency installation fails:

1. Verify Internet or repository access.
2. Confirm that the package manager is working.
3. Install `openssh-client`/`openssh-clients`, `sshpass`, and `coreutils` manually as appropriate for the distribution.

## License

No license has been specified yet.

Before publishing the repository for public reuse, replace `<LICENSE>` with the license you choose and add the corresponding `LICENSE` file.
