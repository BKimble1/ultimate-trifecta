class_name LoadingTips
extends RefCounted
## Tips for the loading screen (2.2): controls for the device in hand,
## strategy for the role you've been given this round, and general play.
## Every value quoted comes from the round's own rules (RulesConfig), so a
## tip can never contradict the game.

const RUNNER := [
	"Splash the three marked waters in any order: plan the shortest loop back home.",
	"Caught? You keep every splash you've made and you're back in %d seconds.",
	"Nobody can be tagged inside your home dorm. Make for a door when the Night Watch closes in.",
	"Carts can't climb stairs, hedges or low walls. Footpaths are your friend.",
	"Turbo Sneakers give a burst of speed for 3 seconds. Save them for an escape.",
	"A Squeaky Decoy makes footstep noise somewhere else. Toss it, then slip away.",
	"Splash Bombs slow a cart that's chasing you. Aim for the driver's path.",
	"A gentle push on the stick walks quietly: the Night Watch can't hear soft steps.",
	"%d runners home wins it for every runner. Help your team by drawing the chase away.",
	"A splash shows the Night Watch where the water is, never where you are.",
]
const WATCH := [
	"Wait for Tag to light up: a press too early just misses.",
	"Carts are fast on roads. Drive close, hop out and finish on foot.",
	"Splash markers show which water a runner just used. Head them off on the way home.",
	"Runners are safe inside their home dorm. Cut them off before the doors.",
	"Listen for footsteps: the arrows show where a running runner is.",
	"Stop %d runners getting home before the clock runs out to win.",
	"A tagged runner is out for %d seconds. Tag a different runner to stretch the team thin.",
]
const GENERAL := [
	"Pick up gold coins on the paths: each one is yours to keep.",
	"Season XP comes from online rounds and daily challenges. Check the Season Pass for rewards.",
	"Fastest Run and Season Points are on the Rankings board. Finish #1 to design next season's skin!",
	"Invite friends from the lobby: they join your party and play on your team or against you.",
	"Use Quick Chat or type in party chat. Be kind: bad words are bleeped.",
	"Try every role in Practice. It plays the same rules against bots.",
]
const TOUCH := [
	"Move with your left thumb anywhere on the left side; drag the right side to look around.",
	"Tap Jump, then tap again in the air to dive.",
	"Settings › Controls › Edit layout lets you move and resize every button.",
	"Prefer a fixed stick? Switch it in Settings › Controls.",
]
const PAD := [
	"Controllers work everywhere: left stick to move, right stick to look.",
	"Press Jump twice to dive further.",
	"Open the map with the View / Share button to see tonight's waters.",
]
const KEYS := [
	"WASD to move, mouse to look, Space to jump (twice to dive), F to tag, E for carts.",
	"Press M for the full map.",
]


## Tips for this round: role tips first in the mix, then controls, then
## general, interleaved and shuffled with `seed` so each load differs.
static func for_round(role: int, cfg: RulesConfig, device: String, seed_v: int) -> Array[String]:
	var role_tips: Array = WATCH if role == TC.Role.PATROL else RUNNER
	var dev: Array = PAD if device == "gamepad" else (KEYS if device == "keyboard" else TOUCH)
	var out: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pools: Array = [_fill(role_tips, cfg), _fill(dev, cfg), _fill(GENERAL, cfg)]
	for p in pools:
		_shuffle(p, rng)
	var i := 0
	while out.size() < 12:
		var pool: Array = pools[[0, 1, 0, 2][i % 4]]
		if not pool.is_empty():
			out.append(String(pool.pop_front()))
		i += 1
		if pools.all(func(x: Array) -> bool: return x.is_empty()):
			break
	return out


static func _fill(src: Array, cfg: RulesConfig) -> Array:
	var out: Array = []
	for s in src:
		var t := String(s)
		if t.contains("%d runners") or t.contains("Stop %d"):
			t = t % cfg.runners_needed
		elif t.contains("%d seconds"):
			t = t % int(cfg.capture_penalty_s)
		out.append(t)
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
