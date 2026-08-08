#!/usr/bin/env python3
"""Download, validate, and cache public proxies from trusted GitHub providers."""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


PROXY_PATTERN = re.compile(
    r"^(?:(?:http|https|socks4|socks5)://)?"
    r"(?P<host>(?:\d{1,3}\.){3}\d{1,3}):(?P<port>\d{1,5})/?$"
)
SCHEMES = {1: "http", 4: "socks4", 5: "socks5"}


@dataclass(frozen=True)
class Candidate:
    proxy_type: int
    proxy_url: str
    curl_proxy_url: str
    timeout: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--providers", default="proxy-providers.json")
    parser.add_argument("--test-url", required=True)
    parser.add_argument("--output", default=".proxy-cache/working-proxies.txt")
    parser.add_argument("--max-candidates", type=int, default=30)
    parser.add_argument("--max-working", type=int, default=10)
    parser.add_argument("--concurrency", type=int, default=10)
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    parsed = urllib.parse.urlparse(args.test_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("--test-url must be an absolute HTTP or HTTPS URL")
    if not 1 <= args.max_candidates <= 500:
        raise ValueError("--max-candidates must be between 1 and 500")
    if not 1 <= args.max_working <= 100:
        raise ValueError("--max-working must be between 1 and 100")
    if not 1 <= args.concurrency <= 50:
        raise ValueError("--concurrency must be between 1 and 50")


def normalize_candidate(value: str, proxy_type: int, timeout: int) -> Candidate | None:
    match = PROXY_PATTERN.fullmatch(value.strip())
    if not match:
        return None

    try:
        address = ipaddress.ip_address(match.group("host"))
        port = int(match.group("port"))
    except ValueError:
        return None

    if not isinstance(address, ipaddress.IPv4Address) or not address.is_global:
        return None
    if not 1 <= port <= 65535:
        return None

    scheme = SCHEMES[proxy_type]
    proxy_url = f"{scheme}://{address}:{port}"
    curl_scheme = "socks5h" if proxy_type == 5 else scheme
    return Candidate(proxy_type, proxy_url, f"{curl_scheme}://{address}:{port}", timeout)


def load_candidates(provider_file: Path) -> list[Candidate]:
    config = json.loads(provider_file.read_text(encoding="utf-8"))
    providers = config.get("proxy-providers")
    if not isinstance(providers, list) or not providers:
        raise ValueError("provider file must contain a non-empty proxy-providers array")

    candidates: dict[tuple[int, str], Candidate] = {}
    for provider in providers:
        proxy_type = int(provider.get("type", 0))
        if proxy_type not in SCHEMES:
            print(f"warning: skipping unsupported proxy type {proxy_type}", file=sys.stderr)
            continue

        source_url = str(provider.get("url", ""))
        parsed = urllib.parse.urlparse(source_url)
        if parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com":
            print(f"warning: skipping non-GitHub or non-HTTPS provider: {source_url}", file=sys.stderr)
            continue

        timeout = int(provider.get("timeout", 5))
        if not 1 <= timeout <= 30:
            print(f"warning: skipping provider with invalid timeout: {source_url}", file=sys.stderr)
            continue

        print(f"Downloading type {proxy_type} proxies from {source_url}")
        try:
            request = urllib.request.Request(
                source_url, headers={"User-Agent": "website-load-test-proxy-pool/1.0"}
            )
            with urllib.request.urlopen(request, timeout=20) as response:
                content = response.read(10 * 1024 * 1024 + 1)
            if len(content) > 10 * 1024 * 1024:
                print(f"warning: source is larger than 10 MB: {source_url}", file=sys.stderr)
                continue
            for line in content.decode("utf-8", errors="ignore").splitlines():
                candidate = normalize_candidate(line, proxy_type, timeout)
                if candidate:
                    candidates[(candidate.proxy_type, candidate.proxy_url)] = candidate
        except Exception as exc:  # Provider failure should not hide other providers.
            print(f"warning: could not download {source_url}: {exc}", file=sys.stderr)

    if not candidates:
        raise RuntimeError("no valid proxy candidates were downloaded")
    return list(candidates.values())


def test_candidate(curl: str, candidate: Candidate, test_url: str) -> tuple[Candidate, int, int] | None:
    started = time.monotonic()
    result = subprocess.run(
        [
            curl,
            "--silent",
            "--show-error",
            "--output",
            os.devnull,
            "--write-out",
            "%{http_code}",
            "--max-time",
            str(candidate.timeout),
            "--proxy",
            candidate.curl_proxy_url,
            test_url,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    elapsed_ms = round((time.monotonic() - started) * 1000)
    if result.returncode != 0 or not result.stdout.isdigit():
        return None
    status = int(result.stdout)
    if 200 <= status < 400:
        return candidate, status, elapsed_ms
    return None


def main() -> int:
    args = parse_args()
    validate_args(args)
    curl = shutil.which("curl")
    if not curl:
        raise RuntimeError("curl is required for HTTP, SOCKS4, and SOCKS5 validation")

    candidates = load_candidates(Path(args.providers))
    sample = random.sample(candidates, min(args.max_candidates, len(candidates)))
    print(f"Testing {len(sample)} mixed proxy candidates against {args.test_url}")

    working: list[tuple[Candidate, int, int]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [executor.submit(test_candidate, curl, candidate, args.test_url) for candidate in sample]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                working.append(result)

    if not working:
        raise RuntimeError("no working proxy was found; increase MAX_PROXY_CANDIDATES or try again")

    selected: list[tuple[Candidate, int, int]] = []
    for proxy_type in SCHEMES:
        protocol_results = sorted(
            (item for item in working if item[0].proxy_type == proxy_type),
            key=lambda item: item[2],
        )
        selected.extend(protocol_results[: args.max_working])
    working = selected
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(f"{item[0].proxy_url}\n" for item in working), encoding="ascii")

    for candidate, status, latency in working:
        print(f"Working type {candidate.proxy_type}: {candidate.proxy_url} ({status}, {latency} ms)")
    print(f"Saved {len(working)} working proxies to {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
