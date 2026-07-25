class_name AudioManager
extends Node

signal music_track_changed(index: int)
signal volume_changed(kind: String, value: float)
signal mute_changed(muted: bool)

# --- PROFESSIONAL CONFIGURATION ---
const POOL_SIZE := 4             # How many simultaneous sounds of the same type can play
const FADE_TIME := 0.5           # Fade duration for starting/stopping music
const CROSSFADE_TIME := 1.2      # Seamless blending time between playlist tracks
const PITCH_VARIANCE := 0.08     # Up to 8% pitch variation to prevent ear fatigue (micro-variations)
const VOLUME_VARIANCE_DB := 1.5  # Up to 1.5 dB subtle volume variation for realism
const ERROR_COOLDOWN_MSEC := 90

# Both playlists support infinite songs (we will load your 4 menu and 4 gameplay songs here)
var menu_playlist: Array[AudioStreamPlayer] = []
var gameplay_playlist: Array[AudioStreamPlayer] = []

var current_menu_idx: int = -1
var current_gameplay_idx: int = -1
var _is_playing_menu_playlist: bool = true

# Sound effect players
var success_snd: AudioStreamPlayer
var error_snd: AudioStreamPlayer
var powerup_snd: AudioStreamPlayer
var keystroke_snd: AudioStreamPlayer

# Fallbacks/Bonus SFX
const ITEM_AUDIO_DIR := "res://audio/items/"
var click_snd: AudioStreamPlayer
var notification_snd: AudioStreamPlayer
var levelup_sting_snd: AudioStreamPlayer
var whoosh_snd: AudioStreamPlayer
var gameover_voice_snd: AudioStreamPlayer

# --- PROFESSIONAL AUDIO POOLS ---
# Instead of playing one node over and over (which cuts the sound off), 
# we pool nodes so multiple sounds can overlap beautifully.
var _pools: Dictionary = {}

var _game_state: GameState
var _music_bus_idx := -1
var _sfx_bus_idx := -1
var _last_error_msec := 0
var _duck_tween: Tween


func setup(
	game_state: GameState,
	menu_tracks: Array, # Now accepts your array of menu tracks
	gameplay_tracks: Array, # Accepts your array of gameplay tracks
	success: AudioStreamPlayer,
	error: AudioStreamPlayer,
	keystroke: AudioStreamPlayer = null,
	click: AudioStreamPlayer = null,
	notification: AudioStreamPlayer = null,
	levelup_sting: AudioStreamPlayer = null,
	whoosh: AudioStreamPlayer = null,
	gameover_voice: AudioStreamPlayer = null
) -> void:
	_game_state = game_state
	
	# Cast incoming arrays to the proper type safely
	menu_playlist.clear()
	for track in menu_tracks:
		if track is AudioStreamPlayer:
			menu_playlist.append(track)
			
	gameplay_playlist.clear()
	for track in gameplay_tracks:
		if track is AudioStreamPlayer:
			gameplay_playlist.append(track)

	# --- FIX: force-disable stream looping so `finished` actually fires ---
	# If a track's audio import has "Loop" enabled, AudioStreamPlayer will
	# never emit `finished` and will just replay the same song forever
	# instead of handing off to switch_to_next_music().
	_disable_stream_looping(menu_playlist)
	_disable_stream_looping(gameplay_playlist)

	success_snd = success
	error_snd = error
	_pack_pitch_multiplier = SOUND_PACK_PITCH.get(_game_state.sound_pack, 1.0) if is_instance_valid(_game_state) else 1.0

	_music_bus_idx = AudioServer.get_bus_index("Music")
	_sfx_bus_idx = AudioServer.get_bus_index("SFX")

	# Setup Powerup Player
	powerup_snd = AudioStreamPlayer.new()
	if success_snd and success_snd.stream:
		powerup_snd.stream = success_snd.stream
		powerup_snd.pitch_scale = 1.6
	add_child(powerup_snd)

	# Setup Keystroke Player
	if keystroke and keystroke.stream:
		keystroke_snd = keystroke
	else:
		keystroke_snd = AudioStreamPlayer.new()
		if success_snd and success_snd.stream:
			keystroke_snd.stream = success_snd.stream
		add_child(keystroke_snd)

	# Fallbacks
	click_snd = click if (click and click.stream) else _make_fallback_player("click.wav")
	notification_snd = notification if (notification and notification.stream) else _make_fallback_player("quick_win.wav")
	levelup_sting_snd = levelup_sting if (levelup_sting and levelup_sting.stream) else _make_fallback_player("level_up.mp3")
	whoosh_snd = whoosh if (whoosh and whoosh.stream) else _make_fallback_player("whoosh.mp3")
	gameover_voice_snd = gameover_voice if (gameover_voice and gameover_voice.stream) else _make_fallback_player("game_over_voice.mp3")

	# Build pools for all major sound effects to allow overlapping
	_register_pool("success", success_snd, POOL_SIZE)
	_register_pool("error", error_snd, POOL_SIZE)
	_register_pool("powerup", powerup_snd, POOL_SIZE)
	_register_pool("keystroke", keystroke_snd, 6) # Typing needs a larger pool for fast typists!
	_register_pool("click", click_snd, 5)
	_register_pool("notification", notification_snd, POOL_SIZE)

	# Connect all tracks to our automatic playlist manager
	for track in menu_playlist:
		if track and not track.finished.is_connected(_on_music_track_finished):
			track.finished.connect(_on_music_track_finished)

	for track in gameplay_playlist:
		if track and not track.finished.is_connected(_on_music_track_finished):
			track.finished.connect(_on_music_track_finished)

	apply_volume(true)


# --- FIX: strip looping from imported streams so `finished` fires correctly ---
func _disable_stream_looping(playlist: Array[AudioStreamPlayer]) -> void:
	for track in playlist:
		if not track or not track.stream:
			continue
		var s = track.stream
		if s is AudioStreamOggVorbis or s is AudioStreamMP3:
			s.loop = false
		elif s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_DISABLED


func _make_fallback_player(filename: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := ITEM_AUDIO_DIR + filename
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

# --- HELPER: PROFESSIONAL AUDIO POOLING ---
func _register_pool(pool_name: String, template_player: AudioStreamPlayer, size: int) -> void:
	if not template_player or not template_player.stream:
		return
	var pool_list: Array[AudioStreamPlayer] = []
	pool_list.append(template_player)
	
	for i in range(size - 1):
		var dup := AudioStreamPlayer.new()
		dup.stream = template_player.stream
		dup.bus = template_player.bus
		add_child(dup)
		pool_list.append(dup)
		
	_pools[pool_name] = pool_list


func _play_from_pool(pool_name: String, pitch_mod: float = 1.0, vol_offset_db: float = 0.0) -> void:
	if not _pools.has(pool_name):
		return
	var pool = _pools[pool_name]
	
	# Find a player that isn't currently playing
	var target_player: AudioStreamPlayer = null
	for p in pool:
		if is_instance_valid(p) and not p.playing:
			target_player = p
			break
			
	# If they are all busy, grab the oldest one and restart it
	if not target_player:
		target_player = pool[0]
		
	if is_instance_valid(target_player):
		# Apply Micro-Variations (Pitch and Volume randomization)
		var rand_pitch = pitch_mod + randf_range(-PITCH_VARIANCE, PITCH_VARIANCE)
		var rand_vol = vol_offset_db + randf_range(-VOLUME_VARIANCE_DB, VOLUME_VARIANCE_DB)
		
		target_player.pitch_scale = clamp(rand_pitch * _pack_pitch_multiplier, 0.2, 4.0)
		
		# Set volume relative to the base bus volume config
		var base_sfx_volume = _to_db(_game_state.sfx_volume) if (not _game_state.muted and _game_state.sfx_enabled) else -80.0
		target_player.volume_db = base_sfx_volume + rand_vol
		target_player.play()


func apply_volume(instant: bool = false) -> void:
	var music_off = _game_state.muted or not _game_state.music_enabled
	var sfx_off = _game_state.muted or not _game_state.sfx_enabled
	var target_music_db = _to_db(_game_state.music_volume) if not music_off else -80.0
	var target_sfx_db = _to_db(_game_state.sfx_volume) if not sfx_off else -80.0

	if _music_bus_idx >= 0:
		_apply_bus_volume(_music_bus_idx, target_music_db, instant)
	else:
		for track in menu_playlist:
			_apply_player_volume(track, target_music_db, instant)
		for track in gameplay_playlist:
			_apply_player_volume(track, target_music_db, instant)

	if _sfx_bus_idx >= 0:
		_apply_bus_volume(_sfx_bus_idx, target_sfx_db, instant)
	else:
		for pool_name in _pools:
			for player in _pools[pool_name]:
				_apply_player_volume(player, target_sfx_db, instant)
		for sfx in [levelup_sting_snd, whoosh_snd, gameover_voice_snd]:
			_apply_player_volume(sfx, target_sfx_db, instant)


func _apply_bus_volume(bus_idx: int, target_db: float, instant: bool) -> void:
	if instant:
		AudioServer.set_bus_volume_db(bus_idx, target_db)
		return
	var t := create_tween()
	var current_db = AudioServer.get_bus_volume_db(bus_idx)
	t.tween_method(func(v): AudioServer.set_bus_volume_db(bus_idx, v), current_db, target_db, FADE_TIME)


func _apply_player_volume(player: AudioStreamPlayer, target_db: float, instant: bool) -> void:
	if not player:
		return
	if instant:
		player.volume_db = target_db
		return
	var t := create_tween()
	t.tween_property(player, "volume_db", target_db, FADE_TIME)


func _to_db(linear_volume: float) -> float:
	if linear_volume <= 0.001:
		return -80.0
	return linear_to_db(linear_volume)


func set_music_volume(v: float) -> void:
	_game_state.music_volume = v
	apply_volume()
	volume_changed.emit("music", v)


func set_sfx_volume(v: float) -> void:
	_game_state.sfx_volume = v
	apply_volume()
	volume_changed.emit("sfx", v)


func set_muted(m: bool) -> void:
	_game_state.muted = m
	apply_volume()
	mute_changed.emit(m)


func set_music_enabled(on: bool) -> void:
	_game_state.music_enabled = on
	_game_state.save_data()
	apply_volume()


func set_sfx_enabled(on: bool) -> void:
	_game_state.sfx_enabled = on
	_game_state.save_data()
	apply_volume()


# --- MUSIC PLAYBACK (WITH CROSSFADING) ---

func play_menu_music() -> void:
	_transition_music_playlist(true)


func start_gameplay_music() -> void:
	_transition_music_playlist(false)


func _transition_music_playlist(to_menu: bool) -> void:
	var old_playlist = gameplay_playlist if to_menu else menu_playlist
	var new_playlist = menu_playlist if to_menu else gameplay_playlist
	
	if new_playlist.is_empty():
		return

	_is_playing_menu_playlist = to_menu
	
	# Stop everything on the old playlist with a clean fadeout
	for track in old_playlist:
		if track and track.playing:
			var fade_out = create_tween()
			fade_out.tween_property(track, "volume_db", -80.0, CROSSFADE_TIME)
			fade_out.tween_callback(track.stop)

	# Pick a random starting track on our new playlist
	var next_idx = randi() % new_playlist.size()
	if to_menu:
		current_menu_idx = next_idx
	else:
		current_gameplay_idx = next_idx
		
	var next_track = new_playlist[next_idx]
	if next_track and next_track.stream:
		next_track.volume_db = -80.0
		next_track.play()
		
		var target_db = _to_db(_game_state.music_volume) if not _game_state.muted else -80.0
		var fade_in = create_tween()
		fade_in.tween_property(next_track, "volume_db", target_db, CROSSFADE_TIME)
		
		if not to_menu:
			music_track_changed.emit(current_gameplay_idx)


func switch_to_next_music() -> void:
	var playlist = menu_playlist if _is_playing_menu_playlist else gameplay_playlist
	if playlist.size() <= 1:
		if playlist.size() == 1 and playlist[0] and not playlist[0].playing:
			playlist[0].play()
		return

	var old_idx = current_menu_idx if _is_playing_menu_playlist else current_gameplay_idx
	var old_track = playlist[old_idx] if old_idx >= 0 and old_idx < playlist.size() else null
	
	# Prevent selecting the same song twice in a row
	var new_idx = old_idx
	while new_idx == old_idx:
		new_idx = randi() % playlist.size()

	if _is_playing_menu_playlist:
		current_menu_idx = new_idx
	else:
		current_gameplay_idx = new_idx

	var new_track = playlist[new_idx]
	if not new_track or not new_track.stream:
		return

	var target_db = _to_db(_game_state.music_volume) if not _game_state.muted else -80.0

	# CROSSFADE: Blend old track out while blending new track in
	if old_track and is_instance_valid(old_track) and old_track.playing:
		var fade_out := create_tween()
		fade_out.tween_property(old_track, "volume_db", -80.0, CROSSFADE_TIME)
		fade_out.tween_callback(old_track.stop)

	new_track.volume_db = -80.0
	new_track.play()
	var fade_in := create_tween()
	fade_in.tween_property(new_track, "volume_db", target_db, CROSSFADE_TIME)
	
	if not _is_playing_menu_playlist:
		music_track_changed.emit(current_gameplay_idx)


func stop_all_music() -> void:
	for track in menu_playlist:
		if track and track.playing:
			track.stop()
	for track in gameplay_playlist:
		if track and track.playing:
			track.stop()


func _on_music_track_finished() -> void:
	switch_to_next_music()


# --- SFX CONTROLS WITH MICRO-VARIATIONS ---

const SOUND_PACK_PITCH := {
	"Classic": 1.0,
	"Arcade": 1.25,
	"Chill": 0.8,
}
var _pack_pitch_multiplier := 1.0

func set_sound_pack(pack_name: String) -> void:
	_pack_pitch_multiplier = SOUND_PACK_PITCH.get(pack_name, 1.0)

## combo is optional so every existing call site (play_success() with no
## args) still works exactly as before. When a combo is passed, pitch
## climbs gently with it - capped so a long streak still sounds like the
## same instrument, just more excited, rather than turning into a chipmunk.
func play_success(combo: int = 0) -> void:
	var combo_pitch = 1.0 + clamp(combo * 0.015, 0.0, 0.35)
	_play_from_pool("success", combo_pitch)

func play_error() -> void:
	var now = Time.get_ticks_msec()
	if now - _last_error_msec < ERROR_COOLDOWN_MSEC:
		return
	_last_error_msec = now
	# Pitched down so it reads as "wrong" rather than being an exact copy of
	# the UI click sound it's built from (see main.tscn ErrorPlayer).
	_play_from_pool("error", 0.55)

func play_powerup() -> void:
	_play_from_pool("powerup", 1.6)

func play_keystroke(is_valid: bool = true) -> void:
	var base_pitch = 2.0 if is_valid else 0.85
	# Play with standard keystroke attenuation (-10dB offset so it isn't deafening)
	_play_from_pool("keystroke", base_pitch, -10.0)

func play_ui_click() -> void:
	if _pools.has("click"):
		_play_from_pool("click", 1.0)
	else:
		_play_from_pool("success", 1.3)

func play_notification() -> void:
	_play_from_pool("notification", 1.0)

func play_level_up_sting() -> void:
	if levelup_sting_snd: levelup_sting_snd.play()

func play_whoosh() -> void:
	if whoosh_snd: whoosh_snd.play()

func play_game_over_voice() -> void:
	if gameover_voice_snd: gameover_voice_snd.play()
