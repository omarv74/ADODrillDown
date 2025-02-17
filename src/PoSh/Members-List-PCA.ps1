# Get the directory of the running script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define the path to the CSV file
$csvFilePath = Join-Path -Path $scriptDir -ChildPath "Azure_DevOps_Organizations_2025-01-31_Sample.csv"

# To create the environment variable, use the following command in PowerShell:
# $env:ADODrillDown_PAT = "your_personal_access_token"
$pat = $env:ADODrillDown_PAT

$restApiVersion = '7.1-preview.1'

# Base64 encode the PAT
# $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))

# Create the authorization header
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
}

# Read the CSV file and get the organization names from the second field
$csvData = Import-Csv -Path $csvFilePath

# Iterate through each row and execute the existing code for each organization
foreach ($row in $csvData) {
    $orgName = $row."Organization Name"

    $groupsListUri = "https://vssps.dev.azure.com/$orgName/_apis/graph/groups?api-version=$restApiVersion"

    try {
        $responseGroupsList = $null
        # Make the REST API call to get the members of the security group
        $responseGroupsList = Invoke-RestMethod -Uri $groupsListUri -Method 'GET' -Headers $headers

        # Extract the members from the response
        $groupsList = $responseGroupsList.value | Where-Object { $_.displayName -eq "Project Collection Administrators" }

        # Output the members
        $groupsList | ForEach-Object {
            Write-Output $_.principalName
        }
    }
    catch {
        Write-Error "Failed to retrieve groups for organization '$orgName'."
    }
}
