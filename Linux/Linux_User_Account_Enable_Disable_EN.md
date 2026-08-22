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


# Identifying Disabled User Accounts

Linux does not have one universal account state called `Disabled User`. A user account may be disabled in one or more of the following ways:

- The password is locked.
- The account is expired.
- The login shell is set to `nologin` or `false`.
- A combination of the above is applied.

For accurate results, check all relevant account states.

---

## List Accounts with Locked Passwords

```bash
sudo passwd -Sa | awk '$2=="L"'
```

To display usernames only:

```bash
sudo passwd -Sa | awk '$2=="L" {print $1}'
```

> This output may also include system accounts.

---

## List Normal Users with Locked Passwords

On many Linux distributions, normal user accounts typically have a UID of `1000` or higher.

```bash
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' |
while read user; do
    status=$(sudo passwd -S "$user" 2>/dev/null | awk '{print $2}')
    if [ "$status" = "L" ]; then
        echo "$user"
    fi
done
```

---

## List Accounts with Disabled Login Shells

To find users whose login shell is set to `nologin` or `false`:

```bash
getent passwd | awk -F: '$7 ~ /(nologin|false)$/ {print $1, $3, $7}'
```

Example:

```text
masoud 1001 /usr/sbin/nologin
```

---

## Check Account Expiration for a Specific User

```bash
sudo chage -l masoud
```

Look for:

```text
Account expires : ...
```

---

## Display Full Status for Normal Users

The following command displays password status, account expiration, and login shell for all normal users:

```bash
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' |
while read user; do
    status=$(sudo passwd -S "$user" 2>/dev/null | awk '{print $2}')
    expire=$(sudo chage -l "$user" 2>/dev/null | awk -F': ' '/Account expires/{print $2}')
    shell=$(getent passwd "$user" | cut -d: -f7)

    printf "%-20s Password=%-3s Expire=%-15s Shell=%s\n" \
        "$user" "$status" "$expire" "$shell"
done
```

Example output:

```text
reza                 Password=P   Expire=never           Shell=/bin/bash
masoud               Password=L   Expire=Jan 01, 1970    Shell=/usr/sbin/nologin
ali                   Password=P   Expire=never           Shell=/bin/bash
```

In this output:

- `P` means the password is usable.
- `L` means the password is locked.
- `Expire=never` means the account does not expire.
- `/usr/sbin/nologin` means interactive shell login is disabled.

---

## Recommended Indicators of a Fully Disabled Account

If the account was disabled using the full procedure in this runbook, you will typically see:

```text
Password=L
Account expired
Shell=/usr/sbin/nologin
```

If only the recommended `Lock + Expire` method was used, the login shell may still remain `/bin/bash`.

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
