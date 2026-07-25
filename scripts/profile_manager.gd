class_name ProfileManager
extends RefCounted

## Lightweight multi-profile support for one shared device (siblings, a
## classroom set). Deliberately NOT a rewrite of GameState's save format -
## each "profile" is just a full copy of the same save file GameState
## already reads/writes (SAVE_PATH), stored under its own filename. To
## switch profiles: save the current file under the outgoing profile's
## name, copy the incoming profile's file over the live save path, then
## ask GameState to reload from disk (GameState.load_save_data() is a
## public method, already used for other reload flows).

const SAVE_PATH := "user://keys_learning_save.cfg"
const REGISTRY_PATH := "user://profiles.cfg"
const DEFAULT_PROFILE := "Player 1"

static func _profile_file(profile_name: String) -> String:
	return "user://profile_%s.cfg" % profile_name.to_lower().replace(" ", "_")

static func _load_registry() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(REGISTRY_PATH) # ok if this fails - defaults below cover a fresh install
	return cfg

static func _save_registry(cfg: ConfigFile) -> void:
	cfg.save(REGISTRY_PATH)

static func list_profiles() -> Array:
	var cfg := _load_registry()
	var names: Array = cfg.get_value("profiles", "names", [])
	if names.is_empty():
		names = [DEFAULT_PROFILE]
		cfg.set_value("profiles", "names", names)
		cfg.set_value("profiles", "active", DEFAULT_PROFILE)
		_save_registry(cfg)
	return names

static func get_active_profile() -> String:
	var cfg := _load_registry()
	var active: String = cfg.get_value("profiles", "active", "")
	if active == "":
		list_profiles() # ensures the registry gets initialized with a default
		return DEFAULT_PROFILE
	return active

## Copies the CURRENT save file to `profile_name`'s slot, registers it, and
## makes it the active profile. The new profile starts as a fresh copy of
## whatever the previous profile's progress was - this keeps things simple
## and avoids ever generating a save file GameState hasn't produced itself.
static func create_profile(profile_name: String, game_state: GameState) -> void:
	if is_instance_valid(game_state):
		game_state.save_data()
	var cfg := _load_registry()
	var names: Array = cfg.get_value("profiles", "names", [DEFAULT_PROFILE])
	if not names.has(profile_name):
		names.append(profile_name)
	cfg.set_value("profiles", "names", names)
	_save_registry(cfg)

	# Fresh profile: start from a blank save, not a copy of whoever was
	# active - each family member/student should start their own progress.
	# switch_to() below handles this by removing the live save file when
	# the incoming profile has no file of its own yet.
	switch_to(profile_name, game_state)

## Saves the current profile's progress, then loads `profile_name`'s save
## file (if it has one yet) into the live save path and asks GameState to
## re-read from disk.
static func switch_to(profile_name: String, game_state: GameState) -> void:
	if is_instance_valid(game_state):
		game_state.save_data()

	var outgoing := get_active_profile()

	# Archive the outgoing profile's progress under its own filename.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, _profile_file(outgoing))

	# Bring in the incoming profile's file, if one already exists.
	var incoming_file := _profile_file(profile_name)
	if FileAccess.file_exists(incoming_file):
		DirAccess.copy_absolute(incoming_file, SAVE_PATH)
	elif FileAccess.file_exists(SAVE_PATH):
		# Brand-new profile with no save yet - remove the live save file so
		# GameState.load_save_data() starts from defaults instead of
		# inheriting the outgoing profile's progress.
		DirAccess.remove_absolute(SAVE_PATH)

	var cfg := _load_registry()
	cfg.set_value("profiles", "active", profile_name)
	_save_registry(cfg)

	if is_instance_valid(game_state):
		game_state.load_save_data()
