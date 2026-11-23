#!/usr/bin/env python3
"""Read public release links and config; no accounts, purchases or writes.

Run from the repository root. Reads the URLs from the shipped config and
checks the website's public pages and the sandbox/production route markers.
Writes only status, byte counts and public configuration to the report.
"""
import concurrent.futures
import configparser
import json
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urljoin, urlparse


def main():
    links, service = configparser.ConfigParser(), configparser.ConfigParser()
    links.read("game/config/links.cfg")
    service.read("game/config/service.cfg")
    # Godot config values are quoted strings; all these values are public.
    value = lambda c, section, key: c[section][key].strip('"')
    privacy = value(links, "links", "privacy_url")
    base = privacy.removesuffix("privacy/")
    urls = [(urljoin(base, path), None) for path in
            ("", "privacy/", "support/", "terms/", "rules/", "delete-account/")]
    for route, apple in (("sandbox", "Sandbox"), ("production", "Production")):
        urls.append((value(service, "service", route + "_url") + "/v1/config", (route, apple)))

    def check(item):
        url, expected = item
        result = {"url": url}
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
                result.update(status=response.status, final_url=response.url, bytes=len(data))
                if response.status != 200 or urlparse(response.url).scheme != "https":
                    raise ValueError("Expected an HTTPS 200 response")
                if expected:
                    config = json.loads(data)
                    result["config"] = config
                    if (config.get("environment"), config.get("apple_environment")) != expected:
                        raise ValueError("Deployment environment mismatch")
                else:
                    text = data.decode()
                    if "Ultimate Trifecta" not in text:
                        raise ValueError("Expected app identity missing")
                    if url.endswith(("privacy/", "support/")) and "support@idlery.com" not in text:
                        raise ValueError("Support contact missing")
        except Exception as error:
            result["error"] = str(error)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(check, urls))
    target = Path(sys.argv[1])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(results, indent=2) + "\n")
    for result in results:
        print(result["url"], result.get("error", result.get("status")))
    return int(any("error" in result for result in results))


if __name__ == "__main__":
    sys.exit(main())
