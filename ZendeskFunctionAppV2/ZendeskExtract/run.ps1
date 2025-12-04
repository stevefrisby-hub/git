# === CONFIGURATION ===
$subdomain = "kallidus"
$email = "steve.frisby@kallidus.com/token"
$apiToken = "fZntBAMxIqZLNIn6arH6Ol7niPviIOtYlrnAr9HE"
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${email}:${apiToken}"))
$headers = @{ Authorization = "Basic $base64Auth" }

$culture = [System.Globalization.CultureInfo]::GetCultureInfo("en-GB")
$outputJson = "zendesk_tickets_last2days.json"
$outputCsv = "zendesk_ticket_export.csv"

# === DATE RANGE ===
$startDate = (Get-Date).ToUniversalTime().AddDays(-2)
$endDate = (Get-Date).ToUniversalTime()
$startTime = [int][double]($startDate - [datetime]'1970-01-01').TotalSeconds

# === STEP 1: FETCH TICKETS VIA INCREMENTAL EXPORT ===
function Export-IncrementalTicketsToFile {
    param (
        [int]$startTime,
        [string]$outputPath
    )

    $nextUrl = "https://$subdomain.zendesk.com/api/v2/incremental/tickets.json?start_time=$startTime&include=metric_sets"
    Set-Content -Path $outputPath -Value "["

    $first = $true
    while ($nextUrl) {
        try {
            $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers
            foreach ($ticket in $response.tickets) {
                $createdAt = [datetime]::Parse($ticket.created_at)
                if ($createdAt -ge $startDate -and $createdAt -lt $endDate) {
                    $json = $ticket | ConvertTo-Json -Depth 10
                    if (-not $first) { Add-Content -Path $outputPath -Value "," }
                    Add-Content -Path $outputPath -Value $json
                    $first = $false
                }
            }
            Write-Host "Written $($response.tickets.Count) tickets..."
            $nextUrl = if ($response.end_of_stream -eq $true) { $null } else { $response.next_page }
            Start-Sleep -Milliseconds 500
        } catch {
            Write-Warning "Failed to fetch: $nextUrl"
            break
        }
    }

    Add-Content -Path $outputPath -Value "]"
    Write-Host "Export complete: $outputPath"
	Write-Host "Now building the .csv..."
}

Export-IncrementalTicketsToFile -startTime $startTime -outputPath $outputJson

# === STEP 2: FETCH ORGANIZATIONS ===
function Get-AllResults {
    param (
        [string]$url,
        [string]$objectType
    )

    $results = @()
    $nextUrl = $url
    while ($nextUrl) {
        try {
            $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers
            $results += $response.$objectType
            $nextUrl = $response.next_page
        } catch {
            Write-Warning "Failed to fetch: $nextUrl"
            break
        }
    }
    return $results
}

$orgs = Get-AllResults -url "https://$subdomain.zendesk.com/api/v2/organizations.json" -objectType "organizations"

# === STEP 3: FETCH CUSTOM FIELD MAPPINGS ===
$ticketFields = (Invoke-RestMethod -Uri "https://$subdomain.zendesk.com/api/v2/ticket_fields.json" -Headers $headers).ticket_fields
$customFieldMap = @{
    "ticket_complexity" = ($ticketFields | Where-Object { $_.title -eq "ticket complexity level" }).id
    "complaint"         = ($ticketFields | Where-Object { $_.title -eq "complaint" }).id
}

# === STEP 4: PROCESS TICKETS FROM FILE ===
$rawJson = Get-Content $outputJson -Raw
$tickets = $rawJson | ConvertFrom-Json

$export = @()
$total = $tickets.Count
$counter = 0

foreach ($ticket in $tickets) {
    $createdAt = [datetime]::Parse($ticket.created_at)
    if ($createdAt -lt $startDate -or $createdAt -ge $endDate) { continue }

    $counter++
    $percentComplete = [math]::Round(($counter / $total) * 100)
    Write-Progress -Activity "Processing Tickets" -Status "Ticket $counter of $total" -PercentComplete $percentComplete

    $metric = $ticket.metric_set
    $org = ($orgs | Where-Object { $_.id -eq $ticket.organization_id }) | Select-Object -First 1
    if (-not $org -or -not $org.organization_fields.salesforce_id -or $org.organization_fields.salesforce_id -eq "0018d00000aFwbAAAS") { continue }

    $customFields = @{}
    foreach ($cf in $ticket.custom_fields) {
        $fieldName = $customFieldMap.GetEnumerator() | Where-Object { $_.Value -eq $cf.id } | Select-Object -ExpandProperty Key
        if ($fieldName) { $customFields[$fieldName] = $cf.value }
    }

    $export += [PSCustomObject]@{
        ID                  = $ticket.id
        created_at          = [datetime]::Parse($ticket.created_at, $culture)
        solved_at           = if ($metric.solved_at) {
            [datetime]::Parse($metric.solved_at, $culture)
        } elseif (($ticket.status -eq "solved") -or ($ticket.status -eq "closed")) {
            [datetime]::Parse($ticket.updated_at, $culture)
        } else {
            '1900-01-01 00:00'
        }
		replies				= if ([string]::IsNullOrWhiteSpace($metric.replies)) { 0 } else { $metric.replies }
        reopens             = if ([string]::IsNullOrWhiteSpace($metric.reopens)) { 0 } else { $metric.reopens }
        channel             = $ticket.via.channel
        satisfaction_rating = $ticket.satisfaction_rating.score
        raw_subject         = $ticket.raw_subject
        org_id              = $ticket.organization_id
        org_name            = $org.name
        org_salesforceid    = $org.organization_fields.salesforce_id
        ticket_complexity   = $customFields["ticket_complexity"]
		priority            = $ticket.priority
        complaint           = $customFields["Complaint"]
        org_created         = [datetime]::Parse($org.created_at, $culture)
    }
}

Write-Progress -Activity "Processing Tickets" -Completed
$export | Export-Csv -Path $outputCsv -NoTypeInformation
