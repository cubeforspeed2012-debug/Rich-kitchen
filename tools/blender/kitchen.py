"""Rich Kitchen — параметрическая 3D-модель П-образной кухни для Blender.

Запуск:
    blender --background --python tools/blender/kitchen.py -- --render
    python tools/blender/kitchen.py --render          # если установлен пакет bpy

Ключи: --render (рендер камер), --glb (экспорт для сайта), --samples N, --res W H,
       --cameras overview,corner,sink,hob, --no-save

Все размеры в метрах, отсчёт от левого дальнего угла пола. Кухня стоит по трём
стенам: левая нога (x=0), задний фронт (y=ROOM_D), правая нога (x=ROOM_W).
Правьте блок «Габариты и раскладка» — модель пересобирается целиком.
"""

import math
import os
import random
import sys

import bpy  # noqa: I100 — bmesh регистрируется только после инициализации bpy
import bmesh
from mathutils import Vector

# --------------------------------------------------------------------------
# Габариты и раскладка
# --------------------------------------------------------------------------

ROOM_W, ROOM_D, ROOM_H = 3.60, 4.40, 2.70

BASE_D = 0.60          # глубина нижнего ряда вместе с фасадом
CARCASS_H = 0.72       # высота корпуса нижнего модуля
PLINTH_H = 0.10        # цоколь
COUNTER_T = 0.04       # толщина столешницы
COUNTER_OVERHANG = 0.02
TOE_RECESS = 0.06      # заглубление цоколя
FRONT_T = 0.018        # толщина фасада
GAP = 0.003            # зазор между фасадами

WALL_D = 0.35          # глубина верхних шкафов
WALL_BOTTOM = 1.50     # низ верхнего ряда
TALL_H = 2.10          # высота пеналов (холодильник, духовой шкаф)

COUNTER_Z1 = PLINTH_H + CARCASS_H + COUNTER_T   # 0.86 — рабочая поверхность
COUNTER_Z0 = COUNTER_Z1 - COUNTER_T

HANDLE_R = 0.008
HANDLE_OFFSET = 0.030  # вынос ручки от фасада

LEG_FRONT = 1.60                  # где ноги «П» начинаются
LEG_BACK = ROOM_D - BASE_D        # где ноги смыкаются с задним фронтом
WALL_LEG_BACK = ROOM_D - WALL_D   # то же для верхнего ряда

# Задний фронт, слева направо. Симметрично относительно мойки по центру окна.
BACK_RUN = [(0.60, "door_r"), (0.75, "drawers3"), (0.90, "sink"),
            (0.75, "drawers3"), (0.60, "door_l")]

# Левая нога: два пенала у входа, дальше нижний ряд до угла.
LEFT_TALL = [(0.60, "fridge"), (0.60, "oven")]
LEFT_BASE = [(0.50, "drawers2"), (0.50, "drawers2")]
LEFT_BASE_START = LEG_FRONT + sum(w for w, _ in LEFT_TALL)

# Правая нога: варочная панель по центру.
RIGHT_RUN = [(0.70, "drawers2"), (0.90, "hob"), (0.60, "door_r")]

WIN_X0, WIN_X1 = 1.20, 2.40       # окно над мойкой
WIN_Z0, WIN_Z1 = 1.20, 2.20
WALL_T = 0.12

SINK_W, SINK_DEPTH, SINK_BOWL = 0.76, 0.44, 0.19
HOB_W, HOB_DEPTH = 0.75, 0.52
HOOD_Z0, HOOD_Z1 = 1.55, 1.72     # низ и верх корпуса вытяжки

DOOR_X0, DOOR_X1 = 0.35, 1.25     # проём в передней стене
DOOR_Z1 = 2.10

# Палитра взята из css/main.css (двухцветная кухня: тёмно-синий низ, светлый верх).
PALETTE = {
    "front_lo": "#16304F",
    "front_hi": "#EDF1F6",
    "carcass": "#D3DAE3",
    "plinth": "#101D2E",
    "stone": "#EAE8E3",
    "stone_vein": "#BAC0CB",
    "oak": "#B0824F",
    "oak_dark": "#8E6339",
    "brass": "#B08D57",
    "steel": "#C8CCD0",
    "black_glass": "#0A0C0F",
    "wall": "#EEF1F5",
    "ceiling": "#FAFBFC",
}

# --------------------------------------------------------------------------
# Утилиты
# --------------------------------------------------------------------------


def srgb(hex_color):
    """HEX (sRGB) -> линейный RGB, который ждут сокеты Blender."""
    h = hex_color.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def reset_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for db in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
               bpy.data.lights, bpy.data.cameras, bpy.data.images):
        for item in list(db):
            db.remove(item)


def collection(name):
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll


def box(name, lo, hi, mat=None, coll=None, bevel=0.0015):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    if mat:
        me.materials.append(mat)
    (coll or bpy.context.scene.collection).objects.link(ob)
    if bevel:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(30)
    return ob


def slab(name, lo, hi, mat=None, coll=None, hole=None, axes=(0, 1), bevel=0.0015):
    """Плита с прямоугольным проёмом: разбивается на 4 куска, без булевых операций."""
    if hole is None:
        return [box(name, lo, hi, mat, coll, bevel)]
    a, b = axes
    a0, a1, b0, b1 = hole
    parts = []

    def piece(tag, la, ha, lb, hb):
        if ha - la <= 1e-6 or hb - lb <= 1e-6:
            return
        p_lo, p_hi = list(lo), list(hi)
        p_lo[a], p_hi[a] = la, ha
        p_lo[b], p_hi[b] = lb, hb
        parts.append(box("%s_%s" % (name, tag), p_lo, p_hi, mat, coll, bevel))

    piece("a", lo[a], a0, lo[b], hi[b])
    piece("b", a1, hi[a], lo[b], hi[b])
    piece("c", a0, a1, lo[b], b0)
    piece("d", a0, a1, b1, hi[b])
    return parts


def cyl(name, center, radius, depth, axis="Z", mat=None, coll=None, segments=32):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=depth)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = center
    if axis == "X":
        ob.rotation_euler = (0.0, math.radians(90), 0.0)
    elif axis == "Y":
        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
    if mat:
        me.materials.append(mat)
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def split_span(lo, hi, weights, gap=GAP):
    """Делит промежуток на фасады с зазорами по краям и между ними."""
    total = float(sum(weights))
    avail = (hi - lo) - gap * (len(weights) + 1)
    out = []
    cur = lo + gap
    for w in weights:
        size = avail * w / total
        out.append((cur, cur + size))
        cur += size + gap
    return out


class Run:
    """Ряд модулей у одной стены.

    u — координата вдоль ряда, d — глубина от плоскости фасада внутрь
    (отрицательная d выносит деталь наружу, для ручек).
    """

    def __init__(self, facing, wall, depth):
        self.facing = facing      # '-Y' задний фронт, '+X' левая нога, '-X' правая
        self.wall = wall
        self.depth = depth

    @property
    def front(self):
        return self.wall - self.depth if self.facing in ("-Y", "-X") else self.wall + self.depth

    @property
    def u_axis(self):
        return "X" if self.facing == "-Y" else "Y"

    @property
    def d_axis(self):
        return "Y" if self.facing == "-Y" else "X"

    def point(self, u, z, d):
        f = self.front
        if self.facing == "-Y":
            return (u, f + d, z)
        if self.facing == "+X":
            return (f - d, u, z)
        return (f + d, u, z)

    def bounds(self, u0, u1, z0, z1, d0, d1):
        f = self.front
        if self.facing == "-Y":
            return (u0, f + d0, z0), (u1, f + d1, z1)
        if self.facing == "+X":
            return (f - d1, u0, z0), (f - d0, u1, z1)
        return (f + d0, u0, z0), (f + d1, u1, z1)


# --------------------------------------------------------------------------
# Материалы
# --------------------------------------------------------------------------


def _set(bsdf, names, value):
    """Сокеты Principled переименовывались между версиями Blender."""
    for n in names:
        if n in bsdf.inputs:
            bsdf.inputs[n].default_value = value
            return True
    return False


def principled(name, color, roughness=0.5, metallic=0.0, transmission=0.0,
               coat=0.0, ior=1.45):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    _set(bsdf, ("Base Color",), (*color, 1.0))
    _set(bsdf, ("Roughness",), roughness)
    _set(bsdf, ("Metallic",), metallic)
    _set(bsdf, ("IOR",), ior)
    if transmission:
        _set(bsdf, ("Transmission Weight", "Transmission"), transmission)
    if coat:
        _set(bsdf, ("Coat Weight", "Clearcoat"), coat)
        _set(bsdf, ("Coat Roughness", "Clearcoat Roughness"), 0.08)
    return mat


def emissive(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def _coords(nt, scale, socket="Object"):
    """Текстурные координаты.

    «Object»: меши строятся в мировых координатах при нулевом origin, поэтому
    рисунок камня сходится на стыках отдельных деталей столешницы и фартука.
    «Generated»: нормируется по габаритам объекта — у каждой доски пола
    получается свой рисунок волокон.
    """
    tex = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    mapping.inputs["Scale"].default_value = scale
    nt.links.new(tex.outputs[socket], mapping.inputs["Vector"])
    return mapping


def stone_material(name, base, vein):
    """Светлый камень: основной тон с редкими мягкими прожилками."""
    mat = principled(name, base, roughness=0.16, coat=0.45)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 0.9)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.5
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.5
    if "Distortion" in noise.inputs:
        noise.inputs["Distortion"].default_value = 1.1
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.50
    ramp.color_ramp.elements[0].color = (*base, 1.0)
    ramp.color_ramp.elements[1].position = 0.63
    ramp.color_ramp.elements[1].color = (*vein, 1.0)
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def oak_material(name, light, dark):
    """Доска пола: волокна вдоль доски, координаты нормированы по объекту."""
    mat = principled(name, light, roughness=0.38, coat=0.2)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, (14.0, 1.0, 1.0), socket="Generated")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 1.0
    wave.inputs["Distortion"].default_value = 3.5
    wave.inputs["Detail"].default_value = 5.0
    wave.inputs["Detail Scale"].default_value = 1.4
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def sky_material(name, horizon, zenith):
    """Заоконный фон: вертикальный градиент от дымки к небу."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 0.9
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -0.5
    rng.inputs["From Max"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*horizon, 1.0)
    ramp.color_ramp.elements[1].color = (*zenith, 1.0)
    nt.links.new(tex.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def matte_front(name, color):
    """Матовый фасад: лёгкая неоднородность шероховатости вместо плоского пластика."""
    mat = principled(name, color, roughness=0.42)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 6.0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 18.0
    noise.inputs["Detail"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.38, 0.38, 0.38, 1.0)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (0.5, 0.5, 0.5, 1.0)
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def build_materials():
    p = {k: srgb(v) for k, v in PALETTE.items()}
    return {
        "front_lo": matte_front("Фасад тёмно-синий", p["front_lo"]),
        "front_hi": matte_front("Фасад светлый", p["front_hi"]),
        "carcass": principled("Корпус ЛДСП", p["carcass"], roughness=0.55),
        "plinth": principled("Цоколь", p["plinth"], roughness=0.5),
        "stone": stone_material("Столешница камень", p["stone"], p["stone_vein"]),
        "oak": [oak_material("Пол дуб %d" % (i + 1), tuple(c * k for c in p["oak"]),
                             tuple(c * k for c in p["oak_dark"]))
                for i, k in enumerate((1.0, 0.82, 1.22))],
        "brass": principled("Латунь брашированная", p["brass"], roughness=0.28, metallic=1.0),
        "steel": principled("Нержавеющая сталь", p["steel"], roughness=0.22, metallic=1.0),
        "steel_matt": principled("Сталь мойки", p["steel"], roughness=0.34, metallic=1.0),
        "sky": sky_material("Вид из окна", srgb("#E6DFD2"), srgb("#7FA6D4")),
        "black_glass": principled("Стекло чёрное", p["black_glass"], roughness=0.19, coat=0.3),
        "glass": principled("Стекло окна", (0.95, 0.97, 1.0), roughness=0.0,
                            transmission=1.0, ior=1.52),
        "wall": principled("Стены", p["wall"], roughness=0.75),
        "ceiling": principled("Потолок", p["ceiling"], roughness=0.85),
        "led": emissive("Подсветка LED", (1.0, 0.86, 0.68), 2.5),
    }


# --------------------------------------------------------------------------
# Фурнитура
# --------------------------------------------------------------------------


def handle(run, u_c, z_c, length, orient, mats, coll):
    bar_axis = run.u_axis if orient == "H" else "Z"
    cyl("Ручка", run.point(u_c, z_c, -HANDLE_OFFSET), HANDLE_R, length,
        bar_axis, mats["brass"], coll, segments=20)
    off = max(length / 2 - 0.035, 0.012)
    for s in (-1, 1):
        if orient == "H":
            centre = run.point(u_c + s * off, z_c, -HANDLE_OFFSET / 2)
        else:
            centre = run.point(u_c, z_c + s * off, -HANDLE_OFFSET / 2)
        cyl("Стойка ручки", centre, 0.005, HANDLE_OFFSET, run.d_axis,
            mats["brass"], coll, segments=14)


def fronts_doors(run, u0, u1, z0, z1, count, mats, coll, mat_key="front_lo",
                 hinge="l", handle_len=0.26):
    """Одна или две створки с вертикальными ручками у линии открывания."""
    spans = split_span(u0, u1, [1.0] * count)
    for i, (a, b) in enumerate(spans):
        box("Фасад", *run.bounds(a, b, z0 + GAP, z1 - GAP, 0.0, FRONT_T),
            mats[mat_key], coll)
        if count == 2:
            # ручки к центральному шву: створки открываются от середины
            edge = b - 0.05 if i == 0 else a + 0.05
        else:
            edge = b - 0.05 if hinge == "l" else a + 0.05
        handle(run, edge, (z0 + z1) / 2, handle_len, "V", mats, coll)


def fronts_drawers(run, u0, u1, z0, z1, weights, mats, coll, mat_key="front_lo"):
    for (a, b) in split_span(z0, z1, weights):
        box("Фасад ящика", *run.bounds(u0 + GAP, u1 - GAP, a, b, 0.0, FRONT_T),
            mats[mat_key], coll)
        length = min(0.42, (u1 - u0) * 0.55)
        handle(run, (u0 + u1) / 2, (a + b) / 2, length, "H", mats, coll)


# --------------------------------------------------------------------------
# Модули
# --------------------------------------------------------------------------


def base_module(run, u0, u1, kind, mats, colls):
    coll = colls["base"]
    box("Цоколь", *run.bounds(u0, u1, 0.0, PLINTH_H, TOE_RECESS, BASE_D),
        mats["plinth"], coll)
    z0, z1 = PLINTH_H, PLINTH_H + CARCASS_H
    box("Корпус", *run.bounds(u0, u1, z0, z1, FRONT_T, BASE_D),
        mats["carcass"], coll)

    if kind in ("door_l", "door_r"):
        fronts_doors(run, u0, u1, z0, z1, 1, mats, coll,
                     hinge="l" if kind == "door_l" else "r")
    elif kind == "sink":
        fronts_doors(run, u0, u1, z0, z1, 2, mats, coll)
    elif kind == "drawers2":
        fronts_drawers(run, u0, u1, z0, z1, (1.0, 1.55), mats, coll)
    elif kind == "drawers3":
        fronts_drawers(run, u0, u1, z0, z1, (0.62, 1.0, 1.0), mats, coll)
    elif kind == "hob":
        # под варочной панелью — неглубокий ящик и два обычных
        fronts_drawers(run, u0, u1, z0, z1, (0.5, 1.0, 1.0), mats, coll)


def wall_module(run, u0, u1, mats, colls):
    coll = colls["wall"]
    box("Корпус верхний", *run.bounds(u0, u1, WALL_BOTTOM, ROOM_H, FRONT_T, WALL_D),
        mats["carcass"], coll)
    lower, upper = split_span(WALL_BOTTOM, ROOM_H, (2.45, 1.0))
    for (a, b) in (lower, upper):
        count = 2 if (u1 - u0) > 0.68 else 1
        for (c, d) in split_span(u0, u1, [1.0] * count):
            box("Фасад верхний", *run.bounds(c, d, a, b, 0.0, FRONT_T),
                mats["front_hi"], coll)
        # ручка-рейлинг по нижней кромке — линия без разрывов по всему ряду
        handle(run, (u0 + u1) / 2, a + 0.045, min(0.5, (u1 - u0) * 0.6),
               "H", mats, coll)
    # подсветка рабочей зоны
    box("Подсветка", *run.bounds(u0 + 0.04, u1 - 0.04, WALL_BOTTOM - 0.012,
                                 WALL_BOTTOM - 0.004, 0.06, WALL_D - 0.04),
        mats["led"], coll, bevel=0.0)


def tall_module(run, u0, u1, kind, mats, colls):
    coll = colls["tall"]
    box("Цоколь пенала", *run.bounds(u0, u1, 0.0, PLINTH_H, TOE_RECESS, BASE_D),
        mats["plinth"], coll)
    box("Корпус пенала", *run.bounds(u0, u1, PLINTH_H, TALL_H, FRONT_T, BASE_D),
        mats["carcass"], coll)

    if kind == "fridge":
        # встроенный холодильник: две распашные створки в одной линии с кухней
        for (a, b) in split_span(PLINTH_H, TALL_H, (2.1, 1.0)):
            box("Фасад холодильника",
                *run.bounds(u0 + GAP, u1 - GAP, a, b, 0.0, FRONT_T),
                mats["front_lo"], coll)
            handle(run, u1 - 0.05, (a + b) / 2, min(0.5, (b - a) * 0.55),
                   "V", mats, coll)
    else:
        # башня: ящик, духовой шкаф, компактный шкаф, верхняя створка
        drawer, oven, micro, door = split_span(PLINTH_H, TALL_H, (0.9, 1.2, 0.9, 1.0))
        box("Фасад ящика", *run.bounds(u0 + GAP, u1 - GAP, *drawer, 0.0, FRONT_T),
            mats["front_lo"], coll)
        handle(run, (u0 + u1) / 2, sum(drawer) / 2, 0.4, "H", mats, coll)
        for span in (oven, micro):
            box("Корпус техники", *run.bounds(u0 + GAP, u1 - GAP, *span, 0.0, 0.012),
                mats["steel"], coll)
            box("Стекло техники",
                *run.bounds(u0 + 0.035, u1 - 0.035, span[0] + 0.055, span[1] - 0.09,
                            -0.006, 0.0),
                mats["black_glass"], coll)
            cyl("Ручка техники", run.point((u0 + u1) / 2, span[1] - 0.05, -0.035),
                0.009, (u1 - u0) - 0.11, run.u_axis, mats["steel"], coll, segments=20)
        box("Фасад пенала", *run.bounds(u0 + GAP, u1 - GAP, *door, 0.0, FRONT_T),
            mats["front_lo"], coll)
        handle(run, u1 - 0.05, sum(door) / 2, 0.26, "V", mats, coll)


def tall_top_box(run, u0, u1, mats, colls):
    coll = colls["tall"]
    box("Корпус антресоли", *run.bounds(u0, u1, TALL_H, ROOM_H, FRONT_T, BASE_D),
        mats["carcass"], coll)
    box("Фасад антресоли", *run.bounds(u0 + GAP, u1 - GAP, TALL_H + GAP,
                                       ROOM_H - GAP, 0.0, FRONT_T),
        mats["front_hi"], coll)
    handle(run, (u0 + u1) / 2, TALL_H + 0.05, min(0.5, (u1 - u0) * 0.6),
           "H", mats, coll)


# --------------------------------------------------------------------------
# Столешницы, фартук, техника
# --------------------------------------------------------------------------


def module_spans(items, start):
    """[(ширина, тип)] -> [(u0, u1, тип)]"""
    out = []
    cur = start
    for width, kind in items:
        out.append((cur, cur + width, kind))
        cur += width
    return out


def find_span(spans, kind):
    for u0, u1, k in spans:
        if k == kind:
            return u0, u1
    return None


def build_counters(mats, colls, sink_hole):
    coll = colls["counter"]
    front_y = ROOM_D - BASE_D - COUNTER_OVERHANG
    front_x_l = BASE_D + COUNTER_OVERHANG
    front_x_r = ROOM_W - BASE_D - COUNTER_OVERHANG

    # задний фронт — с вырезом под мойку
    slab("Столешница задняя", (0.0, front_y, COUNTER_Z0),
         (ROOM_W, ROOM_D, COUNTER_Z1), mats["stone"], coll,
         hole=sink_hole, axes=(0, 1))
    # ноги «П» стыкуются в торец с задней столешницей
    box("Столешница левая", (0.0, LEFT_BASE_START, COUNTER_Z0),
        (front_x_l, front_y, COUNTER_Z1), mats["stone"], coll)
    box("Столешница правая", (front_x_r, LEG_FRONT, COUNTER_Z0),
        (ROOM_W, front_y, COUNTER_Z1), mats["stone"], coll)


def build_backsplash(mats, colls):
    coll = colls["counter"]
    t = 0.012
    # задняя стена: до окна на полную высоту, под окном — до подоконника
    for x0, x1 in ((0.0, WIN_X0), (WIN_X1, ROOM_W)):
        box("Фартук", (x0, ROOM_D - t, COUNTER_Z1), (x1, ROOM_D, WALL_BOTTOM),
            mats["stone"], coll)
    box("Фартук под окном", (WIN_X0, ROOM_D - t, COUNTER_Z1),
        (WIN_X1, ROOM_D, WIN_Z0), mats["stone"], coll)
    # левая нога
    box("Фартук левый", (0.0, LEFT_BASE_START, COUNTER_Z1),
        (t, ROOM_D - BASE_D, WALL_BOTTOM), mats["stone"], coll)
    # правая нога: за варочной панелью фартук поднят до вытяжки
    hob0, hob1 = find_span(module_spans(RIGHT_RUN, LEG_FRONT), "hob")
    for y0, y1, top in ((LEG_FRONT, hob0, WALL_BOTTOM),
                        (hob0, hob1, HOOD_Z0),
                        (hob1, ROOM_D - BASE_D, WALL_BOTTOM)):
        box("Фартук правый", (ROOM_W - t, y0, COUNTER_Z1),
            (ROOM_W, y1, top), mats["stone"], coll)


def build_sink(mats, colls, hole):
    coll = colls["appliances"]
    x0, x1, y0, y1 = hole
    t = 0.008
    bottom = COUNTER_Z1 - SINK_BOWL
    steel = mats["steel_matt"]
    box("Дно мойки", (x0, y0, bottom - t), (x1, y1, bottom), steel, coll)
    box("Стенка мойки", (x0, y0, bottom), (x0 + t, y1, COUNTER_Z0), steel, coll)
    box("Стенка мойки", (x1 - t, y0, bottom), (x1, y1, COUNTER_Z0), steel, coll)
    box("Стенка мойки", (x0 + t, y0, bottom), (x1 - t, y0 + t, COUNTER_Z0), steel, coll)
    box("Стенка мойки", (x0 + t, y1 - t, bottom), (x1 - t, y1, COUNTER_Z0), steel, coll)
    cyl("Слив", ((x0 + x1) / 2, (y0 + y1) / 2, bottom + 0.004), 0.045, 0.008,
        "Z", steel, coll)

    # смеситель-гусак кривой Безье с обводкой — правится в Blender как обычная кривая
    cx = (x0 + x1) / 2
    base_y = y1 + 0.055
    curve = bpy.data.curves.new("Смеситель", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.014
    curve.bevel_resolution = 6
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    # стойка, дуга гусака и излив над центром чаши
    points = [(cx, base_y, COUNTER_Z1), (cx, base_y, COUNTER_Z1 + 0.22),
              (cx, base_y - 0.04, COUNTER_Z1 + 0.34),
              (cx, base_y - 0.16, COUNTER_Z1 + 0.36),
              (cx, (y0 + y1) / 2, COUNTER_Z1 + 0.25)]
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("Смеситель", curve)
    curve.materials.append(mats["steel"])
    coll.objects.link(ob)
    cyl("Основание смесителя", (cx, base_y, COUNTER_Z1 + 0.01), 0.028, 0.02,
        "Z", mats["steel"], coll)


def build_hob_and_hood(mats, colls):
    coll = colls["appliances"]
    hob0, hob1 = find_span(module_spans(RIGHT_RUN, LEG_FRONT), "hob")
    cy = (hob0 + hob1) / 2
    counter_x0 = ROOM_W - BASE_D - COUNTER_OVERHANG
    cx = (counter_x0 + ROOM_W) / 2
    box("Варочная панель", (cx - HOB_DEPTH / 2, cy - HOB_W / 2, COUNTER_Z1),
        (cx + HOB_DEPTH / 2, cy + HOB_W / 2, COUNTER_Z1 + 0.008),
        mats["black_glass"], coll, bevel=0.001)
    for dx in (-0.13, 0.13):
        for dy in (-0.205, 0.205):
            cyl("Зона нагрева", (cx + dx, cy + dy, COUNTER_Z1 + 0.0085),
                0.085, 0.001, "Z", mats["steel"], coll)

    box("Корпус вытяжки", (ROOM_W - 0.52, hob0, HOOD_Z0), (ROOM_W, hob1, HOOD_Z1),
        mats["steel"], coll)
    box("Воздуховод", (ROOM_W - 0.30, cy - 0.16, HOOD_Z1), (ROOM_W, cy + 0.16, ROOM_H),
        mats["steel"], coll)
    box("Подсветка вытяжки", (ROOM_W - 0.48, hob0 + 0.06, HOOD_Z0 - 0.006),
        (ROOM_W - 0.06, hob1 - 0.06, HOOD_Z0), mats["led"], coll, bevel=0.0)


def build_floor(mats, coll):
    """Дубовая палубная доска: отдельные планки со смещёнными стыками."""
    rng = random.Random(11)
    x0, x1 = -WALL_T, ROOM_W + WALL_T
    y0, y1 = -WALL_T, ROOM_D
    count = max(1, int(round((x1 - x0) / 0.19)))
    width = (x1 - x0) / count
    for i in range(count):
        px0 = x0 + i * width
        cur = y0 - rng.uniform(0.0, 1.4)     # смещение стыков между рядами
        while cur < y1:
            end = min(cur + rng.uniform(1.1, 2.1), y1)
            if end > y0:
                box("Доска пола", (px0, max(cur, y0), -0.02), (px0 + width, end, 0.0),
                    mats["oak"][(i * 5 + int(cur * 3)) % len(mats["oak"])],
                    coll, bevel=0.003)
            cur = end


def build_room(mats, colls):
    coll = colls["room"]
    build_floor(mats, coll)
    box("Потолок", (-WALL_T, -WALL_T, ROOM_H), (ROOM_W + WALL_T, ROOM_D, ROOM_H + WALL_T),
        mats["ceiling"], coll)
    slab("Стена задняя", (-WALL_T, ROOM_D, 0.0), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H),
         mats["wall"], coll, hole=(WIN_X0, WIN_X1, WIN_Z0, WIN_Z1), axes=(0, 2))
    box("Стена левая", (-WALL_T, -WALL_T, 0.0), (0.0, ROOM_D, ROOM_H), mats["wall"], coll)
    box("Стена правая", (ROOM_W, -WALL_T, 0.0), (ROOM_W + WALL_T, ROOM_D, ROOM_H),
        mats["wall"], coll)
    slab("Стена передняя", (-WALL_T, -WALL_T, 0.0), (ROOM_W + WALL_T, 0.0, ROOM_H),
         mats["wall"], coll, hole=(DOOR_X0, DOOR_X1, 0.0, DOOR_Z1), axes=(0, 2))

    # окно: рама, стекло, подоконник
    f, fd0, fd1 = 0.055, ROOM_D + 0.02, ROOM_D + 0.08
    for lo, hi in (((WIN_X0, WIN_Z0), (WIN_X0 + f, WIN_Z1)),
                   ((WIN_X1 - f, WIN_Z0), (WIN_X1, WIN_Z1)),
                   ((WIN_X0 + f, WIN_Z0), (WIN_X1 - f, WIN_Z0 + f)),
                   ((WIN_X0 + f, WIN_Z1 - f), (WIN_X1 - f, WIN_Z1))):
        box("Рама окна", (lo[0], fd0, lo[1]), (hi[0], fd1, hi[1]), mats["wall"], coll)
    box("Импост", (WIN_X0 + f, fd0, (WIN_Z0 + WIN_Z1) / 2 - 0.022),
        (WIN_X1 - f, fd1, (WIN_Z0 + WIN_Z1) / 2 + 0.022), mats["wall"], coll)
    box("Стекло", (WIN_X0 + f, ROOM_D + 0.046, WIN_Z0 + f),
        (WIN_X1 - f, ROOM_D + 0.054, WIN_Z1 - f), mats["glass"], coll, bevel=0.0)
    box("Подоконник", (WIN_X0 - 0.06, ROOM_D - 0.10, WIN_Z0 - 0.035),
        (WIN_X1 + 0.06, ROOM_D + 0.02, WIN_Z0), mats["stone"], coll)
    # то, что видно в окно: градиент от дымки к небу вместо пустоты
    box("Фон за окном", (-9.0, ROOM_D + 7.0, -3.0), (13.0, ROOM_D + 7.1, 9.0),
        mats["sky"], coll, bevel=0.0)


def build_lighting(colls):
    coll = colls["lights"]

    def area(name, loc, rot, size_x, size_y, power, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "RECTANGLE"
        data.size, data.size_y = size_x, size_y
        data.energy = power
        data.color = color
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        ob.rotation_euler = rot
        ob.visible_camera = False   # источник не должен попадать в кадр как белый прямоугольник
        coll.objects.link(ob)

    # дневной свет через окно
    area("Свет из окна", ((WIN_X0 + WIN_X1) / 2, ROOM_D + 0.55, 1.70),
         (math.radians(90), 0.0, 0.0), 1.45, 1.15, 320.0, (0.82, 0.90, 1.0))
    sun = bpy.data.lights.new("Солнце", "SUN")
    sun.energy = 1.5
    sun.angle = math.radians(2.5)
    sun.color = (1.0, 0.95, 0.86)
    sun_ob = bpy.data.objects.new("Солнце", sun)
    sun_ob.rotation_euler = (math.radians(58), 0.0, math.radians(196))
    coll.objects.link(sun_ob)
    # общий свет помещения
    for i, x in enumerate((0.95, 2.65)):
        area("Свет потолочный %d" % (i + 1), (x, 2.55, ROOM_H - 0.06),
             (math.radians(180), 0.0, 0.0), 1.1, 1.1, 45.0, (1.0, 0.94, 0.86))
    # видимые в кадре точечные светильники
    for x in (0.85, 2.75):
        for y in (0.80, 1.55):
            cyl("Светильник", (x, y, ROOM_H - 0.006), 0.05, 0.012, "Z",
                bpy.data.materials["Подсветка LED"], coll, segments=20)

    world = bpy.data.worlds.new("Окружение")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.53, 0.7, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    bpy.context.scene.world = world


def build_cameras(colls):
    coll = colls["cameras"]
    specs = {
        # фронтальная камера строго горизонтальна: нет заваленных вертикалей
        "overview": ((1.80, 0.30, 1.45), (1.80, 4.30, 1.32), 24),
        "corner": ((3.00, 0.70, 1.62), (0.50, 4.10, 1.15), 28),
        "sink": ((1.80, 1.95, 1.38), (1.80, 4.40, 1.05), 35),
        "hob": ((1.30, 2.75, 1.35), (3.60, 2.78, 1.20), 38),
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
    bpy.context.scene.camera = cams["overview"]
    return cams


# --------------------------------------------------------------------------
# Сборка
# --------------------------------------------------------------------------


def build():
    reset_scene()
    mats = build_materials()
    colls = {key: collection(title) for key, title in (
        ("room", "01 Помещение"),
        ("base", "02 Нижние модули"),
        ("counter", "03 Столешница и фартук"),
        ("wall", "04 Верхние модули"),
        ("tall", "05 Пеналы"),
        ("appliances", "06 Техника и мойка"),
        ("lights", "07 Свет"),
        ("cameras", "08 Камеры"),
    )}

    back = Run("-Y", ROOM_D, BASE_D)
    left = Run("+X", 0.0, BASE_D)
    right = Run("-X", ROOM_W, BASE_D)
    back_w = Run("-Y", ROOM_D, WALL_D)
    left_w = Run("+X", 0.0, WALL_D)
    right_w = Run("-X", ROOM_W, WALL_D)

    back_spans = module_spans(BACK_RUN, 0.0)
    for u0, u1, kind in back_spans:
        base_module(back, u0, u1, kind, mats, colls)

    for u0, u1, kind in module_spans(LEFT_TALL, LEG_FRONT):
        tall_module(left, u0, u1, kind, mats, colls)
        tall_top_box(left, u0, u1, mats, colls)
    for u0, u1, kind in module_spans(LEFT_BASE, LEFT_BASE_START):
        base_module(left, u0, u1, kind, mats, colls)

    right_spans = module_spans(RIGHT_RUN, LEG_FRONT)
    for u0, u1, kind in right_spans:
        base_module(right, u0, u1, kind, mats, colls)

    # верхний ряд: задняя стена по обе стороны окна
    for x0, x1 in ((0.0, WIN_X0), (WIN_X1, ROOM_W)):
        for a, b in split_span(x0, x1, [1.0, 1.0], gap=0.0):
            wall_module(back_w, a, b, mats, colls)
    # левая нога — над нижним рядом, до угла с задним фронтом
    for a, b in split_span(LEFT_BASE_START, WALL_LEG_BACK, [1.0, 1.0], gap=0.0):
        wall_module(left_w, a, b, mats, colls)
    # правая нога — по обе стороны вытяжки
    hob0, hob1 = find_span(right_spans, "hob")
    wall_module(right_w, LEG_FRONT, hob0, mats, colls)
    wall_module(right_w, hob1, WALL_LEG_BACK, mats, colls)

    sink0, sink1 = find_span(back_spans, "sink")
    scx = (sink0 + sink1) / 2
    counter_back_y0 = ROOM_D - BASE_D - COUNTER_OVERHANG
    sink_y0 = counter_back_y0 + 0.07
    sink_hole = (scx - SINK_W / 2, scx + SINK_W / 2, sink_y0, sink_y0 + SINK_DEPTH)

    build_counters(mats, colls, sink_hole)
    build_backsplash(mats, colls)
    build_sink(mats, colls, sink_hole)
    build_hob_and_hood(mats, colls)
    build_room(mats, colls)
    build_lighting(colls)
    return build_cameras(colls)


def setup_render(samples, res):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.012
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 8
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.exposure = -0.3
    for look in ("AgX - Punchy", "Punchy", "None"):
        try:
            scene.view_settings.look = look
            break
        except TypeError:
            continue


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    do_render = "--render" in argv
    do_glb = "--glb" in argv
    do_save = "--no-save" not in argv
    samples = 96
    res = (1600, 1000)
    names = ["overview", "corner", "sink"]
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
    print("Объектов в сцене: %d" % len(bpy.data.objects))

    if do_save:
        path = os.path.join(out_3d, "rich-kitchen.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print("Сохранено: %s" % path)

    if do_glb:
        try:
            bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
        except Exception:
            pass
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(out_3d, "rich-kitchen.glb"),
            export_format="GLB", export_cameras=False, export_lights=False,
            export_apply=True)
        print("Экспортировано: rich-kitchen.glb")

    if do_render:
        scene = bpy.context.scene
        for name in names:
            scene.camera = cams[name]
            scene.render.filepath = os.path.join(out_img, name + ".png")
            print("Рендер %s -> %s" % (name, scene.render.filepath))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
