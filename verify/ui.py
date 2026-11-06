"""UI sweep driver: dump Flutter semantics, tap by label, screenshot, watch logcat."""
import re
import subprocess
import time

ADB = r"C:\Users\Sawe\Documents\platform-tools\adb.exe"
PKG = "com.mindpocket.mindpocket"


def sh(*args, timeout=180):
    return subprocess.run([ADB, *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def raw(*args, timeout=180):
    return subprocess.run([ADB, *args], capture_output=True, timeout=timeout).stdout


def dump(retries=5):
    """Return list of node dicts from the uiautomator hierarchy.

    uiautomator leaves the previous file in place when it fails, so the file is
    deleted first and the dump is rejected unless it mentions our package.
    """
    xml = ""
    for _ in range(retries):
        sh("shell", "rm", "-f", "/sdcard/ui.xml")
        sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        xml = sh("shell", "cat", "/sdcard/ui.xml").stdout
        if "<hierarchy" in xml and PKG in xml:
            break
        time.sleep(0.8)
    nodes = []
    for m in re.finditer(r"<node ([^>]*?)/?>", xml):
        attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
        b = re.search(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", attrs.get("bounds", ""))
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        nodes.append({
            "text": attrs.get("text", ""),
            "desc": attrs.get("content-desc", ""),
            "cls": attrs.get("class", ""),
            "clickable": attrs.get("clickable") == "true",
            "scrollable": attrs.get("scrollable") == "true",
            "cx": (x1 + x2) // 2,
            "cy": (y1 + y2) // 2,
            "bounds": (x1, y1, x2, y2),
        })
    return nodes


def labels(nodes=None):
    nodes = nodes if nodes is not None else dump()
    out = []
    for n in nodes:
        for v in (n["text"], n["desc"]):
            v = v.replace("\n", " | ").strip()
            if v and v not in out:
                out.append(v)
    return out


def find(pattern, nodes=None, index=0, required=True):
    nodes = nodes if nodes is not None else dump()
    rx = re.compile(pattern, re.I)
    hits = [n for n in nodes if rx.search(n["text"]) or rx.search(n["desc"])]
    if not hits:
        if required:
            raise LookupError(f"no node matching {pattern!r}; saw {labels(nodes)}")
        return None
    return hits[min(index, len(hits) - 1)]


def has(pattern, nodes=None):
    return find(pattern, nodes=nodes, required=False) is not None


def tap(pattern, index=0, nodes=None, wait=0.9):
    n = find(pattern, nodes=nodes, index=index)
    sh("shell", "input", "tap", str(n["cx"]), str(n["cy"]))
    time.sleep(wait)
    return n


def tap_xy(x, y, wait=0.9):
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def type_text(value, wait=0.5):
    # `input text` treats spaces as %s; do it in one shot to avoid IME races.
    safe = value.replace(" ", "%s")
    sh("shell", "input", "text", safe)
    time.sleep(wait)


def key(code, wait=0.6):
    sh("shell", "input", "keyevent", str(code))
    time.sleep(wait)


def back(wait=1.0):
    key(4, wait)


def shot(name):
    png = raw("exec-out", "screencap", "-p")
    path = f"verify/shots/{name}.png"
    with open(path, "wb") as f:
        f.write(png)
    return path


def swipe(x1, y1, x2, y2, ms=300, wait=0.9):
    sh("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))
    time.sleep(wait)


def scroll_down(times=1, wait=0.6):
    for _ in range(times):
        swipe(540, 1700, 540, 800, 250, wait)


def scroll_up(times=1, wait=0.6):
    for _ in range(times):
        swipe(540, 800, 540, 1700, 250, wait)


def start():
    sh("shell", "am", "force-stop", PKG)
    sh("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    time.sleep(4.5)


def stop():
    sh("shell", "am", "force-stop", PKG)
    time.sleep(1)


def pull_db(name="db.sqlite"):
    for suffix in ("", "-wal", "-shm"):
        data = raw("exec-out", "run-as", PKG, "cat",
                   f"app_flutter/mindpocket/mindpocket.db{suffix}")
        with open(f"verify/{name}{suffix}", "wb") as f:
            f.write(data)
    return f"verify/{name}"


def query(sql, db="verify/db.sqlite"):
    import sqlite3
    con = sqlite3.connect(db)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


ERR_PATTERNS = [
    r"EXCEPTION CAUGHT BY",
    r"Another exception was thrown",
    r"improper use of a GetX",
    r"RenderFlex overflowed",
    r"Failed assertion",
    r"Null check operator used on a null value",
    r"Unhandled Exception",
    r"setState\(\) or markNeedsBuild",
]
_err_rx = re.compile("|".join(ERR_PATTERNS))


def logcat_errors(tag="flutter"):
    out = sh("logcat", "-d", "-v", "brief", "-s", tag).stdout
    lines = [ln for ln in out.splitlines() if _err_rx.search(ln)]
    return lines


def logcat_since(marker_cmd=("logcat", "-c"), tag="flutter"):
    """Clear then read — call clear_errors() before an interaction."""
    sh(*marker_cmd)


def screen_report(name):
    """Screenshot + dump + error scan for the current screen."""
    path = shot(name)
    texts = labels()
    errs = logcat_errors()
    return {"shot": path, "texts": texts, "errors": errs}
