#!/usr/bin/python3
# 
# export-acme-certs.py
#
# The certificates created by traefik end up in the acme.json file. To use
# these with other servers it can be useful to have the cert and key exported
# to .pem files. 
#
# This script will export each cert in the json into a pair of
# .pem files.
#
# There's a .gitignore in this directory for *.pem, but careful not to commit
# your keys!
#
import json
import base64
import os

# Read Traefik ACME JSON
try:
    with open("acme.json") as acme_file:
        acme = json.load(acme_file)
except OSError as error:
    print("Failed to access acme.json - try 'sudo ./export-acme-certs.py' - ")
    print(error)
    quit()

# Create directory for .pem files. Fails if already present
try:
    cwd = os.getcwd()
    os.mkdir(cwd+"/pem")
except OSError as error:
    print("I need my own space, please get rid of "+cwd+"/pem so I can use it")
    print(error)
    quit()

# Select certificates from a specific resolver
resolver_name = "myresolver"
certs = acme[resolver_name]["Certificates"]

# Find the specific certificate we are looking for
for c in range(len(certs)):
    # Extract X.509 certificate data
    certificate_data = base64.b64decode(certs[c]["certificate"])
    key_data = base64.b64decode(certs[c]["key"])

    domain = certs[c]["domain"]["main"] 

    # Export certificate and key to file
    filename = cwd+"/pem/"+domain+".certificate.pem"
    with open(filename, "wb") as certfile:
        certfile.write(certificate_data)
        os.chmod(filename , 0o400)

    filename = cwd+"/pem/"+domain+".key.pem"
    with open(filename, "wb") as keyfile:
        keyfile.write(key_data)
        os.chmod(filename , 0o400)

print()
print("Export successful")
print("Find your certificates at "+cwd+"/pem")
print("Certificates have been permissioned for owner (likely root if using sudo) read only (400)")
print()
