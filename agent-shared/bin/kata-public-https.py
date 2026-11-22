#!/usr/bin/env python3
import ipaddress
import json
import os
import socket
import sys
from urllib.parse import urlsplit

def public_address(host):
    for record in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM):
        address = ipaddress.ip_address(record[4][0])
        if (
            address.is_global
            and not address.is_multicast
            and not address.is_reserved
            and not getattr(address, "ipv4_mapped", None)
            and not getattr(address, "sixtofour", None)
            and not getattr(address, "teredo", None)
        ):
            return f"[{address}]" if address.version == 6 else str(address)
    raise ValueError("The host has no public address.")

def arguments(url, validators):
    if any(ord(character) < 32 or ord(character) == 127 for character in url):
        raise ValueError("Invalid HTTPS URL.")
    parsed = urlsplit(url)
    host = parsed.hostname
    if (
        parsed.scheme != "https" or not host or "." not in host
        or parsed.username is not None or parsed.password is not None
        or parsed.port not in (None, 443) or parsed.fragment
    ):
        raise ValueError("Use a public HTTPS URL without credentials.")
    if not isinstance(validators, dict):
        raise ValueError("Invalid HTTP validators.")
    headers = []
    for name, value in validators.items():
        if (
            name not in ("If-None-Match", "If-Modified-Since")
            or not isinstance(value, str)
            or any(ord(character) < 32 or ord(character) == 127 for character in value)
        ):
            raise ValueError("Invalid HTTP validator.")
        headers.extend(("--header", f"{name}: {value}"))
    address = public_address(host)
    return [
        "curl", "-q", "--silent", "--show-error", "--include",
        "--no-location", "--globoff", "--suppress-connect-headers",
        "--proto", "=https", "--max-time", "6", "--max-filesize", "65536",
        "--connect-to", f"{host}:443:{address}:443", *headers, "--", url,
    ]

if __name__ == "__main__":
    try:
        url, headers = sys.argv[1:]
        command = arguments(url, json.loads(headers))
        os.execvp(command[0], command)
    except (OSError, ValueError) as error:
        sys.exit(f"Public HTTPS read rejected: {error}")
