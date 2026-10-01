#!/usr/bin/env python3
"""Print the essentials of an Apple .ips crash report (iOS 15+ JSON format):
exception, termination reason, and the faulting thread's top frames."""
import json, sys

path = sys.argv[1]
raw = open(path).read()
head, _, body = raw.partition("\n")
hdr = json.loads(head)
rep = json.loads(body)
print(f"== {path.split('/')[-1]}")
print("app:", hdr.get("app_name"), hdr.get("app_version"), hdr.get("build_version"), "| os:", hdr.get("os_version"))
print("captured:", rep.get("captureTime"), "| launched:", rep.get("procLaunch"), "| uptime s:", rep.get("uptime"))
print("exception:", json.dumps(rep.get("exception")))
print("termination:", json.dumps(rep.get("termination")))
if rep.get("asi"):
    print("asi:", json.dumps(rep.get("asi"))[:600])
images = rep.get("usedImages", [])
ft = rep.get("faultingThread", 0)
threads = rep.get("threads", [])
if threads:
    t = threads[ft] if ft < len(threads) else threads[0]
    print(f"faulting thread {ft}:", t.get("name") or t.get("queue") or "")
    for fr in t.get("frames", [])[:24]:
        img = images[fr["imageIndex"]]["name"] if fr.get("imageIndex", -1) < len(images) and fr.get("imageIndex", -1) >= 0 else "?"
        print(f"   {img:40s} {fr.get('symbol', '?')} +{fr.get('symbolLocation', fr.get('imageOffset', ''))}")
