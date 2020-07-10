Set-StrictMode -Version Latest
class AutoCloseBugManager {
    hidden [SVTEventContext []] $ControlResults
    hidden [SubscriptionContext] $subscriptionContext;
    AutoCloseBugManager([SubscriptionContext] $subscriptionContext, [SVTEventContext []] $ControlResults) {
        $this.subscriptionContext = $subscriptionContext;
        $this.ControlResults = $ControlResults
    }


    #function to auto close resolved bugs
    hidden [void] AutoCloseBug([SVTEventContext []] $ControlResults) {

        #tags that need to be searched
        $TagSearchKeyword = ""
        #flag to check number of current keywords in the tag
        $QueryKeyWordCount = 0;
        #maximum no of keywords that need to be checked per batch     
        $MaxKeyWordsToQuery = 100;
        #all passing control results go here
        $PassedControlResults = @();

        #collect all passed control results
        $ControlResults | ForEach-Object {
            if ($_.ControlResults[0].VerificationResult -eq "Passed") {
                $PassedControlResults += $_
            }
        }

        #number of passed controls
        $PassedControlResultsLength = $PassedControlResults.Length


        $PassedControlResults | ForEach-Object {
            			
            $control = $_;

            #if control results are less than the maximum no of tags per batch
            if ($PassedControlResultsLength -lt $MaxKeyWordsToQuery) {
                #check for number of tags in current query
                $QueryKeyWordCount++;
                #complete the query
                $TagSearchKeyword += "Tags: " + $this.GetHashedTag($control.ControlItem.Id, $control.ResourceContext.ResourceId) + " OR "
                #if the query count equals the passing control results, search for bugs for this batch
                if ($QueryKeyWordCount -eq $PassedControlResultsLength) {
                    #to remove OR from the last tag keyword
                    $TagSearchKeyword = $TagSearchKeyword.Substring(0, $TagSearchKeyword.length - 3)
                    $response = $this.GetWorkItemByHash($TagSearchKeyword)
                    #if bug was present
                    if ($response[0].results.count -gt 0) {
                        $response.results.values | ForEach-Object {
                            #close the bug
                            $id = ($_.fields | where { $_.name -eq "ID" }).value
                            $Project = $_.project
                            $this.CloseBug($id, $Project)
                        }
                    }
                }
            }
                #if the number of control results was more than batch size
                else {
                    $QueryKeyWordCount++;
                    $TagSearchKeyword += "Tags: " + $this.GetHashedTag($control.ControlItem.Id, $control.ResourceContext.ResourceId) + " OR "
                    #if number of tags reaches batch limit
                    if ($QueryKeyWordCount -eq $MaxKeyWordsToQuery) {
                        #query for all these tags and their bugs
                        $TagSearchKeyword = $TagSearchKeyword.Substring(0, $TagSearchKeyword.length - 3)
                        $response = $this.GetWorkItemByHash($TagSearchKeyword)
                        if ($response[0].results.count -gt 0) {
                            $response.results.values | ForEach-Object {
                                $id = ($_.fields | where { $_.name -eq "ID" }).value
                                $Project = $_.project
                                $this.CloseBug($id, $Project)
                            }
                        }
                        #Reinitialize for the next batch
                        $QueryKeyWordCount = 0;
                        $TagSearchKeyword = "";
                        $PassedControlResultsLength -= $MaxKeyWordsToQuery
                    }
                }
                
            }

        
        
    
    }

    #function to close an active bug
    hidden [void] CloseBug([string] $id, [string] $Project) {
        $url = "https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=5.1" -f $this.subscriptionContext.SubscriptionName, $Project, $id
        
        #load the closed bug template
        $BugTemplate = [ConfigurationManager]::LoadServerConfigFile("TemplateForClosedBug.Json")
        $BugTemplate = $BugTemplate | ConvertTo-Json -Depth 10

           
           
        $header = [WebRequestHelper]::GetAuthHeaderFromUriPatch($url)
                
        try {
            $responseObj = Invoke-RestMethod -Uri $url -Method Patch  -ContentType "application/json-patch+json ; charset=utf-8" -Headers $header -Body $BugTemplate

        }
        catch {
            Write-Host "Could not close the bug" -Red
        }
    }

    #function to retrieve all new/active/resolved bugs 
    hidden [object] GetWorkItemByHash([string] $hash) {
		
        $url = "https://{0}.almsearch.visualstudio.com/_apis/search/workItemQueryResults?api-version=5.1-preview" -f $this.subscriptionContext.SubscriptionName

        $body = '{"searchText":"{0}","skipResults":0,"takeResults":100,"sortOptions":[],"summarizedHitCountsNeeded":true,"searchFilters":{"Projects":[],"Work Item Types":["Bug"],"States":["Active","New","Resolved"]},"filters":[],"includeSuggestions":false}' | ConvertFrom-Json
  
        $body.searchText = $hash
    
        $response = [WebRequestHelper]:: InvokePostWebRequest($url, $body)
        
        return  $response
    
    }

    #function to create hash for bug tag
    hidden [string] GetHashedTag([string] $ControlId, [string] $ResourceId) {
        $hashedTag = $null
        $stringToHash = "{0}#{1}"
        #create a hash of resource id and control id
        $stringToHash = $stringToHash.Replace("{0}", $ResourceId)
        $stringToHash = $stringToHash.Replace("{1}", $ControlId)
        #return the bug tag
        $hashedTag = [Helpers]::ComputeHash($stringToHash)
        $hashedTag = "ADOScanID: " + $hashedTag.Substring(0, 12)
        return $hashedTag
    }



}