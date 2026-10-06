"""Reference-campus coordinate frame (shared by every campus tool).

World frame: metres, +x = grid east, +z = grid south (north is -Z, as the
game has always used), y = up.  It is a local offset of NAD83 / UTM zone 16N
(EPSG:26916):

    x = E - E0        z = N0 - N

Grid north (UTM) is used as the game's north; true north differs by under a
degree here and is ignored everywhere.  The research imagery lives OUTSIDE
this repository (CAMPUS_REF, default /home/user/campus_ref/
Ultimate_Trifecta_Campus_Pack): it is private reference material and must
never be copied into game/ or shipped.
"""
import json
import os

E0 = 627300.0
N0 = 4479400.0

REF = os.environ.get("CAMPUS_REF", "/home/user/campus_ref/Ultimate_Trifecta_Campus_Pack")


def to_local(e, n):
    return (e - E0, N0 - n)


def to_utm(x, z):
    return (x + E0, N0 - z)


class Raster:
    """A georeferenced aerial (JPEG + metadata JSON from the pack)."""

    def __init__(self, name="aerial_campus"):
        meta = json.load(open(os.path.join(REF, "maps", name + "_metadata.json")))
        ext = meta["response"]["extent"]
        self.path = os.path.join(REF, "maps", name + ".jpg")
        self.w = meta["response"]["width"]
        self.h = meta["response"]["height"]
        self.xmin, self.ymin = ext["xmin"], ext["ymin"]
        self.xmax, self.ymax = ext["xmax"], ext["ymax"]
        self.sx = (self.xmax - self.xmin) / self.w
        self.sy = (self.ymax - self.ymin) / self.h
        self._img = None

    def image(self):
        if self._img is None:
            from PIL import Image
            Image.MAX_IMAGE_PIXELS = None
            self._img = Image.open(self.path).convert("RGB")
        return self._img

    # continuous image-edge coordinates (no 0.5 pixel-centre offset)
    def px(self, x, z):
        e, n = to_utm(x, z)
        return ((e - self.xmin) / self.sx, (self.ymax - n) / self.sy)

    def local(self, p, q):
        return to_local(self.xmin + p * self.sx, self.ymax - q * self.sy)

    def bounds_local(self):
        x0, z0 = self.local(0, 0)
        x1, z1 = self.local(self.w, self.h)
        return (x0, z0, x1, z1)
