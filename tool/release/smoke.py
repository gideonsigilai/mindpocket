#!/usr/bin/env python3
"""Smoke-launch a desktop build and fail if it exits or crashes immediately.

A GUI app that starts and stays resident for the observation window proves the
native bundle resolved its plugin libraries and the Dart entrypoint ran. It does
not prove any feature works, so this deliberately claims only "launches".
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

OBSERVE_SECONDS = 12


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: smoke.py <path-to-executable>", file=sys.stderr)
        return 2
    executable = Path(sys.argv[1])
    if not executable.exists():
        print(f"executable not found: {executable}", file=sys.stderr)
        return 1

    log = Path("build") / "smoke.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    # Xvfb provides X11, so force the GDK backend the headless X server serves.
    environment.setdefault("GDK_BACKEND", "x11")
    # A missing session bus makes GTK/GTK-based plugins abort on startup.
    environment.setdefault("NO_AT_BRIDGE", "1")

    with log.open("wb") as sink:
        process = subprocess.Popen(
            [str(executable)],
            stdout=sink,
            stderr=subprocess.STDOUT,
            env=environment,
        )
        deadline = time.monotonic() + OBSERVE_SECONDS
        while time.monotonic() < deadline:
            code = process.poll()
            if code is not None:
                output = log.read_text(encoding="utf-8", errors="replace")
                print(f"application exited early with {code}\n{output}", file=sys.stderr)
                return 1
            time.sleep(0.5)
        process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=15)

    output = log.read_text(encoding="utf-8", errors="replace")
    fatal = [
        line
        for line in output.splitlines()
        if "Unhandled Exception" in line or "MissingPluginException" in line
    ]
    if fatal:
        print("application logged fatal errors:\n" + "\n".join(fatal), file=sys.stderr)
        return 1
    print(f"{executable.name} launched and stayed resident for {OBSERVE_SECONDS}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
