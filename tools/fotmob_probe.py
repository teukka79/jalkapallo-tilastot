#!/usr/bin/env python3
"""Koeajo: vastaako FotMob ja löytyykö laukauskartta (koordinaatit, xG). Käyttö: .venv/bin/python tools/fotmob_probe.py [liigan id, oletus 130 = MLS]"""
import json
import re
import sys
import urllib.request

try:
    import certifi, ssl
    CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    CTX = None

UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
      "Accept-Language": "en-US,en;q=0.9"}


def get(url):
    try:
        import tls_requests
        r = tls_requests.get(url, headers=UA, timeout=30)
        return r.status_code, r.text
    except ImportError:
        pass
    except Exception as exc:
        print("  tls_requests:", str(exc)[:100])
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30, context=CTX) as r:
            return r.status, r.read().decode("utf-8", "ignore")
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except Exception as exc:
        return 0, str(exc)[:100]


def next_data(html):
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except ValueError as exc:
        print("   JSON ei aukea:", exc)
        return None


def walk(obj, visit):
    if isinstance(obj, dict):
        visit(obj)
        for v in obj.values():
            walk(v, visit)
    elif isinstance(obj, list):
        for v in obj:
            walk(v, visit)


league = sys.argv[1] if len(sys.argv) > 1 else "130"
print(f"1) Sarjasivu /leagues/{league}/overview/x")
status, html = get(f"https://www.fotmob.com/leagues/{league}/overview/x")
print("   HTTP", status, "| pituus", len(html), "| __NEXT_DATA__:", "__NEXT_DATA__" in html)
data = next_data(html) if status == 200 else None
if not data:
    print("   -> sivua ei saatu tai sen rakenne on muuttunut. Alku:", html[:200].replace("\n", " "))
    print("2) API ilman allekirjoitusta:")
    s2, t2 = get(f"https://www.fotmob.com/api/leagues?id={league}")
    print("   HTTP", s2, t2[:150].replace("\n", " "))
    sys.exit(0)

matches = []
walk(data, lambda d: matches.append(d) if "pageUrl" in d and isinstance(d.get("status"), dict) else None)
finished = [m for m in matches if m["status"].get("finished")]
print(f"   otteluita löytyi {len(matches)}, pelattuja {len(finished)}")
if not finished:
    sys.exit("   ei pelattuja otteluita sivulla")
finished.sort(key=lambda x: str(x["status"].get("utcTime") or ""))
m = finished[-1]
print("   ajankohta:", m["status"].get("utcTime"), "|", m["status"].get("scoreStr"))
print("   valittu ottelu:", m.get("pageUrl"), "| id", m.get("id"))

print("2) Ottelusivu")
status, html = get("https://www.fotmob.com" + m["pageUrl"])
print("   HTTP", status, "| pituus", len(html))
page = next_data(html) if status == 200 else None
if page:
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "_fotmob_match.json"), "w", encoding="utf-8") as f:
        json.dump(page.get("props", {}).get("pageProps", {}), f, ensure_ascii=False)
    with open(os.path.join(here, "_fotmob_fixture.json"), "w", encoding="utf-8") as f:
        json.dump({"fixture": m, "sample_other": finished[:3]}, f, ensure_ascii=False)
    print("   tallennettu tools/_fotmob_match.json ja _fotmob_fixture.json")
if not page:
    print("   -> ottelusivun dataa ei saatu")
    sys.exit(0)
found = []


def find_shots(d):
    for key, value in d.items():
        if "shot" in key.lower():
            found.append((key, value))


walk(page, find_shots)
print("   avaimet joissa 'shot':", [(k, type(v).__name__, (list(v.keys())[:8] if isinstance(v, dict) else len(v) if isinstance(v, list) else v)) for k, v in found][:10])
shots = None
for key, value in found:
    if isinstance(value, dict) and isinstance(value.get("shots"), list):
        shots = value["shots"]
        break
    if isinstance(value, list) and value and isinstance(value[0], dict) and "x" in value[0]:
        shots = value
        break
content = page.get("props", {}).get("pageProps", {}).get("content", {})
if not shots:
    print("   -> laukauskarttaa ei löytynyt. content-avaimet:", list(content.keys())[:25])
    sys.exit(0)
print(f"   LAUKAUSKARTTA LÖYTYI: {len(shots)} laukausta")
print("   kentät:", sorted(shots[0].keys()))
for s_ in shots[:3]:
    print("  ", json.dumps({k: s_.get(k) for k in ("playerName", "teamId", "x", "y", "min", "eventType", "situation", "expectedGoals", "isOnTarget", "isBlocked")}, ensure_ascii=False))
