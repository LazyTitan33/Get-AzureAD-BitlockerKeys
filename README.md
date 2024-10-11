# Get-AzureAD-BitlockerKeys

Full powershell script to directly query the BitlockerKeys of devices registered for the given account.  
In case of 2FA, the AzureAD powershell module is automatically installed within the context of the current user (low privilege) and you are prompted to login interactively.

## Usage

```text
.\Get-AzureAD-BitlockerKeys.ps1 -email email@example.com -password Password123!
```

![image](https://github.com/user-attachments/assets/1b5b7a51-9fa5-4279-82eb-52a69fe7b783)

