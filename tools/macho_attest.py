#!/usr/bin/env python3

import argparse
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path

MAGIC_THIN_64 = 0xfeedfacf
MAGIC_FAT = 0xcafebabe
MAGIC_FAT_64 = 0xcafebabf
MAGIC_FAT_SWAPPED = 0xbebafeca
MAGIC_FAT_64_SWAPPED = 0xbfbafeca
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
MAGIC = 0x41545453
VERSION = 1
ALGORITHM = 1
KEY_ID = 0x3CE00B70
SECTION_SIZE = 256
SIGNATURE_CAPACITY = 96
SECTION_NAME = b"__attestation"
SEGMENT_NAME = b"__TEXT"


class AttestationError(Exception):
    pass


def read_u32(data, offset, endian="<"):
    if offset < 0 or offset + 4 > len(data):
        raise AttestationError("integer outside Mach-O bounds")
    return struct.unpack_from(endian + "I", data, offset)[0]


def read_i32(data, offset, endian="<"):
    if offset < 0 or offset + 4 > len(data):
        raise AttestationError("integer outside Mach-O bounds")
    return struct.unpack_from(endian + "i", data, offset)[0]


def read_u64(data, offset, endian="<"):
    if offset < 0 or offset + 8 > len(data):
        raise AttestationError("integer outside Mach-O bounds")
    return struct.unpack_from(endian + "Q", data, offset)[0]


def parse_thin(data):
    if len(data) < 32:
        raise AttestationError("Mach-O header is truncated")
    magic = read_u32(data, 0)
    if magic != MAGIC_THIN_64:
        raise AttestationError("expected a little-endian 64-bit Mach-O slice")
    cpu_type = read_i32(data, 4)
    cpu_subtype = read_i32(data, 8)
    ncmds = read_u32(data, 16)
    sizeofcmds = read_u32(data, 20)
    commands_start = 32
    commands_end = commands_start + sizeofcmds
    if commands_end > len(data):
        raise AttestationError("load commands are truncated")
    section = None
    code_signature = None
    linkedit_vmsize = None
    linkedit_filesize = None
    offset = commands_start
    for _ in range(ncmds):
        if offset + 8 > commands_end:
            raise AttestationError("load command header is truncated")
        command = read_u32(data, offset)
        command_size = read_u32(data, offset + 4)
        if command_size < 8 or offset + command_size > commands_end:
            raise AttestationError("invalid load command size")
        if command == LC_SEGMENT_64:
            if command_size < 72:
                raise AttestationError("segment command is truncated")
            segment_name = data[offset + 8 : offset + 24].split(b"\0", 1)[0]
            if segment_name == b"__LINKEDIT":
                linkedit_vmsize = offset + 32
                linkedit_filesize = offset + 48
            section_count = read_u32(data, offset + 64)
            sections_end = offset + 72 + section_count * 80
            if sections_end > offset + command_size:
                raise AttestationError("section table is truncated")
            section_offset = offset + 72
            for _ in range(section_count):
                section_name = data[section_offset : section_offset + 16].split(b"\0", 1)[0]
                section_segment = data[section_offset + 16 : section_offset + 32].split(b"\0", 1)[0]
                if section_name == SECTION_NAME and section_segment == SEGMENT_NAME:
                    file_offset = read_u32(data, section_offset + 48)
                    file_size = read_u64(data, section_offset + 40)
                    if file_size != SECTION_SIZE or file_offset + file_size > len(data):
                        raise AttestationError("invalid attestation section")
                    section = {"offset": file_offset, "size": file_size}
                section_offset += 80
        elif command == LC_CODE_SIGNATURE:
            if command_size < 16:
                raise AttestationError("code signature command is truncated")
            signature_offset = read_u32(data, offset + 8)
            signature_size = read_u32(data, offset + 12)
            if signature_offset > len(data):
                raise AttestationError("code signature offset is outside the slice")
            code_signature = {
                "command_offset": offset,
                "offset": signature_offset,
                "size": signature_size,
            }
        offset += command_size
    if section is None:
        raise AttestationError("attestation section is missing")
    boundary = code_signature["offset"] if code_signature else len(data)
    if boundary > len(data):
        raise AttestationError("canonicalization boundary is outside the slice")
    return {
        "cpu_type": cpu_type,
        "cpu_subtype": cpu_subtype,
        "section": section,
        "code_signature": code_signature,
        "linkedit_vmsize": linkedit_vmsize,
        "linkedit_filesize": linkedit_filesize,
        "boundary": boundary,
    }


def fat_slices(data):
    if len(data) < 4:
        raise AttestationError("file is empty")
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (MAGIC_FAT, MAGIC_FAT_SWAPPED):
        endian = ">" if magic == MAGIC_FAT else "<"
        count = struct.unpack_from(endian + "I", data, 4)[0]
        header_size = 8
        entry_size = 20
        is_64 = False
    elif magic in (MAGIC_FAT_64, MAGIC_FAT_64_SWAPPED):
        endian = ">" if magic == MAGIC_FAT_64 else "<"
        count = struct.unpack_from(endian + "I", data, 4)[0]
        header_size = 8
        entry_size = 32
        is_64 = True
    else:
        info = parse_thin(data)
        return [(0, len(data), info["cpu_type"], info["cpu_subtype"])]
    entries_end = header_size + count * entry_size
    if entries_end > len(data):
        raise AttestationError("fat architecture table is truncated")
    slices = []
    for index in range(count):
        entry = header_size + index * entry_size
        cpu_type = struct.unpack_from(endian + "i", data, entry)[0]
        cpu_subtype = struct.unpack_from(endian + "i", data, entry + 4)[0]
        offset = struct.unpack_from(endian + "Q" if is_64 else endian + "I", data, entry + 8)[0]
        size = struct.unpack_from(endian + "Q" if is_64 else endian + "I", data, entry + (16 if is_64 else 12))[0]
        if offset + size > len(data):
            raise AttestationError("fat architecture slice is outside the file")
        slices.append((offset, size, cpu_type, cpu_subtype))
    return slices


def canonical_slice(slice_data):
    info = parse_thin(slice_data)
    canonical = bytearray(slice_data[: info["boundary"]])
    section_offset = info["section"]["offset"]
    if section_offset + SECTION_SIZE > len(canonical):
        raise AttestationError("attestation section is outside canonical data")
    canonical[section_offset + 24 : section_offset + 56] = b"\0" * 32
    canonical[section_offset + 56 : section_offset + 58] = b"\0" * 2
    canonical[section_offset + 60 : section_offset + 60 + SIGNATURE_CAPACITY] = b"\0" * SIGNATURE_CAPACITY
    code_signature = info["code_signature"]
    if code_signature:
        command_offset = code_signature["command_offset"]
        if command_offset + 16 > len(canonical):
            raise AttestationError("code signature command is outside canonical data")
        canonical[command_offset + 8 : command_offset + 16] = b"\0" * 8
    # Re-signers can grow the mapped __LINKEDIT range when the new blob is larger.
    if info["linkedit_vmsize"] is not None:
        field = info["linkedit_vmsize"]
        if field + 8 > len(canonical):
            raise AttestationError("__LINKEDIT command is outside canonical data")
        canonical[field : field + 8] = b"\0" * 8
    if info["linkedit_filesize"] is not None:
        field = info["linkedit_filesize"]
        if field + 8 > len(canonical):
            raise AttestationError("__LINKEDIT command is outside canonical data")
        canonical[field : field + 8] = b"\0" * 8
    return bytes(canonical), info


def read_attestation(slice_data, info):
    offset = info["section"]["offset"]
    raw = slice_data[offset : offset + SECTION_SIZE]
    values = struct.unpack_from("<IHHIIIi32sHH96s41s32s27s", raw)
    return {
        "magic": values[0],
        "version": values[1],
        "algorithm": values[2],
        "size": values[3],
        "key_id": values[4],
        "cpu_type": values[5],
        "cpu_subtype": values[6],
        "digest": values[7],
        "signature_length": values[8],
        "signature": values[10][: values[8]],
        "commit_hash": values[11].split(b"\0", 1)[0].decode("ascii", "replace"),
        "package_version": values[12].split(b"\0", 1)[0].decode("ascii", "replace"),
    }


def sign_file(path, private_key, commit_hash, package_version):
    original = bytearray(Path(path).read_bytes())
    slices = fat_slices(original)
    for offset, size, cpu_type, cpu_subtype in slices:
        slice_data = bytearray(original[offset : offset + size])
        info = parse_thin(slice_data)
        section = bytearray(SECTION_SIZE)
        struct.pack_into("<IHHIIIi", section, 0, MAGIC, VERSION, ALGORITHM, SECTION_SIZE, KEY_ID, cpu_type, cpu_subtype)
        commit_bytes = commit_hash.encode("ascii")
        version_bytes = package_version.encode("utf-8")
        if len(commit_bytes) > 40 or len(version_bytes) > 31:
            raise AttestationError("attestation metadata exceeds its fixed capacity")
        section[156 : 156 + len(commit_bytes)] = commit_bytes
        section[197 : 197 + len(version_bytes)] = version_bytes
        section_offset = info["section"]["offset"]
        slice_data[section_offset : section_offset + SECTION_SIZE] = section
        canonical, info = canonical_slice(slice_data)
        digest = hashlib.sha256(canonical).digest()
        with tempfile.TemporaryDirectory() as temporary:
            canonical_path = Path(temporary) / "canonical.bin"
            signature_path = Path(temporary) / "signature.bin"
            canonical_path.write_bytes(canonical)
            subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", str(private_key), "-out", str(signature_path), str(canonical_path)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            signature = signature_path.read_bytes()
        if len(signature) > SIGNATURE_CAPACITY:
            raise AttestationError("P-256 signature exceeds embedded capacity")
        struct.pack_into("<32sH", section, 24, digest, len(signature))
        section[60 : 60 + len(signature)] = signature
        original[offset + section_offset : offset + section_offset + SECTION_SIZE] = section
    Path(path).write_bytes(original)


def verify_file(path, public_key):
    data = Path(path).read_bytes()
    results = []
    for offset, size, cpu_type, cpu_subtype in fat_slices(data):
        slice_data = data[offset : offset + size]
        canonical, info = canonical_slice(slice_data)
        attestation = read_attestation(slice_data, info)
        if attestation["magic"] != MAGIC or attestation["version"] != VERSION or attestation["algorithm"] != ALGORITHM:
            raise AttestationError("attestation header is invalid")
        if attestation["size"] != SECTION_SIZE or attestation["key_id"] != KEY_ID:
            raise AttestationError("attestation metadata is invalid")
        if attestation["cpu_type"] != cpu_type or attestation["cpu_subtype"] != cpu_subtype:
            raise AttestationError("attestation architecture does not match its slice")
        if not 1 <= attestation["signature_length"] <= SIGNATURE_CAPACITY:
            raise AttestationError("attestation signature length is invalid")
        digest = hashlib.sha256(canonical).digest()
        if digest != attestation["digest"]:
            raise AttestationError("attestation digest does not match the Mach-O slice")
        with tempfile.TemporaryDirectory() as temporary:
            canonical_path = Path(temporary) / "canonical.bin"
            signature_path = Path(temporary) / "signature.bin"
            canonical_path.write_bytes(canonical)
            signature_path.write_bytes(attestation["signature"])
            subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(public_key), "-signature", str(signature_path), str(canonical_path)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        results.append({"cpuType": cpu_type, "cpuSubtype": cpu_subtype, "digest": digest.hex(), "signatureLength": attestation["signature_length"], "commitHash": attestation["commit_hash"], "packageVersion": attestation["package_version"]})
    return results


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    sign_parser = subparsers.add_parser("sign")
    sign_parser.add_argument("path", type=Path)
    sign_parser.add_argument("--private-key", required=True, type=Path)
    sign_parser.add_argument("--commit-hash", required=True)
    sign_parser.add_argument("--package-version", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("path", type=Path)
    verify_parser.add_argument("--public-key", required=True, type=Path)
    arguments = parser.parse_args()
    if arguments.command == "sign":
        sign_file(arguments.path, arguments.private_key, arguments.commit_hash, arguments.package_version)
        print(json.dumps({"path": str(arguments.path), "status": "signed"}))
    else:
        results = verify_file(arguments.path, arguments.public_key)
        for result in results:
            print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (AttestationError, OSError, subprocess.CalledProcessError, ValueError) as error:
        raise SystemExit(str(error))
