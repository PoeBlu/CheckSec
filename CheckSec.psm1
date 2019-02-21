function checkDomain {
    param (
        [Parameter(Mandatory)]
        [string]
        $domain
    )
    try {
        Write-Verbose "Checking if the domain exists"
        Resolve-DnsName $Domain -NoHostsFile -DnsOnly -ErrorAction stop | out-null
    }
    catch {
        Write-error "`n$_"
        Break
    }
}
function spfExtractor {
    param (
        # SPF TXT value
        [Parameter(Position = 0,Mandatory)]
        [string]
        $SpfTxt
    )
    $SpfCounter = $SpfTxt.substring(7)
    $SpfCounter = $SpfCounter -split " "
    $global:SpfCounter = ($SpfCounter.count - 1)
    if ($SpfTxt -like "*PTR:*") {
        $global:SpfPtr = $true
    } else {
        $global:SpfPtr = $false
    }
}
function Get-EmailDetail {
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $Domain
    )
    # Check whether domain exists
    checkDomain $Domain
    $domainMX    = Resolve-DnsName $Domain -Type MX | Select-Object NameExchange -first 1
    $domainSPF   = Resolve-DnsName $Domain -Type TXT | Where-Object -Property Strings -Like "v=spf1*" #TODO: få bort strings
    $domainDmarc = Resolve-DnsName "_dmarc.$Domain" -type TXT -ErrorAction SilentlyContinue
    # SPF
    if ($domainSPF) {
        Write-Verbose "SPF, present!"
        $spfPresent = $true
        $SpfRecord  = $domainSPF.strings.replace("{}","")
    } else {
        $spfPresent = $false
        $SpfRecord  = "N/A"
    }
    if ($domainSPF){
        spfExtractor -SpfTxt $SpfRecord
    }
    if ($global:SpfPtr) {
        Write-Warning "Using the PTR mechanism is not recommended!"
        Write-Warning "Reference: RFC7208 Section 5.5."
    }
    if ($global:spfCounter -gt 10) {
        Write-Warning "Too many DNS mechanics"
    }
    # DKIM
    if ($emailDetail.MX -like "*outlook.com") {
        $dkimCheck = Resolve-DnsName selector1._domainkey.$domain -DnsOnly -ErrorAction SilentlyContinue
        if ($dkimCheck){
            $dkimPresent = $true
        } else {
            $dkimPresent = $false
        }
    }
    # DMARC
    if ($domainDmarc) {
        $domainDmarcPresent = $true
    } else {
        $domainDmarcPresent = $false
    }
    if ($domainDmarc.strings -like "*p=reject*") {
        $dmarcPolicy = "reject"
    } elseif ($domainDmarc.strings -like "*p=quarantine*") {
        $dmarcPolicy = "quarantine"
    } elseif ($domainDmarc.strings -like "*p=none*") {
        $dmarcPolicy = "none"
    } else {
        $dmarcPolicy = "N/A"
    }
    [PSCustomObject]@{
        'Domain'          = $Domain
        'MX'              = $domainMX.NameExchange
        'SpfPresent'      = $spfPresent
        'SpfRecord'       = $SpfRecord
        'SpfDnsMechanics' = $global:spfCounter
        'SpfPtrInUse'     = $global:SpfPtr
        'DkimPresent'     = $dkimPresent
        'DmarcPresent'    = $domainDmarcPresent
        'DmarcPolicy'     = $dmarcPolicy
    }
}