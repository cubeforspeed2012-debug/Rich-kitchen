#!/usr/bin/env python3
"""Собирает из .lua исходников готовые файлы для Roblox Studio.

Для каждой игры получается:
  build/<Имя>.rbxlx        - готовое место: File -> Open in Studio, жми Play
  build/<Папка>.rbxmx      - отдельные модели, если место открывать не хочется

Запуск:  python3 tools/build_roblox_files.py
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PROJECTS = [
    {
        "dir": "roblox-he-will-come",
        "place": "HeWillCome",
        "groups": [
            ("ReplicatedStorage", "HWCShared", "src/shared"),
            ("ServerScriptService", "HWCServer", "src/server"),
            ("StarterPlayerScripts", "HWCClient", "src/client"),
        ],
    },
    {
        "dir": "roblox-locust-house",
        "place": "DomSaranchi",
        "groups": [
            ("ReplicatedStorage", "LocustShared", "src/shared"),
            ("ServerScriptService", "LocustServer", "src/server"),
            ("StarterPlayerScripts", "LocustClient", "src/client"),
        ],
    },
]


class Ref:
    def __init__(self):
        self.n = 0

    def next(self):
        value = "RBX%X" % self.n
        self.n += 1
        return value


def script_class(path: pathlib.Path):
    """По имени файла понимаем, какой это тип скрипта в Roblox."""
    name = path.name
    if name.endswith(".server.lua"):
        return "Script", name[: -len(".server.lua")]
    if name.endswith(".client.lua"):
        return "LocalScript", name[: -len(".client.lua")]
    return "ModuleScript", name[: -len(".lua")]


def script_item(path: pathlib.Path, ref: Ref, indent: str) -> str:
    class_name, instance_name = script_class(path)
    source = path.read_text(encoding="utf-8")
    if "]]>" in source:
        raise SystemExit("Нельзя: в %s есть ]]> - сломает CDATA" % path)
    return (
        '{i}<Item class="{c}" referent="{r}">\n'
        "{i}\t<Properties>\n"
        '{i}\t\t<string name="Name">{n}</string>\n'
        '{i}\t\t<ProtectedString name="Source"><![CDATA[{s}]]></ProtectedString>\n'
        "{i}\t</Properties>\n"
        "{i}</Item>\n"
    ).format(i=indent, c=class_name, r=ref.next(), n=instance_name, s=source)


def folder_item(folder_name: str, src_dir: pathlib.Path, ref: Ref, indent: str) -> str:
    out = [
        '{i}<Item class="Folder" referent="{r}">\n'
        "{i}\t<Properties>\n"
        '{i}\t\t<string name="Name">{n}</string>\n'
        "{i}\t</Properties>\n".format(i=indent, r=ref.next(), n=folder_name)
    ]
    for path in sorted(src_dir.glob("*.lua")):
        out.append(script_item(path, ref, indent + "\t"))
    out.append("{i}</Item>\n".format(i=indent))
    return "".join(out)


HEADER = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
)
FOOTER = "</roblox>\n"


def service_item(class_name: str, ref: Ref, inner: str) -> str:
    """Сервис верхнего уровня места (Workspace, ReplicatedStorage и т.д.)."""
    return (
        '\t<Item class="{c}" referent="{r}">\n'
        "\t\t<Properties>\n"
        '\t\t\t<string name="Name">{c}</string>\n'
        "\t\t</Properties>\n"
        "{inner}"
        "\t</Item>\n"
    ).format(c=class_name, r=ref.next(), inner=inner)


def build(project) -> None:
    base = ROOT / project["dir"]
    out_dir = base / "build"
    out_dir.mkdir(exist_ok=True)

    # 1) отдельные модели на каждую папку
    for _, folder_name, src in project["groups"]:
        ref = Ref()
        body = folder_item(folder_name, base / src, ref, "\t")
        (out_dir / (folder_name + ".rbxmx")).write_text(HEADER + body + FOOTER, encoding="utf-8")

    # 2) целое место со всеми скриптами на своих местах
    ref = Ref()
    parts = [service_item("Workspace", ref, ""), service_item("Lighting", ref, "")]

    for service, folder_name, src in project["groups"]:
        if service == "StarterPlayerScripts":
            scripts_holder = (
                '\t\t<Item class="StarterPlayerScripts" referent="{r}">\n'
                "\t\t\t<Properties>\n"
                '\t\t\t\t<string name="Name">StarterPlayerScripts</string>\n'
                "\t\t\t</Properties>\n"
                "{inner}"
                "\t\t</Item>\n"
            ).format(r=ref.next(), inner=folder_item(folder_name, base / src, ref, "\t\t\t"))
            # R15 нужен для приседания и подката (масштаб роста персонажа)
            avatar = '\t\t\t<token name="GameSettingsAvatar">1</token>\n'
            parts.append(service_item("StarterPlayer", ref, scripts_holder).replace(
                "\t\t</Properties>\n", avatar + "\t\t</Properties>\n", 1))
        else:
            parts.append(service_item(service, ref, folder_item(folder_name, base / src, ref, "\t\t")))

    (out_dir / (project["place"] + ".rbxlx")).write_text(HEADER + "".join(parts) + FOOTER, encoding="utf-8")
    print("готово:", out_dir)


for project in PROJECTS:
    build(project)
