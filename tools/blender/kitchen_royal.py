"""Дворцовая кухня — классика в духе замковых интерьеров, процедурная модель для Blender.

Запуск:  blender --background --python tools/blender/kitchen_royal.py -- [ключи]
         python tools/blender/kitchen_royal.py [ключи]       (при установленном bpy)
Ключи:   --render, --glb, --samples N, --res W H, --cameras a,b,c, --no-save

Помещение 5.4 × 4.8 м с потолком 3.2 м. Г-образная кухня: слева мойка-фермерская
под арочным окном, вдоль дальней стены — плита-камин с порталом между двумя
арочными окнами, справа — буфет с тарелками. В центре ореховый остров на точёных
ножках с мраморной столешницей. Фасады филёнчатые, слоновая кость с золотыми
бусинами; каменные стены, шахматный мраморный пол, кессонный потолок, люстра
со свечами. Все текстуры процедурные — видны во вьюпорте без внешних файлов.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen import (  # noqa: E402
    box, collection, cyl, emissive, principled, reset_scene, setup_render, slab,
    split_span, srgb, _coords,
)

# --------------------------------------------------------------------------
# Габариты и раскладка
# --------------------------------------------------------------------------

ROOM_W, ROOM_D, ROOM_H = 5.4, 4.8, 3.2
WALL_T = 0.18

BASE_D = 0.62
PLINTH_H = 0.10
TOE_RECESS = 0.05
CARCASS_TOP = 0.86
COUNTER_T = 0.04
COUNTER_Z1 = CARCASS_TOP + COUNTER_T
COUNTER_OVERHANG = 0.035
FRONT_T = 0.022
GAP = 0.004
STILE = 0.07                  # рамка филёнчатого фасада
PILASTER_W = 0.12

WALL_D = 0.36
WALL_Z0, WALL_Z1 = 1.45, 2.35
CORNICE_H = 0.13

# Левая линия (стена x=0), от входа вглубь.
LEFT_START = 0.90
LEFT_END = ROOM_D - BASE_D
LEFT_RUN = [(0.12, "pilaster"), (0.70, "door_l"), (0.90, "sink"), (0.80, "drawers"),
            (0.64, "door_r"), (0.12, "pilaster")]

# Дальняя стена (y=ROOM_D), от угла с левой линией до правой стены.
BACK_START = BASE_D
BACK_RUN = [(0.12, "pilaster"), (0.77, "door_r"), (0.90, "drawers"), (1.20, "range"),
            (0.90, "drawers"), (0.77, "door_l"), (0.12, "pilaster")]

# Окна: арочные, стена/центр/ширина, низ прямоугольной части и пята арки.
WIN_W, WIN_Z0, WIN_Z1 = 0.80, 1.25, 2.35
WIN_R = WIN_W / 2
WINDOWS_BACK_X = (1.96, 4.06)
WINDOW_LEFT_Y = 2.17

# Остров.
ISL_X0, ISL_X1 = 1.80, 4.20
ISL_Y0, ISL_Y1 = 1.90, 3.00
ISL_OVER = 0.30
STOOL_XS = (2.25, 3.00, 3.75)

# Буфет у правой стены.
DRESSER_Y0, DRESSER_Y1 = 2.20, 4.00
DRESSER_D, DRESSER_TOP_D = 0.50, 0.30

# Вход: арка в передней стене.
DOOR_X0, DOOR_X1, DOOR_Z1 = 2.00, 3.40, 2.20

BEAM_YS = (1.2, 2.4, 3.6)
CHANDELIER = ((ISL_X0 + ISL_X1) / 2, 2.40)

PALETTE = {
    "ivory": "#EFE6D3",
    "ivory_shadow": "#E4DAC5",
    "gold": "#CFA84C",
    "gold_dark": "#8A6A22",
    "walnut": "#5B3B24",
    "walnut_dark": "#33200F",
    "marble": "#F1EADB",
    "marble_vein": "#D6C29A",
    "marble_vein2": "#CFCBC2",
    "emperador": "#4A3527",
    "emperador_vein": "#9A7F5E",
    "stone": "#CDBE9F",
    "stone_dark": "#A9997A",
    "mortar": "#8E8068",
    "plaster": "#F1EADC",
    "iron": "#1E1B18",
    "copper": "#B4703A",
    "burgundy": "#4E1620",
    "ceramic": "#F5F1E8",
    "leather": "#5A2A24",
    "glass_tint": "#E8F0F4",
}


# --------------------------------------------------------------------------
# Утилиты
# --------------------------------------------------------------------------


class Face:
    """Плоскость фасадов: u — вдоль ряда, d — глубина от плоскости фасада внутрь."""

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


def mesh_object(name, verts, faces, mat, coll, bevel=0.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    if mat:
        me.materials.append(mat)
    coll.objects.link(ob)
    if bevel:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(30)
    return ob


def frustum(name, lo, hi, mat, coll, bevel=0.0):
    """Усечённая пирамида: lo=(x0,x1,y0,y1,z), hi=(x0,x1,y0,y1,z)."""
    ax0, ax1, ay0, ay1, az = lo
    bx0, bx1, by0, by1, bz = hi
    verts = [(ax0, ay0, az), (ax1, ay0, az), (ax1, ay1, az), (ax0, ay1, az),
             (bx0, by0, bz), (bx1, by0, bz), (bx1, by1, bz), (bx0, by1, bz)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return mesh_object(name, verts, faces, mat, coll, bevel)


def sphere(name, center, radius, mat, coll, segments=20):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = center
    if mat:
        me.materials.append(mat)
    coll.objects.link(ob)
    return ob


def torus(name, center, major, minor, mat, coll, axis="Z", segments=40, rings=10):
    verts, faces = [], []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        for j in range(rings):
            b = 2 * math.pi * j / rings
            r = major + minor * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))
    for i in range(segments):
        for j in range(rings):
            n_i, n_j = (i + 1) % segments, (j + 1) % rings
            faces.append((i * rings + j, n_i * rings + j, n_i * rings + n_j, i * rings + n_j))
    ob = mesh_object(name, verts, faces, mat, coll)
    ob.location = center
    if axis == "X":
        ob.rotation_euler = (0.0, math.radians(90), 0.0)
    elif axis == "Y":
        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
    return ob


def arch(name, center, plane, depth, r_in, r_out, mat, coll, segments=24):
    """Полукольцо арки. center=(u, z) в плоскости стены, plane=('X'|'Y', const, dir)."""
    cu, cz = center
    axis, const, direction = plane
    d0, d1 = (const, const + depth * direction)
    verts = []

    def p(u, z, d):
        return (u, d, z) if axis == "Y" else (d, u, z)

    for i in range(segments + 1):
        t = math.pi * i / segments
        cu_, sz = math.cos(t), math.sin(t)
        for d in (d0, d1):
            verts.append(p(cu + r_in * cu_, cz + r_in * sz, d))
            verts.append(p(cu + r_out * cu_, cz + r_out * sz, d))
    faces = []
    for i in range(segments):
        b = i * 4
        n = b + 4
        # порядок: [in d0, out d0, in d1, out d1]
        faces.append((b + 0, b + 1, n + 1, n + 0))       # лицо d0
        faces.append((b + 2, n + 2, n + 3, b + 3))       # лицо d1
        faces.append((b + 1, b + 3, n + 3, n + 1))       # наружная поверхность
        faces.append((b + 0, n + 0, n + 2, b + 2))       # внутренняя поверхность
    faces.append((0, 2, 3, 1))
    e = segments * 4
    faces.append((e + 0, e + 1, e + 3, e + 2))
    return mesh_object(name, verts, faces, mat, coll)


# --------------------------------------------------------------------------
# Материалы с текстурами
# --------------------------------------------------------------------------


def noise_ramp(nt, mapping, scale, detail, stops, distortion=0.0, roughness=0.5):
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    noise.inputs["Roughness"].default_value = roughness
    if distortion and "Distortion" in noise.inputs:
        noise.inputs["Distortion"].default_value = distortion
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = stops[0]
    ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = stops[1]
    for pos, col in stops[2:]:
        el = ramp.color_ramp.elements.new(pos)
        el.color = col
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    return ramp


def marble_material(name, base, vein, vein2, scale=1.0, roughness=0.12, coat=0.5):
    mat = principled(name, base, roughness=roughness, coat=coat)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, scale)
    coarse = noise_ramp(nt, mapping, 1.1, 9.0,
                        [(0.50, (*base, 1.0)), (0.585, (*vein, 1.0))], distortion=1.4)
    fine = noise_ramp(nt, mapping, 3.4, 6.0,
                      [(0.57, (0, 0, 0, 1.0)), (0.64, (1, 1, 1, 1.0))], distortion=0.6)
    mix = nt.nodes.new("ShaderNodeMix") if hasattr(bpy.types, "ShaderNodeMix") else None
    if mix:
        mix.data_type = "RGBA"
        mix.inputs["B"].default_value = (*vein2, 1.0)
        nt.links.new(fine.outputs["Color"], mix.inputs["Factor"])
        nt.links.new(coarse.outputs["Color"], mix.inputs["A"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(coarse.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def wood_material(name, light, dark, scale=1.0, roughness=0.38, coat=0.25, along="Y"):
    """Орех: годовые кольца, вытянутые вдоль детали, плюс мелкие волокна."""
    mat = principled(name, light, roughness=roughness, coat=coat)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    stretch = {"X": (1.0, 9.0, 9.0), "Y": (9.0, 1.0, 9.0), "Z": (9.0, 9.0, 1.0)}[along]
    mapping = _coords(nt, tuple(s * scale for s in stretch))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 1.6
    wave.inputs["Distortion"].default_value = 4.5
    wave.inputs["Detail"].default_value = 6.0
    wave.inputs["Detail Scale"].default_value = 1.6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.2
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.8
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def stone_wall_material(name, stone, stone_dark, mortar, plane):
    """Каменная кладка: узор кирпича в плоскости стены (plane='XZ' или 'YZ')."""
    mat = principled(name, stone, roughness=0.9)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(tex.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["X" if plane == "XZ" else "Y"], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.012
    brick.inputs["Mortar Smooth"].default_value = 0.4
    brick.inputs["Brick Width"].default_value = 0.72
    brick.inputs["Row Height"].default_value = 0.30
    brick.inputs["Mortar"].default_value = (*mortar, 1.0)
    brick.inputs["Color1"].default_value = (*stone, 1.0)
    brick.inputs["Color2"].default_value = (*stone_dark, 1.0)
    brick.offset = 0.5
    nt.links.new(comb.outputs["Vector"], brick.inputs["Vector"])
    # неравномерность камня поверх кладки
    mapping = _coords(nt, 1.0)
    grain = noise_ramp(nt, mapping, 6.0, 5.0,
                       [(0.3, (0.82, 0.8, 0.78, 1.0)), (0.7, (1.0, 1.0, 1.0, 1.0))])
    mul = nt.nodes.new("ShaderNodeMix") if hasattr(bpy.types, "ShaderNodeMix") else None
    if mul:
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(brick.outputs["Color"], mul.inputs["A"])
        nt.links.new(grain.outputs["Color"], mul.inputs["B"])
        nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(brick.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def checker_marble_material(name, light, light_vein, dark, dark_vein, tile=0.6):
    """Шахматный мраморный пол по диагонали: два мрамора по клеткам."""
    mat = principled(name, light, roughness=0.14, coat=0.5)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 1.0)
    a = noise_ramp(nt, mapping, 1.3, 8.0, [(0.45, (*light, 1.0)), (0.57, (*light_vein, 1.0))],
                   distortion=1.2)
    b = noise_ramp(nt, mapping, 1.7, 8.0, [(0.44, (*dark, 1.0)), (0.58, (*dark_vein, 1.0))],
                   distortion=1.0)
    rot = nt.nodes.new("ShaderNodeMapping")
    rot.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(45))
    rot.inputs["Scale"].default_value = (1.0 / tile, 1.0 / tile, 1.0)
    nt.links.new(mapping.outputs["Vector"], rot.inputs["Vector"])
    checker = nt.nodes.new("ShaderNodeTexChecker")
    checker.inputs["Scale"].default_value = 1.0
    nt.links.new(rot.outputs["Vector"], checker.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(checker.outputs["Fac"], mix.inputs["Factor"])
    nt.links.new(a.outputs["Color"], mix.inputs["A"])
    nt.links.new(b.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def gold_material(name, color, dark):
    """Старое золото: металл с неравномерным блеском и потемнениями."""
    mat = principled(name, color, roughness=0.3, metallic=1.0)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 8.0)
    tone = noise_ramp(nt, mapping, 5.0, 4.0, [(0.35, (*dark, 1.0)), (0.6, (*color, 1.0))])
    rough = noise_ramp(nt, mapping, 9.0, 3.0,
                       [(0.3, (0.22, 0.22, 0.22, 1.0)), (0.7, (0.45, 0.45, 0.45, 1.0))])
    nt.links.new(tone.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def enamel_material(name, color, shadow):
    """Эмаль слоновой кости: лёгкая патина в неровностях."""
    mat = principled(name, color, roughness=0.3, coat=0.35)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    mapping = _coords(nt, 3.0)
    tone = noise_ramp(nt, mapping, 7.0, 4.0, [(0.30, (*shadow, 1.0)), (0.70, (*color, 1.0))])
    nt.links.new(tone.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def sky_day_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.1
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -1.0
    rng.inputs["From Max"].default_value = 7.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*srgb("#F3E9CF"), 1.0)
    ramp.color_ramp.elements[1].color = (*srgb("#6E9DD6"), 1.0)
    nt.links.new(tex.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def build_materials():
    p = {k: srgb(v) for k, v in PALETTE.items()}
    return {
        "ivory": enamel_material("Эмаль слоновая кость", p["ivory"], p["ivory_shadow"]),
        "gold": gold_material("Золото старое", p["gold"], p["gold_dark"]),
        "walnut": wood_material("Орех", p["walnut"], p["walnut_dark"], along="Y"),
        "walnut_x": wood_material("Орех вдоль X", p["walnut"], p["walnut_dark"], along="X"),
        "walnut_z": wood_material("Орех вертикальный", p["walnut"], p["walnut_dark"], along="Z"),
        "marble": marble_material("Мрамор калакатта голд", p["marble"], p["marble_vein"],
                                  p["marble_vein2"]),
        "emperador": marble_material("Мрамор эмперадор", p["emperador"], p["emperador_vein"],
                                     p["marble_vein2"], roughness=0.16),
        "floor": checker_marble_material("Пол мраморный шахматный", p["marble"], p["marble_vein"],
                                         p["emperador"], p["emperador_vein"]),
        "stone_xz": stone_wall_material("Кладка (задняя и передняя)", p["stone"], p["stone_dark"],
                                        p["mortar"], "XZ"),
        "stone_yz": stone_wall_material("Кладка (боковые)", p["stone"], p["stone_dark"],
                                        p["mortar"], "YZ"),
        "limestone": principled("Известняк резной", p["stone"], roughness=0.85),
        "plaster": principled("Штукатурка", p["plaster"], roughness=0.8),
        "carcass": principled("Корпус", p["ivory_shadow"], roughness=0.6),
        "iron": principled("Чугун", p["iron"], roughness=0.55, metallic=0.6),
        "copper": principled("Медь", p["copper"], roughness=0.3, metallic=1.0),
        "burgundy": principled("Эмаль бордо", p["burgundy"], roughness=0.22, coat=0.6),
        "ceramic": principled("Керамика", p["ceramic"], roughness=0.12, coat=0.7),
        "leather": principled("Кожа бордо", p["leather"], roughness=0.5),
        "glass": principled("Стекло", p["glass_tint"], roughness=0.0, transmission=1.0, ior=1.5),
        "sky": sky_day_material("Небо за окном"),
        "candle": principled("Воск", p["ivory"], roughness=0.5),
        "flame": emissive("Пламя свечи", (1.0, 0.72, 0.38), 40.0),
        "flame_soft": emissive("Свет свечи", (1.0, 0.8, 0.5), 6.0),
    }


# --------------------------------------------------------------------------
# Классические фасады и профили
# --------------------------------------------------------------------------


def panel_door(face, u0, u1, z0, z1, mats, coll, glass=False, name="Фасад"):
    """Филёнчатый фасад: рамка, утопленное поле, выпуклая филёнка с фаской, золотая бусина."""
    a, b = u0 + GAP, u1 - GAP
    c, d = z0 + GAP, z1 - GAP
    m = mats["ivory"]
    box(name + " стойка", *face.bounds(a, a + STILE, c, d, 0.0, FRONT_T), m, coll)
    box(name + " стойка", *face.bounds(b - STILE, b, c, d, 0.0, FRONT_T), m, coll)
    box(name + " перекладина", *face.bounds(a + STILE, b - STILE, c, c + STILE, 0.0, FRONT_T),
        m, coll)
    box(name + " перекладина", *face.bounds(a + STILE, b - STILE, d - STILE, d, 0.0, FRONT_T),
        m, coll)
    ia, ib, ic, id_ = a + STILE, b - STILE, c + STILE, d - STILE
    # золотая бусина по внутреннему краю рамки
    g = 0.006
    for lo, hi in (((ia, ic), (ia + g, id_)), ((ib - g, ic), (ib, id_)),
                   ((ia + g, ic), (ib - g, ic + g)), ((ia + g, id_ - g), (ib - g, id_))):
        box("Бусина", *face.bounds(lo[0], hi[0], lo[1], hi[1], -0.003, 0.004), mats["gold"],
            coll, bevel=0.0)
    if glass:
        box(name + " стекло", *face.bounds(ia, ib, ic, id_, 0.009, 0.013), mats["glass"], coll,
            bevel=0.0)
        # крестовина
        mu, mz = (ia + ib) / 2, (ic + id_) / 2
        box("Шпрос", *face.bounds(mu - 0.008, mu + 0.008, ic, id_, 0.004, 0.018), m, coll)
        box("Шпрос", *face.bounds(ia, ib, mz - 0.008, mz + 0.008, 0.004, 0.018), m, coll)
        return
    box(name + " поле", *face.bounds(ia, ib, ic, id_, 0.011, FRONT_T), m, coll, bevel=0.0)
    inset = 0.035
    if ib - ia > 2 * inset + 0.05 and id_ - ic > 2 * inset + 0.05:
        box(name + " филёнка", *face.bounds(ia + inset, ib - inset, ic + inset, id_ - inset,
                                            0.002, 0.012), m, coll, bevel=0.012)


def knob(face, u, z, mats, coll):
    sphere("Ручка-шар", face.point(u, z, -0.03), 0.016, mats["gold"], coll, segments=16)
    cyl("Ножка ручки", face.point(u, z, -0.012), 0.006, 0.024, {"X": "Y", "Y": "X"}[face.u_axis],
        mats["gold"], coll, segments=12)


def bar_pull(face, u_c, z, length, mats, coll):
    cyl("Ручка-скоба", face.point(u_c, z, -0.034), 0.007, length, face.u_axis, mats["gold"],
        coll, segments=14)
    for s in (-1, 1):
        u = u_c + s * (length / 2 - 0.02)
        cyl("Стойка скобы", face.point(u, z, -0.017), 0.006, 0.034,
            {"X": "Y", "Y": "X"}[face.u_axis], mats["gold"], coll, segments=12)
        sphere("Шар скобы", face.point(u_c + s * length / 2, z, -0.034), 0.011, mats["gold"],
               coll, segments=12)


def cornice(face, u0, u1, z_top, mats, coll):
    """Карниз: три ступени с выносом наружу и золотая полоса."""
    steps = ((0.0, 0.02, 0.03), (0.03, 0.045, 0.03), (0.06, 0.075, 0.07))
    for dz0, out, h in steps:
        box("Карниз", *face.bounds(u0 - out, u1 + out, z_top + dz0, z_top + dz0 + h, -out, WALL_D),
            mats["ivory"], coll)
    box("Золото карниза", *face.bounds(u0 - 0.045, u1 + 0.045, z_top + 0.03, z_top + 0.042,
                                       -0.05, -0.045), mats["gold"], coll, bevel=0.0)


def pilaster(face, u0, u1, z0, z1, depth, mats, coll):
    """Каннелированная пилястра с базой и капителью."""
    m = mats["ivory"]
    box("Пилястра", *face.bounds(u0, u1, z0, z1, -0.02, depth), m, coll)
    box("База пилястры", *face.bounds(u0 - 0.01, u1 + 0.01, z0, z0 + 0.09, -0.035, depth), m, coll)
    box("Капитель", *face.bounds(u0 - 0.015, u1 + 0.015, z1 - 0.08, z1, -0.04, depth), m, coll)
    box("Золото капители", *face.bounds(u0 - 0.015, u1 + 0.015, z1 - 0.085, z1 - 0.075, -0.042, -0.04),
        mats["gold"], coll, bevel=0.0)
    w = u1 - u0
    for k in range(3):
        u = u0 + w * (0.25 + 0.25 * k)
        box("Каннелюра", *face.bounds(u - 0.008, u + 0.008, z0 + 0.14, z1 - 0.14, -0.02, -0.012),
            mats["ivory_shadow"] if "ivory_shadow" in mats else mats["carcass"], coll, bevel=0.0)


def plinth_molded(face, u0, u1, mats, coll, depth=BASE_D):
    box("Цоколь", *face.bounds(u0, u1, 0.0, PLINTH_H, TOE_RECESS, depth), mats["ivory"], coll)
    box("Плинтус", *face.bounds(u0, u1, 0.0, 0.03, TOE_RECESS - 0.02, TOE_RECESS), mats["ivory"],
        coll)


# --------------------------------------------------------------------------
# Модули
# --------------------------------------------------------------------------


def base_module(face, u0, u1, kind, mats, coll):
    if kind == "pilaster":
        pilaster(face, u0, u1, 0.0, CARCASS_TOP, BASE_D, mats, coll)
        return
    if kind == "range":
        return
    plinth_molded(face, u0, u1, mats, coll)
    box("Корпус", *face.bounds(u0, u1, PLINTH_H, CARCASS_TOP, FRONT_T, BASE_D), mats["carcass"], coll)
    z0, z1 = PLINTH_H, CARCASS_TOP
    if kind in ("door_l", "door_r"):
        panel_door(face, u0, u1, z0, z1, mats, coll)
        knob(face, u1 - STILE / 2 - 0.01 if kind == "door_l" else u0 + STILE / 2 + 0.01,
             (z0 + z1) / 2, mats, coll)
    elif kind == "sink":
        # фермерская мойка выступает над двумя дверцами
        apron_z0 = z1 - 0.25
        for a, b in split_span(u0, u1, (1.0, 1.0), gap=0.0):
            panel_door(face, a, b, z0, apron_z0, mats, coll)
        knob(face, (u0 + u1) / 2 - 0.035, (z0 + apron_z0) / 2, mats, coll)
        knob(face, (u0 + u1) / 2 + 0.035, (z0 + apron_z0) / 2, mats, coll)
        box("Мойка фартук", *face.bounds(u0 + 0.02, u1 - 0.02, apron_z0, COUNTER_Z1 - 0.005,
                                         -0.035, 0.30), mats["ceramic"], coll, bevel=0.01)
    elif kind == "drawers":
        for a, b in split_span(z0, z1, (0.7, 1.0, 1.0), gap=0.0):
            panel_door(face, u0, u1, a, b, mats, coll, name="Фасад ящика")
            bar_pull(face, (u0 + u1) / 2, (a + b) / 2, min(0.24, (u1 - u0) * 0.4), mats, coll)


def wall_module(face, u0, u1, mats, coll, glass=False):
    box("Корпус верхний", *face.bounds(u0, u1, WALL_Z0, WALL_Z1, FRONT_T, WALL_D), mats["carcass"],
        coll)
    count = 2 if (u1 - u0) > 0.75 else 1
    spans = split_span(u0, u1, (1.0,) * count, gap=0.0)
    for i, (a, b) in enumerate(spans):
        panel_door(face, a, b, WALL_Z0, WALL_Z1, mats, coll, glass=glass, name="Фасад верхний")
        u = (b - STILE / 2 - 0.01) if (count == 1 or i == 0) else (a + STILE / 2 + 0.01)
        knob(face, u, WALL_Z0 + 0.16, mats, coll)


# --------------------------------------------------------------------------
# Линии, окна, стены
# --------------------------------------------------------------------------


def build_run(face, run, start, mats, colls, wall_items):
    spans = module_spans(run, start)
    for u0, u1, kind in spans:
        base_module(face, u0, u1, kind, mats, colls["base"])
    wall_face = Face(face.facing, face.wall, WALL_D)
    for u0, u1, glass in wall_items:
        wall_module(wall_face, u0, u1, mats, colls["wall"], glass=glass)
    for u0, u1, _ in wall_items:
        cornice(wall_face, u0, u1, WALL_Z1, mats, colls["wall"])
        for a, b in ((u0 - PILASTER_W, u0), (u1, u1 + PILASTER_W)):
            pilaster(wall_face, a, b, WALL_Z0, WALL_Z1 + 0.06, WALL_D, mats, colls["wall"])
    return spans


def counter_for(face, u0, u1, mats, coll, hole=None, axes=(0, 1)):
    lo, hi = face.bounds(u0, u1, CARCASS_TOP, COUNTER_Z1, -COUNTER_OVERHANG, BASE_D)
    slab("Столешница мрамор", lo, hi, mats["marble"], coll, hole=hole, axes=axes, bevel=0.012)


def backsplash_for(face, u0, u1, z1, mats, coll):
    box("Фартук мрамор", *face.bounds(u0, u1, COUNTER_Z1, z1, BASE_D - 0.012, BASE_D),
        mats["marble"], coll)


def arched_window(plane_axis, wall_const, direction, centre_u, mats, coll):
    """Арочное окно: каменный наличник, замковый камень, свинцовая расстекловка."""
    cu = centre_u
    u0, u1 = cu - WIN_R, cu + WIN_R
    inner = wall_const
    if plane_axis == "Y":   # окно в стене y=const, плоскость XZ
        def P(u, z, d):
            return (u, inner + d * direction, z)
    else:
        def P(u, z, d):
            return (inner + d * direction, u, z)

    def B(ua, ub, za, zb, da, db):
        p1, p2 = P(ua, za, da), P(ub, zb, db)
        return tuple(min(a, b) for a, b in zip(p1, p2)), tuple(max(a, b) for a, b in zip(p1, p2))

    # стекло с расстекловкой в глубине проёма
    box("Стекло", *B(u0, u1, WIN_Z0, WIN_Z1 + WIN_R, 0.10, 0.11), mats["glass"], coll, bevel=0.0)
    for k in range(1, 3):
        u = u0 + (u1 - u0) * k / 3
        box("Свинец", *B(u - 0.006, u + 0.006, WIN_Z0, WIN_Z1 + WIN_R * 0.75, 0.095, 0.115),
            mats["iron"], coll, bevel=0.0)
    for k in range(1, 4):
        z = WIN_Z0 + (WIN_Z1 - WIN_Z0) * k / 4
        box("Свинец", *B(u0, u1, z - 0.006, z + 0.006, 0.095, 0.115), mats["iron"], coll, bevel=0.0)
    box("Свинец", *B(u0, u1, WIN_Z1 - 0.006, WIN_Z1 + 0.006, 0.095, 0.115), mats["iron"], coll,
        bevel=0.0)
    # каменный наличник: косяки, подоконник, арка с замковым камнем
    j = 0.10
    for a, b in ((u0 - j, u0), (u1, u1 + j)):
        box("Косяк", *B(a, b, WIN_Z0 - 0.05, WIN_Z1, -0.05, 0.0), mats["limestone"], coll)
    box("Подоконник", *B(u0 - j - 0.04, u1 + j + 0.04, WIN_Z0 - 0.07, WIN_Z0, -0.12, 0.09),
        mats["marble"], coll, bevel=0.01)
    plane = ("Y" if plane_axis == "Y" else "X", inner, -direction)
    arch("Арка окна", (cu, WIN_Z1), plane, 0.05, WIN_R, WIN_R + j, mats["limestone"], coll)
    box("Замковый камень", *B(cu - 0.06, cu + 0.06, WIN_Z1 + WIN_R + 0.04, WIN_Z1 + WIN_R + 0.20,
                              -0.07, 0.0), mats["limestone"], coll)
    # арочная часть проёма закрыта стеной снаружи — здесь дуга в толще стены
    for i in range(8):
        t0, t1 = math.pi * i / 8, math.pi * (i + 1) / 8
        za = WIN_Z1 + WIN_R * min(math.sin(t0), math.sin(t1))
        ua, ub = cu + WIN_R * math.cos(t1), cu + WIN_R * math.cos(t0)
        box("Откос арки", *B(min(ua, ub), max(ua, ub), za, WIN_Z1 + WIN_R + 0.001, 0.0, WALL_T),
            mats["limestone"], coll, bevel=0.0)


def build_room(mats, colls):
    coll = colls["room"]
    box("Пол", (-WALL_T, -WALL_T, -0.02), (ROOM_W + WALL_T, ROOM_D, 0.0), mats["floor"], coll,
        bevel=0.0)
    box("Потолок", (-WALL_T, -WALL_T, ROOM_H), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H + WALL_T),
        mats["plaster"], coll)

    # задняя стена с двумя окнами: два проёма — режем поочерёдно
    parts = slab("Стена задняя", (-WALL_T, ROOM_D, 0.0), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H),
                 mats["stone_xz"], coll,
                 hole=(WINDOWS_BACK_X[0] - WIN_R, WINDOWS_BACK_X[0] + WIN_R, WIN_Z0, WIN_Z1 + WIN_R),
                 axes=(0, 2))
    # второе окно: правая часть первого разреза делится ещё раз
    right = [p for p in parts if p.name.endswith("_b")][0]
    lo, hi = (WINDOWS_BACK_X[0] + WIN_R, ROOM_D, 0.0), (ROOM_W + WALL_T, ROOM_D + WALL_T, ROOM_H)
    bpy.data.objects.remove(right, do_unlink=True)
    slab("Стена задняя", lo, hi, mats["stone_xz"], coll,
         hole=(WINDOWS_BACK_X[1] - WIN_R, WINDOWS_BACK_X[1] + WIN_R, WIN_Z0, WIN_Z1 + WIN_R),
         axes=(0, 2))
    slab("Стена левая", (-WALL_T, -WALL_T, 0.0), (0.0, ROOM_D, ROOM_H), mats["stone_yz"], coll,
         hole=(WINDOW_LEFT_Y - WIN_R, WINDOW_LEFT_Y + WIN_R, WIN_Z0, WIN_Z1 + WIN_R), axes=(1, 2))
    box("Стена правая", (ROOM_W, -WALL_T, 0.0), (ROOM_W + WALL_T, ROOM_D, ROOM_H), mats["stone_yz"],
        coll)
    slab("Стена передняя", (-WALL_T, -WALL_T, 0.0), (ROOM_W + WALL_T, 0.0, ROOM_H), mats["stone_xz"],
         coll, hole=(DOOR_X0, DOOR_X1, 0.0, DOOR_Z1), axes=(0, 2))

    for cx in WINDOWS_BACK_X:
        arched_window("Y", ROOM_D, +1, cx, mats, coll)
    arched_window("X", 0.0, -1, WINDOW_LEFT_Y, mats, coll)

    # арка входа: наличник из известняка внутри
    door_c, door_r = (DOOR_X0 + DOOR_X1) / 2, (DOOR_X1 - DOOR_X0) / 2
    arch("Арка входа", (door_c, DOOR_Z1), ("Y", 0.0, +1), 0.06, door_r, door_r + 0.12,
         mats["limestone"], coll)
    for a, b in ((DOOR_X0 - 0.12, DOOR_X0), (DOOR_X1, DOOR_X1 + 0.12)):
        box("Косяк входа", (a, 0.0, 0.0), (b, 0.06, DOOR_Z1), mats["limestone"], coll)
    for i in range(8):
        t0, t1 = math.pi * i / 8, math.pi * (i + 1) / 8
        za = DOOR_Z1 + door_r * min(math.sin(t0), math.sin(t1))
        ua, ub = door_c + door_r * math.cos(t1), door_c + door_r * math.cos(t0)
        box("Откос арки входа", (min(ua, ub), -WALL_T, za), (max(ua, ub), 0.0, DOOR_Z1 + door_r + 0.001),
            mats["stone_xz"], coll, bevel=0.0)
    box("Стена над входом", (DOOR_X0, -WALL_T, DOOR_Z1 + door_r), (DOOR_X1, 0.0, ROOM_H),
        mats["stone_xz"], coll)
    box("Коридор", (-1.0, -2.2, 0.0), (ROOM_W + 1.0, -2.1, ROOM_H), mats["stone_xz"], coll, bevel=0.0)
    box("Коридор пол", (-1.0, -2.1, -0.02), (ROOM_W + 1.0, -WALL_T, 0.0), mats["floor"], coll,
        bevel=0.0)

    # небо за окнами
    box("Небо", (-12.0, ROOM_D + 6.0, -3.0), (18.0, ROOM_D + 6.1, 12.0), mats["sky"], coll, bevel=0.0)
    box("Небо слева", (-6.1, -8.0, -3.0), (-6.0, 14.0, 12.0), mats["sky"], coll, bevel=0.0)

    # кессонный потолок: балки вдоль X и по периметру
    bw, bh = 0.16, 0.22
    for y in BEAM_YS:
        box("Балка", (0.0, y - bw / 2, ROOM_H - bh), (ROOM_W, y + bw / 2, ROOM_H), mats["walnut_x"], coll)
    for x in (1.8, 3.6):
        box("Балка поперечная", (x - bw / 2, 0.0, ROOM_H - bh + 0.06), (x + bw / 2, ROOM_D, ROOM_H),
            mats["walnut"], coll)
    for lo, hi in (((0.0, 0.0), (ROOM_W, 0.12)), ((0.0, ROOM_D - 0.12), (ROOM_W, ROOM_D)),
                   ((0.0, 0.0), (0.12, ROOM_D)), ((ROOM_W - 0.12, 0.0), (ROOM_W, ROOM_D))):
        box("Балка периметр", (*lo, ROOM_H - bh), (*hi, ROOM_H), mats["walnut"], coll)


# --------------------------------------------------------------------------
# Плита-камин, остров, буфет, люстра
# --------------------------------------------------------------------------


def build_range(spans, mats, colls):
    coll = colls["range"]
    x0, x1 = find_span(spans, "range")
    cx = (x0 + x1) / 2
    y_front = ROOM_D - 0.66
    box("Плита корпус", (x0 + 0.02, y_front, 0.0), (x1 - 0.02, ROOM_D - 0.02, 0.88), mats["burgundy"],
        coll, bevel=0.006)
    box("Плита верх", (x0 + 0.02, y_front - 0.01, 0.88), (x1 - 0.02, ROOM_D - 0.02, 0.905), mats["iron"],
        coll)
    box("Плита бортик", (x0 + 0.02, ROOM_D - 0.09, 0.905), (x1 - 0.02, ROOM_D - 0.02, 1.05), mats["iron"],
        coll)
    # два духовых шкафа со стеклом и латунными поручнями
    for a, b in split_span(x0 + 0.02, x1 - 0.02, (1.0, 1.0), gap=0.0):
        box("Дверца духовки", (a + 0.03, y_front - 0.02, 0.18), (b - 0.03, y_front, 0.68), mats["burgundy"],
            coll, bevel=0.004)
        box("Стекло духовки", (a + 0.08, y_front - 0.024, 0.28), (b - 0.08, y_front - 0.02, 0.58),
            mats["glass_dark"] if "glass_dark" in mats else mats["iron"], coll, bevel=0.0)
        cyl("Поручень духовки", ((a + b) / 2, y_front - 0.055, 0.64), 0.011, (b - a) - 0.12, "X",
            mats["gold"], coll, segments=16)
    # ряд ящиков-подогревателей снизу и золотые накладки
    box("Ящик плиты", (x0 + 0.05, y_front - 0.02, 0.06), (x1 - 0.05, y_front, 0.15), mats["burgundy"],
        coll, bevel=0.004)
    box("Латунь плиты", (x0 + 0.02, y_front - 0.022, 0.70), (x1 - 0.02, y_front - 0.002, 0.72),
        mats["gold"], coll, bevel=0.0)
    box("Латунь плиты", (x0 + 0.02, y_front - 0.022, 0.86), (x1 - 0.02, y_front - 0.002, 0.88),
        mats["gold"], coll, bevel=0.0)
    for i in range(6):
        cyl("Ручка плиты", (x0 + 0.14 + i * ((x1 - x0) - 0.28) / 5, y_front - 0.02, 0.78), 0.02,
            0.03, "Y", mats["gold"], coll, segments=16)
    # чугунные решётки конфорок
    for dx in (-0.36, 0.0, 0.36):
        for dy in (-0.16, 0.14):
            torus("Решётка", (cx + dx, ROOM_D - 0.36 + dy, 0.925), 0.10, 0.008, mats["iron"], coll)
            for k in range(4):
                a = math.pi / 4 + k * math.pi / 2
                cyl("Спица решётки", (cx + dx + 0.06 * math.cos(a), ROOM_D - 0.36 + dy + 0.06 * math.sin(a),
                                      0.925), 0.006, 0.12, "X", mats["iron"], coll, segments=8
                    ).rotation_euler = (0.0, math.radians(90), a)
    # портал вытяжки: усечённый колпак, ореховая полка на кронштейнах, дымоход
    hood_z0, shelf_z = 1.62, 1.62
    frustum("Колпак портала", (x0 - 0.10, x1 + 0.10, ROOM_D - 0.66, ROOM_D, hood_z0 + 0.08),
            (cx - 0.42, cx + 0.42, ROOM_D - 0.62, ROOM_D, 2.45), mats["plaster"], coll)
    box("Дымоход", (cx - 0.42, ROOM_D - 0.62, 2.45), (cx + 0.42, ROOM_D, ROOM_H), mats["plaster"], coll)
    box("Полка портала", (x0 - 0.18, ROOM_D - 0.72, shelf_z), (x1 + 0.18, ROOM_D, shelf_z + 0.08),
        mats["walnut_x"], coll, bevel=0.01)
    box("Золото полки", (x0 - 0.18, ROOM_D - 0.722, shelf_z + 0.02), (x1 + 0.18, ROOM_D - 0.70, shelf_z + 0.035),
        mats["gold"], coll, bevel=0.0)
    for a in (x0 - 0.12, x1 + 0.02):
        frustum("Кронштейн", (a, a + 0.10, ROOM_D - 0.16, ROOM_D, shelf_z - 0.26),
                (a, a + 0.10, ROOM_D - 0.62, ROOM_D, shelf_z), mats["walnut_z"], coll)
    box("Ниша портала", (x0 - 0.10, ROOM_D - 0.012, COUNTER_Z1), (x1 + 0.10, ROOM_D, hood_z0),
        mats["emperador"], coll)
    box("Рамка ниши", (x0 - 0.10, ROOM_D - 0.02, COUNTER_Z1), (x0 - 0.06, ROOM_D, hood_z0), mats["gold"],
        coll, bevel=0.0)
    box("Рамка ниши", (x1 + 0.06, ROOM_D - 0.02, COUNTER_Z1), (x1 + 0.10, ROOM_D, hood_z0), mats["gold"],
        coll, bevel=0.0)
    # медные кастрюли на латунном рейлинге
    rail_x0, rail_x1 = x1 + 0.25, x1 + 1.0
    cyl("Рейлинг", ((rail_x0 + rail_x1) / 2, ROOM_D - 0.05, 1.35), 0.01, rail_x1 - rail_x0, "X",
        mats["gold"], coll, segments=14)
    for i, r in enumerate((0.11, 0.09, 0.13)):
        px = rail_x0 + 0.12 + i * 0.26
        cyl("Кастрюля", (px, ROOM_D - 0.08, 1.35 - 0.09 - r), r, 0.12, "Y", mats["copper"], coll)
        cyl("Ручка кастрюли", (px, ROOM_D - 0.08, 1.35 - 0.05), 0.008, 0.10, "Z", mats["iron"], coll,
            segments=10)


def turned_leg(x, y, mats, coll, z_top=CARCASS_TOP):
    m = mats["walnut_z"]
    box("База ножки", (x - 0.055, y - 0.055, 0.0), (x + 0.055, y + 0.055, 0.10), m, coll)
    cyl("Ножка", (x, y, 0.24), 0.04, 0.28, "Z", m, coll, segments=24)
    sphere("Баллюстра", (x, y, 0.42), 0.065, m, coll, segments=20)
    cyl("Ножка", (x, y, 0.58), 0.036, 0.22, "Z", m, coll, segments=24)
    sphere("Баллюстра", (x, y, 0.70), 0.055, m, coll, segments=20)
    cyl("Ножка", (x, y, (0.72 + z_top) / 2), 0.045, z_top - 0.72, "Z", m, coll, segments=24)


def build_island(mats, colls):
    coll = colls["island"]
    m = mats["walnut"]
    for x in (ISL_X0 + 0.06, ISL_X1 - 0.06):
        for y in (ISL_Y0 + 0.06, ISL_Y1 - 0.06):
            turned_leg(x, y, mats, coll)
    box("Корпус острова", (ISL_X0 + 0.04, ISL_Y0 + 0.04, 0.12), (ISL_X1 - 0.04, ISL_Y1 - 0.04, CARCASS_TOP),
        mats["carcass"], coll)
    # филёнчатые панели по всем сторонам; со стороны стульев — глухие, со стороны плиты — дверцы
    front, back = Face("+Y", ISL_Y1, 0.0), Face("-Y", ISL_Y0, 0.0)
    ends = (Face("-X", ISL_X0, 0.0), Face("+X", ISL_X1, 0.0))
    for face in (front, back):
        u0, u1 = ISL_X0 + 0.11, ISL_X1 - 0.11
        for a, b in split_span(u0, u1, (1.0, 1.0, 1.0), gap=0.0):
            walnut_panel(face, a, b, 0.14, CARCASS_TOP - 0.02, mats, coll)
            if face is front:
                knob(face, b - STILE / 2 - 0.01, 0.5, mats, coll)
    for face in ends:
        walnut_panel(face, ISL_Y0 + 0.11, ISL_Y1 - 0.11, 0.14, CARCASS_TOP - 0.02, mats, coll)
    # мраморная столешница с выносом и кронштейны под ним
    box("Столешница острова", (ISL_X0 - 0.06, ISL_Y0 - ISL_OVER, CARCASS_TOP),
        (ISL_X1 + 0.06, ISL_Y1 + 0.06, COUNTER_Z1), mats["marble"], coll, bevel=0.014)
    for x in (ISL_X0 + 0.25, (ISL_X0 + ISL_X1) / 2, ISL_X1 - 0.25):
        frustum("Кронштейн острова", (x - 0.04, x + 0.04, ISL_Y0 - 0.02, ISL_Y0, CARCASS_TOP - 0.24),
                (x - 0.04, x + 0.04, ISL_Y0 - ISL_OVER + 0.03, ISL_Y0, CARCASS_TOP), mats["walnut_z"], coll)
    # стулья: точёные ножки, ореховое сиденье, кожаная подушка
    for x in STOOL_XS:
        y = ISL_Y0 - 0.22
        for dx in (-0.14, 0.14):
            for dy in (-0.14, 0.14):
                cyl("Ножка стула", (x + dx, y + dy, 0.32), 0.018, 0.64, "Z", mats["walnut_z"], coll, segments=12)
                sphere("Баллюстра стула", (x + dx, y + dy, 0.30), 0.03, mats["walnut_z"], coll, segments=12)
        for (ax, ay, bx, by) in ((-0.14, -0.14, 0.14, -0.14), (-0.14, 0.14, 0.14, 0.14),
                                 (-0.14, -0.14, -0.14, 0.14), (0.14, -0.14, 0.14, 0.14)):
            cyl("Проножка", (x + (ax + bx) / 2, y + (ay + by) / 2, 0.22), 0.012, 0.28,
                "X" if ay == by else "Y", mats["walnut_z"], coll, segments=10)
        cyl("Сиденье", (x, y, 0.66), 0.20, 0.04, "Z", mats["walnut"], coll, segments=32)
        cyl("Подушка", (x, y, 0.70), 0.185, 0.04, "Z", mats["leather"], coll, segments=32)
    # ваза с фруктами и хлебная доска — масштаб
    cyl("Ваза", (3.0, 2.55, COUNTER_Z1 + 0.06), 0.16, 0.12, "Z", mats["ceramic"], coll, segments=32)
    for i, (dx, dy) in enumerate(((-0.06, 0.02), (0.05, 0.04), (0.0, -0.05), (0.03, -0.01))):
        sphere("Фрукт", (3.0 + dx, 2.55 + dy, COUNTER_Z1 + 0.15), 0.04, mats["burgundy"] if i % 2 else mats["copper"],
               coll, segments=14)
    box("Доска", (2.05, 2.35, COUNTER_Z1), (2.5, 2.7, COUNTER_Z1 + 0.03), mats["walnut_x"], coll)


def walnut_panel(face, u0, u1, z0, z1, mats, coll):
    m = mats["walnut"] if face.u_axis == "X" else mats["walnut_x"]
    box("Панель рамка", *face.bounds(u0, u1, z0, z1, 0.0, 0.02), m, coll)
    box("Панель поле", *face.bounds(u0 + STILE, u1 - STILE, z0 + STILE, z1 - STILE, -0.004, 0.004),
        mats["walnut_dark"] if "walnut_dark" in mats else m, coll, bevel=0.0)
    inset = 0.03
    box("Филёнка", *face.bounds(u0 + STILE + inset, u1 - STILE - inset, z0 + STILE + inset,
                                z1 - STILE - inset, -0.012, -0.002), m, coll, bevel=0.01)
    g = 0.006
    for lo, hi in (((u0 + STILE, z0 + STILE), (u0 + STILE + g, z1 - STILE)),
                   ((u1 - STILE - g, z0 + STILE), (u1 - STILE, z1 - STILE))):
        box("Бусина", *face.bounds(lo[0], hi[0], lo[1], hi[1], -0.006, 0.0), mats["gold"], coll, bevel=0.0)


def build_dresser(mats, colls):
    coll = colls["dresser"]
    face = Face("-X", ROOM_W, DRESSER_D)
    y0, y1 = DRESSER_Y0, DRESSER_Y1
    plinth_molded(face, y0, y1, mats, coll, depth=DRESSER_D)
    box("Корпус буфета", *face.bounds(y0, y1, PLINTH_H, CARCASS_TOP, FRONT_T, DRESSER_D), mats["carcass"], coll)
    for a, b in split_span(y0 + PILASTER_W, y1 - PILASTER_W, (1.0, 1.0, 1.0), gap=0.0):
        panel_door(face, a, b, PLINTH_H, CARCASS_TOP, mats, coll)
        knob(face, b - STILE / 2 - 0.01, 0.5, mats, coll)
    for a, b in ((y0, y0 + PILASTER_W), (y1 - PILASTER_W, y1)):
        pilaster(face, a, b, 0.0, CARCASS_TOP, DRESSER_D, mats, coll)
    box("Столешница буфета", *face.bounds(y0 - 0.03, y1 + 0.03, CARCASS_TOP, COUNTER_Z1, -0.03, DRESSER_D),
        mats["walnut"], coll, bevel=0.01)
    # верх: открытые полки с тарелками, боковины, карниз
    top_face = Face("-X", ROOM_W, DRESSER_TOP_D)
    z_top = 2.30
    for a, b in ((y0, y0 + 0.03), (y1 - 0.03, y1)):
        box("Боковина буфета", *top_face.bounds(a, b, COUNTER_Z1, z_top, 0.0, DRESSER_TOP_D), mats["ivory"], coll)
    box("Задник буфета", *top_face.bounds(y0, y1, COUNTER_Z1, z_top, DRESSER_TOP_D - 0.012, DRESSER_TOP_D),
        mats["ivory"], coll)
    for z in (1.30, 1.65, 2.00):
        box("Полка буфета", *top_face.bounds(y0 + 0.03, y1 - 0.03, z, z + 0.025, 0.0, DRESSER_TOP_D),
            mats["ivory"], coll)
        n = 4
        for i in range(n):
            py = y0 + 0.03 + (y1 - y0 - 0.06) * (i + 0.5) / n
            cyl("Тарелка", (ROOM_W - 0.06, py, z + 0.025 + 0.125), 0.125, 0.008, "X", mats["ceramic"], coll,
                segments=32).rotation_euler = (0.0, math.radians(80), 0.0)
            cyl("Кайма тарелки", (ROOM_W - 0.062, py, z + 0.025 + 0.125), 0.13, 0.004, "X", mats["gold"], coll,
                segments=32).rotation_euler = (0.0, math.radians(80), 0.0)
    cornice(top_face, y0, y1, z_top, mats, coll)


def build_chandelier(mats, colls):
    coll = colls["lights"]
    cx, cy = CHANDELIER
    z_ring = 2.05
    cyl("Штанга люстры", (cx, cy, (ROOM_H - 0.22 + 2.35) / 2), 0.012, ROOM_H - 0.22 - 2.35, "Z", mats["gold"],
        coll, segments=12)
    sphere("Корпус люстры", (cx, cy, 2.30), 0.07, mats["gold"], coll)
    cyl("Стержень люстры", (cx, cy, (2.30 + z_ring) / 2), 0.02, 2.30 - z_ring, "Z", mats["gold"], coll, segments=12)
    torus("Обод люстры", (cx, cy, z_ring), 0.42, 0.018, mats["gold"], coll)
    torus("Обод люстры малый", (cx, cy, z_ring + 0.12), 0.22, 0.012, mats["gold"], coll)
    sphere("Низ люстры", (cx, cy, z_ring - 0.10), 0.05, mats["gold"], coll)
    for i in range(8):
        a = 2 * math.pi * i / 8
        px, py = cx + 0.42 * math.cos(a), cy + 0.42 * math.sin(a)
        cyl("Спица люстры", ((cx + px) / 2, (cy + py) / 2, z_ring + 0.06), 0.006, 0.42, "X", mats["gold"], coll,
            segments=8).rotation_euler = (0.0, math.radians(90), a)
        cyl("Чашка свечи", (px, py, z_ring + 0.03), 0.028, 0.035, "Z", mats["gold"], coll, segments=16)
        cyl("Свеча", (px, py, z_ring + 0.11), 0.012, 0.13, "Z", mats["candle"], coll, segments=12)
        sphere("Пламя", (px, py, z_ring + 0.20), 0.012, mats["flame"], coll, segments=10)
    return [(cx + 0.42 * math.cos(2 * math.pi * i / 8), cy + 0.42 * math.sin(2 * math.pi * i / 8), z_ring + 0.22)
            for i in range(8)]


def build_sconces(mats, colls):
    coll = colls["lights"]
    spots = []
    for (x, y, facing) in ((ROOM_W, 1.40, "-X"), (ROOM_W, 4.50, "-X"), (1.40, 0.0, "+Y"), (4.00, 0.0, "+Y")):
        face = Face(facing, x if facing == "-X" else y, 0.0)
        u = y if facing == "-X" else x
        z = 1.95
        box("Кронштейн бра", *face.bounds(u - 0.03, u + 0.03, z - 0.10, z, -0.14, 0.0), mats["gold"], coll)
        cyl("Чашка бра", face.point(u, z, -0.13), 0.03, 0.03, "Z", mats["gold"], coll, segments=16)
        cyl("Свеча бра", face.point(u, z + 0.09, -0.13), 0.012, 0.14, "Z", mats["candle"], coll, segments=12)
        sphere("Пламя бра", face.point(u, z + 0.185, -0.13), 0.012, mats["flame"], coll, segments=10)
        spots.append(face.point(u, z + 0.22, -0.13))
    return spots


# --------------------------------------------------------------------------
# Свет и камеры
# --------------------------------------------------------------------------


def build_lighting(colls, flames):
    coll = colls["lights"]

    def area(name, loc, rot, sx, sy, power, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "RECTANGLE"
        data.size, data.size_y = sx, sy
        data.energy = power
        data.color = color
        ob = bpy.data.objects.new(name, data)
        ob.location, ob.rotation_euler = loc, rot
        ob.visible_camera = ob.visible_glossy = ob.visible_transmission = False
        coll.objects.link(ob)

    for cx in WINDOWS_BACK_X:
        area("Свет окна", (cx, ROOM_D + 0.6, 1.9), (math.radians(90), 0.0, 0.0), 1.1, 1.6, 260.0,
             (0.96, 0.97, 1.0))
    area("Свет окна левого", (-0.6, WINDOW_LEFT_Y, 1.9), (0.0, math.radians(-90), 0.0), 1.1, 1.6, 240.0,
         (0.96, 0.97, 1.0))
    sun = bpy.data.lights.new("Солнце", "SUN")
    sun.energy = 2.2
    sun.angle = math.radians(3.0)
    sun.color = (1.0, 0.93, 0.8)
    sun_ob = bpy.data.objects.new("Солнце", sun)
    sun_ob.rotation_euler = (math.radians(52), 0.0, math.radians(205))
    coll.objects.link(sun_ob)
    area("Заполняющий", (ROOM_W / 2, ROOM_D / 2, ROOM_H - 0.3), (0.0, 0.0, 0.0), 3.0, 3.0, 55.0,
         (1.0, 0.92, 0.8))
    for i, (x, y, z) in enumerate(flames):
        data = bpy.data.lights.new("Свеча свет %d" % i, "POINT")
        data.energy = 9.0
        data.color = (1.0, 0.72, 0.42)
        data.shadow_soft_size = 0.03
        ob = bpy.data.objects.new("Свеча свет %d" % i, data)
        ob.location = (x, y, z)
        coll.objects.link(ob)

    world = bpy.data.worlds.new("Окружение")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.66, 0.72, 1.0)
    bg.inputs["Strength"].default_value = 0.45
    bpy.context.scene.world = world


def build_cameras(colls):
    coll = colls["cameras"]
    specs = {
        "overview": ((2.70, 0.28, 1.72), (2.70, 4.80, 1.30), 18),
        "range": ((1.00, 1.30, 1.55), (3.20, 4.60, 1.20), 26),
        "sink": ((2.40, 3.90, 1.50), (0.00, 2.00, 1.15), 26),
        "dresser": ((1.00, 3.70, 1.55), (5.40, 2.80, 1.15), 26),
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
    mats["ivory_shadow"] = principled("Тень эмали", srgb(PALETTE["ivory_shadow"]), roughness=0.4)
    mats["walnut_dark"] = principled("Орех тёмный", srgb(PALETTE["walnut_dark"]), roughness=0.4, coat=0.2)
    mats["glass_dark"] = principled("Стекло духовки", (0.02, 0.02, 0.02), roughness=0.1, coat=0.5)
    colls = {key: collection(title) for key, title in (
        ("room", "01 Помещение"),
        ("base", "02 Нижние модули"),
        ("counter", "03 Столешницы и фартуки"),
        ("wall", "04 Верхние шкафы"),
        ("range", "05 Плита-камин"),
        ("island", "06 Остров"),
        ("dresser", "07 Буфет"),
        ("appliances", "08 Мойка"),
        ("lights", "09 Люстра, бра, свет"),
        ("cameras", "10 Камеры"),
    )}

    # левая линия: окно над мойкой, верхние шкафы по обе стороны от окна
    left = Face("+X", 0.0, BASE_D)
    left_spans = module_spans(LEFT_RUN, LEFT_START)
    sink0, sink1 = find_span(left_spans, "sink")
    l_wall = [(LEFT_START + PILASTER_W, sink0 - 0.03, True),
              (sink1 + 0.03, LEFT_END - PILASTER_W, False)]
    build_run(left, LEFT_RUN, LEFT_START, mats, colls, l_wall)
    cy = (sink0 + sink1) / 2
    hole = (0.08, 0.08 + 0.46, cy - 0.40, cy + 0.40)
    counter_for(left, LEFT_START, LEFT_END, mats, colls["counter"], hole=hole, axes=(0, 1))
    backsplash_for(left, LEFT_START, LEFT_END, WIN_Z0 - 0.07, mats, colls["counter"])
    build_sink(mats, colls["appliances"], hole, cy)

    # дальняя стена: плита посередине, верхние шкафы только над крайними модулями
    back = Face("-Y", ROOM_D, BASE_D)
    back_spans = module_spans(BACK_RUN, BACK_START)
    r0, r1 = find_span(back_spans, "range")
    b_wall = [(BACK_START + PILASTER_W, WINDOWS_BACK_X[0] - WIN_R - 0.22, True),
              (WINDOWS_BACK_X[1] + WIN_R + 0.22, ROOM_W - PILASTER_W, True)]
    build_run(back, BACK_RUN, BACK_START, mats, colls, b_wall)
    counter_for(back, BACK_START, r0, mats, colls["counter"])
    counter_for(back, r1, ROOM_W, mats, colls["counter"])
    backsplash_for(back, BACK_START, r0 - 0.10, WIN_Z0 - 0.07, mats, colls["counter"])
    backsplash_for(back, r1 + 0.10, ROOM_W, WIN_Z0 - 0.07, mats, colls["counter"])

    build_range(back_spans, mats, colls)
    build_island(mats, colls)
    build_dresser(mats, colls)
    build_room(mats, colls)
    flames = build_chandelier(mats, colls) + build_sconces(mats, colls)
    build_lighting(colls, flames)
    return build_cameras(colls)


def build_sink(mats, coll, hole, cy):
    x0, x1, y0, y1 = hole
    t = 0.012
    bottom = COUNTER_Z1 - 0.22
    m = mats["ceramic"]
    box("Дно мойки", (x0, y0, bottom - t), (x1, y1, bottom), m, coll)
    box("Стенка мойки", (x0, y0, bottom), (x0 + t, y1, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x1 - t, y0, bottom), (x1, y1, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x0 + t, y0, bottom), (x1 - t, y0 + t, CARCASS_TOP), m, coll)
    box("Стенка мойки", (x0 + t, y1 - t, bottom), (x1 - t, y1, CARCASS_TOP), m, coll)
    cyl("Слив", ((x0 + x1) / 2, cy, bottom + 0.004), 0.04, 0.008, "Z", mats["gold"], coll)
    # смеситель-мост: две стойки, перемычка, дуга излива
    fx = 0.05
    for dy in (-0.10, 0.10):
        cyl("Стойка смесителя", (fx, cy + dy, COUNTER_Z1 + 0.09), 0.014, 0.18, "Z", mats["gold"], coll, segments=16)
        cyl("Вентиль", (fx, cy + dy, COUNTER_Z1 + 0.20), 0.03, 0.02, "Z", mats["gold"], coll, segments=16)
        for k in range(4):
            a = k * math.pi / 2
            cyl("Крестовина", (fx + 0.03 * math.cos(a), cy + dy + 0.03 * math.sin(a), COUNTER_Z1 + 0.21), 0.005,
                0.06, "X", mats["gold"], coll, segments=8).rotation_euler = (0.0, math.radians(90), a)
    cyl("Перемычка", (fx, cy, COUNTER_Z1 + 0.15), 0.014, 0.20, "Y", mats["gold"], coll, segments=16)
    curve = bpy.data.curves.new("Излив", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.012
    curve.bevel_resolution = 6
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    points = [(fx, cy, COUNTER_Z1 + 0.15), (fx, cy, COUNTER_Z1 + 0.32), (fx + 0.06, cy, COUNTER_Z1 + 0.40),
              (fx + 0.20, cy, COUNTER_Z1 + 0.38), ((x0 + x1) / 2, cy, COUNTER_Z1 + 0.26)]
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("Излив", curve)
    curve.materials.append(mats["gold"])
    coll.objects.link(ob)


def setup_viewport():
    for obj in bpy.data.objects:
        if obj.name.startswith(("Потолок", "Стена передняя", "Стена над входом", "Откос арки входа",
                                "Арка входа", "Косяк входа")):
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
                space.shading.studio_light = "courtyard.exr"
                space.shading.studiolight_intensity = 1.0
                space.overlay.show_extras = False
                space.overlay.show_relationship_lines = False
                space.clip_start = 0.02
                space.clip_end = 300.0
                space.lens = 28.0
                for region in area.regions:
                    if region.type == "WINDOW" and region.data is not None:
                        rv = region.data
                        rv.view_perspective = "PERSP"
                        rv.view_location = (2.7, 2.6, 1.25)
                        rv.view_rotation = Euler((math.radians(76), 0.0, math.radians(-4)), "XYZ").to_quaternion()
                        rv.view_distance = 6.0


def export_glb(path):
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception:
        pass
    for obj in bpy.data.objects:
        skip = obj.type in {"CAMERA", "LIGHT"} or obj.hide_viewport
        obj.select_set(not skip)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    do_render = "--render" in argv
    do_glb = "--glb" in argv
    do_save = "--no-save" not in argv
    samples = 48
    res = (1280, 800)
    names = ["overview", "range", "sink", "dresser"]
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
        path = os.path.join(out_3d, "rich-kitchen-royal.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print("Сохранено: %s" % path)
    if do_glb:
        export_glb(os.path.join(out_3d, "rich-kitchen-royal.glb"))
        print("Экспортировано: rich-kitchen-royal.glb")
    if do_render:
        scene = bpy.context.scene
        for name in names:
            scene.camera = cams[name]
            scene.render.filepath = os.path.join(out_img, "royal-" + name + ".png")
            print("Рендер %s -> %s" % (name, scene.render.filepath))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
