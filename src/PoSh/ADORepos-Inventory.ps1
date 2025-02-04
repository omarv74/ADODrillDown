# Define variables
# To create the environment variable, use the following command in PowerShell:
# $env:ADODrillDown_PAT = "your_personal_access_token"
$pat = $env:ADODrillDown_PAT
$restApiVersion = '7.1-preview.1'

# Create the authorization header
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
}

# Get the directory of the current script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define the path to the input CSV file
# The file is an ADO Export of all organizations from the tenant
# i.e. Organization Settings -> Microsoft Entra -> Download button
# Place the downloaded file in the same folder as this script and 
# set the correct file name in the $csvOrgsPath variable.
$csvOrgsPath = Join-Path -Path $scriptDir -ChildPath 'Azure_DevOps_Organizations_2025-01-31_Sample.csv'

# Define the path to the output CSV file with a current date and time stamp
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$ADOReposInventory = Join-Path -Path $scriptDir -ChildPath "ADOReposInventory_$timestamp.csv"

# Open CSV file for writing
$ADOReposInventory = New-Object System.IO.StreamWriter($ADOReposInventory)

# Write the header to the output CSV file
$ADOReposInventory.WriteLine("OrganizationName,ProjectName,GitRepoName")

# Read the input CSV file
$csvOrgs = Import-Csv -Path $csvOrgsPath

# Initialize the counter
$counter = 0

# Iterate through each row in the input CSV file
$csvOrgs | ForEach-Object {
    $counter++
    $orgName = $_."Organization Name"

    Write-Host "$counter. $orgName" -ForegroundColor Green

    try {
        # Define the API endpoint for listing projects
        $projectsUrl = "https://dev.azure.com/$orgName/_apis/projects?api-version=$restApiVersion"

        # Make the API call to get the list of projects
        $response = Invoke-RestMethod -Uri $projectsUrl -Headers $headers -Method 'GET'

        # Process the response and get the list of projects
        foreach ($project in $response.value) {
            $projectName = $project.name

            try {
                # Define the API endpoint for listing Git repositories
                $reposUrl = "https://dev.azure.com/$orgName/$projectName/_apis/git/repositories?api-version=$restApiVersion"

                # Make the API call to get the list of Git repositories
                $reposResponse = Invoke-RestMethod -Uri $reposUrl -Headers $headers -Method 'GET'

                # Process the response and write Git repository details to the output CSV file
                foreach ($repo in $reposResponse.value) {
                    $gitRepoName = $repo.name
                    $ADOReposInventory.WriteLine("$orgName,$projectName,$gitRepoName")
                }
            } catch {
                Write-Host "Error retrieving repositories: $_" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Error retrieving projects: $_" -ForegroundColor Red
    }
}

# Close the CSV file
$ADOReposInventory.Close()
