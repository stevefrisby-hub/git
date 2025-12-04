param($Request)

$scriptPath = "C:\Export\zendesk\getticketdata.ps1"

if (Test-Path $scriptPath) {
    try {
        & $scriptPath
        $response = @{
            status  = "Success"
            message = "Zendesk export script executed."
            output  = "Zendesk_Org_Ticket_Summary.csv created."
        }
        return Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body = $response
        })
    } catch {
        $errorResponse = @{
            status  = "Error"
            message = $_.Exception.Message
        }
        return Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::InternalServerError
            Body = $errorResponse
        })
    }
} else {
    $missingResponse = @{
        status  = "Error"
        message = "Script not found at $scriptPath"
    }
    return Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::NotFound
        Body = $missingResponse
    })
}
