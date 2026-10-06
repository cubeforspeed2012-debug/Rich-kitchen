"""«Волна» — анимация: поле светящихся столбиков, волны, финал буквами RK.

Запуск:  blender --background --python tools/blender/wave_rk.py -- [ключи]
         python tools/blender/wave_rk.py [ключи]       (при установленном bpy)
Ключи:   --render (видео MP4), --still N (один кадр в PNG), --samples N, --res W H,
         --frames N, --no-save

Сетка 26×26 столбиков. Первые две трети ролика по полю бегут две волны — круговая
от центра и бегущая по диагонали; потом столбики оседают, а те, что образуют RK,
поднимаются. Цвет торца зависит от высоты: низкие — глубокий синий, высокие —
тёплое золото. Камера медленно облетает поле и в конце встаёт против букв.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen import collection, reset_scene, srgb  # noqa: E402

GRID = 26
PITCH = 1.0
SIZE = 0.86
PILLAR_LEN = 8.0
FPS = 24
FRAMES = 168                 # 7 секунд
FORM_START, FORM_END = 104, 140
LOW, HIGH = 0.15, 2.6

# 5×7 пиксельные буквы
LETTERS = {
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
}


def letter_mask():
    """Клетки сетки, из которых складываются буквы RK, по центру поля."""
    cells = set()
    scale = 2
    word = ["R", "K"]
    width = (5 * len(word) + (len(word) - 1)) * scale
    height = 7 * scale
    x0 = (GRID - width) // 2
    y0 = (GRID - height) // 2
    for li, ch in enumerate(word):
        for row, line in enumerate(LETTERS[ch]):
            for col, bit in enumerate(line):
                if bit != "1":
                    continue
                for dx in range(scale):
                    for dy in range(scale):
                        gx = x0 + (li * 6 + col) * scale + dx
                        gy = y0 + (6 - row) * scale + dy
                        cells.add((gx, gy))
    return cells


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def height_at(i, j, f, in_word):
    c = (GRID - 1) / 2
    x, y = (i - c) * PITCH, (j - c) * PITCH
    t = f / FPS
    r = math.hypot(x, y)
    ring = math.sin(r * 0.55 - t * 4.2) * math.exp(-r * 0.04)
    diag = math.sin((x + y) * 0.32 + t * 2.6)
    wave = 0.5 + 0.32 * ring + 0.18 * diag
    wave_h = LOW + (HIGH * 0.75 - LOW) * wave
    target = HIGH if in_word else LOW
    # отложенный старт: буквы проявляются волной от центра
    delay = r * 0.6
    k = smooth((f - FORM_START - delay) / (FORM_END - FORM_START))
    return wave_h * (1 - k) + target * k


def pillar_mesh():
    me = bpy.data.meshes.new("Столбик")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(SIZE, SIZE, PILLAR_LEN), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, -PILLAR_LEN / 2), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.035, segments=2, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    return me


def pillar_material():
    """Бока — тёмный полированный металл, торец светится цветом по высоте."""
    mat = bpy.data.materials.new("Столбик")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    metal = nt.nodes.new("ShaderNodeBsdfPrincipled")
    metal.inputs["Base Color"].default_value = (*srgb("#1A1D24"), 1.0)
    metal.inputs["Metallic"].default_value = 1.0
    metal.inputs["Roughness"].default_value = 0.22
    glow = nt.nodes.new("ShaderNodeEmission")
    info = nt.nodes.new("ShaderNodeObjectInfo")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = LOW
    rng.inputs["From Max"].default_value = HIGH
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (*srgb("#1036A8"), 1.0)
    els[1].position, els[1].color = 1.0, (*srgb("#FFC46B"), 1.0)
    els.new(0.45).color = (*srgb("#19B6E8"), 1.0)
    els.new(0.75).color = (*srgb("#F06AD0"), 1.0)
    nt.links.new(info.outputs["Location"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], glow.inputs["Color"])
    strength = nt.nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY_ADD"
    strength.inputs[1].default_value = 3.0
    strength.inputs[2].default_value = 1.2
    nt.links.new(rng.outputs["Result"], strength.inputs[0])
    nt.links.new(strength.outputs["Value"], glow.inputs["Strength"])
    # маска торца: нормаль смотрит вверх
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nsep = nt.nodes.new("ShaderNodeSeparateXYZ")
    cap = nt.nodes.new("ShaderNodeMapRange")
    cap.inputs["From Min"].default_value = 0.97
    cap.inputs["From Max"].default_value = 0.99
    nt.links.new(geo.outputs["Normal"], nsep.inputs["Vector"])
    nt.links.new(nsep.outputs["Z"], cap.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(cap.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(metal.outputs["BSDF"], mix.inputs[1])
    nt.links.new(glow.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def floor_material():
    mat = bpy.data.materials.new("Пол зеркальный")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.004, 0.005, 0.008, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.12
    return mat


def build():
    reset_scene()
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, FRAMES
    scene.render.fps = FPS
    pillars = collection("01 Столбики")
    stage = collection("02 Сцена")
    cams = collection("03 Камера и свет")

    me = pillar_mesh()
    mat = pillar_material()
    me.materials.append(mat)
    word = letter_mask()
    c = (GRID - 1) / 2
    count = 0
    for i in range(GRID):
        for j in range(GRID):
            ob = bpy.data.objects.new("Столбик %02d-%02d" % (i, j), me)
            ob.location = ((i - c) * PITCH, (j - c) * PITCH, 0.0)
            pillars.objects.link(ob)
            in_word = (i, j) in word
            for f in range(1, FRAMES + 1, 2):
                ob.location.z = height_at(i, j, f, in_word)
                ob.keyframe_insert("location", index=2, frame=f)
            count += 1

    floor = bpy.data.meshes.new("Пол")
    floor.from_pydata([(-200, -200, 0), (200, -200, 0), (200, 200, 0), (-200, 200, 0)], [], [(0, 1, 2, 3)])
    fob = bpy.data.objects.new("Пол", floor)
    fob.location.z = -0.02
    floor.materials.append(floor_material())
    stage.objects.link(fob)

    world = bpy.data.worlds.new("Тьма")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.004, 0.006, 0.012, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world

    # мягкий верхний свет — даёт блики на металле
    data = bpy.data.lights.new("Верхний", "AREA")
    data.size = 18.0
    data.energy = 2500.0
    data.color = (0.75, 0.82, 1.0)
    light = bpy.data.objects.new("Верхний", data)
    light.location = (0, 0, 14)
    light.visible_camera = False
    cams.objects.link(light)

    # камера облетает поле по спирали и в финале встаёт против букв
    cam_data = bpy.data.cameras.new("Камера")
    cam_data.lens = 32
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 2.8
    cam = bpy.data.objects.new("Камера", cam_data)
    cams.objects.link(cam)
    target = bpy.data.objects.new("Цель", None)
    cams.objects.link(target)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    cam_data.dof.focus_object = target
    for f in range(1, FRAMES + 1, 4):
        t = (f - 1) / (FRAMES - 1)
        settle = smooth((f - FORM_START) / (FRAMES - FORM_START))
        ang = math.radians(-35 + 150 * t) * (1 - settle) + math.radians(-90) * settle
        radius = (24 - 6 * t) * (1 - settle) + 17 * settle
        height = (15 - 4 * t) * (1 - settle) + 27 * settle
        cam.location = (radius * math.cos(ang), radius * math.sin(ang), height)
        cam.keyframe_insert("location", frame=f)
        target.location = (0, -1.5 * settle, 0.6 + 1.4 * settle)
        target.keyframe_insert("location", frame=f)
    scene.camera = cam
    return count


def setup_render(samples, res):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.view_settings.look = "AgX - Punchy" if "AgX - Punchy" in [
        i.identifier for i in scene.view_settings.bl_rna.properties["look"].enum_items] else "None"
    scene.render.film_transparent = False


def setup_viewport():
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.shading.type = "RENDERED"
                        space.overlay.show_extras = False
                        for region in area.regions:
                            if region.type == "WINDOW" and region.data is not None:
                                region.data.view_perspective = "CAMERA"


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    samples, res = 24, (1280, 720)
    if "--samples" in argv:
        samples = int(argv[argv.index("--samples") + 1])
    if "--res" in argv:
        i = argv.index("--res")
        res = (int(argv[i + 1]), int(argv[i + 2]))
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.abspath(os.path.join(here, "..", "..", "assets", "3d"))
    os.makedirs(os.path.join(out, "renders"), exist_ok=True)

    n = build()
    scene = bpy.context.scene
    if "--frames" in argv:
        scene.frame_end = int(argv[argv.index("--frames") + 1])
    setup_render(samples, res)
    setup_viewport()
    print("Столбиков: %d, кадров: %d" % (n, scene.frame_end))

    if "--no-save" not in argv:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "wave-rk.blend"), compress=True)
        print("Сохранено: wave-rk.blend")
    if "--still" in argv:
        for f in argv[argv.index("--still") + 1].split(","):
            scene.frame_set(int(f))
            scene.render.image_settings.file_format = "PNG"
            scene.render.filepath = os.path.join(out, "renders", "wave-rk-%s.png" % f)
            bpy.ops.render.render(write_still=True)
    if "--render" in argv:
        if hasattr(scene.render.image_settings, "media_type"):
            scene.render.image_settings.media_type = "VIDEO"
        scene.render.image_settings.file_format = "FFMPEG"
        scene.render.ffmpeg.format = "MPEG4"
        scene.render.ffmpeg.codec = "H264"
        scene.render.ffmpeg.constant_rate_factor = "HIGH"
        scene.render.filepath = os.path.join(out, "renders", "wave-rk.mp4")
        bpy.ops.render.render(animation=True)
        print("Видео: %s" % scene.render.filepath)


if __name__ == "__main__":
    main()
