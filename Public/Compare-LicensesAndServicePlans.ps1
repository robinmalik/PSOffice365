#Requires -Modules AzureAD
function Compare-LicensesAndServicePlans
{
    <#
		.SYNOPSIS 
			This function will compare Office 365 account SKUs and service plans with those stored in a CSV file.
			If there is no CSV file (e.g. first run), it will create one. On subsequent runs it will overwrite the
			existing file with the latest data.
		.DESCRIPTION
			This function will compare Office 365 account SKUs and service plans with those stored in a CSV file.
			If there is no CSV file (e.g. first run), it will create one. On subsequent runs it will overwrite the
			existing file with the latest data.
			It was written to help detect when new SKUs are added to an Office 365 tenancy, or when Microsoft release
			new Service Plans and include them in existing SKUs.
		.PARAMETER CSVFile
			Path for a CSV file.
		.PARAMETER Credential
			A credential object for a user with administrative permissions in Office 365.
		.EXAMPLE
			Compare-LicensesAndServicePlans
		.EXAMPLE
			Compare-LicensesAndServicePlans -CSVFile "C:\users\me\desktop\skus-and-serviceplans.csv -Credential $credentialobject
		.OUTPUTS
			ChangeType     SkuPartNumber             NewServicePlans
			----------     -------------             ---------------
			NewSku         CRMSTORAGE                CRMSTORAGE
			NewSku         POWER_BI_PRO_FACULTY      BI_AZURE_P2;EXCHANGE_S_FOUNDATION
			NewServicePlan PROJECTESSENTIALS_FACULTY EXCHANGE_S_FOUNDATION
			NewServicePlan STANDARDWOFFPACK_STUDENT  AAD_BASIC_EDU
		.NOTES
			Author: Robin Malik
    #>
    
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
		[Parameter(Mandatory=$false)]	
		[String]$CSVFile = "$PSScriptRoot\skus-and-serviceplans.csv",
	
		[Parameter(Mandatory=$false)]
		[System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )
	
	# If a user does not provide credentials:
	if(!$Credential)
	{
		# We may already be authenticated, so try and get the SKUs but if not, fall through and prompt for authentication.
		try 
		{
			Write-Verbose -Message 'Attempting to get account SKUs.'
			$Skus = Get-AzureADSubscribedSku -ErrorAction Stop
		}
		catch [Microsoft.Open.Azure.AD.CommonLibrary.AadNeedAuthenticationException] 
		{
			Write-Warning -Message 'You are authenticated. Please provide credentials for Office 365.'
			$Credential = Get-Credential -ErrorAction Stop		
			Write-Verbose -Message 'Connecting to Office 365.'
			$Connect = Connect-AzureAD -Credential $Credential -ErrorAction Stop
			$Skus = Get-AzureADSubscribedSku -ErrorAction Stop
		} 
		catch 
		{
			throw $_
		}
	}
	else
	{
		# User has provided credentials so try and connect and then get the SKUs:
		try 
		{
			Write-Verbose -Message 'Connecting to Office 365.'
			$Connect = Connect-AzureAD -Credential $Credential -ErrorAction Stop
			Write-Verbose -Message 'Attempting to get account SKUs'
			$Skus = Get-AzureADSubscribedSku -ErrorAction Stop
		}
		catch
		{
			throw $_
		}
	}

	$SkuData = $Skus | Sort-Object -Property SkuPartNumber | Select-Object SkuPartNumber,@{Name='ServicePlans';Expression={($_.ServicePlans.ServicePlanName | Sort-Object) -join ';'}},@{Name='ServicePlanCount';Expression={($_.ServicePlans).count}}
	
	if($SkuData.count -gt 0)
	{
		# If the CSV file exists, let's compare data and alert if need be:
		if(Test-Path -Path $CSVFile)
		{
			Write-Verbose -Message 'Importing CSV'
			try
			{
				$CsvData = Import-CSV $CSVFile -ErrorAction Stop
			}
			catch
			{
				throw $_
			}

			# Create arrays to hold data on any new SKUs, or new service plans:
			$NewSKUs = @()
			$NewServicePlans = @()

			$Changes = @()

			Write-Verbose -Message 'Starting check of live data against existing CSV file'
			# We can use Compare-Object -Property ServicePlans and this would show differences, but the object returned would not contain the SkuPartNumber
			# and therefore we'd be unable to accurately ascertain which SKU this new service plan was in.
			# So instead, let's loop:
			foreach($Sku in $SkuData) 
			{
				# Get the corresponding SKU from the CSV file
				$CsvSkuMatch = $CsvData | Where-Object { $_.SkuPartNumber -eq $sku.SkuPartNumber }

				if(!$CsvSkuMatch)
				{
					Write-Verbose -Message "$($Sku.SkuPartNumber): Not found in CSV file! This is a new SKU in your tenancy."
					$hashTable = [ordered]@{
						'ChangeType' = 'NewSku'
						'SkuPartNumber' = $Sku.SkuPartNumber
						'NewServicePlans' = $Sku.ServicePlans
					}
					$Changes += (New-Object -TypeName PSObject -Property $hashTable)
					continue
				}

				# If the SKU is in both live data and CSV, compare the service plans line:
				if($CsvSkuMatch.ServicePlans -ne $Sku.ServicePlans)
				{
					Write-Warning -Message "$($Sku.SkuPartNumber): Service Plans are not equal."
					$CsvServicePlanArray = $CsvSkuMatch.ServicePlans -split ';'
					$LiveDataServicePlanArray = $Sku.ServicePlans -split ';'
		
					$NewO365ServicePlans = Compare-Object -ReferenceObject $csvServicePlanArray -DifferenceObject $liveDataServicePlanArray | Where-Object { $_.SideIndicator -eq '=>' }
					if($NewO365ServicePlans)
					{
						$hashTable = [ordered]@{
							'ChangeType' = 'NewServicePlan'
							'SkuPartNumber' = $Sku.SkuPartNumber
							'NewServicePlans' = $newO365ServicePlans.InputObject
						}
						$Changes += (New-Object -TypeName PSObject -Property $hashTable)
					}
				}
				else
				{
					Write-Verbose -Message "$($Sku.SkuPartNumber): Service Plans are equal."
				}
			}

			if($Changes.count -gt 0)
			{
				$Changes
			}
		}
		else 
		{
			Write-Warning -Message "No CSV file found. One will be created."
		}

		# Export O365 data to the CSV file. PowerShell 5 retains column order but previous version of PowerShell may not, so use Select-Object to force the ordering:
		if($SkuData)
		{
			try
			{
				$SkuData | Select-Object SkuPartNumber,ServicePlans,ServicePlanCount | Export-CSV $CSVFile -NoTypeInformation -Force -ErrorAction Stop
			}
			catch
			{
				throw $_				
			}
		}
	}
	else 
	{
		throw "No SKU data?"
	}






}