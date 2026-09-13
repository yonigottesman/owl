#!/usr/bin/env python3
"""Sign using the local certificate export, without importing into login keychain."""
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parent.parent
app = root / "Owl.app"


def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        # Arguments can contain passwords: never include them in errors/logs.
        if Path(args[0]).name == "codesign":
            print(result.stderr.strip(), file=sys.stderr)
        raise RuntimeError(f"{Path(args[0]).name} {args[1]} failed (exit {result.returncode})")
    return result.stdout


def main():
    certificate = root / "apple_secrets/owl-developer-id.cer"
    private_key = root / "apple_secrets/owl-developer-id.key"
    if not certificate.exists() or not private_key.exists():
        raise RuntimeError("Missing the new Developer ID certificate or matching private key")
    with tempfile.TemporaryDirectory(prefix="owl-sign-") as directory:
        keychain = str(Path(directory) / "signing.keychain-db")
        key = secrets.token_urlsafe(32)
        previous = shlex.split(run(["security", "list-keychains", "-d", "user"]))
        try:
            run(["security", "create-keychain", "-p", key, keychain])
            run(["security", "list-keychains", "-d", "user", "-s", *previous, keychain])
            run(["security", "set-keychain-settings", "-lut", "300", keychain])
            run(["security", "unlock-keychain", "-p", key, keychain])
            pem = Path(directory) / "certificate.pem"
            pem.write_text(run(["openssl", "x509", "-inform", "DER", "-in", str(certificate), "-outform", "PEM"]))
            archive = Path(directory) / "identity.p12"
            password = secrets.token_urlsafe(32)
            export = subprocess.run(["openssl", "pkcs12", "-export", "-inkey", str(private_key),
                "-in", str(pem), "-out", str(archive), "-passout", "stdin"],
                input=password + "\n", text=True, capture_output=True)
            if export.returncode:
                raise RuntimeError("Could not package the signing identity")
            run(["security", "import", str(archive), "-k", keychain,
                 "-P", password, "-T", "/usr/bin/codesign"])
            # Supply Apple's intermediate certificate in the isolated keychain;
            # system trust anchors still perform normal certificate validation.
            intermediate = Path(directory) / "DeveloperIDG2CA.cer"
            with urllib.request.urlopen("https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer", timeout=30) as response:
                intermediate.write_bytes(response.read())
            run(["security", "import", str(intermediate), "-k", keychain])
            anchor = Path(directory) / "AppleIncRootCertificate.cer"
            with urllib.request.urlopen("https://www.apple.com/appleca/AppleIncRootCertificate.cer", timeout=30) as response:
                anchor.write_bytes(response.read())
            run(["security", "import", str(anchor), "-k", keychain])
            # Keep Apple's public chain available after the ephemeral private-key
            # keychain disappears; securityd caches certificate locations.
            login = shlex.split(run(["security", "default-keychain", "-d", "user"]))[0]
            for public_cert in [intermediate, anchor]:
                result = subprocess.run(["security", "import", str(public_cert), "-k", login], capture_output=True, text=True)
                if result.returncode and "already exists" not in result.stderr:
                    raise RuntimeError("Could not install Apple's public certificate chain")
            run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                 "-s", "-k", key, keychain])
            identities = run(["security", "find-identity", "-v", "-p", "codesigning", keychain])
            match = re.search(r'([0-9A-F]{40}) "(Developer ID Application: [^"]+)"', identities)
            if not match:
                raise RuntimeError("No valid Developer ID Application identity; refusing development or revoked certificates")
            identity, name = match.groups()
            cert = Path(directory) / "signer.pem"
            cert.write_text(run(["security", "find-certificate", "-c", name, "-p", keychain]))
            run(["security", "verify-cert", "-c", str(cert), "-p", "codeSign", "-k", keychain, "-R", "ocsp", "-R", "require"])
            # Allow securityd to observe the newly imported chain before codesign.
            time.sleep(2)
            for target in [app / "Contents/Resources/com.yonigo.Owl.helper", app]:
                for attempt in range(3):
                    try:
                        run(["codesign", "--force", "--sign", identity, "--keychain", keychain,
                             "--identifier", "com.yonigo.Owl.helper" if target != app else "com.yonigo.Owl",
                             "--options", "runtime", "--timestamp", str(target)])
                        break
                    except RuntimeError:
                        if attempt == 2:
                            raise
                        time.sleep(2)
            run(["codesign", "--verify", "--deep", "--strict", str(app)])
            print(f"Signed Owl with {name}; certificate revocation and signature checks passed. Notarization is still required.")
        finally:
            run(["security", "list-keychains", "-d", "user", "-s", *previous])
            if Path(keychain).exists():
                run(["security", "delete-keychain", keychain])


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Signing failed: {error}", file=sys.stderr)
        sys.exit(1)
