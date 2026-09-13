"""Кухня хай-тек с островом — процедурная модель для Blender.

Запуск:  blender --background --python tools/blender/kitchen_hitech.py -- [ключи]
         python tools/blender/kitchen_hitech.py [ключи]       (при установленном bpy)
Ключи:   --render, --glb, --samples N, --res W H, --cameras a,b,c, --no-save

Планировка 6.0 × 5.6 м, вход с торца. Вдоль дальней стены — сплошной ряд пеналов
до потолка со встроенной техникой и подсвеченной нишей; слева — рабочая линия
с мойкой; справа — панорамное остекление; в центре — остров с варочной панелью,
водопадной столешницей и барной стойкой. Фасады без ручек: гола-профили.
"""
import math
import os
import random
import sys

import bpy
import bmesh  # noqa: F401  (регистрируется после bpy)
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen import (  # noqa: E402
    box, collection, cyl, emissive, matte_front, principled, reset_scene,
    setup_render, sky_material, slab, split_span, srgb, stone_material, _coords,
)

# --------------------------------------------------------------------------
# Габариты и раскладка
# --------------------------------------------------------------------------

ROOM_W, ROOM_D, ROOM_H = 6.0, 5.6, 2.9
WALL_T = 0.15

BASE_D = 0.62
PLINTH_H = 0.12
TOE_RECESS = 0.08
CARCASS_TOP = 0.88
COUNTER_T = 0.02            # тонкий керамогранит
COUNTER_Z1 = CARCASS_TOP + COUNTER_T
COUNTER_OVERHANG = 0.03
FRONT_T = 0.02
GAP = 0.004
GOLA_H = 0.035              # высота паза под пальцы
GOLA_D = 0.03               # его глубина
CARCASS_D0 = GOLA_D + 0.012 # корпус начинается за профилем

TALL_D = 0.62
TALL_SPLIT = 2.30           # граница пенала и антресоли
WALL_D = 0.35
WALL_Z0, WALL_Z1 = 1.45, 2.25

# Левая линия вдоль стены x=0: от входа к пеналам.
LEFT_START = 0.90
LEFT_END = ROOM_D - TALL_D
LEFT_RUN = [(1.00, "drawers3"), (1.00, "sink"), (1.08, "drawers3"), (1.00, "drawers2")]

# Дальняя стена: пеналы от угла до угла.
TALL_RUN = [(0.90, "pantry"), (0.75, "fridge"), (0.75, "fridge"), (1.50, "niche"),
            (0.60, "oven"), (0.60, "coffee"), (0.90, "pantry")]
NICHE_TOP = 1.55

# Остров.
ISL_X0, ISL_X1 = 1.90, 4.90
ISL_Y0, ISL_Y1 = 2.55, 3.55
ISL_OVER = 0.35             # вынос столешницы под барные стулья
ISL_BACK = [(1.0, "drawers2")] * 3
HOB_W, HOB_D = 0.90, 0.52
HOB_CX, HOB_CY = 3.40, ISL_Y0 + 0.62
STOOL_XS = (2.50, 3.40, 4.30)

SINK_W, SINK_D, SINK_BOWL = 0.80, 0.42, 0.20

# Остекление правой стены и проём входа.
GLAZE_Y0, GLAZE_Y1 = 0.80, 5.20
GLAZE_Z0, GLAZE_Z1 = 0.12, 2.78
DOOR_X0, DOOR_X1, DOOR_Z1 = 3.80, 5.60, 2.40

# Опущенный потолок над островом.
DROP_X0, DROP_X1, DROP_Y0, DROP_Y1 = 1.60, 5.20, 2.20, 3.90
DROP_Z0 = 2.75
PENDANT_Y = 2.72

PALETTE = {
    "graphite": "#31353A",
    "white_gloss": "#F4F5F7",
    "carcass": "#34373C",
    "plinth": "#121417",
    "porcelain": "#F1EFEA",
    "porcelain_vein": "#A3A8AF",
    "black_glass": "#050608",
    "anod": "#1A1C1F",
    "steel": "#8C9196",
    "floor": "#B4B2AD",
    "floor_dark": "#8F8D88",
    "wall": "#8E9196",
    "wall_dark": "#7C7F84",
    "ceiling": "#F3F4F5",
    "leather": "#1E1F22",
    "walnut": "#4A3626",
    "skyline": "#182238",
}


# --------------------------------------------------------------------------
# Утилиты
# --------------------------------------------------------------------------


class Face:
    """Плоскость фасадов у стены или у острова.

    u — координата вдоль ряда, d — глубина от плоскости фасада внутрь.
    """

    def __init__(self, facing, wall, depth):
        self.facing, self.wall, self.depth = facing, wall, depth

    @property
    def front(self):
        return self.wall - self.depth if self.facing in ("-Y", "-X") else self.wall + self.depth

    @property
    def u_axis(self):
        return "X" if self.facing in ("-Y", "+Y") else "Y"

    def point(self, u, z, d):
        f = self.front
        return {"-Y": (u, f + d, z), "+Y": (u, f - d, z),
                "+X": (f - d, u, z), "-X": (f + d, u, z)}[self.facing]

    def bounds(self, u0, u1, z0, z1, d0, d1):
        f = self.front
        if self.facing == "-Y":
            return (u0, f + d0, z0), (u1, f + d1, z1)
        if self.facing == "+Y":
            return (u0, f - d1, z0), (u1, f - d0, z1)
        if self.facing == "+X":
            return (f - d1, u0, z0), (f - d0, u1, z1)
        return (f + d0, u0, z0), (f + d1, u1, z1)


def module_spans(items, start):
    out, cur = [], start
    for width, kind in items:
        out.append((cur, cur + width, kind))
        cur += width
    return out


def find_span(spans, kind):
    for u0, u1, k in spans:
        if k == kind:
            return u0, u1
    return None


# --------------------------------------------------------------------------
# Материалы
# --------------------------------------------------------------------------


def concrete_material(name, light, dark, roughness, coat=0.0, scale=2.0):
    mat = principled(name, light, roughness=roughness, coat=coat)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, scale)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.62
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.36
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.66
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def dusk_material(name):
    """Закат: тёплый горизонт через сиреневую дымку в тёмно-синий зенит, на уровне глаз."""
    mat = sky_material(name, srgb("#E4A87C"), srgb("#1B2946"))
    nt = mat.node_tree
    rng = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -1.5
    rng.inputs["From Max"].default_value = 5.5
    ramp = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeValToRGB")
    mid = ramp.color_ramp.elements.new(0.42)
    mid.color = (*srgb("#8C7A94"), 1.0)
    return mat


def build_materials():
    p = {k: srgb(v) for k, v in PALETTE.items()}
    return {
        "graphite": matte_front("Фасад графит", p["graphite"]),
        "white_gloss": principled("Фасад белый глянец", p["white_gloss"],
                                  roughness=0.07, coat=0.8),
        "carcass": principled("Корпус", p["carcass"], roughness=0.6),
        "plinth": principled("Цоколь", p["plinth"], roughness=0.5),
        "porcelain": stone_material("Керамогранит калакатта", p["porcelain"],
                                    p["porcelain_vein"]),
        "black_glass": principled("Стекло чёрное", p["black_glass"], roughness=0.04, coat=0.4),
        "anod": principled("Алюминий чёрный анодированный", p["anod"],
                           roughness=0.35, metallic=1.0),
        "steel": principled("Сталь тёмная брашированная", p["steel"],
                            roughness=0.3, metallic=1.0),
        "composite": principled("Композит мойки", p["anod"], roughness=0.5),
        "floor": [concrete_material("Керамогранит пол %d" % (i + 1),
                                    tuple(c * k for c in p["floor"]),
                                    tuple(c * k for c in p["floor_dark"]),
                                    roughness=0.28, coat=0.2, scale=1.4)
                  for i, k in enumerate((1.0, 0.93, 1.06))],
        "wall": concrete_material("Микроцемент", p["wall"], p["wall_dark"],
                                  roughness=0.82, scale=1.0),
        "ceiling": principled("Потолок", p["ceiling"], roughness=0.85),
        "leather": principled("Кожа", p["leather"], roughness=0.45),
        "walnut": principled("Орех", p["walnut"], roughness=0.4, coat=0.15),
        "glass": principled("Стекло остекления", (0.93, 0.96, 1.0), roughness=0.0,
                            transmission=1.0, ior=1.52),
        "sky": dusk_material("Закат за окном"),
        "skyline": principled("Силуэт города", p["skyline"], roughness=0.9),
        "led": emissive("LED холодный", (0.84, 0.91, 1.0), 3.5),
        "led_warm": emissive("LED тёплый", (1.0, 0.84, 0.64), 8.0),
        "ring": principled("Разметка панели", (0.55, 0.57, 0.6), roughness=0.4, metallic=0.5),
    }


# --------------------------------------------------------------------------
# Фасады без ручек
# --------------------------------------------------------------------------


def gola(face, u0, u1, z, mats, coll):
    """Паз под пальцы над кромкой фасада: тёмный профиль в глубине."""
    box("Гола-профиль", *face.bounds(u0 + GAP, u1 - GAP, z - GOLA_H, z, GOLA_D, GOLA_D + 0.012),
        mats["anod"], coll, bevel=0.0)


def front(face, u0, u1, z0, z1, mats, coll, mat_key="graphite", name="Фасад"):
    box(name, *face.bounds(u0 + GAP, u1 - GAP, z0 + GAP, z1 - GAP, 0.0, FRONT_T),
        mats[mat_key], coll)


def drawer_stack(face, u0, u1, z0, z1, weights, mats, coll):
    for a, b in split_span(z0, z1, weights, gap=0.0):
        front(face, u0, u1, a, b - GOLA_H, mats, coll, name="Фасад ящика")
        gola(face, u0, u1, b, mats, coll)


def door_pair(face, u0, u1, z0, z1, mats, coll):
    for a, b in split_span(u0, u1, (1.0, 1.0), gap=0.0):
        front(face, a, b, z0, z1 - GOLA_H, mats, coll)
    gola(face, u0, u1, z1, mats, coll)


# --------------------------------------------------------------------------
# Модули
# --------------------------------------------------------------------------


def base_module(face, u0, u1, kind, mats, coll):
    box("Цоколь", *face.bounds(u0, u1, 0.0, PLINTH_H, TOE_RECESS, BASE_D), mats["plinth"], coll)
    box("Корпус", *face.bounds(u0, u1, PLINTH_H, CARCASS_TOP, CARCASS_D0, BASE_D),
        mats["carcass"], coll)
    # подсветка цоколя: полоса под корпусом, светит на пол
    box("LED цоколя", *face.bounds(u0 + 0.02, u1 - 0.02, PLINTH_H - 0.008, PLINTH_H,
                                   0.02, 0.035), mats["led"], coll, bevel=0.0)
    if kind == "drawers3":
        drawer_stack(face, u0, u1, PLINTH_H, CARCASS_TOP, (0.75, 1.0, 1.0), mats, coll)
    elif kind == "drawers2":
        drawer_stack(face, u0, u1, PLINTH_H, CARCASS_TOP, (1.0, 1.4), mats, coll)
    elif kind == "sink":
        door_pair(face, u0, u1, PLINTH_H, CARCASS_TOP, mats, coll)


def wall_module(face, u0, u1, mats, coll):
    box("Корпус верхний", *face.bounds(u0, u1, WALL_Z0, WALL_Z1, CARCASS_D0, WALL_D),
        mats["carcass"], coll)
    front(face, u0, u1, WALL_Z0 + GOLA_H, WALL_Z1, mats, coll, mat_key="white_gloss",
          name="Фасад верхний")
    box("Гола-профиль", *face.bounds(u0 + GAP, u1 - GAP, WALL_Z0, WALL_Z0 + GOLA_H,
                                     GOLA_D, GOLA_D + 0.012), mats["anod"], coll, bevel=0.0)
    box("LED рабочей зоны", *face.bounds(u0 + 0.03, u1 - 0.03, WALL_Z0 - 0.01, WALL_Z0,
                                         0.06, WALL_D - 0.05), mats["led"], coll, bevel=0.0)


def appliance_front(face, u0, u1, z0, z1, mats, coll, band=True):
    """Встроенная техника: стальная рамка, чёрное стекло, тонкий горизонтальный поручень."""
    box("Корпус техники", *face.bounds(u0 + GAP, u1 - GAP, z0 + GAP, z1 - GAP, 0.0, 0.012),
        mats["steel"], coll)
    box("Стекло техники", *face.bounds(u0 + 0.03, u1 - 0.03, z0 + 0.03, z1 - 0.03, -0.006, 0.0),
        mats["black_glass"], coll)
    if band:
        cyl("Поручень", face.point((u0 + u1) / 2, z1 - 0.06, -0.03), 0.007, (u1 - u0) - 0.10,
            face.u_axis, mats["steel"], coll, segments=18)


def tall_module(face, u0, u1, kind, mats, coll):
    box("Цоколь пенала", *face.bounds(u0, u1, 0.0, PLINTH_H, TOE_RECESS, TALL_D),
        mats["plinth"], coll)
    if kind == "niche":
        niche_module(face, u0, u1, mats, coll)
        return
    box("Корпус пенала", *face.bounds(u0, u1, PLINTH_H, ROOM_H, FRONT_T, TALL_D),
        mats["carcass"], coll)
    front(face, u0, u1, TALL_SPLIT, ROOM_H, mats, coll, name="Фасад антресоли")

    if kind == "pantry":
        front(face, u0, u1, PLINTH_H, TALL_SPLIT, mats, coll, name="Фасад пенала")
    elif kind == "fridge":
        front(face, u0, u1, PLINTH_H, 0.85, mats, coll, name="Фасад морозильника")
        front(face, u0, u1, 0.85, TALL_SPLIT, mats, coll, name="Фасад холодильника")
    elif kind == "oven":
        drawer_stack(face, u0, u1, PLINTH_H, 0.55, (1.0,), mats, coll)
        appliance_front(face, u0, u1, 0.55, 1.15, mats, coll)
        appliance_front(face, u0, u1, 1.15, 1.60, mats, coll)
        front(face, u0, u1, 1.60, TALL_SPLIT, mats, coll, name="Фасад пенала")
    elif kind == "coffee":
        drawer_stack(face, u0, u1, PLINTH_H, 0.55, (1.0,), mats, coll)
        appliance_front(face, u0, u1, 0.55, 0.70, mats, coll, band=False)
        appliance_front(face, u0, u1, 0.70, 1.15, mats, coll)
        appliance_front(face, u0, u1, 1.15, 1.60, mats, coll)
        front(face, u0, u1, 1.60, TALL_SPLIT, mats, coll, name="Фасад пенала")


def niche_module(face, u0, u1, mats, coll):
    """Рабочая ниша в стене пеналов: ящики, столешница, стеклянная стенка, свет."""
    box("Корпус ниши", *face.bounds(u0, u1, PLINTH_H, CARCASS_TOP, CARCASS_D0, TALL_D),
        mats["carcass"], coll)
    drawer_stack(face, u0, u1, PLINTH_H, CARCASS_TOP, (1.0, 1.4), mats, coll)
    box("Столешница ниши", *face.bounds(u0, u1, CARCASS_TOP, COUNTER_Z1, -COUNTER_OVERHANG, TALL_D),
        mats["porcelain"], coll)
    box("Стенка ниши", *face.bounds(u0 + 0.02, u1 - 0.02, COUNTER_Z1, NICHE_TOP,
                                    TALL_D - 0.02, TALL_D), mats["black_glass"], coll)
    for a, b in ((u0, u0 + 0.02), (u1 - 0.02, u1)):
        box("Бок ниши", *face.bounds(a, b, COUNTER_Z1, NICHE_TOP + 0.02, 0.0, TALL_D),
            mats["graphite"], coll)
    box("Верх ниши", *face.bounds(u0 + 0.02, u1 - 0.02, NICHE_TOP, NICHE_TOP + 0.02, 0.0, TALL_D),
        mats["graphite"], coll)
    box("LED ниши", *face.bounds(u0 + 0.05, u1 - 0.05, NICHE_TOP - 0.008, NICHE_TOP,
                                 TALL_D - 0.09, TALL_D - 0.06), mats["led"], coll, bevel=0.0)
    box("Корпус над нишей", *face.bounds(u0, u1, NICHE_TOP + 0.02, ROOM_H, FRONT_T, TALL_D),
        mats["carcass"], coll)
    for a, b in split_span(u0, u1, (1.0, 1.0), gap=0.0):
        front(face, a, b, NICHE_TOP + 0.02, TALL_SPLIT, mats, coll, name="Фасад над нишей")
    front(face, u0, u1, TALL_SPLIT, ROOM_H, mats, coll, name="Фасад антресоли")

    # кофемашина и две чашки — масштаб и «обжитость» ниши
    cu = (u0 + u1) / 2 + 0.25
    box("Кофемашина", *face.bounds(cu - 0.18, cu + 0.18, COUNTER_Z1, COUNTER_Z1 + 0.40, 0.14, 0.52),
        mats["black_glass"], coll)
    box("Панель кофемашины", *face.bounds(cu - 0.18, cu + 0.18, COUNTER_Z1 + 0.30,
                                          COUNTER_Z1 + 0.34, 0.134, 0.14), mats["steel"], coll)
    for du in (-0.55, -0.42):
        cyl("Чашка", face.point((u0 + u1) / 2 + du, COUNTER_Z1 + 0.035, 0.30), 0.035, 0.07,
            "Z", mats["white_gloss"], coll, segments=20)


# --------------------------------------------------------------------------
# Остров, столешницы, техника
# --------------------------------------------------------------------------


def build_island(mats, colls):
    coll = colls["island"]
    back = Face("+Y", ISL_Y1, 0.0)
    box("Цоколь острова", (ISL_X0 + TOE_RECESS, ISL_Y0 + TOE_RECESS, 0.0),
        (ISL_X1 - TOE_RECESS, ISL_Y1 - TOE_RECESS, PLINTH_H), mats["plinth"], coll)
    box("Корпус острова", (ISL_X0, ISL_Y0 + FRONT_T, PLINTH_H),
        (ISL_X1, ISL_Y1 - CARCASS_D0, CARCASS_TOP), mats["carcass"], coll)
    box("Панель острова", (ISL_X0 + GAP, ISL_Y0, PLINTH_H + GAP),
        (ISL_X1 - GAP, ISL_Y0 + FRONT_T, CARCASS_TOP - GAP), mats["graphite"], coll)
    for u0, u1, kind in module_spans(ISL_BACK, ISL_X0):
        drawer_stack(back, u0, u1, PLINTH_H, CARCASS_TOP, (1.0, 1.4), mats, coll)

    # подсветка цоколя по периметру: остров «парит»
    z0, z1 = PLINTH_H - 0.008, PLINTH_H
    for lo, hi in (((ISL_X0 + 0.02, ISL_Y0 + 0.02), (ISL_X1 - 0.02, ISL_Y0 + 0.035)),
                   ((ISL_X0 + 0.02, ISL_Y1 - 0.035), (ISL_X1 - 0.02, ISL_Y1 - 0.02)),
                   ((ISL_X0 + 0.02, ISL_Y0 + 0.02), (ISL_X0 + 0.035, ISL_Y1 - 0.02)),
                   ((ISL_X1 - 0.035, ISL_Y0 + 0.02), (ISL_X1 - 0.02, ISL_Y1 - 0.02))):
        box("LED острова", (*lo, z0), (*hi, z1), mats["led"], coll, bevel=0.0)

    # водопадная столешница: плита и два торца до пола
    y0, y1 = ISL_Y0 - ISL_OVER, ISL_Y1 + COUNTER_T
    box("Столешница острова", (ISL_X0 - COUNTER_T, y0, CARCASS_TOP),
        (ISL_X1 + COUNTER_T, y1, COUNTER_Z1), mats["porcelain"], coll)
    box("Торец водопад", (ISL_X0 - COUNTER_T, y0, 0.0), (ISL_X0, y1, CARCASS_TOP),
        mats["porcelain"], coll)
    box("Торец водопад", (ISL_X1, y0, 0.0), (ISL_X1 + COUNTER_T, y1, CARCASS_TOP),
        mats["porcelain"], coll)

    # варочная панель заподлицо
    box("Варочная панель", (HOB_CX - HOB_W / 2, HOB_CY - HOB_D / 2, COUNTER_Z1),
        (HOB_CX + HOB_W / 2, HOB_CY + HOB_D / 2, COUNTER_Z1 + 0.004),
        mats["black_glass"], coll, bevel=0.001)
    for dx in (-0.22, 0.22):
        for dy in (-0.12, 0.12):
            cyl("Зона нагрева", (HOB_CX + dx, HOB_CY + dy, COUNTER_Z1 + 0.0045), 0.095, 0.0008,
                "Z", mats["ring"], coll)

    # барные стулья: колонна на диске, кожаное сиденье
    for x in STOOL_XS:
        y = ISL_Y0 - 0.22
        cyl("Основание стула", (x, y, 0.008), 0.20, 0.016, "Z", mats["anod"], coll, segments=40)
        cyl("Стойка стула", (x, y, 0.34), 0.022, 0.64, "Z", mats["anod"], coll, segments=20)
        cyl("Сиденье", (x, y, 0.69), 0.19, 0.05, "Z", mats["leather"], coll, segments=40)

    # поднос со специями и доска — масштаб
    box("Поднос", (4.25, 3.15, COUNTER_Z1), (4.75, 3.37, COUNTER_Z1 + 0.018), mats["anod"], coll)
    for i in range(3):
        cyl("Банка", (4.33 + i * 0.17, 3.26, COUNTER_Z1 + 0.06), 0.035, 0.085, "Z",
            mats["steel"], coll, segments=20)
    box("Доска", (2.05, 3.05, COUNTER_Z1), (2.45, 3.40, COUNTER_Z1 + 0.025), mats["walnut"], coll)


def build_left_run(mats, colls):
    face = Face("+X", 0.0, BASE_D)
    wall_face = Face("+X", 0.0, WALL_D)
    spans = module_spans(LEFT_RUN, LEFT_START)
    for u0, u1, kind in spans:
        base_module(face, u0, u1, kind, mats, colls["base"])
    box("Бок линии", (0.0, LEFT_START - FRONT_T, 0.0), (BASE_D, LEFT_START, CARCASS_TOP),
        mats["graphite"], colls["base"])

    for a, b in split_span(LEFT_START, LEFT_END, (1.0,) * 4, gap=0.0):
        wall_module(wall_face, a, b, mats, colls["wall"])
    box("Бок верхний", (0.0, LEFT_START - FRONT_T, WALL_Z0), (WALL_D, LEFT_START, WALL_Z1),
        mats["white_gloss"], colls["wall"])

    sink0, sink1 = find_span(spans, "sink")
    cy = (sink0 + sink1) / 2
    hole = (0.13, 0.13 + SINK_D, cy - SINK_W / 2, cy + SINK_W / 2)
    slab("Столешница", (0.0, LEFT_START - FRONT_T, CARCASS_TOP),
         (BASE_D + COUNTER_OVERHANG, LEFT_END, COUNTER_Z1), mats["porcelain"],
         colls["counter"], hole=hole, axes=(0, 1))
    box("Фартук", (0.0, LEFT_START - FRONT_T, COUNTER_Z1), (0.012, LEFT_END, WALL_Z0),
        mats["black_glass"], colls["counter"])
    build_sink(mats, colls["appliances"], hole)


def build_sink(mats, coll, hole):
    x0, x1, y0, y1 = hole
    t = 0.008
    bottom = COUNTER_Z1 - SINK_BOWL
    m = mats["composite"]
    box("Дно мойки", (x0, y0, bottom - t), (x1, y1, bottom), m, coll)
    box("Стенка мойки", (x0, y0, bottom), (x0 + t, y1, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x1 - t, y0, bottom), (x1, y1, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x0 + t, y0, bottom), (x1 - t, y0 + t, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x0 + t, y1 - t, bottom), (x1 - t, y1, CARCASS_TOP), m, coll)
    cyl("Слив", ((x0 + x1) / 2, (y0 + y1) / 2, bottom + 0.004), 0.045, 0.008, "Z",
        mats["anod"], coll)

    # чёрный смеситель: высокая дуга над центром чаши
    cy = (y0 + y1) / 2
    fx = 0.065
    curve = bpy.data.curves.new("Смеситель", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.013
    curve.bevel_resolution = 6
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    points = [(fx, cy, COUNTER_Z1), (fx, cy, COUNTER_Z1 + 0.26),
              (fx + 0.05, cy, COUNTER_Z1 + 0.38), (fx + 0.18, cy, COUNTER_Z1 + 0.39),
              ((x0 + x1) / 2, cy, COUNTER_Z1 + 0.27)]
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("Смеситель", curve)
    curve.materials.append(mats["anod"])
    coll.objects.link(ob)
    cyl("Основание смесителя", (fx, cy, COUNTER_Z1 + 0.01), 0.026, 0.02, "Z", mats["anod"], coll)


def build_tall_wall(mats, colls):
    face = Face("-Y", ROOM_D, TALL_D)
    for u0, u1, kind in module_spans(TALL_RUN, 0.0):
        tall_module(face, u0, u1, kind, mats, colls["tall"])


# --------------------------------------------------------------------------
# Помещение, потолок, свет
# --------------------------------------------------------------------------


def build_floor(mats, coll):
    """Керамогранит 1200×600 со смещением рядов на полплиты."""
    rng = random.Random(7)
    tile_x, tile_y, joint = 1.2, 0.6, 0.003
    x_lo, x_hi = -WALL_T, ROOM_W + WALL_T
    y_lo, y_hi = -WALL_T, ROOM_D
    row = 0
    y = y_lo
    while y < y_hi:
        x = x_lo - (tile_x / 2 if row % 2 else 0.0)
        while x < x_hi:
            x0, x1 = max(x, x_lo), min(x + tile_x - joint, x_hi)
            y0, y1 = max(y, y_lo), min(y + tile_y - joint, y_hi)
            if x1 > x0 and y1 > y0:
                box("Плитка пола", (x0, y0, -0.02), (x1, y1, 0.0),
                    mats["floor"][rng.randrange(3)], coll, bevel=0.002)
            x += tile_x
        y += tile_y
        row += 1
    box("Затирка", (x_lo, y_lo, -0.03), (x_hi, y_hi, -0.004), mats["plinth"], coll, bevel=0.0)


def build_room(mats, colls):
    coll = colls["room"]
    build_floor(mats, coll)
    box("Потолок", (-WALL_T, -WALL_T, ROOM_H), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H + WALL_T),
        mats["ceiling"], coll)
    box("Стена задняя", (-WALL_T, ROOM_D, 0.0), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H),
        mats["wall"], coll)
    box("Стена левая", (-WALL_T, -WALL_T, 0.0), (0.0, ROOM_D, ROOM_H), mats["wall"], coll)
    slab("Стена правая", (ROOM_W, -WALL_T, 0.0), (ROOM_W + WALL_T, ROOM_D, ROOM_H),
         mats["wall"], coll, hole=(GLAZE_Y0, GLAZE_Y1, GLAZE_Z0, GLAZE_Z1), axes=(1, 2))
    slab("Стена передняя", (-WALL_T, -WALL_T, 0.0), (ROOM_W + WALL_T, 0.0, ROOM_H),
         mats["wall"], coll, hole=(DOOR_X0, DOOR_X1, 0.0, DOOR_Z1), axes=(0, 2))

    # панорамное остекление: стекло в тонких чёрных импостах
    gx0, gx1 = ROOM_W + 0.04, ROOM_W + 0.05
    box("Остекление", (gx0, GLAZE_Y0, GLAZE_Z0), (gx1, GLAZE_Y1, GLAZE_Z1), mats["glass"],
        coll, bevel=0.0)
    n = 4
    for i in range(n + 1):
        y = GLAZE_Y0 + (GLAZE_Y1 - GLAZE_Y0) * i / n
        box("Импост", (ROOM_W + 0.01, y - 0.025, GLAZE_Z0), (ROOM_W + 0.08, y + 0.025, GLAZE_Z1),
            mats["anod"], coll)
    for z in (GLAZE_Z0, GLAZE_Z1):
        box("Ригель", (ROOM_W + 0.01, GLAZE_Y0, z - 0.03), (ROOM_W + 0.08, GLAZE_Y1, z + 0.03),
            mats["anod"], coll)

    # за стеклом: закатный градиент и силуэт города в дымке
    box("Фон за окном", (ROOM_W + 14.0, -22.0, -6.0), (ROOM_W + 14.1, 30.0, 16.0), mats["sky"],
        coll, bevel=0.0)
    rng = random.Random(3)
    y = -16.0
    while y < 24.0:
        w, h = rng.uniform(1.2, 3.2), rng.uniform(1.6, 6.0)
        x = ROOM_W + rng.uniform(7.0, 11.0)
        box("Дом вдали", (x, y, -6.0), (x + w, y + w, h), mats["skyline"], coll, bevel=0.0)
        y += w + rng.uniform(0.3, 1.6)

    # за проёмом — приглушённый коридор, а не улица
    cx0, cx1 = -1.0, ROOM_W + 3.0
    box("Коридор стена", (cx0, -1.9, 0.0), (cx1, -1.8, ROOM_H), mats["wall"], coll, bevel=0.0)
    box("Коридор пол", (cx0, -1.8, -0.02), (cx1, -WALL_T, 0.0), mats["floor"][1], coll, bevel=0.0)
    box("Коридор потолок", (cx0, -1.8, ROOM_H), (cx1, -WALL_T, ROOM_H + 0.1), mats["ceiling"],
        coll, bevel=0.0)


def build_ceiling_features(mats, colls):
    coll = colls["ceiling"]
    # опущенный короб над островом с вытяжкой и световым контуром
    box("Потолок над островом", (DROP_X0, DROP_Y0, DROP_Z0), (DROP_X1, DROP_Y1, ROOM_H),
        mats["graphite"], coll)
    inset, w = 0.05, 0.02
    for lo, hi in (((DROP_X0 + inset, DROP_Y0 + inset), (DROP_X1 - inset, DROP_Y0 + inset + w)),
                   ((DROP_X0 + inset, DROP_Y1 - inset - w), (DROP_X1 - inset, DROP_Y1 - inset)),
                   ((DROP_X0 + inset, DROP_Y0 + inset), (DROP_X0 + inset + w, DROP_Y1 - inset)),
                   ((DROP_X1 - inset - w, DROP_Y0 + inset), (DROP_X1 - inset, DROP_Y1 - inset))):
        box("LED короба", (*lo, DROP_Z0 - 0.006), (*hi, DROP_Z0), mats["led"], coll, bevel=0.0)
    box("Рамка вытяжки", (HOB_CX - 0.52, HOB_CY - 0.32, DROP_Z0 - 0.035),
        (HOB_CX + 0.52, HOB_CY + 0.32, DROP_Z0), mats["steel"], coll)
    box("Вытяжка потолочная", (HOB_CX - 0.50, HOB_CY - 0.30, DROP_Z0 - 0.04),
        (HOB_CX + 0.50, HOB_CY + 0.30, DROP_Z0 - 0.035), mats["black_glass"], coll)

    # подвесы над барной стороной
    for x in STOOL_XS:
        cyl("Подвес трос", (x, PENDANT_Y, (DROP_Z0 + 1.85) / 2), 0.004, DROP_Z0 - 1.85, "Z",
            mats["anod"], coll, segments=8)
        cyl("Подвес", (x, PENDANT_Y, 1.70), 0.055, 0.30, "Z", mats["anod"], coll, segments=32)
        cyl("Подвес рассеиватель", (x, PENDANT_Y, 1.548), 0.046, 0.004, "Z", mats["led_warm"],
            coll, segments=32)

    # линейные светильники вдоль проходов
    for y in (1.30, 4.55):
        box("Линейный светильник", (0.5, y - 0.025, ROOM_H - 0.004), (5.5, y + 0.025, ROOM_H),
            mats["led"], coll, bevel=0.0)


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
        # источник за стеклом не должен просвечивать и отражаться белым прямоугольником
        ob.visible_camera = False
        ob.visible_glossy = False
        ob.visible_transmission = False
        coll.objects.link(ob)

    # вечерний свет с улицы через остекление
    area("Свет из окна", (ROOM_W + 0.45, (GLAZE_Y0 + GLAZE_Y1) / 2, 1.5),
         (0.0, math.radians(90), 0.0), GLAZE_Y1 - GLAZE_Y0, 2.5, 420.0, (0.78, 0.86, 1.0))
    for i, y in enumerate((1.30, 4.55)):
        area("Линейный свет %d" % (i + 1), (3.0, y, ROOM_H - 0.02), (0.0, 0.0, 0.0),
             5.0, 0.12, 140.0, (1.0, 0.96, 0.9))
    area("Свет над островом", (HOB_CX, (DROP_Y0 + DROP_Y1) / 2, DROP_Z0 - 0.05),
         (0.0, 0.0, 0.0), 3.0, 1.2, 85.0, (1.0, 0.95, 0.88))
    for x in STOOL_XS:
        data = bpy.data.lights.new("Подвес свет", "POINT")
        data.energy = 14.0
        data.color = (1.0, 0.84, 0.64)
        data.shadow_soft_size = 0.04
        ob = bpy.data.objects.new("Подвес свет", data)
        ob.location = (x, PENDANT_Y, 1.52)
        coll.objects.link(ob)

    world = bpy.data.worlds.new("Окружение")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.30, 0.38, 0.52, 1.0)
    bg.inputs["Strength"].default_value = 0.35
    bpy.context.scene.world = world


def build_cameras(colls):
    coll = colls["cameras"]
    specs = {
        "overview": ((3.00, 0.35, 1.55), (3.00, 5.40, 1.25), 20),
        "island": ((0.85, 0.95, 1.60), (4.20, 3.60, 0.95), 26),
        "window": ((1.10, 4.75, 1.55), (6.00, 1.60, 0.95), 24),
        "niche": ((1.20, 3.00, 1.62), (4.30, 5.60, 1.15), 30),
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
# Сборка и вид в Blender
# --------------------------------------------------------------------------


def build():
    reset_scene()
    mats = build_materials()
    colls = {key: collection(title) for key, title in (
        ("room", "01 Помещение"),
        ("base", "02 Рабочая линия"),
        ("counter", "03 Столешница и фартук"),
        ("wall", "04 Верхние шкафы"),
        ("tall", "05 Стена пеналов"),
        ("island", "06 Остров"),
        ("appliances", "07 Мойка"),
        ("ceiling", "08 Потолок и светильники"),
        ("lights", "09 Свет"),
        ("cameras", "10 Камеры"),
    )}
    build_left_run(mats, colls)
    build_tall_wall(mats, colls)
    build_island(mats, colls)
    build_room(mats, colls)
    build_ceiling_features(mats, colls)
    build_lighting(colls)
    return build_cameras(colls)


def setup_viewport():
    """Файл открывается уже в цвете, изнутри кухни, без каркасов ламп и камер."""
    for obj in bpy.data.objects:
        if obj.name.startswith(("Потолок", "Стена передняя")) and not obj.name.startswith("Потолок над"):
            obj.hide_viewport = True
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
                space.shading.studio_light = "city.exr"
                space.shading.studiolight_intensity = 0.9
                space.overlay.show_extras = False
                space.overlay.show_relationship_lines = False
                space.clip_start = 0.02
                space.clip_end = 300.0
                space.lens = 28.0
                for region in area.regions:
                    if region.type == "WINDOW" and region.data is not None:
                        rv = region.data
                        rv.view_perspective = "PERSP"
                        rv.view_location = (3.0, 3.1, 1.15)
                        rv.view_rotation = Euler((math.radians(76), 0.0, math.radians(-6)),
                                                 "XYZ").to_quaternion()
                        rv.view_distance = 6.2


def export_glb(path):
    """Вариант для просмотра снаружи: без потолка, передней стены, ламп и камер."""
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception:
        pass
    for obj in bpy.data.objects:
        skip = obj.type in {"CAMERA", "LIGHT"} or obj.name.startswith("Стена передняя") \
            or (obj.name.startswith("Потолок") and not obj.name.startswith("Потолок над"))
        obj.select_set(not skip)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    do_render = "--render" in argv
    do_glb = "--glb" in argv
    do_save = "--no-save" not in argv
    samples = 48
    res = (1280, 800)
    names = ["overview", "island", "window", "niche"]
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
    bpy.context.scene.view_settings.exposure = 0.15
    setup_viewport()
    print("Объектов в сцене: %d" % len(bpy.data.objects))

    if do_save:
        path = os.path.join(out_3d, "rich-kitchen-hitech.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print("Сохранено: %s" % path)

    if do_glb:
        export_glb(os.path.join(out_3d, "rich-kitchen-hitech.glb"))
        print("Экспортировано: rich-kitchen-hitech.glb")

    if do_render:
        scene = bpy.context.scene
        for name in names:
            scene.camera = cams[name]
            scene.render.filepath = os.path.join(out_img, "hitech-" + name + ".png")
            print("Рендер %s -> %s" % (name, scene.render.filepath))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
