import os
import subprocess

# Generate private key and certificate using openssl or python
openssl_cmd = [
    "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", "tls.key", "-out", "tls.crt", "-days", "365",
    "-subj", "/CN=easychat.local/O=EasyChat Production Security"
]

try:
    subprocess.run(openssl_cmd, check=True)
    print("Generated tls.key and tls.crt")
    
    # Create k8s secret
    create_secret_cmd = [
        "kubectl", "--context", "kind-easychat", "create", "secret", "tls", "easychat-tls-cert",
        "--cert=tls.crt", "--key=tls.key", "-n", "default", "--dry-run=client", "-o", "yaml"
    ]
    result = subprocess.run(create_secret_cmd, capture_output=True, text=True, check=True)
    with open("tls_secret.yaml", "w") as f:
        f.write(result.stdout)
    print("Created tls_secret.yaml")
except Exception as e:
    print("Error:", e)
