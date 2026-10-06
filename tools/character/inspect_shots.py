"""Final sweep (ARTFIX): shot lists for inspecting the whole outfit catalogue
at the Season Pass / Shop / Locker stage's scale, for
src/dev/character_lineup.tscn --lineup=custom --light=dorm.

    python3 tools/character/inspect_shots.py OUT_DIR

writes OUT_DIR/<sheet>.json, one shot list per sheet:
  outfits_<n>.json  every outfit (and the Night Watch) full height from the
                    front, three-quarter, both profiles and the back, at
                    about the stage's on-screen size (a 900 px tall tile:
                    the figure is ~700 px, as on a 3x phone's stage)
  hats.json         every hat on its head from the same five sides
  zoom.json         the close-ups of the ARTFIX defects (profile and back,
                    same cameras before and after)
  bands.json        each band worn round the head with each hair style,
                    from the three-quarter back and the back

tools/character/capture_inspection.sh renders them.  Cameras are fixed per
view (world space; the dorm lineup's stage stands at z 0.5), so the same file
renders the same frames from any asset.
"""
import json
import os
import sys

STAGE_Z = 0.5
# yaw (degrees from facing the camera): front, three-quarter, the character's
# left profile, the back, the right profile
VIEWS = [('front', 0.0), ('3/4', 35.0), ('side L', 90.0), ('back', 180.0), ('side R', -90.0)]

# the Shop's showcase looks (character_lineup.gd SHOWCASE / P8_SHOWCASE), so
# the inspection shows the outfits as players see them on sale
SHOWCASE = {
    'pj': {'shoes': 'slippers', 'hair': 'tuft', 'hair_color': 'brown', 'skin': 'tone2', 'color': 'sky', 'pattern': 'stripes'},
    'swim': {'shoes': 'flippers', 'hair': 'bob', 'hair_color': 'black', 'skin': 'tone5', 'color': 'teal'},
    'robe': {'shoes': 'slippers', 'hair': 'curly', 'hair_color': 'black', 'skin': 'tone7', 'color': 'grape'},
    'duck': {'shoes': 'slippers', 'skin': 'tone3'},
    'frog': {'shoes': 'slippers', 'skin': 'tone6'},
    'moonlight_runner': {'shoes': 'sneakers', 'hair': 'tuft', 'hair_color': 'dark_brown', 'skin': 'tone5', 'color': 'navy'},
    'starry_sleeper': {'shoes': 'slippers', 'hair': 'bob', 'hair_color': 'black', 'skin': 'tone3', 'color': 'grape'},
    'varsity_sprinter': {'shoes': 'sneakers', 'hair': 'curly', 'hair_color': 'black', 'skin': 'tone7', 'color': 'coral'},
    'raincoat_explorer': {'shoes': 'sneakers', 'hair': 'buns', 'hair_color': 'ginger', 'skin': 'tone2', 'color': 'sunny'},
    'campus_courier': {'shoes': 'sneakers', 'hair': 'tuft', 'hair_color': 'brown', 'skin': 'tone6', 'color': 'sunny'},
    'lantern_scout': {'shoes': 'sneakers', 'hair': 'bob', 'hair_color': 'auburn', 'skin': 'tone4', 'color': 'lime'},
    'after_hours_hoodie': {'shoes': 'glow_sneakers', 'hair': 'curly', 'hair_color': 'espresso', 'skin': 'tone8', 'color': 'plum'},
    'night_owl': {'shoes': 'slippers', 'hair': 'tuft', 'hair_color': 'brown', 'skin': 'tone1', 'color': 'tangerine'},
    'glow_jogger': {'shoes': 'glow_sneakers', 'hair': 'buns', 'hair_color': 'black', 'skin': 'tone6', 'color': 'mint',
                    'hat': 'headlamp'},
    'library_cardigan': {'shoes': 'moon_boots', 'hair': 'bob', 'hair_color': 'blonde', 'skin': 'tone3', 'color': 'sunny',
                         'hat': 'pompom_beanie'},
    'midnight_mechanic': {'hair': 'tuft', 'hair_color': 'dark_brown', 'skin': 'tone5', 'color': 'sunny'},
    'moonwalk_cadet': {'hair': 'bob', 'hair_color': 'black', 'skin': 'tone2', 'color': 'teal'},
    'pumpkin_pajamas': {'hair': 'curly', 'hair_color': 'auburn', 'skin': 'tone3', 'color': 'tangerine'},
    'arcade_sprinter': {'hair': 'buns', 'hair_color': 'black', 'skin': 'tone7', 'color': 'bubblegum'},
    'cloud_nine': {'hair': 'bob', 'hair_color': 'blonde', 'skin': 'tone4', 'color': 'sky'},
    'bedtime_bandit': {'hair': 'tuft', 'hair_color': 'espresso', 'skin': 'tone8', 'color': 'grape'},
    'record_breaker': {},
    'dr_doom': {},
}
HATS = ['nightcap', 'swimcap', 'party', 'headphones', 'crown', 'headlamp', 'pompom_beanie', 'glow_headband', 'owl_ears']
HAT_HAIR = {'swimcap': 'tuft', 'headphones': 'curly', 'crown': 'buns', 'headlamp': 'curly', 'pompom_beanie': 'bob',
            'glow_headband': 'tuft', 'owl_ears': 'bob', 'party': 'buns', 'nightcap': 'tuft'}


def full(label, look, yaw, role=0):
    s = {'label': label, 'look': look, 'yaw_deg': yaw, 'from': [0.0, 0.95, STAGE_Z + 3.7], 'at': [0.0, 0.83, STAGE_Z], 'fov': 30.0,
         'cols': 5}
    if role:
        s['role'] = role
    return s


def outfit_sheets():
    keys = list(SHOWCASE)
    sheets = {}
    per = 4
    rows = [(k, dict(SHOWCASE[k], outfit=k, **({} if 'hat' in SHOWCASE[k] else {'hat': 'none'}))) for k in keys]
    rows.append(('night_watch', {'color': 'sky', 'skin': 'tone7'}))
    for n in range(0, len(rows), per):
        shots = []
        for k, look in rows[n:n + per]:
            for vname, yaw in VIEWS:
                shots.append(full('%s (%s)' % (k, vname), look, yaw, role=1 if k == 'night_watch' else 0))
        sheets['outfits_%d' % (n // per + 1)] = shots
    return sheets


def hat_sheet():
    shots = []
    for h in HATS:
        look = {'outfit': 'pj', 'pattern': 'plain', 'color': 'teal', 'hat': h, 'hair': HAT_HAIR[h], 'hair_color': 'brown',
                'skin': 'tone4'}
        for vname, yaw in VIEWS:
            shots.append({'label': '%s (%s)' % (h, vname), 'look': look, 'yaw_deg': yaw, 'from': [0.0, 1.32, STAGE_Z + 1.9],
                          'at': [0.0, 1.22, STAGE_Z], 'fov': 30.0, 'cols': 5})
    return shots


# the ARTFIX close-ups (world cameras; the same frames in every tree): the
# body from the hips to the crown, and the head
BODY = ([0.0, 0.98, STAGE_Z + 2.3], [0.0, 0.93, STAGE_Z])
HEAD = ([0.0, 1.22, STAGE_Z + 1.25], [0.0, 1.17, STAGE_Z])


def zoom_sheet():
    owl = dict(SHOWCASE['night_owl'], outfit='night_owl', hat='none')
    bandit = dict(SHOWCASE['bedtime_bandit'], outfit='bedtime_bandit', hat='none')
    cloud = dict(SHOWCASE['cloud_nine'], outfit='cloud_nine', hat='none')
    duck = dict(SHOWCASE['duck'], outfit='duck', hat='none')
    doom = {'outfit': 'dr_doom'}
    jog = dict(SHOWCASE['glow_jogger'], outfit='glow_jogger', hat='headlamp')
    rows = [
        ('night_owl', owl, [('side L', 90.0, BODY), ('side R', -90.0, BODY), ('back', 180.0, BODY), ('head side L', 90.0, HEAD)]),
        ('bedtime_bandit', bandit, [('side L', 90.0, BODY), ('side R', -90.0, BODY), ('back', 180.0, BODY), ('head side L', 90.0, HEAD)]),
        ('cloud_nine', cloud, [('side L', 90.0, BODY), ('side R', -90.0, BODY), ('back', 180.0, BODY), ('head side L', 90.0, HEAD)]),
        ('duck', duck, [('side L', 90.0, BODY), ('side R', -90.0, BODY), ('back', 180.0, BODY), ('head side L', 90.0, HEAD)]),
        ('dr_doom', doom, [('side L', 90.0, BODY), ('side R', -90.0, BODY), ('3/4 back', 145.0, BODY), ('back', 180.0, BODY)]),
        ('glow_jogger + headlamp', jog, [('side L', 90.0, HEAD), ('3/4 back', 145.0, HEAD), ('back', 180.0, HEAD), ('side R', -90.0, HEAD)]),
    ]
    shots = []
    for name, look, views in rows:
        for vname, yaw, cam in views:
            shots.append({'label': '%s (%s)' % (name, vname), 'look': look, 'yaw_deg': yaw, 'from': cam[0], 'at': cam[1], 'fov': 30.0,
                          'cols': 4})
    return shots


def bands_sheet():
    """Every band worn round the head (the headlamp, the glow headband, the
    owl ears' band, the sleep mask's strap) with each hair style, from the
    three-quarter back and the back: the bands lie on the thinner styles
    and press into the bob, so both ends of that range are in view."""
    looks = [('headlamp', {'outfit': 'pj', 'pattern': 'plain', 'color': 'teal', 'hat': 'headlamp'}),
             ('glow_headband', {'outfit': 'pj', 'pattern': 'plain', 'color': 'teal', 'hat': 'glow_headband'}),
             ('owl_ears', {'outfit': 'pj', 'pattern': 'plain', 'color': 'teal', 'hat': 'owl_ears'}),
             ('sleep mask', dict(SHOWCASE['starry_sleeper'], outfit='starry_sleeper', hat='none'))]
    shots = []
    for name, look in looks:
        for vname, yaw in (('3/4 back', 145.0), ('back', 180.0)):
            for hair in ('tuft', 'bob', 'curly', 'buns'):
                lk = dict(look, hair=hair, hair_color=look.get('hair_color', 'brown'), skin=look.get('skin', 'tone4'))
                shots.append({'label': '%s + %s (%s)' % (name, hair, vname), 'look': lk, 'yaw_deg': yaw, 'from': HEAD[0],
                              'at': HEAD[1], 'fov': 30.0, 'cols': 4})
    return shots


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    sheets = outfit_sheets()
    sheets['hats'] = hat_sheet()
    sheets['zoom'] = zoom_sheet()
    sheets['bands'] = bands_sheet()
    for k, v in sheets.items():
        with open(os.path.join(out, k + '.json'), 'w') as f:
            json.dump(v, f, indent=1)
    print(' '.join(sorted(sheets)))


if __name__ == '__main__':
    main()
