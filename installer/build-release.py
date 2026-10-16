#!/usr/bin/env python3
"""Build DesktopSwitch.exe and the per-machine MSI used by SCCM."""

import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = Path(__file__).resolve().parent
VERSION = "1.2.41"
PRODUCT_CODE = "{C4A81E57-2D60-4F93-B8C1-6E9A3D5F0B28}"
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
    write_icon(INSTALLER / "DesktopSwitch.ico")
    shutil.copy(INSTALLER / "DesktopSwitch.ico", stage / "DesktopSwitch.ico")

    names = [
        "DesktopSwitch.ps1",
        "DesktopSwitch.Logic.ps1",
        "DesktopSwitch.Widget.ps1",
        "Install-DesktopSwitch.ps1",
        "Uninstall-DesktopSwitch.ps1",
        "Show-DesktopSwitchStatus.cmd",
        "README.md",
    ]
    for name in names:
        shutil.copy(ROOT / name, stage / name)

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
        "-out:" + str(exe),
        str(INSTALLER / "DesktopSwitch.cs"),
    ])
    if subsystem(exe) != 2:
        raise SystemExit("DesktopSwitch.exe is not a Windows GUI binary")
    blob = exe.read_bytes()
    for banned in (b"config.example.json", b"config.json", b"SHSetKnownFolderPath", b"NotifyIcon", b"JiraBaseUrl"):
        if banned in blob:
            raise SystemExit("DesktopSwitch.exe still contains %s" % banned.decode())

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

    file_table = subprocess.check_output(["msiinfo", "export", str(msi), "File"], text=True, errors="replace")
    for banned in ("config.json", "config.example.json", "news.json"):
        if banned in file_table:
            raise SystemExit("msi still packages %s" % banned)
    summary = subprocess.check_output(["msiinfo", "suminfo", str(msi)], text=True, errors="replace")
    if VERSION not in summary and VERSION not in file_table:
        # ProductVersion lives in the Property table.
        props = subprocess.check_output(["msiinfo", "export", str(msi), "Property"], text=True, errors="replace")
        if "ProductVersion\t%s" % VERSION not in props and "ProductVersion\t%s" % VERSION not in props.replace("\t", " "):
            if VERSION not in props:
                raise SystemExit("msi ProductVersion is not %s" % VERSION)

    note = (
        "DesktopSwitch %s\r\n\r\n"
        "Распакуйте архив на локальный диск и запустите DesktopSwitch.exe.\r\n"
        "Файл конфигурации не нужен. Значка у часов нет. Рабочий стол не переключается.\r\n\r\n"
        "Если интернет пропадает, в правом нижнем углу появляется красная кнопка\r\n"
        "с белым восклицательным знаком. Нажатие открывает C:\\Users\\Public\\Desktop.\r\n"
        "Когда интернет возвращается, кнопка исчезает.\r\n\r\n"
        "Кнопка появляется после двух проверок подряд без интернета\r\n"
        "и исчезает после двух проверок подряд с интернетом. Интервал — 5 секунд.\r\n\r\n"
        "Остановить программу можно в диспетчере задач: процесс DesktopSwitch.\r\n"
        "Если антивирус удаляет exe при скачивании из браузера, берите этот архив.\r\n"
    ) % VERSION
    zip_path = stage / "DesktopSwitch-portable.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(stage / name, "DesktopSwitch/" + name)
        archive.write(exe, "DesktopSwitch/DesktopSwitch.exe")
        archive.writestr("DesktopSwitch/ПРОЧТИТЕ.txt", "\ufeff" + note)

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    shutil.copy(exe, dist / "DesktopSwitch.exe")
    shutil.copy(msi, dist / "DesktopSwitch.msi")
    shutil.copy(zip_path, dist / "DesktopSwitch-portable.zip")
    artifacts = Path("/opt/cursor/artifacts")
    if artifacts.exists():
        shutil.copyfile(exe, artifacts / "DesktopSwitch.exe")
        shutil.copyfile(msi, artifacts / "DesktopSwitch.msi")
        shutil.copyfile(zip_path, artifacts / "DesktopSwitch-portable.zip")
    print(dist / "DesktopSwitch.exe", (dist / "DesktopSwitch.exe").stat().st_size)
    print(dist / "DesktopSwitch.msi", (dist / "DesktopSwitch.msi").stat().st_size)
    print(dist / "DesktopSwitch-portable.zip", (dist / "DesktopSwitch-portable.zip").stat().st_size)
    print("ProductCode", PRODUCT_CODE)
    print("UpgradeCode", UPGRADE_CODE)
    print("Version", VERSION)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
