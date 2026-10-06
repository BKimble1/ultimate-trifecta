extends RefCounted
## The campus rebuild changes the place, not the game: the movement,
## capsule, tag, cart, round and network rules are pinned here at the values
## of the 2.0 release candidate (b3e5d74), and the files that define them
## must not change in this pass (docs/campus/INVARIANTS.md).  A failure here
## means a gameplay rule moved: that is out of scope for the rebuild.
var t

const RULES := {
	"match_duration_s": 240.0, "start_countdown_s": 3.0, "role_reveal_s": 4.0, "runner_head_start_s": 6.0,
	"runner_slots": 6, "patrol_slots": 2, "targets_per_match": 3,
	"capture_penalty_s": 6.0, "respawn_protect_s": 2.0, "bump_protect_s": 1.0, "stumble_s": 0.55,
	"splash_marker_s": 3.0, "splash_sequence_s": 1.5,
	"runner_speed": 6.0, "fast_fraction": 0.85, "ground_accel": 46.0, "ground_decel": 52.0, "air_accel": 14.0,
	"jump_velocity": 6.4, "gravity": 19.0, "max_fall_speed": 30.0, "coyote_time_s": 0.12, "jump_buffer_s": 0.13,
	"dive_speed": 8.0, "dive_up_velocity": 2.4, "dive_land_s": 0.45, "turn_rate_deg": 900.0,
	"patrol_speed": 6.6, "patrol_jump_velocity": 6.0,
	"tag_anticipation_s": 0.14, "tag_lunge_s": 0.22, "tag_lunge_speed": 9.0, "tag_reach_m": 1.6,
	"tag_half_angle_deg": 75.0, "tag_vertical_reach_m": 1.5, "tag_miss_cooldown_s": 0.9,
	"cart_count": 2, "cart_max_speed_road": 11.0, "cart_max_speed_offroad": 6.5, "cart_accel": 6.8,
	"turbo_multiplier": 1.25, "turbo_speed_cap": 8.0, "coin_spawns_per_round": 8,
	"view_range_m": 34.0, "sim_hz": 60, "snapshot_every_ticks": 3,
}


func test_rules_are_the_release_candidates() -> void:
	var cfg: RulesConfig = load("res://config/rules_default.tres")
	var fresh := RulesConfig.new()
	for k in RULES:
		t.check(is_equal_approx(float(cfg.get(k)), float(RULES[k])), "shipped rule %s = %s" % [k, str(RULES[k])])
		t.check(is_equal_approx(float(fresh.get(k)), float(RULES[k])), "default rule %s = %s" % [k, str(RULES[k])])


func test_capsule_and_floor_are_unchanged() -> void:
	t.eq(Motor.CHAR_RADIUS, 0.35, "capsule radius")
	t.eq(Motor.CHAR_HEIGHT, 1.5, "capsule height")
	t.eq(Motor.FLOOR_SNAP, 0.35, "floor snap")
	var b := Motor.make_character_body("probe")
	t.check(is_equal_approx(b.floor_max_angle, deg_to_rad(50.0)), "walkable slope 50 degrees")
	t.check(is_equal_approx(b.safe_margin, 0.02), "safe margin")
	t.eq(b.max_slides, 5, "slides per step")
	b.free()
