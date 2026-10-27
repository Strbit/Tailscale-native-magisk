#!/usr/bin/env python3
"""build-release.py — 构建可刷入的 Magisk 模块 ZIP。

把 module/ 目录的**内容物**直接打包到 ZIP 根目录（module.prop 必须在根），
并保证：
  - 所有条目使用正斜杠路径；
  - 所有文本条目为 LF、无 BOM（Android shell 脚本带 CRLF 会无法执行）；
  - 条目顺序与时间戳固定，构建可复现。

用法：
    python tools/build-release.py            # 构建
    python tools/build-release.py --verify   # 构建两次并比对 SHA256
"""
from __future__ import annotations

import hashlib
import io
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "module"
RELEASE = ROOT / "release"

VERSION = "0.5.2-zh"
ZIP_NAME = f"native-tailscale-magisk-bootstrap-v{ VERSION }.zip"
ZIP_PATH = RELEASE / ZIP_NAME

# 固定时间戳（1980-01-01 是 ZIP 格式可表示的最早时间），保证可复现构建。
FIXED_DATE = (1980, 1, 1, 0, 0, 0)

# 必须存在的文件（相对 ZIP 根）
REQUIRED = [
    "module.prop",
    "customize.sh",
    "service.sh",
    "action.sh",
    "common.sh",
    "i18n.sh",
    "webui.sh",
    "uninstall.sh",
    "README.txt",
    "skip_mount",
    "upstream_commit",
    "bin/.placeholder",
    "webroot/index.html",
    "webroot/app.js",
    "webroot/i18n.js",
    "webroot/styles.css",
]

# 不允许进入 ZIP 的内容
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db"}
EXCLUDED_SUFFIXES = (".bak", ".tmp", ".orig")
EXCLUDED_PREFIXES = (".git",)

TEXT_SUFFIXES = (".sh", ".prop", ".txt", ".js", ".html", ".css", ".json", ".md")


def collect() -> list[tuple[str, bytes]]:
    """收集要打包的条目，按路径排序以保证顺序稳定。"""
    entries: list[tuple[str, bytes]] = []
    for path in sorted(MODULE.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(MODULE).as_posix()

        parts = rel.split("/")
        if any(p.startswith(EXCLUDED_PREFIXES) for p in parts):
            continue
        if parts[-1] in EXCLUDED_NAMES:
            continue
        if rel.endswith(EXCLUDED_SUFFIXES):
            continue

        data = path.read_bytes()

        # 文本文件强制 LF 并去除 BOM
        if rel.endswith(TEXT_SUFFIXES) or rel == "skip_mount":
            if data.startswith(b"\xef\xbb\xbf"):
                data = data[3:]
            data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

        entries.append((rel, data))

    # 目录条目：让 Magisk 安装时目录结构完整
    dirs = sorted({rel.rsplit("/", 1)[0] for rel, _ in entries if "/" in rel})
    result: list[tuple[str, bytes]] = [(d + "/", b"") for d in dirs]
    result.extend(entries)
    return result


def build() -> Path:
    RELEASE.mkdir(parents=True, exist_ok=True)
    entries = collect()

    names = {name for name, _ in entries}
    missing = [r for r in REQUIRED if r not in names]
    if missing:
        raise SystemExit(f"缺少必需文件：{', '.join(missing)}")

    # 自检：不允许 CRLF 残留
    for name, data in entries:
        if not name.endswith(TEXT_SUFFIXES) and name != "skip_mount":
            continue
        if b"\r\n" in data:
            raise SystemExit(f"{name} 仍含 CRLF")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if name.endswith(".sh") else 0o644) << 16
            if name.endswith("/"):
                info.external_attr = (0o755 | 0o040000) << 16
            zf.writestr(info, data)

    payload = buf.getvalue()
    ZIP_PATH.write_bytes(payload)

    digest = hashlib.sha256(payload).hexdigest()
    print(f"built  : {ZIP_PATH.relative_to(ROOT).as_posix()}")
    print(f"size   : {len(payload)} bytes")
    print(f"sha256 : {digest}")
    print(f"entries: {len(entries)}")
    return ZIP_PATH


def update_sums() -> None:
    """把新 ZIP 的校验行追加/替换进 SHA256SUMS（保留历史行）。"""
    sums_path = ROOT / "SHA256SUMS"
    digest = hashlib.sha256(ZIP_PATH.read_bytes()).hexdigest()
    rel = ZIP_PATH.relative_to(ROOT).as_posix()
    line = f"{digest}  {rel}"

    lines: list[str] = []
    if sums_path.exists():
        for raw in sums_path.read_text(encoding="utf-8").splitlines():
            if raw.strip() and rel not in raw:
                lines.append(raw.strip())
    lines.append(line)
    sums_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"sums   : {sums_path.name} 已更新（{len(lines)} 行）")


def verify() -> int:
    """校验 SHA256SUMS 中的每一行，并检查可复现性。"""
    sums_path = ROOT / "SHA256SUMS"
    bad = 0
    total = 0
    for raw in sums_path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        digest, _, rel = raw.partition("  ")
        target = ROOT / rel
        total += 1
        if not target.exists():
            print(f"MISSING {rel}")
            bad += 1
            continue
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != digest:
            print(f"MISMATCH {rel}")
            bad += 1
    print(f"verify : {total - bad}/{total} 行通过")

    first = hashlib.sha256(ZIP_PATH.read_bytes()).hexdigest()
    build()
    second = hashlib.sha256(ZIP_PATH.read_bytes()).hexdigest()
    if first != second:
        print(f"NOT REPRODUCIBLE: {first} != {second}")
        return 1
    print("repro  : 可复现构建通过")
    return 1 if bad else 0


def main() -> int:
    if "--verify" in sys.argv:
        build()
        update_sums()
        return verify()
    build()
    update_sums()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
