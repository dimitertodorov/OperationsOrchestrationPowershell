function Connect-OO{
<#
.SYNOPSIS 
Log into an OO API Endpoint.

.DESCRIPTION
This Cmdlet will log you in and create a token for use during your session. This is stored in $env:OO_USER and $env:OO_TOKEN

.PARAMETER base_url
Full URL to the OO Instance. e.g. https://local.oo.domain.com:9005/oo
    
.PARAMETER credentials
PSCreds

.INPUTS
None. You cannot pipe objects to the script.

.OUTPUTS
None. 

.EXAMPLE
C:\PS> OO-Login -base_url https://local.oo.domain.com:9005/oo -credentials $pscredentialsobject
#>
    [CmdletBinding()]
    Param (
        [string]$base_url  = 'https://dev-hpoo.tools.cihs.gov.on.ca:8443/oo/rest',

        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$credentials

    )
    ####
    $username=$credentials.GetNetworkCredential().UserName
    $password=$credentials.GetNetworkCredential().Password
	$auth = $username + ':' + $password

	$Encoded = [System.Text.Encoding]::UTF8.GetBytes($auth)
	$EncodedPassword = [System.Convert]::ToBase64String($Encoded)
	$headers = @{"Authorization"="Basic $($EncodedPassword)"}

    $uri = $base_url + "/version"
	$version = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ContentType "application/json"
    

    If($version){
        Write-Host "Logged Into $base_url as $username. OO_URL and OO_TOKEN have been exported to the environment"
    }
	Write-Host $version
    
    $env:OO_URL=$base_url
	$env:OO_CREDS=$EncodedPassword

    return $null
}


function OO{
<#
.SYNOPSIS 
Perform REST Actions against an OO Server

.DESCRIPTION
This Cmdlet allows you to perform GET, POST PATCH, PUT, DELETE Requests against an OO Endpoint

.PARAMETER method
Can be one of GET, POST PATCH, PUT, DELETE
    
.PARAMETER path
URL Endpoint. e.g. "/version"

.PARAMETER body
Optional. This should be a JSON-formatted string.

.PARAMETER Verbose
Optional. If this flag is set the JSON object is not printed out to screen. 

.INPUTS
None. You cannot pipe objects to the script.

.OUTPUTS
Powershell Object matching the JSON returned from OO. 

.EXAMPLE
PS C:\> $version=OO GET '/version'
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateSet("Get","Post","Patch","Put","Delete")]
        [string]$method,

        [Parameter(Mandatory=$true, Position=2)]
        [string]$path,

        [Parameter(Position=3)]
        [string]$body,

        [switch]$print
    )
    If(($env:OO_URL) -and ($env:OO_CREDS)){
        $headers = @{"Authorization"="Basic $($env:OO_CREDS)"; "Accept"="application/json"}
        $action_method=$method.ToString().ToUpper()
        try{
            switch ($action_method){
                "GET"{$output=Invoke-RestMethod -Uri $env:OO_URL$path -Method Get -ContentType "application/json" -Headers $headers}
                "POST"{$output=Invoke-RestMethod -Uri $env:OO_URL$path -Method Post -ContentType "application/json" -Headers $headers -Body $body}
                "PATCH"{$output=Invoke-RestMethod -Uri $env:OO_URL$path -Method Patch -ContentType "application/json" -Headers $headers -Body $body}
                "PUT"{$output=Invoke-RestMethod -Uri $env:OO_URL$path -Method Put -ContentType "application/json" -Headers $headers -Body $body}
                "DELETE"{$output=Invoke-RestMethod -Uri $env:OO_URL$path -Method Delete -ContentType "application/json" -Headers $headers}
            }
        }catch{
            $error_exception = $_.Exception
            if(($error_exception.GetType().Name -eq "WebException") -and ($_.Exception.Response)){
                $error_response=$_.Exception.Response
                Write-Host $_.Exception
                Write-Host $error_response
                $response_stream=$error_response.GetResponseStream()
                $reader=New-Object System.IO.StreamReader($response_stream)
                $response_text=$reader.ReadToEnd()
                $formatted_error=@"
OO Error: $($error_exception.Message)
URI: $($error_response.responseuri.AbsoluteUri)
Server: $($error_response.Server)
Full Error Text:
$response_text
"@
            }else{
                $formatted_error=$error_exception
            }
            Write-Host -BackgroundColor DarkRed $formatted_error
            throw $_
        }
        If($PSBoundParameters['Verbose']){
            if($output){
                $output_length=@($output).Length
                Write-Verbose "Object-Count: $output_length"
            }
        }
        If($print){
            $json_output=$output | ConvertTo-Json -Depth 100
            Write-Host $json_output
        }
        return $output
    }else{
        throw "OO_URL and OO_CREDS not found in environment. Please use Connect-OO to log in."
    }

}



function Invoke-OOFlow{
<#
.SYNOPSIS 
Execute OO Flow Synchronously

.DESCRIPTION
Execute Flow and Wait for Results
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, Position=1)]
        [string]$uuid,

        [Parameter(Mandatory=$true, Position=2)]
        [string]$run_name,

        [Parameter(Position=3)]
        $inputs
    )
	$flow_payload= New-Object PSObject -Property @{'flowUuid'=$uuid;
            'runName'=$run_name;
            'logLevel'='EXTENDED';
            'inputs'=$inputs}
	$flow_json = $flow_payload | ConvertTo-Json -Depth 5
	$flow_id = OO POST /latest/executions $flow_json
	$status="STARTED"
	$counter=0
	If($flow_id){
		While(($status -ne "COMPLETED") -and ($counter -lt 30)){
			$execution_summary = OO GET "/latest/executions/$flow_id/summary"
			$status=$execution_summary.status
			$counter++
			If($status -eq "COMPLETED"){
				Write-Progress -Activity "Executing Flow $flow_id" -Status $status -PercentComplete 100 
				return $execution_summary
			}Else{
				$step_count = OO GET "/latest/executions/$flow_id/steps/count"
				Write-Progress -Activity "Executing Flow $flow_id" -Status "$status - Steps: $step_count" -PercentComplete -1 
				Start-Sleep -Seconds 3
			}
		}
	}
}

