#!/usr/bin/env python3

"""Regression test for re-signers that resize the Mach-O __LINKEDIT mapping."""

import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TOOL_PATH = ROOT / "tools" / "macho_attest.py"


def run(*command):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def load_tool():
    spec = importlib.util.spec_from_file_location("macho_attest", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load macho_attest.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if sys.platform != "darwin":
        print("SKIP: this regression test uses macOS codesign")
        return 0
    if any(shutil.which(command) is None for command in ("clang", "codesign", "openssl")):
        print("SKIP: clang, codesign, and openssl are required")
        return 0

    macho_attest = load_tool()
    with tempfile.TemporaryDirectory(prefix="unbound-attestation-") as directory:
        directory = Path(directory)
        source = directory / "fixture.c"
        dylib = directory / "fixture.dylib"
        private_key = directory / "private.pem"
        public_key = directory / "public.pem"
        source.write_text(
            '__attribute__((section("__TEXT,__attestation"), used))\n'
            "const unsigned char AttestationPlaceholder[256] = {0};\n"
        )

        run("clang", "-dynamiclib", "-Wl,-headerpad_max_install_names", "-o", str(dylib), str(source))
        run("openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(private_key))
        run("openssl", "ec", "-in", str(private_key), "-pubout", "-out", str(public_key))
        run(
            sys.executable,
            str(TOOL_PATH),
            "sign",
            str(dylib),
            "--private-key",
            str(private_key),
            "--commit-hash",
            "0" * 40,
            "--package-version",
            "2.5.1",
        )

        before = dylib.read_bytes()
        before_info = macho_attest.parse_thin(before)
        macho_attest.verify_file(dylib, public_key)

        run("codesign", "-f", "-s", "-", str(dylib))

        after = dylib.read_bytes()
        after_info = macho_attest.parse_thin(after)
        if before_info["linkedit_vmsize"] is None or after_info["linkedit_vmsize"] is None:
            raise AssertionError("fixture has no __LINKEDIT segment")
        if before[before_info["linkedit_vmsize"] : before_info["linkedit_vmsize"] + 8] == after[
            after_info["linkedit_vmsize"] : after_info["linkedit_vmsize"] + 8
        ]:
            raise AssertionError("codesign did not exercise the __LINKEDIT.vmsize mutation")
        macho_attest.verify_file(dylib, public_key)

    print("PASS: attestation survives macOS re-signing that grows __LINKEDIT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
