# Linux User Account Enable and Disable Guide

This guide explains how to **temporarily disable a Linux user account without deleting the account, home directory, or user files**.

The main goal is to prevent the user from logging in while preserving the account so it can be safely re-enabled later.

> **Important:** For this scenario, deleting the user with `userdel` is usually not recommended.

---

## 1. Define the Username

The examples in this guide use the `USERNAME` variable.

Example:

```bash
USERNAME="masoud"
```

Before making any changes, verify that the user exists:

```bash
id "$USERNAME"
```

---

# Disabling a User Account

## 2. Lock the Password

The following command locks the user's password:

```bash
sudo usermod -L "$USERNAME"
```

Alternatively:

```bash
sudo passwd -l "$USERNAME"
```

### What does this do?

It locks the password hash in `/etc/shadow`, preventing normal password-based login.

> **Important:** Password locking alone does not always prevent login through SSH public keys or other authentication methods.

For a more complete account disable operation, account expiration is also recommended.

---

## 3. Expire the Account

To immediately expire the account:

```bash
sudo chage -E 0 "$USERNAME"
```

This marks the account as expired and blocks new logins.

To check the expiration status:

```bash
sudo chage -l "$USERNAME"
```

---

## 4. Disable the Interactive Shell

If you also want to prevent interactive shell access, change the user's shell to `nologin`.

First, check the location of `nologin`:

```bash
command -v nologin
```

On Ubuntu/Debian systems, it is commonly:

```bash
/usr/sbin/nologin
```

Then run:

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

Verify the change:

```bash
getent passwd "$USERNAME"
```

> Changing the shell is not required in every scenario. If the account is used by a service or automation process, verify that changing the shell will not break anything.

---

# Terminating Existing Sessions

## 5. Check Current Sessions

Disabling an account does **not necessarily terminate sessions that are already open**.

Check active sessions with:

```bash
who
```

```bash
w
```

On systemd-based systems:

```bash
loginctl list-sessions
```

---

## 6. Terminate the User's Sessions

On systemd-based systems:

```bash
sudo loginctl terminate-user "$USERNAME"
```

A more aggressive method is:

```bash
sudo pkill -KILL -u "$USERNAME"
```

> **Warning:**  
> `pkill -KILL -u USERNAME` terminates every process owned by that user.  
> If the user owns a service, script, scheduled job, container, or application process, this may cause an outage.

Before using it, review the user's running processes:

```bash
ps -u "$USERNAME" -f
```

---

# Checking Account Status

## 7. Check Password Status

```bash
sudo passwd -S "$USERNAME"
```

Example output:

```text
masoud L ...
```

The `L` typically means the password is locked.

---

## 8. Check Account Expiration

```bash
sudo chage -l "$USERNAME"
```

---

## 9. Check the Login Shell

```bash
getent passwd "$USERNAME"
```

Example:

```text
masoud:x:1001:1001::/home/masoud:/usr/sbin/nologin
```

---

# Recommended Temporary Disable Procedure

For a normal human user account that should be temporarily disabled without deleting files:

```bash
USERNAME="masoud"

sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

If interactive shell access should also be blocked:

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

If existing sessions must also be terminated:

```bash
sudo loginctl terminate-user "$USERNAME"
```

Or, after reviewing the user's processes:

```bash
sudo pkill -KILL -u "$USERNAME"
```

---

# Re-Enabling the User Account

## 10. Unlock the Password

```bash
sudo usermod -U "$USERNAME"
```

Alternatively:

```bash
sudo passwd -u "$USERNAME"
```

---

## 11. Remove Account Expiration

```bash
sudo chage -E -1 "$USERNAME"
```

---

## 12. Restore the Login Shell

If the user's previous shell was `/bin/bash`:

```bash
sudo usermod -s /bin/bash "$USERNAME"
```

> If the user previously used a different shell, restore the original one instead.

To view valid shells:

```bash
cat /etc/shells
```

---

# Complete Re-Enable Procedure

```bash
USERNAME="masoud"

sudo usermod -U "$USERNAME"
sudo chage -E -1 "$USERNAME"
sudo usermod -s /bin/bash "$USERNAME"
```

Then verify the account:

```bash
sudo passwd -S "$USERNAME"
sudo chage -l "$USERNAME"
getent passwd "$USERNAME"
```

---

# Home Directory and Files

The methods described in this guide do **not** delete:

- The user's home directory
- User files and directories
- UID and GID
- Group memberships
- File ownership
- SSH keys
- Cron jobs
- User configuration files

Example:

```bash
ls -ld "/home/$USERNAME"
```

Disabling an account is therefore very different from deleting the account.

---

# Important Security Notes

## SSH Public Key Authentication

The following command:

```bash
sudo usermod -L "$USERNAME"
```

locks the password only.

It should **not** be considered a complete method for blocking every possible login mechanism.

For a normal user account, this combination is generally more reliable:

```bash
sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

And if needed:

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

---

## Service Accounts

Before disabling an account, verify that no important application or service is running under its UID:

```bash
ps -u "$USERNAME" -f
```

You can also inspect files owned by the user:

```bash
sudo find / -xdev -user "$USERNAME" -ls 2>/dev/null
```

---

# Quick Pre-Disable Check

```bash
USERNAME="masoud"

id "$USERNAME"
getent passwd "$USERNAME"
ps -u "$USERNAME" -f
sudo passwd -S "$USERNAME"
sudo chage -l "$USERNAME"
```

---

# Command Summary

| Operation | Command |
|---|---|
| Lock password | `sudo usermod -L USERNAME` |
| Unlock password | `sudo usermod -U USERNAME` |
| Expire account | `sudo chage -E 0 USERNAME` |
| Remove expiration | `sudo chage -E -1 USERNAME` |
| Disable shell | `sudo usermod -s /usr/sbin/nologin USERNAME` |
| Restore Bash | `sudo usermod -s /bin/bash USERNAME` |
| View password status | `sudo passwd -S USERNAME` |
| View account aging | `sudo chage -l USERNAME` |
| View user processes | `ps -u USERNAME -f` |
| Terminate systemd user sessions | `sudo loginctl terminate-user USERNAME` |
| Kill all user processes | `sudo pkill -KILL -u USERNAME` |

---

# Practical Recommendation

For **temporarily disabling a normal human user account** while preserving all files and ownership information, the following commands are usually sufficient:

```bash
sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

If interactive shell access should also be disabled:

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

Use `userdel` only when the account should actually be removed and your organization's data-retention policy allows it.
