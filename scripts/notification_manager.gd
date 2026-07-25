class_name NotificationManager
extends RefCounted

## Godot 4 has no built-in cross-platform local notification API — real
## "come back and keep your streak" push reminders need a platform export
## plugin (e.g. a Godot Android/iOS local-notifications plugin) added
## through the export system, same category of limitation as
## MonetizationManager's ad SDK and CloudSaveManager's backend: needs a
## plugin/account this sandboxed environment can't install or test on a
## real device.
##
## What's actually shipped instead: GameState.is_streak_at_risk() drives
## an in-app banner in MoreScreen's header, shown while the player is
## already looking at the screen. It can't reach someone who hasn't
## opened the app, but it's real and working today.
##
## TO WIRE UP REAL PUSH NOTIFICATIONS LATER:
## 1. Pick a plugin (search the Godot Asset Library for "notification" —
##    options differ for Android vs iOS export).
## 2. Install it via the export template / Android Gradle build.
## 3. Call schedule_streak_reminder() below at the point a run ends
##    (main.gd's _on_game_ended already knows current_streak), replacing
##    the no-op body with the plugin's real scheduling call.

## Schedule a local notification reminding the player their streak is at
## risk. Always a no-op today — no plugin installed. hours_from_now lets
## the caller decide the reminder window (e.g. "remind me in 20 hours").
func schedule_streak_reminder(_hours_from_now: float) -> void:
	ErrorLogger.log_warning("NotificationManager.schedule_streak_reminder() called", "No local-notification plugin installed — no-op. See GameState.is_streak_at_risk() for the working in-app alternative.")
	# TODO: real plugin call, e.g. (API varies by plugin):
	#   if Engine.has_singleton("LocalNotification"):
	#       Engine.get_singleton("LocalNotification").schedule(...)

## Cancel any previously scheduled streak reminder, e.g. once the player
## has already played today and the reminder is no longer needed.
func cancel_streak_reminder() -> void:
	pass # TODO: real plugin call once one is installed.
