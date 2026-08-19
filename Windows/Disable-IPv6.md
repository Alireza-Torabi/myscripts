# Disable IPv6 on Windows Using PowerShell

Open **PowerShell as Administrator** and run the following command:

```powershell
Get-NetAdapterBinding -ComponentID ms_tcpip6 |
Where-Object Enabled -eq $true |
ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
}

Write-Host "IPv6 has been disabled on all network adapters."
```

## Re-enable IPv6

To enable IPv6 again on all network adapters:

```powershell
Get-NetAdapter |
ForEach-Object {
    Enable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
}
```

> **Note:** This disables the IPv6 binding (`ms_tcpip6`) on network adapters. Completely disabling IPv6 at the Windows system level is generally not recommended because some Windows components and services may depend on it.
