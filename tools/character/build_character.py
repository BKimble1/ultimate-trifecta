"""Build the Ultimate Trifecta runner character (skinned glTF) with Blender's bpy.

    tools/character/build.sh            # wraps the call below
    tools/.cache/bpyenv/bin/python tools/character/build_character.py [out.glb]

Output (default): game/assets/characters/runner.glb plus runner_manifest.json.
Everything is generated from the Python sources in this folder (geo.py,
rig.py, parts.py, anims.py), which are the editable source of the asset.
The build is deterministic: the same sources give the same GLB.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector, Quaternion  # noqa: E402

import geo  # noqa: E402
import rig  # noqa: E402
import parts  # noqa: E402
import anims  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = sys.argv[-1] if sys.argv[-1].endswith('.glb') else os.path.join(REPO, 'game', 'assets', 'characters', 'runner.glb')


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.fps = anims.FPS
    scn.frame_start = 0
    return scn


def build_armature(scn):
    arm = bpy.data.armatures.new('RunnerRig')
    ob = bpy.data.objects.new('Runner', arm)
    scn.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    table = rig.bone_table()
    for name, (h, t, parent) in table.items():
        eb = arm.edit_bones.new(name)
        eb.head = h
        eb.tail = t
        # deterministic roll: local Z faces forward (+Y) for vertical bones,
        # up (+Z) for bones that lie forward
        d = (t - h).normalized()
        ref = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((0, 0, 1))
        eb.align_roll(ref)
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in ob.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return ob


def make_mesh(mb, arm_ob, scn):
    me = bpy.data.meshes.new(mb.name)
    me.from_pydata([tuple(v) for v in mb.v], [], mb.f)
    me.validate(clean_customdata=False)
    nloops = len(me.loops)
    col = me.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
    uv0 = me.uv_layers.new(name='UVMap')
    uv1 = me.uv_layers.new(name='UVData')
    cols = [0.0] * (nloops * 4)
    uvs0 = [0.0] * (nloops * 2)
    uvs1 = [0.0] * (nloops * 2)
    for li, loop in enumerate(me.loops):
        vi = loop.vertex_index
        c = mb.col[vi]
        cols[li * 4:li * 4 + 4] = [c[0], c[1], c[2], c[3]]
        uvs0[li * 2:li * 2 + 2] = [mb.uv[vi][0], mb.uv[vi][1]]
        uvs1[li * 2:li * 2 + 2] = [mb.uv2[vi][0], mb.uv2[vi][1]]
    # color_srgb takes sRGB input; Blender stores it and the glTF exporter writes linear
    for li in range(nloops):
        col.data[li].color_srgb = cols[li * 4:li * 4 + 4]
    uv0.data.foreach_set('uv', uvs0)
    uv1.data.foreach_set('uv', uvs1)
    me.color_attributes.active_color = col
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.get('character') or bpy.data.materials.new('character')
    me.materials.append(mat)
    ob = bpy.data.objects.new(mb.name, me)
    scn.collection.objects.link(ob)
    ob.parent = arm_ob
    # weights
    groups = {}
    for vi, w in enumerate(mb.w):
        # keep the 4 strongest influences, renormalise
        items = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(v for _, v in items) or 1.0
        for bname, val in items:
            if val / tot < 1e-3:
                continue
            g = groups.get(bname)
            if g is None:
                g = ob.vertex_groups.new(name=bname)
                groups[bname] = g
            g.add([vi], val / tot, 'REPLACE')
    mod = ob.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm_ob
    return ob


def shape_keys(ob, mb):
    """Face shapes on the base mesh: blink, squint (happy ^^), smile, open,
    brow_up, brow_angry.  Only tagged face vertices move."""
    ob.shape_key_add(name='Basis', from_mix=False)
    shapes = {}
    for name in ('blink', 'squint', 'smile', 'open', 'brow_up', 'brow_angry'):
        shapes[name] = ob.shape_key_add(name=name, from_mix=False)
    basis = [v.co.copy() for v in ob.data.vertices]
    # neutral mouth = closed smile line: bake that into the basis first
    for vi, tag in enumerate(mb.tag):
        if tag in ('mouth', 'tongue'):
            c, side, up, n, _ = mb.aux[vi]
            d = basis[vi] - c
            sx, uy, nz = d.dot(side), d.dot(up), d.dot(n)
            if tag == 'mouth':
                nb = c + side * (sx * 0.95) + up * (uy * 0.28 + 0.010 * (sx / 0.042) ** 2) + n * nz
            else:
                nb = c + side * (sx * 0.3) + up * (uy * 0.3 - 0.004) + n * (nz - 0.006)
            basis[vi] = nb
    for vi in range(len(basis)):
        ob.data.vertices[vi].co = basis[vi]
        ob.data.shape_keys.key_blocks['Basis'].data[vi].co = basis[vi]
    for name, sk in shapes.items():
        for vi in range(len(basis)):
            sk.data[vi].co = basis[vi]
    for vi, tag in enumerate(mb.tag):
        if not tag:
            continue
        b = basis[vi]
        if tag in ('eyeL', 'eyeR'):
            c, side, up, n, sx_sign = mb.aux[vi]
            d = b - c
            sx, uy, nz = d.dot(side), d.dot(up), d.dot(n)
            # blink: everything collapses onto a slightly lowered lid line
            shapes['blink'].data[vi].co = c + side * sx + up * (uy * 0.08 - 0.012) + n * (nz * 0.7)
            # squint: happy arch
            arch = 0.016 * (1.0 - min(1.0, (sx / 0.046) ** 2))
            shapes['squint'].data[vi].co = c + side * sx + up * (uy * 0.2 + arch - 0.004) + n * (nz * 0.75)
        elif tag in ('browL', 'browR'):
            c, along, up, n, sx_sign = mb.aux[vi]
            d = b - c
            a = d.dot(along) * sx_sign  # + toward the outer end
            shapes['brow_up'].data[vi].co = b + up * 0.022
            inner = max(-1.0, min(1.0, -a / 0.045))
            shapes["brow_angry"].data[vi].co = b + up * (-0.012 * inner + 0.004)
        elif tag in ('mouth', 'tongue'):
            c, side, up, n, _ = mb.aux[vi]
            # use the *original* (unbaked) layout for open/smile
            d = mb.v[vi] - c
            sx, uy, nz = d.dot(side), d.dot(up), d.dot(n)
            if tag == 'mouth':
                top = uy > 0
                o_uy = (uy * 0.2 if top else uy * 1.35) + 0.004 * (sx / 0.042) ** 2
                shapes['open'].data[vi].co = c + side * (sx * 0.86) + up * o_uy + n * nz
                shapes['smile'].data[vi].co = c + side * (sx * 1.16) + up * (uy * 0.42 + 0.02 * (sx / 0.042) ** 2) + n * nz
            else:
                shapes['open'].data[vi].co = c + side * sx + up * (uy - 0.006) + n * (nz + 0.001)
                shapes['smile'].data[vi].co = b
    return shapes


def bake_actions(arm_ob, scn):
    lib = anims.library()
    R = anims.Rig(arm_ob)
    bones = list(R.order)
    made = []
    for name, (length, loop, fn) in lib.items():
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm_ob.animation_data_create()
        arm_ob.animation_data.action = act
        nframes = max(2, int(round(length * anims.FPS)))
        prev = {}
        last = nframes if not loop else nframes  # loops: key frame N equals frame 0
        for f in range(0, last + 1):
            t = min(length, f / anims.FPS) if not loop else (f / anims.FPS) % length if f < nframes else 0.0
            pose = fn(t)
            L = R.evaluate(pose)
            for bn in bones:
                pb = arm_ob.pose.bones[bn]
                q, loc = L.get(bn, [Quaternion(), Vector()])
                q = q.normalized()
                if bn in prev and prev[bn].dot(q) < 0:
                    q = -q
                prev[bn] = q
                pb.rotation_quaternion = q
                pb.location = loc
                pb.keyframe_insert('rotation_quaternion', frame=f)
                if bn in ('hips', 'root'):
                    pb.keyframe_insert('location', frame=f)
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
        # stash on the NLA so the exporter sees every action
        tr = arm_ob.animation_data.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 0, act)
        tr.mute = True
        arm_ob.animation_data.action = None
        made.append((name, length, loop))
    # rest pose
    for pb in arm_ob.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    return made


def main():
    scn = reset()
    arm_ob = build_armature(scn)
    meshes = {}
    stats = {}
    for fn in parts.ALL_PARTS:
        mb = fn()
        ob = make_mesh(mb, arm_ob, scn)
        if mb.name == 'base':
            shape_keys(ob, mb)
        meshes[mb.name] = ob
        stats[mb.name] = {'verts': len(mb.v), 'tris': sum(len(f) - 2 for f in mb.f)}
    clips = bake_actions(arm_ob, scn)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format='GLB', export_yup=True, export_apply=False,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_frame_range=False, export_anim_single_armature=True, export_reset_pose_bones=True,
        export_morph=True, export_morph_normal=False, export_skins=True, export_all_influences=False,
        export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_texcoords=True, export_normals=True,
        export_tangents=False, export_materials='EXPORT', export_extras=False, export_cameras=False, export_lights=False,
        export_def_bones=False, export_optimize_animation_size=False, export_bake_animation=False)
    manifest = {
        'source': 'tools/character/build_character.py (Blender %s)' % bpy.app.version_string,
        'forward': 'Godot -Z (glTF -Z); built facing Blender +Y',
        'height_m': 1.5,
        'meshes': stats,
        'clips': {n: {'length': round(L, 4), 'loop': lp} for n, L, lp in clips},
        'loco_m_per_cycle': {k: v['speed'] for k, v in anims.LOCO.items()},
        'bones': list(rig.bone_table().keys()),
        'shape_keys': ['blink', 'squint', 'smile', 'open', 'brow_up', 'brow_angry'],
    }
    with open(os.path.splitext(OUT)[0] + '_manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    tot = sum(s['tris'] for s in stats.values())
    print('BUILT', OUT, 'meshes', len(stats), 'tris(all parts)', tot, 'clips', len(clips))
    for k, s in stats.items():
        print('  %-16s %6d verts %6d tris' % (k, s['verts'], s['tris']))


if __name__ == '__main__':
    main()
