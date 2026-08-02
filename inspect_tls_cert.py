import ssl
import socket
import datetime

hostname = '127.0.0.1'
port = 18443

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

with socket.create_connection((hostname, port)) as sock:
    with ctx.wrap_socket(sock, server_hostname='easychat.local') as ssock:
        cert = ssock.getpeercert(binary_form=True)
        # Parse cert X.509
        import ssl
        cert_dict = ssock.getpeercert()
        cipher = ssock.cipher()
        version = ssock.version()
        print("TLS Version:", version)
        print("Cipher Suite:", cipher)
        print("Peer Certificate Raw Length:", len(cert))
