#!/usr/bin/env python3
"""Prepare credentials from one GitHub Actions secret without printing them."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess


def run(arguments):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        raise SystemExit(f"{Path(arguments[0]).name} {arguments[1]} failed; check OWL_SIGNING credentials.")


def main():
    raw = os.environ.pop("OWL_SIGNING", "")
    if not raw:
        raise SystemExit("Set the OWL_SIGNING repository secret before releasing (see docs/DEVELOPMENT.md).")
    credentials = json.loads(raw)
    os.umask(0o077)
    directory = Path("apple_secrets")
    directory.mkdir(exist_ok=True)
    for field, filename in [("certificate", "owl-developer-id.cer"), ("private_key", "owl-developer-id.key")]:
        (directory / filename).write_bytes(base64.b64decode(credentials[field], validate=True))
    keychain = os.environ["NOTARY_KEYCHAIN"]
    password = secrets.token_urlsafe(32)
    run(["security", "create-keychain", "-p", password, keychain])
    run(["security", "set-keychain-settings", "-lut", "3600", keychain])
    run(["security", "unlock-keychain", "-p", password, keychain])
    run(["xcrun", "notarytool", "store-credentials", os.environ["NOTARY_PROFILE"],
         "--keychain", keychain, "--apple-id", credentials["apple_id"],
         "--team-id", credentials["team_id"], "--password", credentials["app_password"]])
    print("Signing files and validated notarization credentials are ready.")


if __name__ == "__main__":
    main()
