"""Стол лофт 1500 × 650 × 780: столешница «кашемир» на чёрном подстолье из трубы 40×20.

Запуск:  blender --background --python tools/blender/table_loft.py -- [ключи]
         python tools/blender/table_loft.py [ключи]       (при установленном bpy)
Ключи:   --render, --glb, --samples N, --res W H, --cameras a,b,c, --no-save

Подстолье — две замкнутые боковые рамы («O») и стальная перегородка сзади между ними,
от 400 мм над полом до столешницы. Скрипт печатает карту раскроя: размеры столешницы,
длины всех отрезков трубы и размер листа.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen import (  # noqa: E402
    box, collection, principled, reset_scene, setup_render, srgb, _coords,
)

# --------------------------------------------------------------------------
# Размеры (метры)
# --------------------------------------------------------------------------

LENGTH, DEPTH, HEIGHT = 1.500, 0.650, 0.780
TOP_T = 0.032                 # столешница ЛДСП 32 мм
TUBE_W, TUBE_T = 0.040, 0.020 # профильная труба 40×20: 40 — в плоскости рамы, 20 — толщина
FRAME_INSET = 0.070           # отступ рамы от торца столешницы
FRAME_DEPTH = 0.550           # рама по глубине (наружный размер)
FRAME_H = HEIGHT - TOP_T      # рама упирается в столешницу
PAD_H = 0.006                 # подпятники
PANEL_Z0 = 0.400              # задняя перегородка: нижняя кромка от пола
PANEL_T = 0.003               # стальной лист

PALETTE = {
    "cashmere": "#CBC1B2",    # ЛДСП «кашемир серый»
    "cashmere_deep": "#C4BAAB",
    "powder": "#111213",      # порошковая краска, чёрный муар
    "rubber": "#0A0A0A",
    "studio": "#E6E3DD",
}


# --------------------------------------------------------------------------
# Материалы
# --------------------------------------------------------------------------


def _bump(nt, bsdf, mapping, scale, strength):
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.7
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = 0.001
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def _rough(nt, bsdf, mapping, scale, lo, hi):
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (lo, lo, lo, 1.0)
    ramp.color_ramp.elements[1].position = 0.65
    ramp.color_ramp.elements[1].color = (hi, hi, hi, 1.0)
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Roughness"])


def laminate_material(name, color, deep):
    """ЛДСП с матовым тиснением: мелкое зерно в рельефе и лёгкая неоднородность тона."""
    mat = principled(name, color, roughness=0.5)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 1.0)
    tone = nt.nodes.new("ShaderNodeTexNoise")
    tone.inputs["Scale"].default_value = 12.0
    tone.inputs["Detail"].default_value = 5.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*deep, 1.0)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*color, 1.0)
    nt.links.new(mapping.outputs["Vector"], tone.inputs["Vector"])
    nt.links.new(tone.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _rough(nt, bsdf, mapping, 40.0, 0.46, 0.58)
    _bump(nt, bsdf, mapping, 600.0, 0.025)
    return mat


def powder_coat_material(name, color):
    """Порошковая краска: чёрная, полуматовая, с характерной «шагренью»."""
    mat = principled(name, color, roughness=0.42, coat=0.06)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 1.0)
    _rough(nt, bsdf, mapping, 60.0, 0.36, 0.5)
    _bump(nt, bsdf, mapping, 260.0, 0.08)
    return mat


def build_materials():
    p = {k: srgb(v) for k, v in PALETTE.items()}
    return {
        "cashmere": laminate_material("ЛДСП кашемир", p["cashmere"], p["cashmere_deep"]),
        "powder": powder_coat_material("Порошковая краска чёрная", p["powder"]),
        "rubber": principled("Подпятник", p["rubber"], roughness=0.85),
        "studio": principled("Студийный фон", p["studio"], roughness=0.6),
    }


# --------------------------------------------------------------------------
# Геометрия
# --------------------------------------------------------------------------


def build_table(mats, colls):
    cut = {"труба 40×20": []}

    # столешница: кромка ABS 2 мм читается как мягкое скругление ребра
    top = colls["top"]
    box("Столешница", (-LENGTH / 2, -DEPTH / 2, FRAME_H), (LENGTH / 2, DEPTH / 2, HEIGHT),
        mats["cashmere"], top, bevel=0.002)

    frame = colls["frame"]
    y_out = FRAME_DEPTH / 2
    x_centers = (-(LENGTH / 2 - FRAME_INSET - TUBE_T / 2), LENGTH / 2 - FRAME_INSET - TUBE_T / 2)
    leg_len = FRAME_H
    rail_len = FRAME_DEPTH - 2 * TUBE_W
    for xc in x_centers:
        x0, x1 = xc - TUBE_T / 2, xc + TUBE_T / 2
        for ya, yb in ((-y_out, -y_out + TUBE_W), (y_out - TUBE_W, y_out)):
            box("Стойка рамы", (x0, ya, PAD_H), (x1, yb, FRAME_H), mats["powder"], frame, bevel=0.0015)
            cut["труба 40×20"].append(("стойка", leg_len - PAD_H))
        for za, zb in ((PAD_H, PAD_H + TUBE_W), (FRAME_H - TUBE_W, FRAME_H)):
            box("Перекладина рамы", (x0, -y_out + TUBE_W, za), (x1, y_out - TUBE_W, zb),
                mats["powder"], frame, bevel=0.0015)
            cut["труба 40×20"].append(("перекладина", rail_len))
        for ya, yb in ((-y_out, -y_out + TUBE_W), (y_out - TUBE_W, y_out)):
            box("Подпятник", (x0 - 0.001, ya, 0.0), (x1 + 0.001, yb, PAD_H), mats["rubber"], frame,
                bevel=0.0)

    # задняя перегородка: стальной лист между задними стойками, вварен в плоскости рамы,
    # от PANEL_Z0 до столешницы — связывает рамы и не даёт столу «играть»
    sx0, sx1 = x_centers[0] + TUBE_T / 2, x_centers[1] - TUBE_T / 2
    py = y_out - TUBE_W / 2
    box("Перегородка", (sx0, py - PANEL_T / 2, PANEL_Z0), (sx1, py + PANEL_T / 2, FRAME_H),
        mats["powder"], frame, bevel=0.0008)
    cut["лист 3 мм"] = [("перегородка %d × %d мм" % ((sx1 - sx0) * 1000, (FRAME_H - PANEL_Z0) * 1000),
                         sx1 - sx0)]

    # пластины крепления к столешнице — видны снизу, как в реальном изделии
    for xc in x_centers:
        box("Пластина крепления", (xc - 0.03, -y_out + TUBE_W, FRAME_H - 0.004),
            (xc + 0.03, y_out - TUBE_W, FRAME_H), mats["powder"], frame, bevel=0.0)
    return cut


def build_studio(mats, colls):
    coll = colls["studio"]
    box("Пол студии", (-8.0, -8.0, -0.02), (8.0, 8.0, 0.0), mats["studio"], coll, bevel=0.0)
    box("Задник студии", (-8.0, 3.2, 0.0), (8.0, 3.3, 5.0), mats["studio"], coll, bevel=0.0)


def build_lighting(colls):
    coll = colls["lights"]

    def area(name, loc, target, sx, sy, power, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "RECTANGLE"
        data.size, data.size_y = sx, sy
        data.energy = power
        data.color = color
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        ob.visible_camera = False
        coll.objects.link(ob)

    area("Рисующий", (-1.6, -2.2, 2.6), (0.0, 0.0, 0.6), 2.2, 2.2, 330.0, (1.0, 0.97, 0.93))
    area("Заполняющий", (2.2, -1.6, 1.6), (0.0, 0.0, 0.5), 2.0, 2.0, 90.0, (0.93, 0.96, 1.0))
    area("Контровой", (0.8, 2.4, 2.2), (0.0, 0.0, 0.7), 1.2, 0.5, 180.0, (1.0, 1.0, 1.0))
    world = bpy.data.worlds.new("Окружение")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.8, 0.8, 0.8, 1.0)
    bg.inputs["Strength"].default_value = 0.18
    bpy.context.scene.world = world


def build_cameras(colls):
    coll = colls["cameras"]
    specs = {
        "hero": ((-1.75, -2.05, 1.20), (0.05, 0.05, 0.50), 45),
        "side": ((2.55, -0.25, 0.75), (0.0, 0.0, 0.46), 50),
        "detail": ((-1.35, -1.25, 1.05), (-0.50, -0.15, 0.70), 55),
        "back": ((1.75, 2.05, 1.05), (-0.05, 0.0, 0.48), 45),
    }
    cams = {}
    for name, (loc, target, lens) in specs.items():
        data = bpy.data.cameras.new("CAM_" + name)
        data.lens = lens
        ob = bpy.data.objects.new("CAM_" + name, data)
        ob.location = loc
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        coll.objects.link(ob)
        cams[name] = ob
    bpy.context.scene.camera = cams["hero"]
    return cams


def build():
    reset_scene()
    mats = build_materials()
    colls = {key: collection(title) for key, title in (
        ("top", "01 Столешница"),
        ("frame", "02 Подстолье"),
        ("studio", "03 Студия"),
        ("lights", "04 Свет"),
        ("cameras", "05 Камеры"),
    )}
    cut = build_table(mats, colls)
    build_studio(mats, colls)
    build_lighting(colls)
    return build_cameras(colls), cut


def setup_viewport():
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                space.shading.type = "MATERIAL"
                space.shading.use_scene_lights = False
                space.shading.use_scene_world = False
                space.shading.studio_light = "studio.exr"
                space.overlay.show_extras = False
                space.overlay.show_relationship_lines = False
                space.clip_start = 0.01
                space.clip_end = 100.0
                for region in area.regions:
                    if region.type == "WINDOW" and region.data is not None:
                        rv = region.data
                        rv.view_perspective = "PERSP"
                        rv.view_location = (0.0, 0.0, 0.45)
                        rv.view_rotation = Euler((math.radians(68), 0.0, math.radians(-38)),
                                                 "XYZ").to_quaternion()
                        rv.view_distance = 2.9


def export_glb(path):
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception:
        pass
    for obj in bpy.data.objects:
        skip = obj.type in {"CAMERA", "LIGHT"} or obj.name.startswith(("Пол студии", "Задник"))
        obj.select_set(not skip)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)


def print_cut_list(cut):
    print("\nКарта раскроя")
    print("  столешница ЛДСП %d мм: %d × %d мм, кромка ABS 2 мм по периметру"
          % (TOP_T * 1000, LENGTH * 1000, DEPTH * 1000))
    for stock, items in cut.items():
        total = 0.0
        counts = {}
        for name, length in items:
            key = (name, round(length * 1000))
            counts[key] = counts.get(key, 0) + 1
            total += length
        for (name, mm), n in sorted(counts.items(), key=lambda kv: -kv[0][1]):
            print("  %s: %d шт × %d мм — %s" % (stock, n, mm, name))
        if stock.startswith("труба"):
            print("  итого трубы: %.2f м (без учёта реза)" % total)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    do_render = "--render" in argv
    do_glb = "--glb" in argv
    do_save = "--no-save" not in argv
    samples = 64
    res = (1280, 800)
    names = ["hero", "side", "detail", "back"]
    if "--samples" in argv:
        samples = int(argv[argv.index("--samples") + 1])
    if "--res" in argv:
        i = argv.index("--res")
        res = (int(argv[i + 1]), int(argv[i + 2]))
    if "--cameras" in argv:
        names = argv[argv.index("--cameras") + 1].split(",")

    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    out_3d = os.path.join(root, "assets", "3d")
    out_img = os.path.join(out_3d, "renders")
    os.makedirs(out_img, exist_ok=True)

    cams, cut = build()
    setup_render(samples, res)
    bpy.context.scene.view_settings.exposure = 0.0
    setup_viewport()
    print("Объектов в сцене: %d" % len(bpy.data.objects))
    print_cut_list(cut)

    if do_save:
        path = os.path.join(out_3d, "table-loft.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print("Сохранено: %s" % path)
    if do_glb:
        export_glb(os.path.join(out_3d, "table-loft.glb"))
        print("Экспортировано: table-loft.glb")
    if do_render:
        scene = bpy.context.scene
        for name in names:
            scene.camera = cams[name]
            scene.render.filepath = os.path.join(out_img, "table-" + name + ".png")
            print("Рендер %s -> %s" % (name, scene.render.filepath))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
