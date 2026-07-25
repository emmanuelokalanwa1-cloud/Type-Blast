class_name ErrorLogger
extends RefCounted

## Not a crash reporter — GDScript has no way to catch native engine
## crashes, and wiring up a real crash-reporting service (Crashlytics,
## Sentry, etc.) needs an account + SDK integration that's a separate
## decision to make deliberately, not something to bolt in silently.
##
## What this DOES give you: a plain text log file on the device
## (user://logs/session_log.txt) that important failures get written to
## as they happen — starting with save-file write/read failures, the one
## silent-failure case that existed in game_state.gd. Since there's no
## PC/debugger in this workflow, pull the file with any Android file
## manager (Android/data/.../files/logs/session_log.txt, or via
## OS.get_user_data_dir() if you want to print the exact path) and paste
## its contents here if something's misbehaving.

const LOG_PATH := "user://logs/session_log.txt"
const MAX_LOG_BYTES := 200_000 # trim before this to avoid the file growing forever

static func log_error(context: String, detail: String = "") -> void:
	_write("ERROR", context, detail)

static func log_warning(context: String, detail: String = "") -> void:
	_write("WARN", context, detail)

static func _write(level: String, context: String, detail: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if not dir.dir_exists("logs"):
		dir.make_dir("logs")

	_trim_if_needed()

	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var line := "[%s] %s: %s" % [Time.get_datetime_string_from_system(), level, context]
	if detail != "":
		line += " — " + detail
	f.store_line(line)
	f.close()
	# Also push to the normal Godot log so it shows up if a debugger IS
	# attached, without changing behavior when it isn't.
	if level == "ERROR":
		push_error(context + (" — " + detail if detail != "" else ""))
	else:
		push_warning(context + (" — " + detail if detail != "" else ""))

static func _trim_if_needed() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return
	var size := f.get_length()
	if size <= MAX_LOG_BYTES:
		f.close()
		return
	# Keep only the tail half so the file doesn't grow forever.
	f.seek(size / 2)
	var tail := f.get_as_text()
	f.close()
	var out := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if out:
		out.store_string(tail)
		out.close()
