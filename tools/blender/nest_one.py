"""Nest One, Tashkent City — процедурная модель башни в вечернем городе.

Запуск:  blender --background --python tools/blender/nest_one.py -- [ключи]
         python tools/blender/nest_one.py [ключи]       (при установленном bpy)
Ключи:   --render, --glb, --samples N, --res W H, --cameras a,b,c, --no-save

Башня ~266 м: стеклянный ствол из трёх секций с уступами и световыми поясами, корона
с открытым каркасом и шпилем, стилобат с лобби и козырьком, площадь с деревьями и
фонарями, кварталы вокруг. Фасадная текстура задаётся в метрах (модуль окна × этаж):
развёртка строится по периметру, поэтому сетка импостов совпадает на всех гранях.
Форма — по общему облику башни; точные пропорции правятся в блоке «Габариты».
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen import box, collection, cyl, emissive, principled, reset_scene, setup_render, srgb, _coords  # noqa: E402

# --------------------------------------------------------------------------
# Габариты (метры)
# --------------------------------------------------------------------------

FLOOR_H = 3.6
MODULE_W = 1.5
# секции ствола: (низ, верх, полуширина, срез угла)
SECTIONS = [(24.0, 96.0, 23.0, 7.0), (96.0, 176.0, 21.5, 6.5), (176.0, 250.0, 19.5, 6.0)]
CROWN_Z0, CROWN_Z1 = 250.0, 266.0
SPIRE_Z1 = 290.0
PODIUM = (-42.0, 42.0, -34.0, 30.0, 24.0)       # x0, x1, y0, y1, высота
LOBBY_H = 7.2
PLAZA = (-120.0, 120.0, -130.0, 80.0)

PALETTE = {
    "glass": "#1B2836",
    "mullion": "#9AA3AC",
    "window_light": "#FFB566",
    "roof": "#3A3D41",
    "granite": "#A39E96",
    "granite_dark": "#7C7872",
    "asphalt": "#26282B",
    "grass": "#3E5A2C",
    "foliage": "#2F4A24",
    "bark": "#3A2A1E",
    "led": "#BFE4FF",
}


# --------------------------------------------------------------------------
# Геометрия: призма по многоугольнику с развёрткой в метрах
# --------------------------------------------------------------------------


def chamfered(h, c, cx=0.0, cy=0.0):
    pts = [(h - c, -h), (h, -h + c), (h, h - c), (h - c, h),
           (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h)]
    return [(cx + x, cy + y) for x, y in pts]


def rect(x0, x1, y0, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def prism(name, poly, z0, z1, side_mat, cap_mat, coll, caps=True):
    """Боковые грани получают UV = (путь по периметру, высота) в метрах."""
    verts, faces, uvs, mat_idx = [], [], [], []
    perim = 0.0
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        length = math.dist(p, q)
        b = len(verts)
        verts += [(p[0], p[1], z0), (q[0], q[1], z0), (q[0], q[1], z1), (p[0], p[1], z1)]
        uvs += [(perim, z0), (perim + length, z0), (perim + length, z1), (perim, z1)]
        faces.append((b, b + 1, b + 2, b + 3))
        mat_idx.append(0)
        perim += length
    if caps:
        b = len(verts)
        verts += [(x, y, z1) for x, y in poly]
        uvs += list(poly)
        faces.append(tuple(range(b, b + n)))
        mat_idx.append(1)
        b = len(verts)
        verts += [(x, y, z0) for x, y in poly]
        uvs += list(poly)
        faces.append(tuple(reversed(range(b, b + n))))
        mat_idx.append(1)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    me.materials.append(side_mat)
    me.materials.append(cap_mat or side_mat)
    for poly_, idx in zip(me.polygons, mat_idx):
        poly_.material_index = idx
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def offset(poly, d):
    """Грубое смещение выпуклого многоугольника наружу (для поясов и карнизов)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    out = []
    for x, y in poly:
        vx, vy = x - cx, y - cy
        r = math.hypot(vx, vy)
        out.append((x + vx / r * d, y + vy / r * d))
    return out


# --------------------------------------------------------------------------
# Материалы
# --------------------------------------------------------------------------


def _ramp(nt, stops, constant=False):
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    if constant:
        ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0]
    els[1].position, els[1].color = stops[1]
    for pos, col in stops[2:]:
        els.new(pos).color = col
    return ramp


def _input(node, *names):
    for n in names:
        if n in node.inputs:
            return node.inputs[n]
    raise KeyError(names)


def facade_material(name, module_w, floor_h, lit, glass, mullion, light, strength, mortar=0.14):
    """Стеклянный фасад: сетка импостов и ригелей, часть окон горит тёплым светом."""
    mat = principled(name, glass, roughness=0.05, coat=0.4)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.squash = 1.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = mortar
    brick.inputs["Mortar Smooth"].default_value = 0.0
    brick.inputs["Bias"].default_value = 0.0
    brick.inputs["Brick Width"].default_value = module_w
    brick.inputs["Row Height"].default_value = floor_h
    brick.inputs["Color1"].default_value = (0.0, 0.0, 0.0, 1.0)
    brick.inputs["Color2"].default_value = (1.0, 1.0, 1.0, 1.0)
    brick.inputs["Mortar"].default_value = (0.0, 0.0, 0.0, 1.0)
    nt.links.new(tex.outputs["UV"], brick.inputs["Vector"])

    # стекло ↔ алюминиевый профиль
    frame = _ramp(nt, [(0.0, (*glass, 1.0)), (0.5, (*mullion, 1.0))], constant=True)
    nt.links.new(brick.outputs["Fac"], frame.inputs["Fac"])
    nt.links.new(frame.outputs["Color"], bsdf.inputs["Base Color"])
    rough = nt.nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.04
    rough.inputs["To Max"].default_value = 0.35
    nt.links.new(brick.outputs["Fac"], rough.inputs["Value"])
    nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    nt.links.new(brick.outputs["Fac"], bsdf.inputs["Metallic"])

    # горящие окна: случайная доля модулей, без профилей
    lit_mask = _ramp(nt, [(0.0, (0, 0, 0, 1)), (1.0 - lit, (1, 1, 1, 1))], constant=True)
    nt.links.new(brick.outputs["Color"], lit_mask.inputs["Fac"])
    not_frame = nt.nodes.new("ShaderNodeMath")
    not_frame.operation = "SUBTRACT"
    not_frame.inputs[0].default_value = 1.0
    nt.links.new(brick.outputs["Fac"], not_frame.inputs[1])
    mask = nt.nodes.new("ShaderNodeMath")
    mask.operation = "MULTIPLY"
    nt.links.new(lit_mask.outputs["Color"], mask.inputs[0])
    nt.links.new(not_frame.outputs["Value"], mask.inputs[1])
    # яркость окна немного плавает от модуля к модулю
    vary = nt.nodes.new("ShaderNodeMath")
    vary.operation = "MULTIPLY_ADD"
    vary.inputs[2].default_value = 0.4
    nt.links.new(brick.outputs["Color"], vary.inputs[0])
    vary.inputs[1].default_value = 0.6
    amount = nt.nodes.new("ShaderNodeMath")
    amount.operation = "MULTIPLY"
    nt.links.new(mask.outputs["Value"], amount.inputs[0])
    nt.links.new(vary.outputs["Value"], amount.inputs[1])
    gain = nt.nodes.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = strength
    nt.links.new(amount.outputs["Value"], gain.inputs[0])
    _input(bsdf, "Emission Color", "Emission").default_value = (*light, 1.0)
    nt.links.new(gain.outputs["Value"], _input(bsdf, "Emission Strength"))
    return mat


def paving_material(name, light, dark, tile_w, tile_h):
    mat = principled(name, light, roughness=0.55)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 1.0)
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.5
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.008
    brick.inputs["Brick Width"].default_value = tile_w
    brick.inputs["Row Height"].default_value = tile_h
    brick.inputs["Color1"].default_value = (*light, 1.0)
    brick.inputs["Color2"].default_value = (*dark, 1.0)
    brick.inputs["Mortar"].default_value = (*[c * 0.55 for c in dark], 1.0)
    nt.links.new(mapping.outputs["Vector"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], bsdf.inputs["Base Color"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def noisy_material(name, color, dark, roughness, scale):
    mat = principled(name, color, roughness=roughness)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 1.0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 8.0
    ramp = _ramp(nt, [(0.3, (*dark, 1.0)), (0.7, (*color, 1.0))])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def build_materials():
    p = {k: srgb(v) for k, v in PALETTE.items()}
    return {
        "tower": facade_material("Фасад башни", MODULE_W, FLOOR_H, 0.2, p["glass"], p["mullion"],
                                 p["window_light"], 1.6),
        "podium": facade_material("Фасад стилобата", 3.0, 6.0, 0.35, p["glass"], p["mullion"],
                                  p["window_light"], 1.4, mortar=0.22),
        "lobby": facade_material("Витраж лобби", 2.4, LOBBY_H, 0.92, p["glass"], p["mullion"],
                                 p["window_light"], 2.4, mortar=0.12),
        "city": facade_material("Фасады города", 1.8, 3.3, 0.14, srgb("#2B3038"), srgb("#5E646B"),
                                p["window_light"], 1.1, mortar=0.3),
        "roof": principled("Кровля", p["roof"], roughness=0.7),
        "steel": principled("Сталь короны", p["mullion"], roughness=0.3, metallic=1.0),
        "led": emissive("LED пояс", p["led"], 8.0),
        "led_warm": emissive("Фонари", p["window_light"], 30.0),
        "granite": paving_material("Гранит площади", p["granite"], p["granite_dark"], 1.2, 0.6),
        "asphalt": noisy_material("Асфальт", p["asphalt"], srgb("#1A1B1D"), 0.85, 40.0),
        "grass": noisy_material("Газон", p["grass"], srgb("#2C4220"), 0.9, 25.0),
        "foliage": noisy_material("Крона", p["foliage"], srgb("#20341A"), 0.8, 3.0),
        "bark": principled("Кора", p["bark"], roughness=0.9),
        "sign": emissive("Вывеска", (1.0, 1.0, 1.0), 12.0),
    }


# --------------------------------------------------------------------------
# Башня, стилобат, площадь, город
# --------------------------------------------------------------------------


def build_tower(mats, colls):
    coll = colls["tower"]
    for i, (z0, z1, h, c) in enumerate(SECTIONS):
        poly = chamfered(h, c)
        prism("Ствол %d" % (i + 1), poly, z0, z1, mats["tower"], mats["roof"], coll)
        # световой пояс и карниз на уступе
        prism("Пояс %d" % (i + 1), offset(poly, 0.35), z1 - 0.9, z1, mats["led"], mats["roof"], coll)
        prism("Карниз %d" % (i + 1), offset(poly, 0.6), z1, z1 + 0.6, mats["steel"], mats["roof"], coll)

    # корона: колонны по углам, кольца, внутренняя подсветка, шпиль
    h, c = SECTIONS[-1][2] - 1.0, SECTIONS[-1][3]
    crown = colls["crown"]
    for (x, y) in chamfered(h, c):
        prism("Колонна короны", chamfered(0.7, 0.2, x * 0.97, y * 0.97), CROWN_Z0, CROWN_Z1,
              mats["steel"], mats["steel"], crown)
    for z in (CROWN_Z0 + 5.0, CROWN_Z0 + 10.5, CROWN_Z1 - 0.8):
        ring_out = chamfered(h + 0.6, c)
        prism("Кольцо короны", ring_out, z, z + 0.8, mats["steel"], mats["steel"], crown, caps=False)
    prism("Свет короны", chamfered(h - 2.5, c - 1.0), CROWN_Z0, CROWN_Z0 + 0.4, mats["led"],
          mats["led"], crown)
    prism("Техэтаж", chamfered(h - 6.0, c - 2.0), CROWN_Z0, CROWN_Z0 + 8.0, mats["roof"],
          mats["roof"], crown)
    cyl("Шпиль", (0.0, 0.0, (CROWN_Z0 + 8.0 + SPIRE_Z1) / 2), 0.9, SPIRE_Z1 - CROWN_Z0 - 8.0, "Z",
        mats["steel"], crown, segments=24)
    cyl("Огонь шпиля", (0.0, 0.0, SPIRE_Z1 + 0.6), 0.5, 1.2, "Z", emissive("Огонь", (1.0, 0.15, 0.1), 60.0),
        crown, segments=16)


def build_podium(mats, colls):
    coll = colls["podium"]
    x0, x1, y0, y1, ph = PODIUM
    prism("Лобби", rect(x0 + 2.0, x1 - 2.0, y0 + 2.0, y1 - 2.0), 0.0, LOBBY_H, mats["lobby"],
          mats["roof"], coll)
    prism("Стилобат", rect(x0, x1, y0, y1), LOBBY_H, ph, mats["podium"], mats["roof"], coll)
    prism("Пояс стилобата", rect(x0 - 0.3, x1 + 0.3, y0 - 0.3, y1 + 0.3), ph - 0.6, ph, mats["led"],
          mats["roof"], coll)
    # козырёк входа
    box("Козырёк", (-14.0, y0 - 9.0, LOBBY_H - 0.9), (14.0, y0 + 2.0, LOBBY_H - 0.3), mats["steel"],
        coll, bevel=0.05)
    box("Свет козырька", (-13.5, y0 - 8.5, LOBBY_H - 0.95), (13.5, y0 + 1.5, LOBBY_H - 0.9),
        mats["led_warm"], coll, bevel=0.0)
    for x in (-12.0, 12.0):
        cyl("Опора козырька", (x, y0 - 8.0, (LOBBY_H - 0.9) / 2), 0.25, LOBBY_H - 0.9, "Z",
            mats["steel"], coll, segments=20)
    # название над входом
    curve = bpy.data.curves.new("Вывеска", type="FONT")
    curve.body = "NEST ONE"
    curve.size = 3.2
    curve.extrude = 0.15
    curve.align_x = "CENTER"
    ob = bpy.data.objects.new("Вывеска", curve)
    ob.location = (0.0, y0 - 0.4, LOBBY_H + 1.6)
    ob.rotation_euler = (math.radians(90), 0.0, 0.0)
    curve.materials.append(mats["sign"])
    coll.objects.link(ob)
    # зелёная кровля стилобата
    box("Сад на кровле", (x0 + 4.0, y0 + 4.0, ph), (x1 - 4.0, y1 - 4.0, ph + 0.4), mats["grass"], coll,
        bevel=0.0)


def build_plaza(mats, colls):
    coll = colls["plaza"]
    x0, x1, y0, y1 = PLAZA
    box("Площадь", (x0, y0, -0.3), (x1, y1, 0.0), mats["granite"], coll, bevel=0.0)
    box("Земля", (-2000.0, -2000.0, -0.6), (2000.0, 2000.0, -0.3), mats["asphalt"], coll, bevel=0.0)
    # проспект перед башней и разметка
    box("Проспект", (-2000.0, y0 - 40.0, -0.29), (2000.0, y0, -0.28), mats["asphalt"], coll, bevel=0.0)
    for k in range(-60, 60):
        box("Разметка", (k * 12.0, y0 - 20.4, -0.28), (k * 12.0 + 5.0, y0 - 19.6, -0.275),
            mats["sign"], coll, bevel=0.0)
    # газоны, деревья, фонари вдоль подхода
    rng = random.Random(5)
    for side in (-1, 1):
        box("Газон", (side * 20.0 - (0 if side > 0 else 30.0), y0 + 8.0, -0.05),
            (side * 20.0 + (30.0 if side > 0 else 0), PODIUM[2] - 14.0, 0.15), mats["grass"], coll,
            bevel=0.0)
        for i in range(6):
            x = side * (24.0 + (i % 3) * 9.0)
            y = y0 + 14.0 + (i // 3) * 30.0 + rng.uniform(-2, 2)
            tree(x, y, rng.uniform(7.0, 10.0), mats, coll)
        for i in range(8):
            y = y0 + 6.0 + i * 12.0
            lamp(side * 15.0, y, mats, coll)


def tree(x, y, h, mats, coll):
    cyl("Ствол дерева", (x, y, h * 0.3), 0.25, h * 0.6, "Z", mats["bark"], coll, segments=12)
    me = bpy.data.meshes.new("Крона")
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=h * 0.32)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Крона", me)
    ob.location = (x, y, h * 0.72)
    ob.scale = (1.0, 1.0, 1.15)
    me.materials.append(mats["foliage"])
    coll.objects.link(ob)


def lamp(x, y, mats, coll):
    cyl("Опора фонаря", (x, y, 2.5), 0.08, 5.0, "Z", mats["steel"], coll, segments=12)
    cyl("Фонарь", (x, y, 5.1), 0.28, 0.25, "Z", mats["led_warm"], coll, segments=20)


def build_city(mats, colls):
    coll = colls["city"]
    rng = random.Random(21)
    placed = 0
    for gx in range(-9, 10):
        for gy in range(-9, 10):
            cx, cy = gx * 70.0, gy * 70.0
            if -170 < cx < 170 and -230 < cy < 150:
                continue
            if rng.random() < 0.18:
                continue
            w, d = rng.uniform(24, 46), rng.uniform(24, 46)
            dist = math.hypot(cx, cy)
            h = rng.uniform(18, 60) * (1.0 + max(0.0, 1.0 - dist / 700.0))
            if rng.random() < 0.08:
                h = rng.uniform(90, 150)
            cx += rng.uniform(-8, 8)
            cy += rng.uniform(-8, 8)
            prism("Дом", rect(cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2), 0.0, h, mats["city"],
                  mats["roof"], coll)
            placed += 1
    return placed


# --------------------------------------------------------------------------
# Небо, свет, камеры
# --------------------------------------------------------------------------


def build_world():
    world = bpy.data.worlds.new("Сумерки")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.5
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -0.05
    rng.inputs["From Max"].default_value = 0.9
    ramp = _ramp(nt, [(0.0, (*srgb("#E8935A"), 1.0)), (1.0, (*srgb("#0E1A33"), 1.0)),
                      (0.12, (*srgb("#C77A6A"), 1.0)), (0.35, (*srgb("#4C4F7A"), 1.0))])
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = world


def build_lighting(colls):
    coll = colls["lights"]
    sun = bpy.data.lights.new("Закатное солнце", "SUN")
    sun.energy = 1.6
    sun.angle = math.radians(1.5)
    sun.color = (1.0, 0.62, 0.38)
    ob = bpy.data.objects.new("Закатное солнце", sun)
    ob.rotation_euler = (math.radians(83), 0.0, math.radians(-125))
    coll.objects.link(ob)
    # прожекторы подсветки ствола с площади
    for i, (x, y) in enumerate(((-28.0, -40.0), (28.0, -40.0), (-40.0, 36.0), (40.0, 36.0))):
        data = bpy.data.lights.new("Прожектор %d" % i, "SPOT")
        data.energy = 4.0e6
        data.spot_size = math.radians(9.0)
        data.spot_blend = 0.6
        data.color = (0.75, 0.88, 1.0)
        data.shadow_soft_size = 0.5
        spot = bpy.data.objects.new("Прожектор %d" % i, data)
        spot.location = (x, y, 26.0)
        spot.rotation_euler = (Vector((x * 0.25, y * 0.25, 230.0)) - Vector((x, y, 26.0))).to_track_quat(
            "-Z", "Y").to_euler()
        coll.objects.link(spot)
    build_world()


def build_cameras(colls):
    coll = colls["cameras"]
    specs = {
        "hero": ((-55.0, -190.0, 1.7), (0.0, 0.0, 120.0), 16),
        "aerial": ((300.0, -380.0, 190.0), (0.0, 0.0, 115.0), 32),
        "crown": ((95.0, -120.0, 245.0), (0.0, 0.0, 255.0), 45),
        "plaza": ((22.0, -110.0, 2.0), (0.0, -34.0, 12.0), 24),
    }
    cams = {}
    for name, (loc, target, lens) in specs.items():
        data = bpy.data.cameras.new("CAM_" + name)
        data.lens = lens
        data.clip_start = 0.1
        data.clip_end = 6000.0
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
        ("tower", "01 Башня"),
        ("crown", "02 Корона и шпиль"),
        ("podium", "03 Стилобат и лобби"),
        ("plaza", "04 Площадь и улица"),
        ("city", "05 Город"),
        ("lights", "06 Свет"),
        ("cameras", "07 Камеры"),
    )}
    build_tower(mats, colls)
    build_podium(mats, colls)
    build_plaza(mats, colls)
    houses = build_city(mats, colls)
    build_lighting(colls)
    print("Домов вокруг: %d" % houses)
    return build_cameras(colls)


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
                space.shading.studio_light = "sunset.exr"
                space.overlay.show_extras = False
                space.overlay.show_relationship_lines = False
                space.clip_start = 0.1
                space.clip_end = 6000.0
                space.lens = 30.0
                for region in area.regions:
                    if region.type == "WINDOW" and region.data is not None:
                        rv = region.data
                        rv.view_perspective = "PERSP"
                        rv.view_location = (0.0, 0.0, 110.0)
                        rv.view_rotation = Euler((math.radians(78), 0.0, math.radians(-30)), "XYZ").to_quaternion()
                        rv.view_distance = 420.0


def export_glb(path):
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception:
        pass
    for obj in bpy.data.objects:
        skip = obj.type in {"CAMERA", "LIGHT"} or obj.name.startswith(("Земля", "Проспект", "Разметка", "Дом"))
        obj.select_set(not skip)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    do_render = "--render" in argv
    do_glb = "--glb" in argv
    do_save = "--no-save" not in argv
    samples = 48
    res = (1280, 800)
    names = ["hero", "aerial", "crown", "plaza"]
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

    cams = build()
    setup_render(samples, res)
    bpy.context.scene.view_settings.exposure = 0.0
    setup_viewport()
    print("Объектов в сцене: %d" % len(bpy.data.objects))

    if do_save:
        path = os.path.join(out_3d, "nest-one.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print("Сохранено: %s" % path)
    if do_glb:
        export_glb(os.path.join(out_3d, "nest-one.glb"))
        print("Экспортировано: nest-one.glb")
    if do_render:
        scene = bpy.context.scene
        for name in names:
            scene.camera = cams[name]
            scene.render.filepath = os.path.join(out_img, "nest-one-" + name + ".png")
            print("Рендер %s -> %s" % (name, scene.render.filepath))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
