#Requires -Modules AzureAD
function Copy-UserLicense
{
	<#
		.SYNOPSIS
			This function will copy all Office 365 Licenses (respecting disabled service plans) from one user, to one or more others.
		.DESCRIPTION
			This function will copy all Office 365 Licenses (respecting disabled service plans) from one user, to one or more others.

			More specifically it will:
			- Replicate SKUs and Service Plans where the target user does not possess those SKUs already.
			- Overwrite Service Plan configuration within a SKU, where the target user already has that SKU.
			- Ignores SKUs that the target user possesses but the source user does not (i.e. it does not remove SKUs).
		.PARAMETER UserToLicense
			Can be an array, or string. The userprincipalname names of the accounts you wish to edit licenses for.
		.PARAMETER UserToCopy
			The userprincipal name of the account you wish to copy.
		.PARAMETER Credential
			A credential object for a user with administrative permissions in Office 365.
		.EXAMPLE
			# Copy the SKUs and service plans from a template staff account to a new user account:
			Copy-UserLicense -UserToLicense 'newstaffuser@domain.com' -UserToCopy 'standardstaffmember@domain.com' -Verbose
		.EXAMPLE
			# Get user accounts from Active Directory in an OU called student, that have been created in the last 1 day: 
			$NewADUsers = Get-ADUser -Filter * -Properties WhenCreated | Where-Object { $_.DistinguishedName -match 'OU=Student' -and $_.WhenCreated -gt (Get-Date).AddDays(-1) }

			# Pass all userprincipalnames to the function to license them, copying the config of a template student:
			Copy-UserLicense -UserToLicense $NewADUsers.UserPrincipalName -UserToCopy 'template-student@domain.com' -Verbose
		.OUTPUTS
			None
	#>

    [CmdletBinding()]
    Param
    (
		[Parameter(Mandatory = $true)]
		[String[]]
		$UserToLicense,

		[Parameter(Mandatory=$true)]
		[string]
		$UserToCopy,

		[Parameter(Mandatory=$false)]
		[System.Management.Automation.PSCredential]
		[System.Management.Automation.Credential()]
		$Credential
    )

    Begin
    {
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
				Write-Verbose -Message 'Attempting to get account SKUs.'
				$Skus = Get-AzureADSubscribedSku -ErrorAction Stop
			}
			catch
			{
				throw $_
			}
		}		

        Write-Verbose -Message "$($UserToCopy): Getting User Object"
        try 
        {
            $UserWith = Get-AzureADUser -ObjectId $UserToCopy -ErrorAction Stop	
        }
		catch
		{
			throw $_
		}

		# Compare-Object -ReferenceObject $userwith.AssignedLicenses -DifferenceObject $userwithout.AssignedLicenses -Property SkuId -IncludeEqual
		# if <= this means the userWith has a licence the userwithout doesn't.
		# if => this means the user WITHOUT has a licence the reference user doesn't suggesting we remove it.

		Write-Verbose -Message "Creating an AssignedLicenses object from $UserToCopy"
		try
		{            
			# Define an Microsoft.Open.AzureAD.Model.AssignedLicenses object. Eventually this is passed to Set-AzureADUserLicense
			$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses

			# Define an array to hold (potentially) mulitple instances of 'Microsoft.Open.AzureAD.Model.AssignedLicense'
			$SkuArray = @()

			# For each Sku/license in the $UserWith:
			foreach($Sku in $UserWith.AssignedLicenses)
			{               
				# Create a new License object:
				$License = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
				# Add the SkuID and DisabledPlans to it:
				$License.SkuId = $Sku.SkuId
				$License.DisabledPlans = $Sku.DisabledPlans

				# Add to the $SkuArray (We can use $Licenses.AddLicense but this would overwrite each time)
				$SkuArray += $License

				# Information:
				$CurrentSku = ($skus | Where-Object { $_.Skuid -eq $Sku.SkuId })
				Write-Verbose -Message "Adding $($CurrentSku.SkuPartNumber) license"
				if($Sku.DisabledPlans)
				{
					Write-Verbose -Message "  > Adding service plans to disabled array:"
					foreach($SkuID in $Sku.DisabledPlans)
					{
					$Disabled = $CurrentSku.ServicePlans | Where-Object { $_.ServicePlanId -eq $SkuId } | Select-Object -ExpandProperty ServicePlanName
					Write-Verbose -Message "    > $Disabled"
					}
				}
				else
				{
					Write-Verbose -Message "  > No disabled service plans in this license"
				}
			}

			# Add the array of Microsoft.Open.AzureAD.Model.AssignedLicense to the Microsoft.Open.AzureAD.Model.AssignedLicenses object:
			$Licenses.AddLicenses = $SkuArray
		}
		catch 
		{
			throw $_
		}
	}
	Process 
	{
		foreach($User in $UserToLicense)
		{
			Write-Verbose -Message "$($User): Getting User Object"
			try 
			{
				$UserWithout = Get-AzureADUser -ObjectId $User -ErrorAction Stop	
			}
			catch 
			{
				$_
				continue
			}         

			Write-Verbose -Message "$($User): Applying Licences"
			try
			{
				Set-AzureADUserLicense -ObjectId $UserWithout.ObjectId -AssignedLicenses $Licenses -ErrorAction Stop
			}
			catch 
			{
				$_
				continue
			}
		}
    }
    End
    {
    }
}