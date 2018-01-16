# PSOffice365

This PowerShell module is a stripped down version of a customised module used at work for managing Office 365. 

## Requirements
 - Fully tested on PowerShell 5.1.
 - AzureAD module (`Install-Module -Name AzureAD` if need be, from PowerShell).

## Usage
1. Git Clone, or download the [latest release](https://github.com/robinmalik/PSOffice365/releases/latest) and extract the zip files to your PowerShell profile directory (i.e. the `Modules` directory under wherever `$profile` points to in your PS console). 
2. Close and reopen PowerShell.
3. Optional: Connect to AzureAD by running `Connect-AzureAD` - if you don't do this, functions will prompt you for credentials.
4. Run `Get-Command -Module PSOffice365` to see all commands in the module.
5. Run `Get-Help <function name>` to get help on a particular function.

