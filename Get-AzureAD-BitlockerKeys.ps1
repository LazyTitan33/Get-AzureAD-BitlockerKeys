param (
    [string]$email,
    [string]$password
)

function Show-Usage {
    Write-Host "Usage:  .\Get-AzureAD-BitlockerKeys.ps1 -email 'email@example.com' -password 'your-password'"
    exit 1
}

# Check if all required parameters are provided
if (-not $email -or -not $password) {
    Write-Host "Error: Missing required parameters." -ForegroundColor Red
    Show-Usage
}


try {
    $FQDN = $email.Split('@')[1]
    $uri = "https://login.microsoftonline.com/$($FQDN)/.well-known/openid-configuration"
    $rest = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $uri
    if ($rest.authorization_endpoint) {
        $result = $(($rest.authorization_endpoint | Select-String '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}').Matches.Value)
        if ([guid]::Parse($result)) {

            $tenantID = $result.ToString()
        }
        else {
            throw "Tenant ID not found."
        }
    }
    else {
        throw "Tenant ID not found."
    }
    # Step 1: Authenticate the user
    $clientID = '1b730954-1685-4b74-9bfd-dac224a7b894' # this is the Azure AD Powershell client id

    $body = @{
        grant_type    = 'password'
        client_id     = $clientID
        resource      = 'https://graph.windows.net/'
        username      = $email
        password      = $password
    }

    # Attempt to get the token
    $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantID/oauth2/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body -ErrorAction Stop
    $token = $response.access_token
}
catch {
    if ($_.Exception.Response) {
        # Check if the response body contains the specific multi-factor authentication error
        if ($_ -like "*multi-factor*") {
            Write-Host "2FA detected, please login interactively" -ForegroundColor Yellow
            powershell -ep bypass Install-Module -Name AzureAD -Scope CurrentUser -AllowClobber
            Connect-AzureAD
        }
        else {
            Write-Host "Authentication failed. Response: $_" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
}


try {
    # Step 2: Query the user
    $userResponse = Invoke-RestMethod -Uri "https://graph.windows.net/$tenantID/users?api-version=1.6&%24filter=userPrincipalName%20eq%20'$email'" -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
    $userObjectID = $userResponse.value[0].objectId
}
catch {
    Write-Host "Failed to retrieve user information. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    # Step 3: Get the registered devices for the user
    $deviceResponse = Invoke-RestMethod -Uri "https://graph.windows.net/$tenantID/users/$userObjectID/registeredDevices?api-version=1.6" -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
}
catch {
    Write-Host "Failed to retrieve registered devices. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Output the devices
$devices = $deviceResponse.value | ForEach-Object {
    [PSCustomObject]@{
        ObjectID    = $_.objectId
        DeviceID    = $_.deviceId
        DisplayName = $_.displayName
    }
}

# Check if $devices is empty or contains objects
if (-not $devices) {
    Write-Host "No devices found." -ForegroundColor Yellow
    exit 1
} 
else {
    # Measure the number of devices
    $deviceCount = ($devices | Measure-Object).Count

    if ($deviceCount -eq 1) {
        Write-Host ""
        Write-Host "One device found:" -ForegroundColor Green
        $devices | Format-Table -AutoSize
        $objectID = $devices.ObjectID
    } 
    elseif ($deviceCount -gt 1) {
        Write-Host "$deviceCount devices found:"  -ForegroundColor Green
        $devices | Format-Table -AutoSize
        $objectID = Read-Host -Prompt "Enter ObjectID to get BitLocker keys"
    }
}

try {
    $response = Invoke-RestMethod -Uri "https://graph.windows.net/$tenantID/devices/$objectID\?api-version=1.61-internal" -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
    $bitLockerKeys = $response.bitLockerKey | ForEach-Object {
        [PSCustomObject]@{
            keyIdentifier      = $_.keyIdentifier
            BitlockerKey = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.keyMaterial))
        }
    }
    $bitLockerKeys
}
catch {
    Write-Host "Failed to retrieve BitLocker keys. Error: $($_.Exception.Message)" -ForegroundColor Red
}
