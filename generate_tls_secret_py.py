import base64
import datetime
import subprocess

# Standard RSA self-signed PEM certificate & key generator using PowerShell / CertEnroll or Python ssl
ps_script = """
$cert = New-SelfSignedCertificate -DnsName "easychat.local", "*.easychat.local" -CertStoreLocation "cert:\\CurrentUser\\My" -NotAfter (Get-Date).AddYears(1)
$key = [System.IO.File]::ReadAllBytes("$env:TEMP\\dummy.key")
"""

# Or use simple openssl via Git Bash / WSL if available or PowerShell New-SelfSignedCertificate
cmd = 'powershell -Command "$cert = New-SelfSignedCertificate -DnsName \\"easychat.local\\", \\"*.easychat.local\\" -CertStoreLocation \\"cert:\\LocalMachine\\My\\"; Export-Certificate -Cert $cert -FilePath \\"$env:TEMP\\cert.cer\\""'

try:
    subprocess.run(cmd, shell=True, check=True)
    print("PowerShell self-signed certificate generated")
except Exception as e:
    print("PS Error:", e)
