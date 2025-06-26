Add-Type -AssemblyName System.Security
$password = "EF6-U6!!"
([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::Unicode.GetBytes($password), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser) | ForEach-Object ToString X2) -join "" | clip 