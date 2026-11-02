#!/usr/bin/env python3
"""Build Safari content-blocker rules and DNS domain lists from ABP-style filter lists.

Output (--out, default dist/):
  safari/<list>.json   Safari content-blocker rules
  dns/<list>.json      sing-box rule-set (source format) for the Pro DNS tunnel
  dns/<list>.txt       plain domain list (for a DoH server such as AdGuard Home / blocky)
  manifest.json        build time and counts

--bundle also copies the Safari lists into ContentBlocker/Lists/ for shipping in the app.

Only network rules of the form ||domain^ (optionally $third-party) and @@||domain^ exceptions are
converted; cosmetic and path rules are skipped for now.
Note: EasyList/EasyPrivacy are GPLv3 / CC BY-SA 3.0 — credit them in the app.
"""
import argparse
import datetime
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = {
    "ads": ["https://easylist.to/easylist/easylist.txt"],
    "privacy": ["https://easylist.to/easylist/easyprivacy.txt"],
}
# Built for DNS-level blocking (fewer site breakages than EasyList at DNS level). GPLv3.
DNS_SOURCES = ["https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"]
SAFARI_MAX_RULES = 150_000
RULE_RE = re.compile(r"^(@@)?\|\|([a-z0-9.-]+)\^(?:\$(.+))?$", re.IGNORECASE)
DOMAIN_RE = re.compile(r"^(?:[a-z0-9-]+\.)+[a-z0-9-]{2,}$")


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "spamurai-filter-builder"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", "replace")


def parse(text: str):
    block, block_3p, allow, allow_doc = set(), set(), set(), set()
    for line in text.splitlines():
        m = RULE_RE.match(line.strip())
        if not m:
            continue
        exception, domain, opts = m.group(1), m.group(2).lower().strip("."), m.group(3)
        if not DOMAIN_RE.match(domain):
            continue
        opts = set(opts.lower().split(",")) - {"important"} if opts else set()
        if exception:
            if not opts:
                allow.add(domain)
            elif opts == {"document"}:
                allow_doc.add(domain)
        elif not opts:
            block.add(domain)
        elif opts == {"third-party"}:
            block_3p.add(domain)
    return block, block_3p, allow, allow_doc


def covered(domain: str, domains: set) -> bool:
    """True if domain or any parent domain is in `domains`."""
    parts = domain.split(".")
    return any(".".join(parts[i:]) in domains for i in range(len(parts) - 1))


def parents_only(domains: set) -> list:
    """Drop subdomains already covered by a listed parent."""
    out = []
    for d in sorted(domains):
        parts = d.split(".")
        if not any(".".join(parts[i:]) in domains for i in range(1, len(parts) - 1)):
            out.append(d)
    return out


def url_filter(domain: str) -> str:
    return r"^[htpsw]+://([a-z0-9-]+\.)*" + domain.replace(".", r"\.") + r"[/:]"


def safari_rules(block, block_3p, allow, allow_doc) -> list:
    block = parents_only(block)
    block_3p = [d for d in parents_only(block_3p) if not covered(d, set(block))]
    exceptions = [{"trigger": {"url-filter": url_filter(d)}, "action": {"type": "ignore-previous-rules"}}
                  for d in sorted(allow)]
    exceptions += [{"trigger": {"url-filter": ".*", "if-domain": [f"*{d}"]},
                    "action": {"type": "ignore-previous-rules"}} for d in sorted(allow_doc)]

    rules = [{"trigger": {"url-filter": url_filter(d)}, "action": {"type": "block"}} for d in block]
    rules += [{"trigger": {"url-filter": url_filter(d), "load-type": ["third-party"]},
               "action": {"type": "block"}} for d in block_3p]

    budget = SAFARI_MAX_RULES - len(exceptions)
    if len(rules) > budget:
        print(f"  warning: {len(rules)} block rules exceed budget {budget}, truncating", file=sys.stderr)
        rules = rules[:budget]
    # Exceptions must come after the rules they override.
    return rules + exceptions


def dns_domains(block, allow, allow_doc) -> list:
    allowed = allow | allow_doc
    return [d for d in parents_only(block) if not covered(d, allowed)]


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "dist")
    ap.add_argument("--bundle", action="store_true", help="copy Safari lists into ContentBlocker/Lists")
    args = ap.parse_args()

    manifest = {"generated": datetime.datetime.now(datetime.timezone.utc).isoformat(), "safari": {}}
    for name, urls in SOURCES.items():
        rules = safari_rules(*load(urls))
        write_json(args.out / "safari" / f"{name}.json", rules)
        manifest["safari"][name] = len(rules)
        print(f"safari/{name}: {len(rules)} rules")
        if args.bundle:
            shutil.copy(args.out / "safari" / f"{name}.json", ROOT / "ContentBlocker" / "Lists" / f"{name}.json")

    block, _, allow, allow_doc = load(DNS_SOURCES)
    domains = dns_domains(block, allow, allow_doc)
    write_json(args.out / "dns" / "default.json", {"version": 1, "rules": [{"domain_suffix": domains}]})
    (args.out / "dns" / "default.txt").write_text("\n".join(domains) + "\n", encoding="utf-8")
    manifest["dns"] = len(domains)
    print(f"dns/default: {len(domains)} domains")
    if args.bundle:
        shutil.copy(args.out / "dns" / "default.json", ROOT / "PacketTunnel" / "Lists" / "dns.json")

    write_json(args.out / "manifest.json", manifest)


def load(urls):
    sets = [set(), set(), set(), set()]
    for url in urls:
        print(f"fetching {url}")
        for acc, part in zip(sets, parse(fetch(url))):
            acc |= part
    return sets


if __name__ == "__main__":
    main()
