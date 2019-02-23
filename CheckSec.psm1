function checkDomain {
    param (
        [Parameter(Mandatory)]
        [string]
        $Domain
    )
    try {
        Write-Verbose "Checking if the domain exists"
        Resolve-DnsName $Domain -NoHostsFile -DnsOnly -ErrorAction stop | out-null
    }
    catch {
        Write-error "`n$_"
        Break
    }
    $mxCheck = Resolve-DnsName $Domain -type MX
    if ($mxCheck.type -eq "MX") {
        $global:mxCheck = $true
    } else {
        $global:mxCheck = $false
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
    # Check whether domain exists & check if there is an MX and set it accordingly
    checkDomain $Domain
    if ($global:mxCheck) {
        $domainMX = (Resolve-DnsName $Domain -Type MX -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NameExchange -first 1 -ErrorAction SilentlyContinue).toLower()
    }
    $domainSPF   = (Resolve-DnsName $Domain -Type TXT -ErrorAction SilentlyContinue | Where-Object -Property Strings -Like "v=spf1*" | Select-Object -ExpandProperty Strings)
    $domainDmarc = (Resolve-DnsName "_dmarc.$Domain" -type TXT -ErrorAction SilentlyContinue)
    # SPF
    if ($domainSPF) {
        Write-Verbose "SPF, present!"
        $spfPresent = $true
        $SpfRecord  = $domainSPF.replace("{}","")
    } else {
        $spfPresent = $false
        $SpfRecord  = "N/A"
    }
    if ($domainSPF){
        spfExtractor -SpfTxt $SpfRecord.ToString()
    }
    if ($global:SpfPtr) {
        Write-Warning "Using the PTR mechanism is not recommended!"
        Write-Warning "Reference: RFC7208 Section 5.5."
    }
    if ($global:spfCounter -gt 10) {
        Write-Warning "Too many DNS mechanism"
    }
    # DKIM
    if ($domainMX -like "*outlook.com") {
        # Exchange Online uses selector1 and selector2._domainkey
        $dkimCheck = Resolve-DnsName selector1._domainkey.$domain -DnsOnly -ErrorAction SilentlyContinue
        if ($dkimCheck){
            $dkimPresent = $true
        } else {
            $dkimPresent = $false
        }
    }
    if ($domainMX -like "*google.com") {
        # G suite uses google._domainkey
        $dkimCheck = Resolve-DnsName google._domainkey.$domain -DnsOnly -ErrorAction SilentlyContinue
        if ($dkimCheck){
            $dkimPresent = $true
        } else {
            $dkimPresent = $false
        }
    }
    if ($domainMX -eq "mail.protonmail.ch") {
        $dkimCheck = Resolve-DnsName protonmail._domainkey.$domain -DnsOnly -ErrorAction SilentlyContinue
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
        'MX'              = $domainMX
        'SpfPresent'      = $spfPresent
        'SpfRecord'       = $SpfRecord
        'SpfDnsmechanism' = $global:spfCounter
        'SpfPtrInUse'     = $global:SpfPtr
        'DkimPresent'     = $dkimPresent
        'DmarcPresent'    = $domainDmarcPresent
        'DmarcPolicy'     = $dmarcPolicy
    }
}