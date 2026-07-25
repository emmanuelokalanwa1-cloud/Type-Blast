class_name AnalyticsManager
extends RefCounted

## Not connected to a real analytics service (Firebase Analytics, Amplitude,
## etc.) — that needs an account + SDK plugin, same limitation as
## MonetizationManager's ad SDK and ErrorLogger's crash reporting. What
## this DOES give you: every event is written locally as one JSON object
## per line to user://logs/analytics_log.jsonl, in the shape most
## analytics SDKs expect (name + params + timestamp), so:
##   1. You can already see what players are actually doing by pulling the
##      file (same way as ErrorLogger's session_log.txt — any Android file
##      manager, or OS.get_user_data_dir() for the exact path).
##   2. Wiring in a real SDK later is a one-line change inside log_event()
##      below (call the SDK instead of/alongside _write_local()) rather
##      than hunting down every call site across the codebase.
##
## Call sites wired so far: run_started, run_ended,
## interstitial_shown. Add more log_event() calls anywhere else a
## real product decision would want data (e.g. which career ranks players
## stall out on, which settings get changed most).

const LOG_PATH := "user://logs/analytics_log.jsonl"
const MAX_LOG_BYTES := 500_000 # trim before this to avoid the file growing forever

static func log_event(event_name: String, params: Dictionary = {}) -> void:
	var entry := {
		"event": event_name,
		"params": params,
		"time": Time.get_datetime_string_from_system(),
	}
	_write_local(entry)
	# TODO once a real analytics SDK is installed, also forward here, e.g.:
	#   if Engine.has_singleton("FirebaseAnalytics"):
	#       Engine.get_singleton("FirebaseAnalytics").log_event(event_name, params)

static func _write_local(entry: Dictionary) -> void:
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
	f.store_line(JSON.stringify(entry))
	f.close()

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
