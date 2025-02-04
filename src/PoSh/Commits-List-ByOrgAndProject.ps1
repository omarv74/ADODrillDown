# Define variables
# To create the environment variable, use the following command in PowerShell:
# $env:ADODrillDown_PAT = "your_personal_access_token"
$pat = $env:ADODrillDown_PAT
$restApiVersion = '7.1-preview.1'
$daysAgo = -30  # Variable for the number of days ago

# Initialize a set to store unique committers
$committers = [System.Collections.Generic.HashSet[string]]::new()

# Calculate the date based on the variable
$commitsStartDate = (Get-Date).AddDays($daysAgo).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Create the authorization header
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
}

# Define the path to the input CSV file
# The file is an ADO Export of all organizations from the tenant
# i.e. Organization Settings -> Microsoft Entra -> Download button
# Place the downloaded file in the same folder as this script and 
# set the correct file name in the $csvOrgsPath variable.
$csvOrgsPath = Join-Path -Path $scriptDir -ChildPath 'Azure_DevOps_Organizations_2025-01-31_Sample.csv'

# Get the directory of the current script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define the path to the output CSV file with a current date and time stamp
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$csvCommittersPath = Join-Path -Path $scriptDir -ChildPath "committers_$timestamp.csv"

# Open CSV file for writing
$csvCommitters = New-Object System.IO.StreamWriter($csvCommittersPath)

# Read the input CSV file
$csvOrgs = Import-Csv -Path $csvOrgsPath

# Initialize the counter
$counter = 0

# Iterate through each row in the input CSV file
$csvOrgs | ForEach-Object {
    $counter++
    $orgName = $_."Organization Name"
    $adoGroupPCA = $null

    Write-Host "$counter. $orgName" -ForegroundColor Green

    # Check Access by trying to retrieve the Org's PCA Group
    $groupsListUri = "https://vssps.dev.azure.com/$orgName/_apis/graph/groups?api-version=$restApiVersion"

    # Set to Null b/c Invoke-RestMethod will not clear the value from the previous loop iteration
    # when certain server-side errors occur. Those errors will sometimes not end in the catch block.
    # Need additional research or OSS community contribution to improve.
    $responseGroupsList = $null 
    try {
        $responseGroupsList = Invoke-RestMethod -Uri $groupsListUri -Method 'GET' -Headers $headers
        $groupsList = $responseGroupsList.value | Where-Object { $_.displayName -eq "Project Collection Administrators" -and $_.domain -like "*Framework/IdentityDomain*" }

        if ($groupsList.Count -ne 1) {
            Write-Host "   Error: Expected 1 Group named 'Project Collection Administrators'. Retrieved $(groupList.Count)" -ForegroundColor Yellow
            return
        }
        $adoGroupPCA = $groupsList[0]
    }
    catch {
        Write-Host "   Failed to retrieve groups for organization '$orgName'." -ForegroundColor Red
        return
    }

    # Construct the API URL for projects
    $projectsUri = "https://dev.azure.com/$orgName/_apis/projects?api-version=$restApiVersion"

    # Set $projectsResponse to null
    $projectsResponse = $null

    # Make the API call to get projects with error handling
    try {
        $projectsResponse = Invoke-RestMethod -Uri $projectsUri -Method Get -Headers $headers
    } catch [System.Net.WebException] {
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
            Write-Host "$orgName Unauthorized." -ForegroundColor Red
            return
        } else {
            throw
        }
    }

    # Check if the response is null or contains the typeKey property
    if (-not $projectsResponse -or ($projectsResponse.PSObject.Properties['typeKey'] -and $projectsResponse.typeKey -eq 'UnauthorizedRequestException')) {
        Write-Host "$orgName - Unauthorized" -ForegroundColor Red
        return
    }

    # Check if the list of projects is empty
    if ($projectsResponse.value.Count -eq 0) {
        Write-Host "0 Projects" -ForegroundColor Yellow
        return
    }

    # Iterate through each project
    $projectsResponse.value | ForEach-Object {
        $projectName = $_.name
        Write-Host "Project: $projectName"

        # Construct the API URL for repositories
        $repoUri = "https://dev.azure.com/$orgName/$projectName/_apis/git/repositories?api-version=$restApiVersion"

        # Make the API call to get repositories
        $reposResponse = Invoke-RestMethod -Uri $repoUri -Method Get -Headers $headers

        # Iterate through each repository
        $reposResponse.value | ForEach-Object {
            $repoName = $_.name
            $repoId = $_.id
            Write-Host "  Repository: $repoName"

            # Construct the API URL for commits with date filter
            $commitsUri = "https://dev.azure.com/$orgName/$projectName/_apis/git/repositories/$repoId/commits?searchCriteria.fromDate=$commitsStartDate&api-version=$restApiVersion"

            # Make the API call to get commits with error handling
            try {
                $commitsResponse = Invoke-RestMethod -Uri $commitsUri -Method Get -Headers $headers
            } catch {
                Write-Host "$orgName,$projectName,$repoName" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                return
            }

            # Extract and add unique author names to the set and write to CSV
            $commitsResponse.value | ForEach-Object {
                $authorName = $_.author.name
                if ($committers.Add($authorName)) {
                    $csvCommitters.WriteLine("$orgName,$projectName,$repoName,$authorName")
                    Write-Host $authorName
                }
            }
        }
    }
}

# Close the CSV file
$csvCommitters.Close()
