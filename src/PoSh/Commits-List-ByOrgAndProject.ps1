# Define variables
$pat = '<YOUR_PERSONAL_ACCESS_TOKEN_GOES_HERE>'
$restApiVersion = '7.1'

# Initialize a set to store unique committers
$committers = [System.Collections.Generic.HashSet[string]]::new()

# Calculate the date 30 days ago
$commitsStartDate = (Get-Date).AddDays(-4500).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Create the authorization header
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
}

# Get the directory of the current script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define the path to the input CSV file
# The files is an ADO Export of all organizations from the tenant
# i.e. Organization Settings -> Microsoft Entra -> Download button
# Place the Downloaded file in the same folder as this script and 
# set the correct file name in the $csvOrgsPath variable.
$csvOrgsPath = Join-Path -Path $scriptDir -ChildPath 'Azure_DevOps_Organizations_2025-01-31_Sample.csv'

# Define the path to the output CSV file
$csvPath = Join-Path -Path $scriptDir -ChildPath 'committers.csv'

# Open CSV file for writing
$csvCommitters = New-Object System.IO.StreamWriter($csvPath)

# Read the input CSV file
$csvOrgs = Import-Csv -Path $csvOrgsPath

# Iterate through each row in the input CSV file
$csvOrgs | ForEach-Object {
    $orgName = $_."Organization Name"
    Write-Host $orgName -ForegroundColor Green

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

    # Iterate through each project
    $projectsResponse.value | ForEach-Object {
        $projectName = $_.name
        Write-Output "Project: $projectName"

        # Construct the API URL for repositories
        $repoUri = "https://dev.azure.com/$orgName/$projectName/_apis/git/repositories?api-version=$restApiVersion"

        # Make the API call to get repositories
        $reposResponse = Invoke-RestMethod -Uri $repoUri -Method Get -Headers $headers

        # Iterate through each repository
        $reposResponse.value | ForEach-Object {
            $repoName = $_.name
            $repoId = $_.id
            Write-Output "  Repository: $repoName"

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
                    Write-Output $authorName
                }
            }
        }
    }
}

# Close the CSV file
$csvCommitters.Close()
