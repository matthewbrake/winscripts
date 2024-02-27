<#
    This is an attempt at a script to provision a DC VM in a disposable testlab
    This will also set the DC as authoritative time source, DHCP, and DNS server
    Windows Server® 2012 and 2012 R2 Core Network Guide
    https://gallery.technet.microsoft.com/Windows-Server-2012-and-7c5fe8ea
#>

# rename the computer and reboot, this isn't needed if using Vagrant
#Rename-Computer -NewName newhost -Restart -Force

$domain = "mort.lab"
$host = $env:COMPUTERNAME
$ip = "10.11.1.11" #Read-Host "Enter the IP for this host, e.g. 10.11.1.x: "
$gateway = "10.11.1.1"

# set timezone
tzutil /s 'Pacific Standard Time'

# disable DHCP
Get-NetAdapter | Set-NetAdapter -Dhcp Disabled
# set a static IP on the interface, would need some logic on a physical host
Get-NetAdapter | New-NetIPAddress -AddressFamily IPv4 -IPAddress $ip  -PrefixLength 24 -Type Unicast -DefaultGateway $gateway
# set DNS to GoogleDNS, only works if we have an outside connection
Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter).ifindex -ServerAddresses ("8.8.8.8","8.8.4.4")


# install Active Directory Domain Services
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# create a new forest with Windows Server 2012 R2 domain and forest functional level
Install-ADDSForest -DomainName $domain -DomainNetbiosName "MORTLAB" -ForestMode Win2012R2 -DomainMode Win2012R2

# create the forward lookup zone for DNS
Add-DnsServerPrimaryZone -ReplicationScope Forest -Name $domain -DynamicUpdate Secure
# create a reverse lookup zone for DNS
Add-DnsServerPrimaryZone -ReplicationScope Forest -NetworkId "10.11.1.0/24" -DynamicUpdate Secure

# set up the DC as the authoritative time source, we'll use ntp.org servers to sync with
# info about w32tm https://technet.microsoft.com/en-us/library/w32tm.aspx
w32tm.exe /config /manualpeerlist:"0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org" /syncfromflags:manual /reliable:YES /update
w32tm.exe /config /update
Restart-Service w32time

# if we need to bring up a new PDC and demote this one, we'll need to revert it to normal time sync
#w32tm.exe /config /syncfromflags:Domhier /reliable:NO /update
#w32tm.exe /config /update
#Restart-Service w32time

# Enable AD Recycle BIN:
Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $domain -Confirm:$False

# Add DHCP
Add-WindowsFeature DHCP -IncludeManagementTools
# Bind the DHCP to listen on the correct Interface
Set-DhcpServerv4Binding -BindingState $true -InterfaceAlias "Local Area Connection"
# Authorize with the DC
Add-DhcpServerInDC -DnsName dc01.mort.lab -IPAddress $ip
# DHCP configuration: Add a Dhcpv4 Scope for the clients
Add-DhcpServerv4Scope -Name "mortlab" -StartRange 10.11.1.1 -EndRange 10.11.1.254 -SubnetMask 255.255.255.0 -State Active
# DHCP configuration: Set Exclusions for the Dhcpv4 scope
Add-Dhcpserverv4ExclusionRange -ScopeId 10.11.1.0 -StartRange 10.11.1.1 -EndRange 10.11.1.100
Add-Dhcpserverv4ExclusionRange -ScopeId 10.11.1.0 -StartRange 10.11.1.200 -EndRange 10.11.1.254
# DHCP configuration: Set Dhcpv4 Scope Option for Gateway (to satisfy BPA for DHCP)
Set-DhcpServerv4OptionValue -OptionId 3 -Value $gateway -ScopeId 10.11.1.0
# DHCP configuration: Set Dhcpv4 Option for DNS
Set-DhcpServerv4OptionValue -OptionId 6 -Value $ip
# DHCP configuration: Set Dhcpv4 Option for DNS Server prefix
Set-DhcpServerv4OptionValue -OptionId 15 -Value $domain

# DHCP configuration: Because the DHCP Post-Deployment Configuration wizard will complain that it has not been run
# we must update the registry, not needed if installing on CORE
#Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2
