Set-StrictMode -Version Latest 
class VariableGroup: ADOSVTBase
{    

    hidden [PSObject] $VarGrp;
    hidden [PSObject] $ProjectId;
    hidden [PSObject] $VarGrpId;
    
    VariableGroup([string] $subscriptionId, [SVTResource] $svtResource): Base($subscriptionId,$svtResource) 
    {
        $apiURL = $this.ResourceContext.ResourceId
        $this.ProjectId = $this.ResourceContext.ResourceId.Split('/')[3]
        $this.VarGrpId = $this.ResourceContext.ResourceDetails.id
        $this.VarGrp = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

    }
    hidden [ControlResult] CheckPipelineAccess([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/{1}/_apis/build/authorizedresources?type=variablegroup&id={2}&api-version=5.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId) ,$($this.VarGrpId);
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            # If var grp is not shared across all pipelines, 'count' property is available for $responseObj[0] and its value is 0. 
            # If var grp is shared across all pipelines, 'count' property is not available for $responseObj[0]. 
            #'Count' is a PSObject property and 'count' is response object property. Notice the case sensitivity here.
            
            # TODO: When there var grp is not shared across all pipelines, CheckMember in the below condition returns false when checknull flag [third param in CheckMember] is not specified (default value is $true). Assiging it $false. Need to revisit.
            if(([Helpers]::CheckMember($responseObj[0],"count",$false)) -and ($responseObj[0].count -eq 0))
            {
                $controlResult.AddMessage([VerificationResult]::Passed, "Variable group is not accessible to all pipelines.");
            }
             # When var grp is shared across all pipelines - the below condition will be true.
            elseif((-not ([Helpers]::CheckMember($responseObj[0],"count"))) -and ($responseObj.Count -gt 0) -and ([Helpers]::CheckMember($responseObj[0],"authorized"))) 
            {
                if($responseObj[0].authorized -eq $true)
                {
                    $controlResult.AddMessage([VerificationResult]::Failed, "Variable group is accessible to all pipelines.");
                }
                else
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "Variable group is not accessible to all pipelines.");
                }  
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Error, "Could not fetch authorization details of variable group.");
            }   

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch authorization details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckInheritedPermissions([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.variablegroup/roleassignments/resources/{1}%24{2}?api-version=6.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName),$($this.ProjectId) ,$($this.VarGrpId); 
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            $inheritedRoles = $responseObj | Where-Object {$_.access -eq "inherited"}
            if(($inheritedRoles | Measure-Object).Count -gt 0)
            {
                $roles = @();
                $roles += ($inheritedRoles  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}}, @{Name="Role"; Expression = {$_.role.displayName}});
                $controlResult.AddMessage([VerificationResult]::Failed,"Review the list of inherited role assignments on variable group: ", $roles);
                $controlResult.SetStateData("List of inherited role assignments on variable group: ", $roles);
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No inherited role assignments found on variable group.")
            }

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch permission details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckRBACAccess([ControlResult] $controlResult)
    {
        $url = 'https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.variablegroup/roleassignments/resources/{1}%24{2}?api-version=6.1-preview.1' -f $($this.SubscriptionContext.SubscriptionName), $($this.ProjectId), $($this.VarGrpId); 
        try 
        {
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($url);
            if(($responseObj | Measure-Object).Count -gt 0)
            {
                $roles = @();
                $roles += ($responseObj  | Select-Object -Property @{Name="Name"; Expression = {$_.identity.displayName}}, @{Name="Role"; Expression = {$_.role.displayName}}, @{Name="AccessType"; Expression = {$_.access}});
                $controlResult.AddMessage([VerificationResult]::Verify,"Review the list of role assignments on variable group: ", $roles);
                $controlResult.SetStateData("List of role assignments on variable group: ", $roles);
            }
            else 
            {
                $controlResult.AddMessage([VerificationResult]::Passed,"No role assignments found on variable group.")
            }

        }
        catch 
        {   
            $controlResult.AddMessage([VerificationResult]::Error,"Could not fetch RBAC details of variable group.");    
        }
        return $controlResult
    }
    hidden [ControlResult] CheckCredInVarGrp([ControlResult] $controlResult)
	{
        if([Helpers]::CheckMember([ConfigurationManager]::GetAzSKSettings(),"SecretsScanToolFolder"))
        {
            $ToolFolderPath = [ConfigurationManager]::GetAzSKSettings().SecretsScanToolFolder
            $SecretsScanToolName = [ConfigurationManager]::GetAzSKSettings().SecretsScanToolName
            if((-not [string]::IsNullOrEmpty($ToolFolderPath)) -and (Test-Path $ToolFolderPath) -and (-not [string]::IsNullOrEmpty($SecretsScanToolName)))
            {
                $ToolPath = Get-ChildItem -Path $ToolFolderPath -File -Filter $SecretsScanToolName -Recurse 
                if($ToolPath)
                { 
                    if($this.VarGrp)
                    {
                        try
                        {
                            $varGrpDefFileName = $($this.ResourceContext.ResourceName).Replace(" ","")
                            $varGrpDefPath = [Constants]::AzSKTempFolderPath + "\VarGrps\"+ $varGrpDefFileName + "\";
                            if(-not (Test-Path -Path $varGrpDefPath))
                            {
                                New-Item -ItemType Directory -Path $varGrpDefPath -Force | Out-Null
                            }

                            $this.VarGrp | ConvertTo-Json -Depth 5 | Out-File "$varGrpDefPath\$varGrpDefFileName.json"
                            $searcherPath = Get-ChildItem -Path $($ToolPath.Directory.FullName) -Include "buildsearchers.xml" -Recurse
                            ."$($Toolpath.FullName)" -I $varGrpDefPath -S "$($searcherPath.FullName)" -f csv -Ve 1 -O "$varGrpDefPath\Scan"    
                            
                            $scanResultPath = Get-ChildItem -Path $varGrpDefPath -File -Include "*.csv"
                            
                            if($scanResultPath -and (Test-Path $scanResultPath.FullName))
                            {
                                $credList = Get-Content -Path $scanResultPath.FullName | ConvertFrom-Csv 
                                if(($credList | Measure-Object).Count -gt 0)
                                {
                                    $controlResult.AddMessage("No. of credentials found:" + ($credList | Measure-Object).Count )
                                    $controlResult.AddMessage([VerificationResult]::Failed,"Found credentials in variables.")
                                }
                                else {
                                    $controlResult.AddMessage([VerificationResult]::Passed,"No credentials found in variables.")
                                }
                            }
                        }
                        catch 
                        {
                            #Publish Exception
                            $this.PublishException($_);
                        }
                        finally
                        {
                            #Clean temp folders 
                            Remove-ITem -Path $varGrpDefPath -Recurse
                        }
                    }
                }
            }
        }
        else {
            try {      
                if([Helpers]::CheckMember($this.VarGrp[0],"variables")) 
                {
                    $varList = @();
                    $noOfCredFound = 0;     
                    $patterns = $this.ControlSettings.Patterns | where {$_.RegexCode -eq "SecretsInBuild"} | Select-Object -Property RegexList;
                    $exclusions = $this.ControlSettings.Build.ExcludeFromSecretsCheck;
                    if(($patterns | Measure-Object).Count -gt 0)
                    {                
                        Get-Member -InputObject $this.VarGrp[0].variables -MemberType Properties | ForEach-Object {
                            if([Helpers]::CheckMember($this.VarGrp[0].variables.$($_.Name),"value") -and  (-not [Helpers]::CheckMember($this.VarGrp[0].variables.$($_.Name),"isSecret")))
                            {
                                
                                $varName = $_.Name
                                $varValue = $this.VarGrp[0].variables.$varName.value 
                                <# helper code to build a list of vars and counts
                                if ([Build]::BuildVarNames.Keys -contains $buildVarName)
                                {
                                        [Build]::BuildVarNames.$buildVarName++
                                }
                                else 
                                {
                                    [Build]::BuildVarNames.$buildVarName = 1
                                }
                                #>
                                if ($exclusions -notcontains $varName)
                                {
                                    for ($i = 0; $i -lt $patterns.RegexList.Count; $i++) {
                                        #Note: We are using '-cmatch' here. 
                                        #When we compile the regex, we don't specify ignoreCase flag.
                                        #If regex is in text form, the match will be case-sensitive.
                                        if ($varValue -cmatch $patterns.RegexList[$i]) { 
                                            $noOfCredFound +=1
                                            $varList += " $varName";   
                                            break  
                                            }
                                        }
                                }
                            } 
                        }
                        if($noOfCredFound -gt 0)
                        {
                            $varList = $varList | select -Unique
                            $controlResult.AddMessage([VerificationResult]::Failed, "Found secrets in variable group. Variables name: $varList" );
                            $controlResult.SetStateData("List of variable name containing secret: ", $varList);
                        }
                        else 
                        {
                            $controlResult.AddMessage([VerificationResult]::Passed, "No credentials found in variable group.");
                        }
                        $patterns = $null;
                    }
                    else 
                    {
                        $controlResult.AddMessage([VerificationResult]::Manual, "Regular expressions for detecting credentials in variable groups are not defined in your organization.");    
                    }
                }
                else 
                {
                    $controlResult.AddMessage([VerificationResult]::Passed, "No variables found in variable group.");
                }
            }
            catch {
                $controlResult.AddMessage([VerificationResult]::Manual, "Could not fetch the variable group definition.");
                $controlResult.AddMessage($_);
            }    
        } 
        return $controlResult;
    }
    hidden [ControlResult] FetchSTMapping([ControlResult] $controlResult) {  
        
        $orgName = "MicrosoftIT"
        $projectName = "OneITVSO"
        $projId = "3d1a556d-2042-4a45-9dae-61808ff33d3b"

        $topNQueryString = '&$top=10000'

        $releaseSTDataFileName ="ReleaseSTData.json";
        $ReleaseSTDetails = [ConfigurationManager]::LoadServerConfigFile($releaseSTDataFileName);

        $variableGroupSTMapping = @{
            data = @();
        };

        Write-Host "`n============================================`n" -ForegroundColor Red
        Write-Host "`nBeginning VG to Release mapping`n" -ForegroundColor Red
        Write-Host "`n============================================`n" -ForegroundColor Red

        $releaseDefnsObj = $null;
        try{
            $releaseDefnURL = ("https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions?api-version=4.1-preview.3" +$topNQueryString) -f $($this.SubscriptionContext.SubscriptionName), $projectName;
            $releaseDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($releaseDefnURL);
        }
        catch
        {

        }    
        if (([Helpers]::CheckMember($releaseDefnsObj, "count") -and $releaseDefnsObj[0].count -gt 0) -or (($releaseDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($releaseDefnsObj[0], "name"))) {
            $i = 1;                   
            foreach ($relDef in $releaseDefnsObj) {
                try{

                    $apiURL =  $relDef.url
                    $releaseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

                    $definitionId = ''
                    $pipelineType = ''
                    
                    $varGrps = @();
                    
                    #add var groups scoped at release scope.
                    if((($releaseObj[0].variableGroups) | Measure-Object).Count -gt 0)
                    {
                        $varGrps += $releaseObj[0].variableGroups
                    }

                    # Each release pipeline has atleast 1 env.
                    $envCount = ($releaseObj[0].environments).Count

                    for($j=0; $j -lt $envCount; $j++)
                    {
                        if((($releaseObj[0].environments[$j].variableGroups) | Measure-Object).Count -gt 0)
                        {
                            $varGrps += $releaseObj[0].environments[$j].variableGroups
                        }
                    }

                    if(($varGrps | Measure-Object).Count -gt 0)
                    {
                        $varGrps | ForEach-Object{
                            try{

                                $varGrpURL = ("https://{0}.visualstudio.com/{1}/_apis/distributedtask/variablegroups/{2}") -f $orgName, $projId, $_;
                                $varGrpObj = [WebRequestHelper]::InvokeGetWebRequest($varGrpURL);

                                $definitionId =  $releaseObj[0].id;
                                $pipelineType = 'Release';

                                $releaseSTData = $ReleaseSTDetails.Data | Where-Object { ($_.releaseDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                                if($releaseSTData){
                                    $variableGroupSTMapping.data += @([PSCustomObject] @{ variableGroupName = $varGrpObj.name; variableGroupID = $varGrpObj.id; serviceID = $releaseSTData.serviceID; projectName = $releaseSTData.projectName; projectID = $releaseSTData.projectID; orgName = $releaseSTData.orgName } )
                                    Write-Host "$i - Id = $definitionId - PipelineType = $pipelineType"
                                }
                            }
                            catch{
                                Write-Host "$i - Exception while fetching variable group id: $_"
                            }
                        }
                    }
                }
                catch
                {
                    Write-Host "$i - Exception while fetching release pipeline: [$($relDef.url)]."
                }
                $i++   
            }
            $releaseDefnsObj = $null;
        }
        $variableGroupSTMapping | ConvertTo-Json -Depth 10 | Out-File 'C:\Users\abdaga\Downloads\VariableGroupSTMapping.json'  

        $buildSTDataFileName ="BuildSTData.json";
        $BuildSTDetails = [ConfigurationManager]::LoadServerConfigFile($buildSTDataFileName);

        Write-Host "`n============================================`n" -ForegroundColor Red
        Write-Host "`nBeginning VG to Build mapping`n" -ForegroundColor Red
        Write-Host "`n============================================`n" -ForegroundColor Red

        $buildDefnsObj = $null;
        
        try{
            $buildDefnURL = ("https://dev.azure.com/{0}/{1}/_apis/build/definitions?api-version=4.1" + $topNQueryString) -f $orgName, $projectName;
            $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
        }
        catch{

        }
        
        if (([Helpers]::CheckMember($buildDefnsObj, "count") -and $buildDefnsObj[0].count -gt 0) -or (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0], "name"))) {
            $i = 1;
            foreach ($bldDef in $buildDefnsObj) {
                $apiURL =  $bldDef.url.split('?')[0]
                $buildObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL);

                $definitionId = ''
                $pipelineType = ''

                if([Helpers]::CheckMember($buildObj[0],"variableGroups"))
                {
                    $varGrps = $buildObj[0].variableGroups
                    $varGrps | ForEach-Object{
                        $definitionId =  $buildObj[0].id;
                        $pipelineType = 'Build';

                        $buildSTData = $BuildSTDetails.Data | Where-Object { ($_.buildDefinitionID -eq $definitionId) -and ($_.projectName -eq $projectName) };
                        if($buildSTData){
                            $variableGroupSTMapping.data += @([PSCustomObject] @{ variableGroupName = $_.name; variableGroupID = $_.id; serviceID = $buildSTData.serviceID; projectName = $buildSTData.projectName; projectID = $buildSTData.projectID; orgName = $buildSTData.orgName } )
                            Write-Host "$i - Id = $definitionId - PipelineType = $pipelineType"
                        }
                    }
                }
                
                $i++
            }
            $buildDefnsObj = $null;
        }

        #Removing duplicate entries of the tuple (variableGroupId,serviceId)
        $variableGroupSTMapping.data = $variableGroupSTMapping.data | Sort-Object -Unique variableGroupID,serviceID
        $variableGroupSTMapping | ConvertTo-Json -Depth 10 | Out-File 'C:\Users\abdaga\Downloads\VariableGroupSTData.json'  
        return $controlResult;
    }

}