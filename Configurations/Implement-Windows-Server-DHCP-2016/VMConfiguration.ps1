<# Notes:

Authors: Jason Helmick and Melissa (Missy) Januszko

The bulk of this DC, DHCP, ADCS config is authored by Melissa (Missy) Januszko and Jason Helmick.
Currently on her public DSC hub located here: https://github.com/majst32/DSC_public.git

Additional contributors of note: Jeff Hicks

Disclaimer

This example code is provided without copyright and AS IS.  It is free for you to use and modify.

#>

Configuration AutoLab {

    $LabData = Import-PowerShellDataFile -Path $psscriptroot\*.psd1
    $Secure = ConvertTo-SecureString -String "$($labdata.allnodes.labpassword)" -AsPlainText -Force
    $credential = New-Object -TypeName Pscredential -ArgumentList Administrator, $secure

    #region DSC Resources
    Import-DSCresource -ModuleName "PSDesiredStateConfiguration" -ModuleVersion "1.1"
    Import-DSCResource -modulename "xPSDesiredStateConfiguration" -ModuleVersion  "9.1.0"
    Import-DSCResource -modulename "xActiveDirectory" -ModuleVersion  "3.0.0.0"
    Import-DSCResource -modulename "xComputerManagement" -ModuleVersion  "4.1.0.0"
    Import-DSCResource -modulename "xNetworking" -ModuleVersion  "5.7.0.0"
    Import-DSCResource -modulename "xDhcpServer" -ModuleVersion  "3.0.0"
    Import-DSCResource -modulename 'xWindowsUpdate' -ModuleVersion  '2.8.0.0'
    Import-DSCResource -modulename 'xADCSDeployment' -ModuleVersion  '1.4.0.0'
    #endregion
    #region All Nodes
    node $AllNodes.Where({ $true }).NodeName {
        #endregion
        #region LCM configuration

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true
            AllowModuleOverwrite = $true
            ConfigurationMode    = 'ApplyOnly'
        }

        #endregion

        #region TLS Settings in registry

        registry TLS {
            Ensure    = "present"
            Key       = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319'
            ValueName = 'SchUseStrongCrypto'
            ValueData = '1'
            ValueType = 'DWord'
        }

        #endregion

        #region IPaddress settings

        If (-not [System.String]::IsNullOrEmpty($node.IPAddress)) {
            xIPAddress 'PrimaryIPAddress' {
                IPAddress      = $node.IPAddress
                InterfaceAlias = $node.InterfaceAlias
                AddressFamily  = $node.AddressFamily
            }

            If (-not [System.String]::IsNullOrEmpty($node.DefaultGateway)) {
                xDefaultGatewayAddress 'PrimaryDefaultGateway' {
                    InterfaceAlias = $node.InterfaceAlias
                    Address        = $node.DefaultGateway
                    AddressFamily  = $node.AddressFamily
                }
            }

            If (-not [System.String]::IsNullOrEmpty($node.DnsServerAddress)) {
                xDnsServerAddress 'PrimaryDNSClient' {
                    Address        = $node.DnsServerAddress
                    InterfaceAlias = $node.InterfaceAlias
                    AddressFamily  = $node.AddressFamily
                }
            }

            If (-not [System.String]::IsNullOrEmpty($node.DnsConnectionSuffix)) {
                xDnsConnectionSuffix 'PrimaryConnectionSuffix' {
                    InterfaceAlias           = $node.InterfaceAlias
                    ConnectionSpecificSuffix = $node.DnsConnectionSuffix
                }
            }
        } #End IF

        #endregion

        #region Firewall Rules


        $LabData = Import-PowerShellDataFile -Path $psscriptroot\*.psd1
        $FireWallRules = $labdata.Allnodes.FirealllRuleNames

        foreach ($Rule in $FireWallRules) {
            xFirewall $Rule {
                Name    = $Rule.name
                Enabled = 'True'
            }
        } #End foreach

    } #end Firewall Rules
    #endregion

    #region Domain Controller config

    node $AllNodes.Where({ $_.Role -eq 'DC' }).NodeName {

        $DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("$($node.DomainName)\$($Credential.UserName)", $Credential.Password)

        xComputer ComputerName {
            Name = $Node.NodeName
        }

        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in @(
                'DNS',
                'AD-Domain-Services',
                'RSAT-AD-Tools',
                'RSAT-AD-PowerShell'
                #For Gui, might like
                #'RSAT-DNS-Server',
                #'GPMC,
                #'RSAT-AD-AdminCenter',
                #'RSAT-ADDS-Tools'

            )) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
            }
        } #End foreach

        xADDomain FirstDC {
            DomainName                    = $Node.DomainName
            DomainAdministratorCredential = $Credential
            SafemodeAdministratorPassword = $Credential
            DatabasePath                  = $Node.DCDatabasePath
            LogPath                       = $Node.DCLogPath
            SysvolPath                    = $Node.SysvolPath
            DependsOn                     = '[WindowsFeature]ADDomainServices'
        }

        #Add OU, Groups, and Users
        $OUs = (Get-Content $PSScriptRoot\AD-OU.json | ConvertFrom-Json)
        $Users = (Get-Content $PSScriptRoot\AD-Users.json | ConvertFrom-Json)
        $Groups = (Get-Content $PSScriptRoot\AD-Group.json | ConvertFrom-Json)

        foreach ($OU in $OUs) {
            xADOrganizationalUnit $OU.Name {
                Path                            = $node.DomainDN
                Name                            = $OU.Name
                Description                     = $OU.Description
                ProtectedFromAccidentalDeletion = $False
                Ensure                          = "Present"
                DependsOn                       = '[xADDomain]FirstDC'
            }
        } #OU

        foreach ($user in $Users) {

            xADUser $user.samaccountname {
                Ensure                        = "Present"
                Path                          = $user.distinguishedname.split(",", 2)[1]
                DomainName                    = $node.domainname
                Username                      = $user.samaccountname
                GivenName                     = $user.givenname
                Surname                       = $user.Surname
                DisplayName                   = $user.Displayname
                Description                   = $user.description
                Department                    = $User.department
                Enabled                       = $true
                Password                      = $DomainCredential
                DomainAdministratorCredential = $DomainCredential
                PasswordNeverExpires          = $True
                DependsOn                     = '[xADDomain]FirstDC'
            }
        } #user

        Foreach ($group in $Groups) {
            xADGroup $group.Name {
                GroupName  = $group.name
                Ensure     = 'Present'
                Path       = $group.distinguishedname.split(",", 2)[1]
                Category   = $group.GroupCategory
                GroupScope = $group.GroupScope
                Members    = $group.members
                DependsOn  = '[xADDomain]FirstDC'
            }
        }

        #prestage Web Server Computer objects

        [string[]]$WebServers = $Null

        foreach ($N in $AllNodes) {
            if ($N.Role -eq "Web") {

                $WebServers = $WebServers + "$($N.NodeName)$"

                xADComputer "CompObj_$($N.NodeName)" {
                    ComputerName                  = "$($N.NodeName)"
                    DependsOn                     = '[xADOrganizationalUnit]Servers'
                    DisplayName                   = $N.NodeName
                    Path                          = "OU=Servers,$($N.DomainDN)"
                    Enabled                       = $True
                    DomainAdministratorCredential = $DomainCredential
                }
            }
        }

        #add Web Servers group with Web Server computer objects as members

        If ($WebServers -ne $Null) {

            xADGroup WebServerGroup {
                GroupName  = 'Web Servers'
                GroupScope = 'Global'
                DependsOn  = '[xADOrganizationalUnit]IT'
                Members    = $WebServers
                Credential = $DomainCredential
                Category   = 'Security'
                Path       = "OU=IT,$($Node.DomainDN)"
                Ensure     = 'Present'
            }
        }

    } #end nodes DC

    #endregion

    #region DHCP
    node $AllNodes.Where({ $_.Role -eq 'DHCP' }).NodeName {

        foreach ($feature in @(
                'DHCP',
                'RSAT-DHCP'
            )) {

            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
                DependsOn            = '[xADDomain]FirstDC'
            }
        } #End foreach

        xDhcpServerAuthorization 'DhcpServerAuthorization' {
            Ensure           = 'Present'
            IsSingleInstance = 'yes'
            DependsOn        = '[WindowsFeature]DHCP'
        }

        xDhcpServerScope 'DhcpScope' {
            Name          = $Node.DHCPName
            ScopeID       = $node.DHCPScopeID
            IPStartRange  = $Node.DHCPIPStartRange
            IPEndRange    = $Node.DHCPIPEndRange
            SubnetMask    = $Node.DHCPSubnetMask
            LeaseDuration = $Node.DHCPLeaseDuration
            State         = $Node.DHCPState
            AddressFamily = $Node.DHCPAddressFamily
            DependsOn     = '[WindowsFeature]DHCP'
        }

        <#
        Deprecated
        xDhcpServerOption 'DhcpOption' {
            ScopeID = $Node.DHCPScopeID
            DnsServerIPAddress = $Node.DHCPDnsServerIPAddress
            Router = $node.DHCPRouter
            AddressFamily = $Node.DHCPAddressFamily
            DependsOn = '[xDhcpServerScope]DhcpScope'
        }
        #>

    } #end DHCP Config
    #endregion

    #region Web config
    node $AllNodes.Where({ $_.Role -eq 'Web' }).NodeName {

        foreach ($feature in @(
                'web-Server'

            )) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present'
                Name                 = $feature
                IncludeAllSubFeature = $False
            }
        }

    }#end Web Config
    #endregion

    #region DomainJoin config
    node $AllNodes.Where({ $_.Role -eq 'DomainJoin' }).NodeName {

        $DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("$($node.DomainName)\$($Credential.UserName)", $Credential.Password)

        xWaitForADDomain DscForestWait {
            DomainName           = $Node.DomainName
            DomainUserCredential = $DomainCredential
            RetryCount           = '20'
            RetryIntervalSec     = '60'
        }

        xComputer JoinDC {
            Name       = $Node.NodeName
            DomainName = $Node.DomainName
            Credential = $DomainCredential
            DependsOn  = '[xWaitForADDomain]DSCForestWait'
        }
    }#end DomainJoin Config
    #endregion

    #region RSAT config
    node $AllNodes.Where({ $_.Role -eq 'RSAT' }).NodeName {

        Script RSAT {
            # Adds RSAT which is now a Windows Capability in Windows 10
            TestScript = {
                $rsat = @(
                    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
                    'Rsat.BitLocker.Recovery.Tools~~~~0.0.1.0',
                    'Rsat.CertificateServices.Tools~~~~0.0.1.0',
                    'Rsat.DHCP.Tools~~~~0.0.1.0',
                    'Rsat.Dns.Tools~~~~0.0.1.0',
                    'Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0',
                    'Rsat.FileServices.Tools~~~~0.0.1.0',
                    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0',
                    'Rsat.IPAM.Client.Tools~~~~0.0.1.0',
                    'Rsat.ServerManager.Tools~~~~0.0.1.0'
                )
                $packages = $rsat | ForEach-Object { Get-WindowsCapability -Online -Name $_ }
                if ($packages.state -contains "NotPresent") {
                    Return $False
                }
                else {
                    Return $True
                }
            } #test

            GetScript  = {
                $rsat = @(
                    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
                    'Rsat.BitLocker.Recovery.Tools~~~~0.0.1.0',
                    'Rsat.CertificateServices.Tools~~~~0.0.1.0',
                    'Rsat.DHCP.Tools~~~~0.0.1.0',
                    'Rsat.Dns.Tools~~~~0.0.1.0',
                    'Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0',
                    'Rsat.FileServices.Tools~~~~0.0.1.0',
                    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0',
                    'Rsat.IPAM.Client.Tools~~~~0.0.1.0',
                    'Rsat.ServerManager.Tools~~~~0.0.1.0'
                )
                $packages = $rsat | ForEach-Object { Get-WindowsCapability -Online -Name $_ } | Select-Object Displayname, State
                $installed = $packages.Where({ $_.state -eq "Installed" })
                Return @{Result = "$($installed.count)/$($packages.count) RSAT features installed" }
            } #get

            SetScript  = {
                $rsat = @(
                    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
                    'Rsat.BitLocker.Recovery.Tools~~~~0.0.1.0',
                    'Rsat.CertificateServices.Tools~~~~0.0.1.0',
                    'Rsat.DHCP.Tools~~~~0.0.1.0',
                    'Rsat.Dns.Tools~~~~0.0.1.0',
                    'Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0',
                    'Rsat.FileServices.Tools~~~~0.0.1.0',
                    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0',
                    'Rsat.IPAM.Client.Tools~~~~0.0.1.0',
                    'Rsat.ServerManager.Tools~~~~0.0.1.0'
                )
                foreach ($item in $rsat) {
                    $pkg = Get-WindowsCapability -Online -Name $item
                    if ($item.state -ne 'Installed') {
                        Add-WindowsCapability -Online -Name $item
                    }
                }

            } #set

        } #rsat script resource


    }#end RSAT Config

    #region RDP config
    node $AllNodes.Where({ $_.Role -eq 'RDP' }).NodeName {
        # Adds RDP support and opens Firewall rules

        Registry RDP {
            Key       = 'HKLM:\System\ControlSet001\Control\Terminal Server'
            ValueName = 'fDenyTSConnections'
            ValueType = 'Dword'
            ValueData = '0'
            Ensure    = 'Present'
        }
        foreach ($Rule in @(
                'RemoteDesktop-UserMode-In-TCP',
                'RemoteDesktop-UserMode-In-UDP',
                'RemoteDesktop-Shadow-In-TCP'
            )) {
            xFirewall $Rule {
                Name      = $Rule
                Enabled   = 'True'
                DependsOn = '[Registry]RDP'
            }
        } # End RDP
    }
    #endregion
    #region ADCS

    node $AllNodes.Where({ $_.Role -eq 'ADCS' }).NodeName {

        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in @(
                'ADCS-Cert-Authority',
                'ADCS-Enroll-Web-Pol',
                'ADCS-Enroll-Web-Svc',
                'ADCS-Web-Enrollment',
                'RSAT-ADCS',
                'RSAT-ADCS-Mgmt'
            )) {

            WindowsFeature $feature.Replace('-', '') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $False;
                DependsOn            = '[xADDomain]FirstDC'
            }
        } #End foreach

        xWaitForADDomain WaitForADADCSRole {
            DomainName           = $Node.DomainName
            RetryIntervalSec     = '30'
            RetryCount           = '10'
            DomainUserCredential = $DomainCredential
            DependsOn            = '[WindowsFeature]ADCSCertAuthority'
        }

        xAdcsCertificationAuthority ADCSConfig {
            CAType                    = $Node.ADCSCAType
            Credential                = $Credential
            CryptoProviderName        = $Node.ADCSCryptoProviderName
            HashAlgorithmName         = $Node.ADCSHashAlgorithmName
            KeyLength                 = $Node.ADCSKeyLength
            CACommonName              = $Node.CACN
            CADistinguishedNameSuffix = $Node.CADNSuffix
            DatabaseDirectory         = $Node.CADatabasePath
            LogDirectory              = $Node.CALogPath
            ValidityPeriod            = $node.ADCSValidityPeriod
            ValidityPeriodUnits       = $Node.ADCSValidityPeriodUnits
            DependsOn                 = '[xWaitForADDomain]WaitForADADCSRole'
        }

        #Add GPO for PKI AutoEnroll
        script CreatePKIAEGpo {
            Credential = $DomainCredential
            TestScript = {
                if ((Get-GPO -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -ErrorAction SilentlyContinue) -eq $Null) {
                    return $False
                }
                else {
                    return $True
                }
            }
            SetScript  = {
                New-GPO -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName
            }
            GetScript  = {
                $GPO = (Get-GPO -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName)
                return @{Result = $($GPO.DisplayName) }
            }
            DependsOn  = '[xWaitForADDomain]WaitForADADCSRole'
        }

        script setAEGPRegSetting1 {
            Credential = $DomainCredential
            TestScript = {
                if ((Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy" -ErrorAction SilentlyContinue).Value -eq 7) {
                    return $True
                }
                else {
                    return $False
                }
            }
            SetScript  = {
                Set-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy" -Value 7 -Type DWord
            }
            GetScript  = {
                $RegVal1 = (Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "AEPolicy")
                return @{Result = "$($RegVal1.FullKeyPath)\$($RegVal1.ValueName)\$($RegVal1.Value)" }
            }
            DependsOn  = '[Script]CreatePKIAEGpo'
        }

        script setAEGPRegSetting2 {
            Credential = $DomainCredential
            TestScript = {
                if ((Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationPercent" -ErrorAction SilentlyContinue).Value -eq 10) {
                    return $True
                }
                else {
                    return $False
                }
            }
            SetScript  = {
                Set-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationPercent" -Value 10 -Type DWord
            }
            GetScript  = {
                $Regval2 = (Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationPercent")
                return @{Result = "$($RegVal2.FullKeyPath)\$($RegVal2.ValueName)\$($RegVal2.Value)" }
            }
            DependsOn  = '[Script]setAEGPRegSetting1'

        }

        script setAEGPRegSetting3 {
            Credential = $DomainCredential
            TestScript = {
                if ((Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationStoreNames" -ErrorAction SilentlyContinue).value -match "MY") {
                    return $True
                }
                else {
                    return $False
                }
            }
            SetScript  = {
                Set-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationStoreNames" -Value "MY" -Type String
            }
            GetScript  = {
                $RegVal3 = (Get-GPRegistryValue -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" -ValueName "OfflineExpirationStoreNames")
                return @{Result = "$($RegVal3.FullKeyPath)\$($RegVal3.ValueName)\$($RegVal3.Value)" }
            }
            DependsOn  = '[Script]setAEGPRegSetting2'
        }

        Script SetAEGPLink {
            Credential = $DomainCredential
            TestScript = {
                try {
                    $GPLink = (Get-GPO -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName).ID
                    $GPLinks = (Get-GPInheritance -Domain $Using:Node.DomainName -Target $Using:Node.DomainDN).gpolinks | Where-Object { $_.GpoID -like "*$GPLink*" }
                    if ($GPLinks.Enabled -eq $True) { return $True }
                    else { return $False }
                }
                catch {
                    Return $False
                }
            }
            SetScript  = {
                New-GPLink -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName -Target $Using:Node.DomainDN -LinkEnabled Yes
            }
            GetScript  = {
                $GPLink = (Get-GPO -Name "PKI AutoEnroll" -Domain $Using:Node.DomainName).ID
                $GPLinks = (Get-GPInheritance -Domain $Using:Node.DomainName -Target $Using:Node.DomainDN).gpolinks | Where-Object { $_.GpoID -like "*$GPLink*" }
                return @{Result = "$($GPLinks.DisplayName) = $($GPLinks.Enabled)" }
            }
            DependsOn  = '[Script]setAEGPRegSetting3'
        }

        #region Create and publish templates

        #Note:  The Test section is pure laziness.  Future enhancement:  test for more than just existence.
        script CreateWebServer2Template {
            DependsOn  = '[xAdcsCertificationAuthority]ADCSConfig'
            Credential = $DomainCredential
            TestScript = {
                try {
                    $WSTemplate = Get-ADObject -Identity "CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * -ErrorAction Stop
                    return $True
                }
                catch {
                    return $False
                }
            }
            SetScript  = {
                $WebServerTemplate = @{'flags'             = '131649';
                    'msPKI-Cert-Template-OID'              = '1.3.6.1.4.1.311.21.8.8211880.1779723.5195193.12600017.10487781.44.7319704.6725493';
                    'msPKI-Certificate-Application-Policy' = '1.3.6.1.5.5.7.3.1';
                    'msPKI-Certificate-Name-Flag'          = '268435456';
                    'msPKI-Enrollment-Flag'                = '32';
                    'msPKI-Minimal-Key-Size'               = '2048';
                    'msPKI-Private-Key-Flag'               = '50659328';
                    'msPKI-RA-Signature'                   = '0';
                    'msPKI-Supersede-Templates'            = 'WebServer';
                    'msPKI-Template-Minor-Revision'        = '3';
                    'msPKI-Template-Schema-Version'        = '2';
                    'pKICriticalExtensions'                = '2.5.29.15';
                    'pKIDefaultCSPs'                       = '2,Microsoft DH SChannel Cryptographic Provider', '1,Microsoft RSA SChannel Cryptographic Provider';
                    'pKIDefaultKeySpec'                    = '1';
                    'pKIExtendedKeyUsage'                  = '1.3.6.1.5.5.7.3.1';
                    'pKIMaxIssuingDepth'                   = '0';
                    'revision'                             = '100'
                }


                New-ADObject -Name "WebServer2" -Type pKICertificateTemplate -Path "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -DisplayName WebServer2 -OtherAttributes $WebServerTemplate
                $WSOrig = Get-ADObject -Identity "CN=WebServer,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * | Select-Object pkiExpirationPeriod, pkiOverlapPeriod, pkiKeyUsage
                Get-ADObject -Identity "CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" | Set-ADObject -Add @{'pKIKeyUsage' = $WSOrig.pKIKeyUsage; 'pKIExpirationPeriod' = $WSOrig.pKIExpirationPeriod; 'pkiOverlapPeriod' = $WSOrig.pKIOverlapPeriod }
            }
            GetScript  = {
                try {
                    $WS2 = Get-ADObject -Identity "CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * -ErrorAction Stop
                    return @{Result = $WS2.DistinguishedName }
                }
                catch {
                    return @{Result = $Null }
                }
            }
        }


        #Note:  The Test section is pure laziness.  Future enhancement:  test for more than just existence.
        script CreateDSCTemplate {
            DependsOn  = '[xAdcsCertificationAuthority]ADCSConfig'
            Credential = $Credential
            TestScript = {
                try {
                    $DSCTemplate = Get-ADObject -Identity "CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * -ErrorAction Stop
                    return $True
                }
                catch {
                    return $False
                }
            }
            SetScript  = {
                $DSCTemplateProps = @{'flags'              = '131680';
                    'msPKI-Cert-Template-OID'              = '1.3.6.1.4.1.311.21.8.16187918.14945684.15749023.11519519.4925321.197.13392998.8282280';
                    'msPKI-Certificate-Application-Policy' = '1.3.6.1.4.1.311.80.1';
                    'msPKI-Certificate-Name-Flag'          = '1207959552';
                    #'msPKI-Enrollment-Flag'='34';
                    'msPKI-Enrollment-Flag'                = '32';
                    'msPKI-Minimal-Key-Size'               = '2048';
                    'msPKI-Private-Key-Flag'               = '0';
                    'msPKI-RA-Signature'                   = '0';
                    #'msPKI-Supersede-Templates'='WebServer';
                    'msPKI-Template-Minor-Revision'        = '3';
                    'msPKI-Template-Schema-Version'        = '2';
                    'pKICriticalExtensions'                = '2.5.29.15';
                    'pKIDefaultCSPs'                       = '1,Microsoft RSA SChannel Cryptographic Provider';
                    'pKIDefaultKeySpec'                    = '1';
                    'pKIExtendedKeyUsage'                  = '1.3.6.1.4.1.311.80.1';
                    'pKIMaxIssuingDepth'                   = '0';
                    'revision'                             = '100'
                }


                New-ADObject -Name "DSCTemplate" -Type pKICertificateTemplate -Path "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -DisplayName DSCTemplate -OtherAttributes $DSCTemplateProps
                $WSOrig = Get-ADObject -Identity "CN=Workstation,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * | Select-Object pkiExpirationPeriod, pkiOverlapPeriod, pkiKeyUsage
                [byte[]] $WSOrig.pkiKeyUsage = 48
                Get-ADObject -Identity "CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" | Set-ADObject -Add @{'pKIKeyUsage' = $WSOrig.pKIKeyUsage; 'pKIExpirationPeriod' = $WSOrig.pKIExpirationPeriod; 'pkiOverlapPeriod' = $WSOrig.pKIOverlapPeriod }
            }
            GetScript  = {
                try {
                    $dsctmpl = Get-ADObject -Identity "CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -Properties * -ErrorAction Stop
                    return @{Result = $dsctmpl.DistinguishedName }
                }
                catch {
                    return @{Result = $Null }
                }
            }
        }

        script PublishWebServerTemplate2 {
            DependsOn  = '[Script]CreateWebServer2Template'
            Credential = $Credential
            TestScript = {
                $Template = Get-CATemplate | Where-Object { $_.Name -match "WebServer2" }
                if ($Template -eq $Null) { return $False }
                else { return $True }
            }
            SetScript  = {
                add-CATemplate -name "WebServer2" -force
            }
            GetScript  = {
                $pubWS2 = Get-CATemplate | Where-Object { $_.Name -match "WebServer2" }
                return @{Result = $pubws2.Name }
            }
        }

        script PublishDSCTemplate {
            DependsOn  = '[Script]CreateDSCTemplate'
            Credential = $Credential
            TestScript = {
                $Template = Get-CATemplate | Where-Object { $_.Name -match "DSCTemplate" }
                if ($Template -eq $Null) { return $False }
                else { return $True }
            }
            SetScript  = {
                add-CATemplate -name "DSCTemplate" -force
                Write-Verbose -Message ("Publishing Template DSCTemplate...")
            }
            GetScript  = {
                $pubDSC = Get-CATemplate | Where-Object { $_.Name -match "DSCTemplate" }
                return @{Result = $pubDSC.Name }
            }
        }


        #endregion - Create and publish templates

        #region template permissions
        #Permission beginning with 0e10... is "Enroll".  Permission beginning with "a05b" is autoenroll.
        #TODO:  Write-Verbose in other script resources.
        #TODO:  Make $Perms a has table with GUID and permission name.  Use name in resource name.

        [string[]]$Perms = "0e10c968-78fb-11d2-90d4-00c04f79dc55", "a05b8cc2-17bc-4802-a710-e7c15ab866a2"

        foreach ($P in $Perms) {

            script "Perms_WebCert_$($P)" {
                DependsOn  = '[Script]CreateWebServer2Template'
                Credential = $DomainCredential
                TestScript = {
                    Import-Module activedirectory -Verbose:$false
                    $WebServerCertACL = (Get-Acl "AD:CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)").Access | Where-Object { $_.IdentityReference -like "*Web Servers" }
                    if ($WebServerCertACL -eq $Null) {
                        Write-Verbose -Message ("Web Servers Group does not have permissions on Web Server template...")
                        Return $False
                    }
                    elseif (($WebServerCertACL.ActiveDirectoryRights -like "*ExtendedRight*") -and ($WebServerCertACL.ObjectType -notcontains $Using:P)) {
                        Write-Verbose -Message ("Web Servers group has permission, but not the correct permission...")
                        Return $False
                    }
                    else {
                        Write-Verbose -Message ("ACL on Web Server Template is set correctly for this GUID for Web Servers Group...")
                        Return $True
                    }
                }
                SetScript  = {
                    Import-Module activedirectory -Verbose:$false
                    $WebServersGroup = Get-ADGroup -Identity "Web Servers" | Select-Object SID
                    $EnrollGUID = [GUID]::Parse($Using:P)
                    $ACL = Get-Acl "AD:CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)"
                    $ACL.AddAccessRule((New-Object System.DirectoryServices.ExtendedRightAccessRule $WebServersGroup.SID, 'Allow', $EnrollGUID, 'None'))
                    #$ACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $WebServersGroup.SID,'ReadProperty','Allow'))
                    #$ACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $WebServersGroup.SID,'GenericExecute','Allow'))
                    Set-Acl "AD:CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -AclObject $ACL
                    Write-Verbose -Message ("Permissions set for Web Servers Group")
                }
                GetScript  = {
                    Import-Module activedirectory -Verbose:$false
                    $WebServerCertACL = (Get-Acl "AD:CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)").Access | Where-Object { $_.IdentityReference -like "*Web Servers" }
                    if ($WebServerCertACL -ne $Null) {
                        return @{Result = $WebServerCertACL }
                    }
                    else {
                        Return @{}
                    }
                }
            }

            script "Perms_DSCCert_$($P)" {
                DependsOn  = '[Script]CreateWebServer2Template'
                Credential = $DomainCredential
                TestScript = {
                    Import-Module activedirectory -Verbose:$false
                    $DSCCertACL = (Get-Acl "AD:CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)").Access | Where-Object { $_.IdentityReference -like "*Domain Computers*" }
                    if ($DSCCertACL -eq $Null) {
                        Write-Verbose -Message ("Domain Computers does not have permissions on DSC template")
                        Return $False
                    }
                    elseif (($DSCCertACL.ActiveDirectoryRights -like "*ExtendedRight*") -and ($DSCCertACL.ObjectType -notcontains $Using:P)) {
                        Write-Verbose -Message ("Domain Computers group has permission, but not the correct permission...")
                        Return $False
                    }
                    else {
                        Write-Verbose -Message ("ACL on DSC Template is set correctly for this GUID for Domain Computers...")
                        Return $True
                    }
                }
                SetScript  = {
                    Import-Module activedirectory -Verbose:$false
                    $DomainComputersGroup = Get-ADGroup -Identity "Domain Computers" | Select-Object SID
                    $EnrollGUID = [GUID]::Parse($Using:P)
                    $ACL = Get-Acl "AD:CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)"
                    $ACL.AddAccessRule((New-Object System.DirectoryServices.ExtendedRightAccessRule $DomainComputersGroup.SID, 'Allow', $EnrollGUID, 'None'))
                    #$ACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $WebServersGroup.SID,'ReadProperty','Allow'))
                    #$ACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $WebServersGroup.SID,'GenericExecute','Allow'))
                    Set-Acl "AD:CN=DSCTemplate,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)" -AclObject $ACL
                    Write-Verbose -Message ("Permissions set for Domain Computers...")
                }
                GetScript  = {
                    Import-Module activedirectory -Verbose:$false
                    $DSCCertACL = (Get-Acl "AD:CN=WebServer2,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$($Using:Node.DomainDN)").Access | Where-Object { $_.IdentityReference -like "*Domain Computers" }
                    if ($DSCCertACL -ne $Null) {
                        return @{Result = $DSCCertACL }
                    }
                    else {
                        Return @{}
                    }
                }
            }
        }

    } #end ADCS Config

} # End AllNodes
#endregion

AutoLab -OutputPath $PSScriptRoot -ConfigurationData $PSScriptRoot\VMConfigurationData.psd1

