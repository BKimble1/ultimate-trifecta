# Friends evidence (FINAL_RELEASE_SWEEP)

**Every picture: desktop render (Godot Mobile renderer on llvmpipe, Linux,
Xvfb) with the TEST-DOUBLE service and Game Center stand-in
(`game/src/dev/fake_friends.gd`, fictional players).** Not a device, not
Game Center, not a deployed service, not frame-rate evidence. Each picture is
stamped at the bottom left.

Rendered by `tools/capture_friends.sh` with `FAST=1`: each device's canvas,
point scale (44 pt touch targets) and safe area; the picture has the
canvas's pixels. Before and after use the same scale per device. Converted
to JPEG q85.

| Folder | Device shape | Canvas, point scale, safe area (pt L,T,R,B) |
|---|---|---|
| `se/` | iPhone SE 667×375 pt | 1334×750, 2, none |
| `p14/` | iPhone 14 844×390 pt | 1558×720, 1.846, 47,0,47,21 |
| `pmax/` | Pro Max 926×428 pt | 1558×720, 1.682, 47,0,47,21 |
| `ipad/` | iPad 1024×768 pt | 1280×960, 1.25, 0,24,0,20 |

## Before (baseline `e3c2cd6`, rendered from a checkout of that commit)

| Shot | What |
|---|---|
| `b01_home` | Home: no Friends entry |
| `b02_play_with_friends` | Play with Friends: "Show Game Center friends" |
| `b03_play_with_friends_list` | the old list: names only, no status, no invite (defect F1) |
| `b04_lobby` | party room: Invite opens Apple's sheet, host only (F5) |

## After

| Shot | What |
|---|---|
| `a01_home` | Home: Friends at the top right |
| `a02_panel_home_list` | Friends from Home: sorted Online → In a party → In a round → Offline → unknown; Invite starts a party |
| `a03_panel_row_actions` | a friend's row opened: Report… / Block… (verified profile) |
| `a04_panel_asking` | asking for friends-list access (on iOS Apple's sheet shows over it) |
| `a05_panel_denied` | access off (Settings) |
| `a06_panel_restricted` | friends list restricted (Screen Time) |
| `a07_panel_signed_out` | Game Center signed out |
| `a08_panel_screen_time` | multiplayer off (Screen Time) |
| `a09_panel_status_unavailable` | service unavailable: "Status unavailable", no dots, no service Invite |
| `a10_panel_network` | network failure |
| `a11_panel_empty` | no Game Center friends |
| `a12_panel_loading` | loading |
| `a13_panel_no_game_center` | no Game Center on this device |
| `a14_toast_home` | an invite arrives on Home: small card, right half |
| `a15_play_with_friends` | Play with Friends: the Friends entry |
| `a16_lobby` | party room: Friends in the top bar (every member) |
| `a17_panel_lobby_invited` | in a party: "Invited ✓" after the service confirmed it, "In your party", party code, Invite with Game Center |
| `a18_toast_lobby` | an invite in the party room; a guest's invite names the host's party |
| `a19_panel_invites` | invites waiting, in the drawer (Decline / Accept, time left) |
| `a20_accept_confirm` | Accept while in a party: asks first |
