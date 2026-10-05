"""Pass 9: a small reader for the exported runner.glb (numpy only, no bpy).

It evaluates the asset the way an importer does: the skin's joints and
inverse bind matrices, the joint nodes' rest TRS, the baked animation
channels (linear), and linear-blend skinning with the GLB's own JOINTS_0 /
WEIGHTS_0 (the 4 influences that were actually exported).  fit_check.py
uses it to measure garment fit on the shipped asset rather than on the
Blender scene that produced it.

Axes are glTF's: x = character's right, y = up, z = backward (the
character faces -Z).  rig.py's Blender axes map as (x, z, -y).
"""
import json
import struct

import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def bl_to_gl(p):
    """rig.py (Blender) point -> glTF axes."""
    return np.array([p[0], p[2], -p[1]], dtype=np.float64)


def gl_to_bl(p):
    p = np.asarray(p)
    return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


def quat_to_mat(q):
    """(..., 4) xyzw -> (..., 3, 3)."""
    q = np.asarray(q, dtype=np.float64)
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    m = np.empty(q.shape[:-1] + (3, 3))
    m[..., 0, 0] = 1 - 2 * (y * y + z * z)
    m[..., 0, 1] = 2 * (x * y - z * w)
    m[..., 0, 2] = 2 * (x * z + y * w)
    m[..., 1, 0] = 2 * (x * y + z * w)
    m[..., 1, 1] = 1 - 2 * (x * x + z * z)
    m[..., 1, 2] = 2 * (y * z - x * w)
    m[..., 2, 0] = 2 * (x * z - y * w)
    m[..., 2, 1] = 2 * (y * z + x * w)
    m[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return m


def trs(t, r, s):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(r) * np.asarray(s, dtype=np.float64)[None, :]
    m[:3, 3] = t
    return m


class Glb:
    def __init__(self, path):
        b = open(path, 'rb').read()
        magic, _ver, _length = struct.unpack('<III', b[:12])
        if magic != 0x46546C67:
            raise ValueError('not a GLB: ' + path)
        off = 12
        chunks = {}
        while off < len(b):
            clen, ctype = struct.unpack('<II', b[off:off + 8])
            chunks[ctype] = b[off + 8:off + 8 + clen]
            off += 8 + clen
        self.j = json.loads(chunks[0x4E4F534A])
        self.bin = chunks[0x004E4942]
        j = self.j
        self.nodes = j['nodes']
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get('children', []):
                self.parent[c] = i
        skin = j['skins'][0]
        self.joints = skin['joints']
        self.joint_names = [self.nodes[i]['name'] for i in self.joints]
        self.ibm = self.accessor(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
        self.rest_local = {}
        for i, n in enumerate(self.nodes):
            self.rest_local[i] = (np.array(n.get('translation', [0, 0, 0]), dtype=np.float64),
                                  np.array(n.get('rotation', [0, 0, 0, 1]), dtype=np.float64),
                                  np.array(n.get('scale', [1, 1, 1]), dtype=np.float64))
        # joints in parent-first order
        self.order = []
        seen = set()

        def visit(i):
            if i in seen:
                return
            if i in self.parent:
                visit(self.parent[i])
            seen.add(i)
            self.order.append(i)
        for i in range(len(self.nodes)):
            visit(i)
        self.meshes = {}
        for i, n in enumerate(self.nodes):
            if 'mesh' in n:
                self.meshes[n['name']] = n['mesh']
        self.clips = {a['name']: a for a in j.get('animations', [])}
        self._clip_cache = {}

    # ------------------------------------------------------------ data
    def accessor(self, i):
        a = self.j['accessors'][i]
        bv = self.j['bufferViews'][a['bufferView']]
        dt = np.dtype(_COMP[a['componentType']])
        n = _NCOMP[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0)
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * a['count'], offset=off).reshape(a['count'], stride)
            arr = raw[:, :dt.itemsize * n].copy().view(dt).reshape(a['count'], n)
        else:
            arr = np.frombuffer(self.bin, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
        if a.get('normalized'):
            arr = arr.astype(np.float64) / np.iinfo(dt).max
        return arr

    def mesh(self, name):
        """{'pos', 'nrm', 'joints', 'weights', 'faces'} of a part (all primitives)."""
        m = self.j['meshes'][self.meshes[name]]
        pos, nrm, jnt, wgt, fac = [], [], [], [], []
        base = 0
        for p in m['primitives']:
            at = p['attributes']
            v = self.accessor(at['POSITION']).astype(np.float64)
            pos.append(v)
            nrm.append(self.accessor(at['NORMAL']).astype(np.float64) if 'NORMAL' in at else np.zeros_like(v))
            jnt.append(self.accessor(at['JOINTS_0']).astype(np.int64))
            wgt.append(self.accessor(at['WEIGHTS_0']).astype(np.float64))
            idx = self.accessor(p['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in p else np.arange(len(v)).reshape(-1, 3)
            fac.append(idx + base)
            base += len(v)
        return {'pos': np.concatenate(pos), 'nrm': np.concatenate(nrm), 'joints': np.concatenate(jnt),
                'weights': np.concatenate(wgt), 'faces': np.concatenate(fac)}

    # ------------------------------------------------------------ poses
    def _clip(self, name):
        if name not in self._clip_cache:
            a = self.clips[name]
            ch = []
            t1 = 0.0
            for c in a['channels']:
                s = a['samplers'][c['sampler']]
                times = self.accessor(s['input']).reshape(-1).astype(np.float64)
                vals = self.accessor(s['output']).astype(np.float64)
                ch.append((c['target']['node'], c['target']['path'], times, vals))
                t1 = max(t1, times[-1])
            self._clip_cache[name] = (ch, t1)
        return self._clip_cache[name]

    def clip_length(self, name):
        return self._clip(name)[1]

    def local_pose(self, clip=None, t=0.0):
        """node -> (t, r, s) at clip time t (rest pose without a clip)."""
        loc = {i: [v.copy() for v in self.rest_local[i]] for i in self.rest_local}
        if clip is None:
            return loc
        ch, _ = self._clip(clip)
        for node, path, times, vals in ch:
            k = int(np.searchsorted(times, t, side='right')) - 1
            k = max(0, min(k, len(times) - 1))
            k2 = min(k + 1, len(times) - 1)
            u = 0.0 if k2 == k else (t - times[k]) / (times[k2] - times[k])
            u = min(1.0, max(0.0, u))
            a, b = vals[k], vals[k2]
            if path == 'rotation':
                if np.dot(a, b) < 0:
                    b = -b
                v = a * (1 - u) + b * u
                v /= np.linalg.norm(v)
                loc[node][1] = v
            elif path == 'translation':
                loc[node][0] = a * (1 - u) + b * u
            elif path == 'scale':
                loc[node][2] = a * (1 - u) + b * u
        return loc

    def globals_from_local(self, loc):
        g = {}
        for i in self.order:
            m = trs(*loc[i])
            p = self.parent.get(i)
            g[i] = g[p] @ m if p is not None else m
        return g

    def joint_matrices(self, clip=None, t=0.0, joint_globals=None):
        """(J, 4, 4) skinning matrices: global joint transform x inverse bind.
        joint_globals: optional {joint name: 4x4 global} (a runtime pose)."""
        if joint_globals is None:
            g = self.globals_from_local(self.local_pose(clip, t))
            G = np.stack([g[i] for i in self.joints])
        else:
            G = np.stack([joint_globals[n] for n in self.joint_names])
        return G @ self.ibm


def skin(mesh, jm, idx=None):
    """Linear-blend skinning of mesh vertices (optionally a subset) with joint
    matrices jm (J, 4, 4).  Returns (N, 3)."""
    pos = mesh['pos'] if idx is None else mesh['pos'][idx]
    jnt = mesh['joints'] if idx is None else mesh['joints'][idx]
    wgt = mesh['weights'] if idx is None else mesh['weights'][idx]
    ph = np.concatenate([pos, np.ones((len(pos), 1))], axis=1)
    out = np.zeros((len(pos), 3))
    for k in range(jnt.shape[1]):
        m = jm[jnt[:, k]]                       # (N, 4, 4)
        out += wgt[:, k:k + 1] * np.einsum('nij,nj->ni', m, ph)[:, :3]
    return out
