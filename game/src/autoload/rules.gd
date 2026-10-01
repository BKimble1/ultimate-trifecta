extends Node
## Global access to the authoritative RulesConfig.

const DEFAULT_PATH := "res://config/rules_default.tres"

var cfg: RulesConfig


func _init() -> void:
	cfg = load(DEFAULT_PATH) as RulesConfig
	if cfg == null:
		push_error("Rules config missing; using script defaults")
		cfg = RulesConfig.new()
