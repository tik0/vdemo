#!/bin/bash
fqdn=$(hostname -f)
openssl req -newkey rsa:2048 -x509 -nodes -keyout "$1" -new -out "$1" -subj /CN=$fqdn -reqexts SAN -extensions SAN -config <(cat /etc/ssl/openssl.cnf - <<< $'[SAN]\nsubjectAltName=DNS:'$fqdn) -sha256 -days 3650
