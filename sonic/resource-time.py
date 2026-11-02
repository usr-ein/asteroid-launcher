#!/usr/bin/env python3
"""Sonic Screwdriver: the time sonic/build.sh has rcc stamp the launcher's
compiled-in resources with, from their contents alone.

    sonic/resource-time.py src/resources-qml.qrc

Prints whole seconds since 1970, from a hash of the .qrc file and of each
file it lists, in its order. The same resources give the same time, so the
same sources still give the same binary; a change to any of them gives
another time.

Qt's QML disk cache, on the watch, takes a cached compiled file as current
when its source's time matches, and for a compiled-in file that time is this
one. A time that never changed made each new build run whatever QML an older
build had compiled into the cache.
"""
import hashlib
import os
import sys
import xml.etree.ElementTree as ET

qrc = sys.argv[1]
base = os.path.dirname(qrc)
digest = hashlib.sha256()
with open(qrc, "rb") as f:
    digest.update(f.read())
for entry in ET.parse(qrc).getroot().iter("file"):
    with open(os.path.join(base, entry.text.strip()), "rb") as f:
        data = f.read()
    digest.update(len(data).to_bytes(8, "big"))
    digest.update(data)
# 28 bits: a time between 1970 and 1978, and never 0, which rcc takes as none.
print(int(digest.hexdigest()[:7], 16) + 1)
