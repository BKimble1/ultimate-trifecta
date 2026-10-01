class_name RulesConfig
extends Resource
## The single authoritative rule + balance configuration for Trifecta Chase.
## UI text, bots, tests and the simulation all read these values. Tune them in
## res://config/rules_default.tres rather than editing gameplay code.

@export_group("Match")
@export var match_duration_s: float = 240.0
@export var start_countdown_s: float = 3.0
@export var role_reveal_s: float = 4.0
@export var runner_head_start_s: float = 6.0
@export var runner_slots: int = 6
@export var patrol_slots: int = 2
@export var runners_needed: int = 4
@export var targets_per_match: int = 3
@export var results_hold_s: float = 1.5

@export_group("Capture")
@export var capture_penalty_s: float = 6.0
@export var respawn_protect_s: float = 2.0
@export var bump_protect_s: float = 1.0
@export var stumble_s: float = 0.55
@export var splash_marker_s: float = 3.0
@export var splash_sequence_s: float = 1.5

@export_group("Runner movement")
@export var runner_speed: float = 5.0
@export var runner_sprint_speed: float = 7.0
@export var sprint_capacity_s: float = 2.5
@export var sprint_regen_delay_s: float = 0.35
@export var sprint_regen_full_s: float = 3.6
@export var sprint_min_to_start: float = 0.15
@export var ground_accel: float = 46.0
@export var ground_decel: float = 52.0
@export var air_accel: float = 14.0
@export var jump_velocity: float = 6.4
@export var gravity: float = 19.0
@export var max_fall_speed: float = 30.0
@export var coyote_time_s: float = 0.12
@export var jump_buffer_s: float = 0.13
@export var dive_speed: float = 8.6
@export var dive_up_velocity: float = 2.4
@export var dive_land_s: float = 0.32
@export var sneak_input_threshold: float = 0.5
@export var turn_rate_deg: float = 900.0

@export_group("Patrol on foot")
@export var patrol_speed: float = 6.2
@export var patrol_jump_velocity: float = 6.0
@export var tag_anticipation_s: float = 0.14
@export var tag_anticipation_move_scale: float = 0.6   # foot speed kept during the wind-up
@export var tag_lunge_s: float = 0.22
@export var tag_lunge_speed: float = 8.2
@export var tag_reach_m: float = 1.6
@export var tag_half_angle_deg: float = 75.0
@export var tag_vertical_reach_m: float = 1.5
@export var tag_miss_cooldown_s: float = 0.9
@export var tag_hit_recover_s: float = 0.5
@export var tag_lag_comp_max_s: float = 0.15
@export var tag_lag_comp_slack_m: float = 0.9
@export var cart_exit_tag_lockout_s: float = 0.5

@export_group("Carts")
@export var cart_count: int = 2
@export var cart_max_speed_road: float = 11.0
@export var cart_max_speed_offroad: float = 6.5
@export var cart_accel: float = 6.8
@export var cart_brake: float = 16.0
@export var cart_reverse_max: float = 4.0
@export var cart_coast_drag: float = 2.2
@export var cart_turn_radius_slow: float = 3.2
@export var cart_turn_radius_fast: float = 9.5
@export var cart_enter_range_m: float = 2.4
@export var cart_enter_max_speed: float = 3.0
@export var cart_exit_max_speed: float = 2.5
@export var cart_exit_auto_brake: float = 20.0
@export var cart_enter_s: float = 0.35
@export var cart_exit_s: float = 0.3
@export var cart_bump_min_speed: float = 2.5
@export var cart_bump_knockback_max: float = 6.0
@export var cart_bump_speed_keep: float = 0.55
@export var cart_wall_speed_keep: float = 0.35

@export_group("Gadgets")
@export var gadgets_enabled: PackedStringArray = PackedStringArray(["turbo", "decoy", "splash_bomb"])
@export var gadget_use_cooldown_s: float = 1.0
@export var gadget_respawn_s: float = 25.0
@export var gadget_pickup_radius_m: float = 1.4
@export var turbo_duration_s: float = 3.0
@export var turbo_multiplier: float = 1.25
@export var turbo_speed_cap: float = 8.0
@export var decoy_range_m: float = 9.0
@export var decoy_duration_s: float = 5.0
@export var decoy_step_speed: float = 4.5
@export var bomb_range_m: float = 11.0
@export var bomb_assist_cone_deg: float = 35.0
@export var bomb_assist_range_m: float = 15.0
@export var bomb_radius_m: float = 3.4
@export var bomb_slow_s: float = 2.0
@export var bomb_slow_max_speed: float = 4.0
@export var bomb_immunity_s: float = 2.5
@export var toss_flight_s: float = 0.6

@export_group("Detection and cues")
@export var view_range_m: float = 34.0
@export var view_half_fov_deg: float = 62.0
@export var spotted_hold_s: float = 2.2
@export var noise_sprint_m: float = 24.0
@export var noise_jog_m: float = 14.0
@export var noise_patrol_step_m: float = 12.0
@export var noise_cart_m: float = 45.0

@export_group("Networking")
@export var sim_hz: int = 60
@export var snapshot_every_ticks: int = 3
@export var interp_delay_s: float = 0.1
@export var disconnect_reserve_s: float = 20.0
@export var host_timeout_s: float = 6.0

@export_group("Rewards")
@export var coins_participation: int = 20
@export var coins_per_stamp: int = 5
@export var coins_finish: int = 15
@export var coins_team_win: int = 15
@export var coins_unique_capture: int = 10
@export var coins_fastest_trifecta: int = 10
@export var practice_reward_scale: float = 0.5
@export var level_xp_base: int = 120
@export var level_xp_growth: float = 1.15


func ticks(seconds: float) -> int:
	return int(round(seconds * float(sim_hz)))


func dt() -> float:
	return 1.0 / float(sim_hz)


func roster_size() -> int:
	return runner_slots + patrol_slots
