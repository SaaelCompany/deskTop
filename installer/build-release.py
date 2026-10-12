#!/usr/bin/env python3
"""Build DesktopSwitch.exe and the per-machine MSI used by SCCM."""

import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = Path(__file__).resolve().parent
VERSION = "1.2.39"
PRODUCT_CODE = "{8C2E6B41-5A19-4D73-9F08-1B7D4C3E6A50}"
UPGRADE_CODE = "{4048E9C4-7965-48DC-A23D-A4554966E57F}"


def run(cmd):
    print("+", " ".join(cmd))
    subprocess.check_call(cmd)


def render_icon(size):
    pixels = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]
    cx = (size - 1) / 2.0
    radius = size / 2.0 - 0.75
    accent = (220, 38, 38, 255)
    for y in range(size):
        for x in range(size):
            if (x - cx) ** 2 + (y - cx) ** 2 <= radius ** 2:
                pixels[y][x] = accent
    scale = size / 32.0

    def mark(px, py, color):
        x = int(round(px * scale))
        y = int(round(py * scale))
        for dy in range(max(1, int(round(scale)))):
            for dx in range(max(1, int(round(scale)))):
                xx = x + dx
                yy = y + dy
                if 0 <= xx < size and 0 <= yy < size and pixels[yy][xx][3]:
                    pixels[yy][xx] = color

    white = (255, 255, 255, 255)
    for y in range(7, 20):
        mark(15, y, white)
        mark(16, y, white)
    for y in range(23, 26):
        mark(15, y, white)
        mark(16, y, white)
    return pixels


def icon_image(pixels):
    size = len(pixels)
    xor_rows = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            red, green, blue, alpha = pixels[y][x]
            xor_rows += bytes((blue, green, red, alpha))
    row_bytes = ((size + 31) // 32) * 4
    mask = bytearray()
    for y in range(size - 1, -1, -1):
        row = bytearray(row_bytes)
        for x in range(size):
            if pixels[y][x][3] < 32:
                row[x // 8] |= 0x80 >> (x % 8)
        mask += row
    header = struct.pack("<IIIHHIIIIII", 40, size, size * 2, 1, 32, 0, len(xor_rows) + len(mask), 0, 0, 0, 0)
    return header + xor_rows + mask


def write_icon(path):
    sizes = (16, 24, 32, 48, 64)
    images = [icon_image(render_icon(size)) for size in sizes]
    blob = bytearray(struct.pack("<HHH", 0, 1, len(images)))
    offset = 6 + 16 * len(images)
    for size, image in zip(sizes, images):
        stored = 0 if size >= 256 else size
        blob += struct.pack("<BBBBHHII", stored, stored, 0, 0, 1, 32, len(image), offset)
        offset += len(image)
    for image in images:
        blob += image
    path.write_bytes(blob)


def sccm_config(example: Path, destination: Path):
    override = INSTALLER / "config.sccm.json"
    if override.exists():
        data = override.read_bytes()
    else:
        text = example.read_text(encoding="utf-8-sig")
        needle = '"Enabled": false'
        if needle not in text:
            raise SystemExit("config.example.json has no Enabled false switch")
        text = text.replace(needle, '"Enabled": true', 1)
        note = "// Файл пакета SCCM. Enabled включён. LocalDesktopPath — C:\\Users\\Public\\Desktop. EmergencyFolder заполните перед раздачей.\n"
        if not text.startswith(note):
            text = note + text
        data = b"\xef\xbb\xbf" + text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
    destination.write_bytes(data)


def sql_quote(value):
    return "'" + value.replace("'", "''") + "'"


def add_action(msi, name, target, sequence):
    if len(target) > 255:
        raise SystemExit("custom action %s is %s characters" % (name, len(target)))
    run([
        "msibuild", str(msi), "-q",
        "INSERT INTO `CustomAction` (`Action`, `Type`, `Source`, `Target`) VALUES (%s, 98, 'SystemFolder', %s)" % (sql_quote(name), sql_quote(target)),
    ])
    run([
        "msibuild", str(msi), "-q",
        "INSERT INTO `InstallExecuteSequence` (`Action`, `Sequence`) VALUES (%s, %s)" % (sql_quote(name), sequence),
    ])


def subsystem(path):
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    magic = struct.unpack_from("<H", data, pe + 24)[0]
    if magic == 0x10B:
        return struct.unpack_from("<H", data, pe + 24 + 68)[0]
    if magic == 0x20B:
        return struct.unpack_from("<H", data, pe + 24 + 68)[0]
    raise SystemExit("unknown PE magic")


def main():
    mcs = shutil.which("mcs")
    wixl = shutil.which("wixl")
    msibuild = shutil.which("msibuild")
    if not mcs or not wixl or not msibuild:
        raise SystemExit("mcs, wixl and msibuild must be installed")
    sma = Path("/tmp/ps5-extract/lib/net4/System.Management.Automation.dll")
    winforms = Path("/usr/lib/mono/4.5/System.Windows.Forms.dll")
    drawing = Path("/usr/lib/mono/4.5/System.Drawing.dll")
    if not sma.exists():
        raise SystemExit("missing PowerShell reference assembly: %s" % sma)
    if not winforms.exists():
        raise SystemExit("missing System.Windows.Forms.dll")

    stage = Path("/tmp/desktopswitch-stage")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    (stage / "examples").mkdir()
    write_icon(INSTALLER / "DesktopSwitch.ico")
    shutil.copy(INSTALLER / "DesktopSwitch.ico", stage / "DesktopSwitch.ico")

    names = [
        "DesktopSwitch.ps1",
        "DesktopSwitch.Logic.ps1",
        "DesktopSwitch.Widget.ps1",
        "Install-DesktopSwitch.ps1",
        "Uninstall-DesktopSwitch.ps1",
        "Show-DesktopSwitchStatus.cmd",
        "config.example.json",
        "README.md",
    ]
    for name in names:
        shutil.copy(ROOT / name, stage / name)
    shutil.copy(ROOT / "examples" / "news.json", stage / "examples" / "news.json")
    sccm_config(ROOT / "config.example.json", stage / "config.json")
    config_text = (stage / "config.json").read_text(encoding="utf-8-sig")
    if '"Enabled": true' not in config_text:
        raise SystemExit("SCCM config is not enabled")

    exe = stage / "DesktopSwitch.exe"
    run([
        mcs, "-nologo", "-target:winexe", "-sdk:4.5", "-platform:anycpu", "-optimize+",
        "-codepage:utf8",
        "-r:" + str(drawing),
        "-r:" + str(winforms),
        "-r:" + str(sma),
        "-win32icon:" + str(stage / "DesktopSwitch.ico"),
        "-resource:" + str(stage / "DesktopSwitch.ps1") + ",DesktopSwitch.ps1",
        "-resource:" + str(stage / "DesktopSwitch.Logic.ps1") + ",DesktopSwitch.Logic.ps1",
        "-resource:" + str(stage / "DesktopSwitch.Widget.ps1") + ",DesktopSwitch.Widget.ps1",
        "-resource:" + str(ROOT / "config.example.json") + ",config.example.json",
        "-out:" + str(exe),
        str(INSTALLER / "DesktopSwitch.cs"),
    ])
    if subsystem(exe) != 2:
        raise SystemExit("DesktopSwitch.exe is not a Windows GUI binary")

    wxs = stage / "DesktopSwitch.wxs"
    shutil.copy(INSTALLER / "DesktopSwitch.wxs", wxs)
    msi = stage / "DesktopSwitch.msi"
    run(["wixl", "-a", "x64", str(wxs), "-o", str(msi)])
    add_action(msi, "CA_KillExe", "taskkill.exe /F /IM DesktopSwitch.exe", 1390)
    add_action(
        msi,
        "CA_RemoveVbs",
        r'cmd.exe /c del /f /q "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\DesktopSwitch.vbs"',
        1391,
    )

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    shutil.copy(exe, dist / "DesktopSwitch.exe")
    shutil.copy(msi, dist / "DesktopSwitch.msi")
    artifacts = Path("/opt/cursor/artifacts")
    if artifacts.exists():
        shutil.copyfile(exe, artifacts / "DesktopSwitch.exe")
        shutil.copyfile(msi, artifacts / "DesktopSwitch.msi")
    print(dist / "DesktopSwitch.exe", (dist / "DesktopSwitch.exe").stat().st_size)
    print(dist / "DesktopSwitch.msi", (dist / "DesktopSwitch.msi").stat().st_size)
    print("ProductCode", PRODUCT_CODE)
    print("UpgradeCode", UPGRADE_CODE)
    print("Version", VERSION)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
