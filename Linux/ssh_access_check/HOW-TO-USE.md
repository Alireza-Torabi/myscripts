# How to Use SSH Access Checker

This guide explains how to prepare, run, verify, and troubleshoot `ssh_access_check.sh` on Linux.

**Type:** How-to Guide  
**Version:** 1.2.0  
**Status:** Active  
**Last Updated:** 2026-09-14  
**Environment:** Linux

## 1. Prepare the Files

Place the script in a working directory:

```text
ssh-access-checker/
├── ssh_access_check.sh
├── ips.txt
├── README.md
└── HOW-TO-USE.md
```

The target list does not need to be named `ips.txt`; any readable text file can be used.

## 2. Make the Script Executable

Run:

```bash
chmod +x ssh_access_check.sh
```

Verify the permission:

```bash
ls -l ssh_access_check.sh
```

A typical result is:

```text
-rwxr-xr-x 1 user user 12345 Sep 13 11:30 ssh_access_check.sh
```

The important part is that the executable bit (`x`) is present.

## 3. Create the Target List

Create a file:

```bash
nano ips.txt
```

Add one IP address or hostname per line:

```text
192.168.10.10
192.168.10.11
192.168.10.12
server01.example.local
```

Comments and blank lines are allowed:

```text
# Production
192.168.10.10
192.168.10.11

# Test environment
192.168.20.10
```

Save the file.

## 4. Verify Credentials Before a Large Run

Before testing a large inventory, manually verify the username/password on one known target.

Example:

```bash
ssh admin@192.168.10.10
```

This is especially important when centralized authentication or account-lockout policies are in use.

Exit the manual SSH session after verification:

```bash
exit
```

## 5. Run the Script

### Method A: Provide the Target File as an Argument

```bash
./ssh_access_check.sh ips.txt
```

### Method B: Select the Target File Interactively

```bash
./ssh_access_check.sh
```

### Plain Output Mode

To disable the live dashboard and use normal line-by-line output:

```bash
./ssh_access_check.sh --plain ips.txt
```

The script will then ask:

```text
Enter the path to the IP address list file:
```

Example:

```text
Enter the path to the IP address list file: ./ips.txt
```

## 6. Enter the SSH Username

Example:

```text
Enter the SSH username: admin
```

The username must not be empty.

## 7. Enter the SSH Password

Example:

```text
Enter the SSH password:
```

Nothing is displayed while the password is typed. This is intentional.

Press `Enter` after typing the password.

## 8. Select the SSH Port

The default SSH port is `22`:

```text
Enter the SSH port [22]:
```

Press `Enter` to use port `22`.

For a custom port, enter the required value:

```text
Enter the SSH port [22]: 2222
```

## 9. Select the Connection Timeout

The default connection timeout is `8` seconds:

```text
Enter the connection timeout in seconds [8]:
```

Press `Enter` to accept the default.

For slow or remote networks, a larger timeout can be used:

```text
Enter the connection timeout in seconds [8]: 15
```

Avoid unnecessarily large timeout values because unreachable hosts will make the complete scan take significantly longer.

## 9A. Select the Number of Concurrent Workers

The default is `5` parallel SSH workers:

```text
Enter the number of concurrent SSH workers [5]:
```

Press `Enter` to use the recommended default.

Parallel workers reduce total scan time, but increasing the value also increases simultaneous authentication attempts. High values can trigger account-lockout policies, SSH rate limits, IDS/IPS controls, or transient connection failures. Start with `5` unless the environment is known to tolerate more.

The workers may finish in a different order, but the generated CSV always preserves the exact original order of the target list.

## 10. Select the CSV Output Filename

The script generates a timestamped filename automatically:

```text
Enter the output CSV filename [ssh_access_results_20260913_113000.csv]:
```

Press `Enter` to use the generated filename.

Or enter a custom path:

```text
Enter the output CSV filename [ssh_access_results_20260913_113000.csv]: ./results/production-ssh-test.csv
```

The parent directory must already exist.

## 11. Monitor the Test

By default, the script displays a live dashboard with:

- Overall progress and percentage.
- Configured and currently running workers.
- Accessible, failed, and remaining target counts.
- Elapsed time.
- Recent worker results.

Example:

```text
SSH ACCESS CHECKER v1.2.0 | PARALLEL LIVE DASHBOARD
----------------------------------------------------------------------------------------------------
Workers: 5    Running: 5    CSV order: Input order
Progress: [####################----------------------------] 42% (42/100)
Accessible: 15     Failed: 27     Remaining: 58
----------------------------------------------------------------------------------------------------
RECENT ACTIVITY (completion order; CSV remains in input order)
```

The dashboard is periodically redrawn while the scan runs. This is expected. If this behavior is not desired, run the script with `--plain`.

The `RECENT ACTIVITY` section shows the actual worker completion order, which may not match the source file order. This does not affect the CSV.

## 12. Review the Final Summary

After all targets are processed, the script prints a summary similar to:

```text
=============================================
               FINAL SUMMARY
=============================================
Targets found : 4
Targets tested: 4
Workers used  : 4
Accessible    : 1
Not accessible: 3
Elapsed time  : 00:00:08
CSV ordering  : Input order preserved

[SUCCESS] All targets were processed.
[SUCCESS] CSV order exactly matches the input target order.
[SUCCESS] Results saved to: ssh_access_results_20260914_113000.csv
```

## 13. Review the CSV File

Display it from the terminal:

```bash
cat ssh_access_results_20260913_113000.csv
```

For easier terminal viewing:

```bash
column -s, -t < ssh_access_results_20260913_113000.csv
```

The CSV rows always follow the exact input-file order, regardless of the order in which parallel workers complete.

Example CSV:

```csv
Target,Port,Username,Access,Result,TestedAt
"192.168.10.10","22","admin","YES","ACCESS_OK","2026-09-13 11:35:12 +0330"
"192.168.10.11","22","admin","NO","AUTHENTICATION_FAILED","2026-09-13 11:35:14 +0330"
"192.168.10.12","22","admin","NO","CONNECTION_REFUSED","2026-09-13 11:35:15 +0330"
"192.168.10.20","22","admin","NO","TIMEOUT","2026-09-13 11:35:28 +0330"
```

The file can also be opened in Excel, LibreOffice Calc, Google Sheets, or another CSV-compatible application.

## 14. Understand the Result Field

| Result | Meaning | Recommended Check |
| --- | --- | --- |
| `ACCESS_OK` | Username/password authentication succeeded. | No action required. |
| `AUTHENTICATION_FAILED` | Credentials were rejected. | Verify password, account state, and SSH authentication policy. |
| `CONNECTION_REFUSED` | Target rejected the TCP connection. | Verify SSH service and port. |
| `HOST_UNREACHABLE` | Routing/network path is unavailable. | Check routing, VLANs, gateways, and ACLs. |
| `TIMEOUT` | No successful SSH response before timeout. | Check firewall, routing, address, and target availability. |
| `DNS_ERROR` | Hostname resolution failed. | Check DNS or use the IP address. |
| `HOST_KEY_ERROR` | SSH host-key verification failed. | Investigate the host identity before retrying. |
| `CONNECTION_CLOSED` | Remote host closed/reset the connection. | Check SSH server logs and security controls. |
| `SSH_NEGOTIATION_FAILED` | SSH algorithm negotiation failed. | Compare supported SSH algorithms on the client and server. |
| `SSH_PROTOCOL_ERROR` | SSH handshake or protocol negotiation failed. | Check the remote service and SSH server logs. |
| `SSH_CLIENT_ERROR` | Local SSH client configuration/option error. | Review local SSH configuration and options. |
| `SSHPASS_ERROR` | `sshpass` could not parse the SSH response. | Review the target SSH behavior and client output. |
| `WORKER_ERROR` | A parallel worker ended without a normal result. | Retry the target and inspect the local environment. |
| `SSH_ERROR` | Unclassified SSH failure. | Review the displayed SSH error detail. |

## 15. Automatic Dependency Installation

The script checks for:

```text
ssh
sshpass
timeout
```

If a dependency is missing, it attempts installation using the detected package manager.

Examples of package mappings include:

### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y openssh-client sshpass coreutils
```

### Fedora / RHEL-Compatible Systems

```bash
sudo dnf install -y openssh-clients sshpass coreutils
```

### Older YUM-Based Systems

```bash
sudo yum install -y openssh-clients sshpass coreutils
```

### openSUSE / SUSE

```bash
sudo zypper --non-interactive install openssh sshpass coreutils
```

### Arch Linux

```bash
sudo pacman -S --needed --noconfirm openssh sshpass coreutils
```

### Alpine Linux

```bash
sudo apk add --no-cache openssh-client sshpass coreutils
```

The exact package names and package availability can vary between distribution versions and configured repositories.

## 16. Common Problems

### `sshpass` Cannot Be Installed

On some RHEL/CentOS-compatible systems, `sshpass` may not exist in the currently enabled repositories.

Check package availability:

```bash
dnf search sshpass
```

or:

```bash
yum search sshpass
```

Use only repositories approved for the system being administered.

### Permission Denied

Example:

```text
Permission denied, please try again.
```

Check:

1. Username.
2. Password.
3. Account lock/expiration state.
4. `/etc/ssh/sshd_config` authentication settings on the target.
5. PAM, LDAP, or Active Directory authentication policies.

### Connection Refused

Check whether SSH is listening on the remote system:

```bash
sudo ss -lntp | grep ssh
```

or:

```bash
sudo systemctl status sshd
```

On Debian/Ubuntu systems, the service may be named `ssh`:

```bash
sudo systemctl status ssh
```

### Timeout

Test basic IP connectivity where ICMP is permitted:

```bash
ping -c 4 192.168.10.10
```

Test the SSH TCP port:

```bash
nc -vz 192.168.10.10 22
```

If `nc` is unavailable, SSH itself can be used for diagnosis:

```bash
ssh -vvv admin@192.168.10.10
```

### Password Authentication Is Disabled

A server may allow SSH keys but reject password authentication.

Check the SSH server configuration for settings such as:

```text
PasswordAuthentication no
```

The script intentionally tests password-based authentication and will not fall back to an existing SSH key.

## 17. Security Notes

Do not place passwords in:

- The target list.
- Script arguments.
- Git commits.
- README files.
- Shell scripts.
- CSV output.

The password is requested interactively and is not intentionally persisted by the script.

If a shared or centralized account is subject to lockout rules, do not repeatedly test a known-invalid password against a large host list. Parallel workers can reach the lockout threshold faster, so verify the credential first and use conservative worker counts.

## 18. Suggested Git Usage

Initialize a repository if needed:

```bash
git init
```

Add the documentation and script:

```bash
git add README.md HOW-TO-USE.md ssh_access_check.sh
```

Review staged changes:

```bash
git status
```

Commit:

```bash
git commit -m "Add SSH access checker and documentation"
```

Avoid committing production inventory files if they contain sensitive infrastructure information.

For example, add the local target list to `.gitignore`:

```bash
printf '%s\n' 'ips.txt' >> .gitignore
```

Then commit `.gitignore` if appropriate:

```bash
git add .gitignore
git commit -m "Ignore local SSH target list"
```

## 19. Recommended Verification Before Production Use

Before running against a production inventory:

1. Test the script with two or three non-critical systems.
2. Confirm that successful credentials return `ACCESS_OK`.
3. Intentionally test one unreachable address and verify timeout handling.
4. Confirm the generated CSV is correct.
5. Verify account-lockout policy for the SSH account.
6. Confirm that the scan is authorized for the target environment.
7. Start with the default `5` workers and increase concurrency only after confirming that authentication, SSH rate limits, and security controls are not being triggered.
8. Confirm that the final CSV order matches the original target-file order.

After these checks, run the larger target list.
