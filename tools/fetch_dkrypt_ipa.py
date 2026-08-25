#!/usr/bin/env python3

"""Resolve and download a retained or freshly decrypted IPA from dkrypt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "https://ipa.dylib.dev"
DEFAULT_BUNDLE_ID = "com.hammerandchisel.discord"
DEFAULT_TIMEOUT_SECONDS = 45 * 60
POLL_INTERVAL_SECONDS = 10
RETRYABLE_STATUS_CODES = {408, 425, 429, 500, 502, 503, 504}
HTTP_USER_AGENT = "loader-ios-dkrypt/1.0 (+https://github.com/unbound-app/loader-ios)"


class DkryptError(RuntimeError):
    """A safe, user-facing dkrypt request error."""


def _safe_message(value: object) -> str:
    message = str(value).replace("\r", " ").replace("\n", " ").strip()
    return message[:500] or "unknown dkrypt error"


def _parse_json(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DkryptError("dkrypt returned an invalid JSON response") from error
    if not isinstance(value, dict):
        raise DkryptError("dkrypt returned an unexpected response")
    return value


def _error_from_http(error: HTTPError) -> DkryptError:
    try:
        body = _parse_json(error.read())
        detail = body.get("error")
    except (DkryptError, OSError):
        detail = None
    suffix = f": {_safe_message(detail)}" if detail else ""
    return DkryptError(f"dkrypt request failed with HTTP {error.code}{suffix}")


def _request_json(
    url: str,
    api_key: str,
    *,
    method: str = "GET",
    body: dict[str, Any] | None = None,
    timeout: float = 30,
) -> dict[str, Any]:
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=payload,
        method=method,
        headers={
            "Accept": "application/json",
            "User-Agent": HTTP_USER_AGENT,
            "Authorization": f"Bearer {api_key}",
            **({"Content-Type": "application/json"} if payload is not None else {}),
        },
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return _parse_json(response.read())
    except HTTPError as error:
        raise _error_from_http(error) from error
    except (URLError, TimeoutError, OSError) as error:
        raise DkryptError(f"could not reach dkrypt: {_safe_message(error)}") from error


def _request_with_retries(
    url: str,
    api_key: str,
    *,
    method: str = "GET",
    body: dict[str, Any] | None = None,
    attempts: int = 3,
    sleep_fn: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    last_error: DkryptError | None = None
    for attempt in range(1, attempts + 1):
        try:
            return _request_json(url, api_key, method=method, body=body)
        except DkryptError as error:
            last_error = error
            if attempt == attempts or "HTTP " not in str(error):
                raise
            status_text = str(error).split("HTTP ", 1)[1].split(":", 1)[0]
            if not status_text.isdigit() or int(status_text) not in RETRYABLE_STATUS_CODES:
                raise
            sleep_fn(min(30, 2 ** (attempt - 1)))
    raise last_error or DkryptError("dkrypt request failed")


def _url(base_url: str, value: str) -> str:
    return urljoin(f"{base_url.rstrip('/')}/", value)


def _notice(message: str) -> None:
    clean = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::notice title=dkrypt::{clean}", flush=True)


def _status_message(payload: dict[str, Any]) -> str | None:
    progress = payload.get("progress")
    if isinstance(progress, str) and progress.strip():
        return progress.strip()
    status = payload.get("status")
    queue = payload.get("queue")
    if isinstance(status, str) and isinstance(queue, dict):
        position = queue.get("position")
        total = queue.get("total")
        if isinstance(position, int) and isinstance(total, int):
            return f"{status}; queue position {position}/{total}"
    return status if isinstance(status, str) else None


def _emit_distinct(payload: dict[str, Any], seen: set[str]) -> None:
    message = _status_message(payload)
    queue = payload.get("queue")
    if isinstance(queue, dict):
        position = queue.get("position")
        total = queue.get("total")
        if isinstance(position, int) and isinstance(total, int):
            message = f"{message or 'queued'} (queue position {position}/{total})"
    if message and message not in seen:
        seen.add(message)
        _notice(message)


def _artifact_payload(payload: dict[str, Any]) -> dict[str, Any]:
    artifact = payload.get("artifact")
    if isinstance(artifact, dict):
        return artifact
    artifact_id = payload.get("artifactId")
    if isinstance(artifact_id, str) and artifact_id:
        return {"id": artifact_id}
    return {}


def _write_outputs(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with Path(output_path).open("a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value.replace(chr(10), ' ').replace(chr(13), ' ')}\n")


def _download_and_verify(
    url: str,
    api_key: str,
    output_path: Path,
    expected_size: int,
    expected_sha256: str,
    *,
    sleep_fn: Callable[[float], None] = time.sleep,
) -> None:
    request = Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/octet-stream",
            "User-Agent": HTTP_USER_AGENT,
        },
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.unlink(missing_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.{uuid.uuid4().hex}.part")
    try:
        response = None
        for attempt in range(1, 4):
            try:
                response = urlopen(request, timeout=60)
                break
            except HTTPError as error:
                if error.code not in RETRYABLE_STATUS_CODES or attempt == 3:
                    raise _error_from_http(error) from error
                sleep_fn(min(30, 2 ** (attempt - 1)))
            except (URLError, TimeoutError, OSError) as error:
                if attempt == 3:
                    raise DkryptError(f"could not download the IPA from dkrypt: {_safe_message(error)}") from error
                sleep_fn(min(30, 2 ** (attempt - 1)))
        if response is None:
            raise DkryptError("dkrypt did not return an IPA")

        digest = hashlib.sha256()
        size = 0
        with response, temporary_path.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                digest.update(chunk)
                size += len(chunk)

        actual_sha256 = digest.hexdigest()
        if size != expected_size:
            raise DkryptError(f"dkrypt IPA size mismatch: expected {expected_size} bytes, got {size}")
        if actual_sha256.lower() != expected_sha256.lower():
            raise DkryptError("dkrypt IPA SHA-256 mismatch")
        temporary_path.replace(output_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def fetch_ipa(
    base_url: str,
    bundle_id: str,
    version: str | None,
    api_key: str,
    output_path: Path,
    *,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    poll_interval_seconds: float = POLL_INTERVAL_SECONDS,
    sleep_fn: Callable[[float], None] = time.sleep,
    now_fn: Callable[[], float] = time.monotonic,
) -> dict[str, str]:
    if not api_key:
        raise DkryptError("DKRYPT_API_KEY is not set")
    body: dict[str, Any] = {"bundleId": bundle_id}
    if version and version.strip():
        body["version"] = version.strip()

    response = _request_with_retries(
        _url(base_url, "/v1/decrypts"),
        api_key,
        method="POST",
        body=body,
        sleep_fn=sleep_fn,
    )
    seen: set[str] = set()
    _emit_distinct(response, seen)
    cache_hit = response.get("cacheHit") is True
    status = response.get("status")
    deadline = now_fn() + timeout_seconds

    while status in {"queued", "running"}:
        if now_fn() >= deadline:
            raise DkryptError(f"dkrypt job timed out after {int(timeout_seconds)} seconds")
        status_url = response.get("statusUrl")
        if not isinstance(status_url, str) or not status_url:
            raise DkryptError("dkrypt did not return a status URL for the decrypt job")
        sleep_fn(poll_interval_seconds)
        response = _request_with_retries(_url(base_url, status_url), api_key, sleep_fn=sleep_fn)
        _emit_distinct(response, seen)
        status = response.get("status")

    if status == "failed":
        raise DkryptError(f"dkrypt decrypt failed: {_safe_message(response.get('error', 'unknown error'))}")
    if status != "done":
        raise DkryptError(f"dkrypt returned an unexpected job status: {_safe_message(status)}")

    artifact = _artifact_payload(response)
    artifact_id = artifact.get("id")
    if isinstance(artifact_id, str) and artifact_id and "sha256" not in artifact:
        artifact = _request_with_retries(_url(base_url, f"/v1/artifacts/{artifact_id}"), api_key, sleep_fn=sleep_fn)

    file_url = artifact.get("fileUrl") or response.get("artifactUrl") or response.get("fileUrl")
    expected_size = artifact.get("sizeBytes", response.get("sizeBytes"))
    expected_sha256 = artifact.get("sha256", response.get("sha256"))
    if not isinstance(file_url, str) or not file_url:
        raise DkryptError("dkrypt did not return an artifact download URL")
    if not isinstance(expected_size, int) or expected_size < 1:
        raise DkryptError("dkrypt did not report the retained IPA size")
    if not isinstance(expected_sha256, str) or len(expected_sha256) != 64:
        raise DkryptError("dkrypt did not report the retained IPA SHA-256")

    channel = response.get("channel")
    if channel not in {"appstore", "testflight"}:
        channel = "testflight" if response.get("testflight") else "appstore"
    resolved_version = response.get("resolvedVersion") or response.get("versionLabel") or artifact.get("versionLabel")
    if not isinstance(resolved_version, str) or not resolved_version:
        resolved_version = version.strip() if version and version.strip() else "latest"

    if cache_hit:
        _notice(f"cache hit for {channel} {resolved_version}")
    else:
        _notice(f"cache miss; decrypted {channel} {resolved_version}")
    _download_and_verify(
        _url(base_url, file_url),
        api_key,
        output_path,
        expected_size,
        expected_sha256,
        sleep_fn=sleep_fn,
    )
    _notice(f"downloaded and verified {expected_size} bytes ({expected_sha256})")
    result = {
        "channel": channel,
        "is_testflight": "true" if channel == "testflight" else "false",
        "version": resolved_version,
        "cache_hit": "true" if cache_hit else "false",
        "artifact_id": str(artifact.get("id") or response.get("artifactId") or ""),
        "sha256": expected_sha256,
        "size_bytes": str(expected_size),
    }
    _write_outputs(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", default="")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout-seconds", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    args = parser.parse_args()
    try:
        result = fetch_ipa(
            args.base_url,
            args.bundle_id,
            args.version,
            os.environ.get("DKRYPT_API_KEY", ""),
            args.output,
            timeout_seconds=args.timeout_seconds,
        )
    except DkryptError as error:
        print(f"::error title=dkrypt::{_safe_message(error)}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
