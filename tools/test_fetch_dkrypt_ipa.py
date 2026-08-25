#!/usr/bin/env python3

import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError


ROOT = Path(__file__).resolve().parent.parent
TOOL_PATH = ROOT / "tools" / "fetch_dkrypt_ipa.py"
SPEC = importlib.util.spec_from_file_location("fetch_dkrypt_ipa", TOOL_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load fetch_dkrypt_ipa.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


IPA_BYTES = b"test ipa bytes"
IPA_SHA256 = hashlib.sha256(IPA_BYTES).hexdigest()


class FakeResponse:
    def __init__(self, body: bytes):
        self.body = io.BytesIO(body)

    def read(self, size=-1):
        return self.body.read(size)

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def response(payload):
    return FakeResponse(json.dumps(payload).encode("utf-8"))


def artifact(file_url="/v1/artifacts/artifact-1/file", sha256=IPA_SHA256):
    return {
        "id": "artifact-1",
        "fileUrl": file_url,
        "sizeBytes": len(IPA_BYTES),
        "sha256": sha256,
        "versionLabel": "342.0",
    }


class FetchDkryptIpaTests(unittest.TestCase):
    def run_fetch(self, opener, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "discord.ipa"
            with patch.object(MODULE, "urlopen", side_effect=opener):
                result = MODULE.fetch_ipa(
                    "https://ipa.dylib.dev",
                    "com.hammerandchisel.discord",
                    "342",
                    "secret-is-never-printed",
                    output,
                    poll_interval_seconds=0,
                    sleep_fn=lambda _seconds: None,
                    **kwargs,
                )
            self.assertEqual(output.read_bytes(), IPA_BYTES)
            return result

    def test_cache_hit_downloads_without_polling(self):
        calls = []

        def opener(request, timeout=0):
            calls.append(request.full_url)
            if request.get_method() == "POST":
                return response({"status": "done", "cacheHit": True, "channel": "appstore", "resolvedVersion": "342.0", "artifact": artifact()})
            return FakeResponse(IPA_BYTES)

        result = self.run_fetch(opener)
        self.assertEqual(result["cache_hit"], "true")
        self.assertEqual(len(calls), 2)

    def test_queued_running_done_reports_distinct_progress(self):
        statuses = iter(
            [
                {"status": "queued", "progress": "queued", "queue": {"position": 2, "total": 4}, "statusUrl": "/v1/jobs/job-1"},
                {"status": "running", "progress": "installing", "statusUrl": "/v1/jobs/job-1"},
                {"status": "done", "channel": "testflight", "versionLabel": "342.0_109440", "artifact": artifact()},
            ]
        )
        notices = []

        def opener(request, timeout=0):
            if request.get_method() == "POST":
                return response(next(statuses))
            if request.full_url.endswith("/file"):
                return FakeResponse(IPA_BYTES)
            return response(next(statuses))

        with patch.object(MODULE, "_notice", side_effect=notices.append):
            result = self.run_fetch(opener)
        self.assertEqual(result["is_testflight"], "true")
        self.assertGreaterEqual(len(notices), 3)
        self.assertEqual(len(notices), len(set(notices)))

    def test_failed_job_is_reported(self):
        def opener(request, timeout=0):
            if request.get_method() == "POST":
                return response({"status": "queued", "statusUrl": "/v1/jobs/job-1"})
            return response({"status": "failed", "error": "device unavailable"})

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "discord.ipa"
            with patch.object(MODULE, "urlopen", side_effect=opener):
                with self.assertRaisesRegex(MODULE.DkryptError, "device unavailable"):
                    MODULE.fetch_ipa("https://ipa.dylib.dev", "com.example.app", "342", "key", output, poll_interval_seconds=0, sleep_fn=lambda _seconds: None)
            self.assertFalse(output.exists())

    def test_download_retries_transient_http_error(self):
        attempts = 0

        def opener(request, timeout=0):
            nonlocal attempts
            if request.get_method() == "POST":
                return response({"status": "done", "artifact": artifact()})
            attempts += 1
            if attempts == 1:
                raise HTTPError(request.full_url, 503, "try again", {}, io.BytesIO(b"{}"))
            return FakeResponse(IPA_BYTES)

        result = self.run_fetch(opener)
        self.assertEqual(result["cache_hit"], "false")
        self.assertEqual(attempts, 2)

    def test_checksum_mismatch_removes_partial_output(self):
        def opener(request, timeout=0):
            if request.get_method() == "POST":
                return response({"status": "done", "artifact": artifact(sha256="0" * 64)})
            return FakeResponse(IPA_BYTES)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "discord.ipa"
            with patch.object(MODULE, "urlopen", side_effect=opener):
                with self.assertRaisesRegex(MODULE.DkryptError, "SHA-256 mismatch"):
                    MODULE.fetch_ipa("https://ipa.dylib.dev", "com.example.app", "342", "key", output, poll_interval_seconds=0, sleep_fn=lambda _seconds: None)
            self.assertFalse(output.exists())

    def test_timeout_is_reported(self):
        clock = iter([0.0, 0.0, 2.0])

        def opener(request, timeout=0):
            if request.method == "POST":
                return response({"status": "queued", "statusUrl": "/v1/jobs/job-1"})
            return response({"status": "running", "progress": "still working", "statusUrl": "/v1/jobs/job-1"})

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "discord.ipa"
            with patch.object(MODULE, "urlopen", side_effect=opener):
                with self.assertRaisesRegex(MODULE.DkryptError, "timed out"):
                    MODULE.fetch_ipa("https://ipa.dylib.dev", "com.example.app", "342", "key", output, timeout_seconds=1, poll_interval_seconds=0, sleep_fn=lambda _seconds: None, now_fn=lambda: next(clock))


if __name__ == "__main__":
    unittest.main()
