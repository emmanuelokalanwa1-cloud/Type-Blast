class_name MissionData
extends RefCounted

## Static mission/map definitions. Pure data — no state lives here, that's
## MissionManager's job. Add more maps by appending to get_maps(); nothing
## else needs to change to support a Map 21, Map 22, etc.
##
## Mission "type" values understood by MissionManager.evaluate_run_end():
##   run_words          - words_typed_total in that run >= target
##   run_combo          - highest combo reached in that run >= target
##   run_accuracy       - that run's accuracy% >= target
##   run_score          - that run's score >= target
##   run_wpm            - that run's WPM >= target
##   reach_level        - level reached in that run >= target
##   survive_full_run   - the run ended by time running out, not by dying
##   use_theme          - that run was played with WordSet == target (String)
##   use_weak_keys      - that run was played with Weak Keys mode on
##
## Additional types understood by MissionManager's lifetime-counter
## evaluators (evaluate_streak_bonus/evaluate_playlist_complete/
## evaluate_ghost_rival/evaluate_daily_login — called from main.gd/
## more_screen.gd/ghost_racer.gd at the moment each of those happens, not
## from evaluate_run_end()):
##   streak_bonus_total - lifetime 10/25/50-combo streak bonuses triggered >= target
##   playlist_complete  - lifetime completed Practice Playlists >= target
##   ghost_rival_win     - lifetime wins against your pinned Ghost Rival >= target
##   login_streak        - best-ever Daily Login streak >= target
##
## ---------------------------------------------------------------------
## Maps 5-20 progression formula (documented so this stays maintainable
## instead of being 80 arbitrary hand-picked numbers):
##   For map index n (5..20), relative to Map 4's baseline (combo 100,
##   score 5000, level 15, wpm 100):
##     combo_target = 100 + (n-4) * 25
##     score_target = 5000 + (n-4) * 2500
##     level_target = 15 + (n-4) * 3
##     wpm_target   = 100 + (n-4) * 6
##   Each map's 5th mission rotates through four flavors on a 4-map cycle:
##     (n-5) % 4 == 0 -> run_accuracy 100  (perfect-run challenge)
##     (n-5) % 4 == 1 -> use_theme         (a themed word-set run)
##     (n-5) % 4 == 2 -> survive_full_run  (finish without dying)
##     (n-5) % 4 == 3 -> use_weak_keys     (a Weak Keys practice run)
##
## NOTE: "use_theme" targets below ("Desert", "Cyber", "Aurora", "Phantom",
## "Ocean", "Volcano", "Space") are placeholder word-set names matching the
## style of the original "Space" mission — double check these exist as
## actual WordSet values in your WordManager before shipping, and swap out
## any that don't.
## ---------------------------------------------------------------------

static func get_maps() -> Array:
	return [
		{
			"name": "Map 1 — Getting Started",
			"missions": [
				{"id": "m1_words20",    "text": "Type 20 words in one run",              "type": "run_words",        "target": 20},
				{"id": "m1_combo10",    "text": "Reach a 10x combo",                      "type": "run_combo",        "target": 10},
				{"id": "m1_accuracy90", "text": "Finish a run with 90%+ accuracy",         "type": "run_accuracy",     "target": 90},
				{"id": "m1_level3",     "text": "Reach Level 3",                           "type": "reach_level",      "target": 3},
				{"id": "m1_score200",   "text": "Score 200 points in one run",             "type": "run_score",        "target": 200},
				{"id": "m1_survive",    "text": "Survive a full run without running out of lives", "type": "survive_full_run", "target": 1},
				{"id": "m1_theme",      "text": "Play a run with the Space word set",       "type": "use_theme",        "target": "Space"},
				{"id": "m1_weak_keys",  "text": "Try a run with Weak Keys practice on",     "type": "use_weak_keys",    "target": 1},
				{"id": "m1_wpm30",      "text": "Reach 30 WPM in one run",                  "type": "run_wpm",          "target": 30},
				{"id": "m1_words50",    "text": "Type 50 words in one run",                 "type": "run_words",        "target": 50},
			{"id": "m1_sentence5",  "text": "Complete 5 sentences in Sentence Practice", "type": "sentence_count",   "target": 5},
			{"id": "m1_sentence_wpm40", "text": "Reach 40 WPM in Sentence Practice",     "type": "sentence_wpm",     "target": 40},
			]
		},
		{
			"name": "Map 2 — Getting Serious",
			"missions": [
				{"id": "m2_combo25",    "text": "Reach a 25x combo",                       "type": "run_combo",    "target": 25},
				{"id": "m2_score500",   "text": "Score 500 points in one run",              "type": "run_score",    "target": 500},
				{"id": "m2_level6",     "text": "Reach Level 6",                            "type": "reach_level",  "target": 6},
				{"id": "m2_wpm50",      "text": "Reach 50 WPM in one run",                  "type": "run_wpm",      "target": 50},
				{"id": "m2_accuracy98", "text": "Finish a run with 98%+ accuracy",          "type": "run_accuracy", "target": 98},
				{"id": "m2_streak_bonus", "text": "Trigger 3 combo streak bonuses (10/25/50x)", "type": "streak_bonus_total", "target": 3},
				{"id": "m2_playlist",     "text": "Complete a Practice Playlist",               "type": "playlist_complete",  "target": 1},
				{"id": "m2_ghost_rival",  "text": "Beat your pinned Ghost Rival",                "type": "ghost_rival_win",    "target": 1},
				{"id": "m2_login_streak", "text": "Reach a 3-day Daily Login streak",            "type": "login_streak",       "target": 3},
			]
		},
		{
			"name": "Map 3 — Mastery",
			"missions": [
				{"id": "m3_combo40",     "text": "Reach a 40x combo",                        "type": "run_combo",        "target": 40},
				{"id": "m3_score1000",   "text": "Score 1000 points in one run",              "type": "run_score",        "target": 1000},
				{"id": "m3_level10",     "text": "Reach Level 10",                            "type": "reach_level",      "target": 10},
				{"id": "m3_wpm70",       "text": "Reach 70 WPM in one run",                   "type": "run_wpm",          "target": 70},
				{"id": "m3_accuracy99",  "text": "Finish a run with 99%+ accuracy",           "type": "run_accuracy",     "target": 99},
				{"id": "m3_words100",    "text": "Type 100 words in one run",                 "type": "run_words",        "target": 100},
				{"id": "m3_survive",     "text": "Complete a full run without losing all your lives", "type": "survive_full_run", "target": 1},
				{"id": "m3_theme_ocean", "text": "Play a run with the Ocean word set",        "type": "use_theme",        "target": "Ocean"},
				{"id": "m3_score1500",   "text": "Score 1500 points in one run",              "type": "run_score",        "target": 1500},
				{"id": "m3_wpm85",       "text": "Reach 85 WPM in one run",                   "type": "run_wpm",          "target": 85},
			]
		},
		{
			"name": "Map 4 — Legendary",
			"missions": [
				{"id": "m4_combo60",      "text": "Reach a 60x combo",                        "type": "run_combo",     "target": 60},
				{"id": "m4_score2500",    "text": "Score 2500 points in one run",              "type": "run_score",     "target": 2500},
				{"id": "m4_level15",      "text": "Reach Level 15",                            "type": "reach_level",   "target": 15},
				{"id": "m4_wpm100",       "text": "Reach 100 WPM in one run",                  "type": "run_wpm",       "target": 100},
				{"id": "m4_accuracy100",  "text": "Finish a run with perfect 100% accuracy",   "type": "run_accuracy",  "target": 100},
				{"id": "m4_words200",     "text": "Type 200 words in one run",                 "type": "run_words",     "target": 200},
				{"id": "m4_theme_volcano","text": "Play a run with the Volcano word set",      "type": "use_theme",     "target": "Volcano"},
				{"id": "m4_weak_keys_run","text": "Complete a full Weak Keys practice run",    "type": "use_weak_keys", "target": 1},
				{"id": "m4_score5000",    "text": "Score 5000 points in one legendary run",    "type": "run_score",     "target": 5000},
				{"id": "m4_combo100",     "text": "Reach a 100x combo",                        "type": "run_combo",     "target": 100},
			]
		},
		{
			"name": "Map 5 — Ascended",
			"missions": [
				{"id": "m5_combo125",   "text": "Reach a 125x combo",              "type": "run_combo",    "target": 125},
				{"id": "m5_score7500",  "text": "Score 7500 points in one run",     "type": "run_score",    "target": 7500},
				{"id": "m5_level18",    "text": "Reach Level 18",                   "type": "reach_level",  "target": 18},
				{"id": "m5_wpm106",     "text": "Reach 106 WPM in one run",         "type": "run_wpm",      "target": 106},
				{"id": "m5_accuracy100","text": "Finish a run with perfect 100% accuracy", "type": "run_accuracy", "target": 100},
			]
		},
		{
			"name": "Map 6 — Mythic",
			"missions": [
				{"id": "m6_combo150",   "text": "Reach a 150x combo",              "type": "run_combo",    "target": 150},
				{"id": "m6_score10000", "text": "Score 10000 points in one run",    "type": "run_score",    "target": 10000},
				{"id": "m6_level21",    "text": "Reach Level 21",                   "type": "reach_level",  "target": 21},
				{"id": "m6_wpm112",     "text": "Reach 112 WPM in one run",         "type": "run_wpm",      "target": 112},
				{"id": "m6_theme_desert","text": "Play a run with the Desert word set", "type": "use_theme", "target": "Desert"},
			]
		},
		{
			"name": "Map 7 — Immortal",
			"missions": [
				{"id": "m7_combo175",   "text": "Reach a 175x combo",              "type": "run_combo",    "target": 175},
				{"id": "m7_score12500", "text": "Score 12500 points in one run",    "type": "run_score",    "target": 12500},
				{"id": "m7_level24",    "text": "Reach Level 24",                   "type": "reach_level",  "target": 24},
				{"id": "m7_wpm118",     "text": "Reach 118 WPM in one run",         "type": "run_wpm",      "target": 118},
				{"id": "m7_survive",    "text": "Complete a full run without losing all your lives", "type": "survive_full_run", "target": 1},
			]
		},
		{
			"name": "Map 8 — Celestial",
			"missions": [
				{"id": "m8_combo200",   "text": "Reach a 200x combo",              "type": "run_combo",    "target": 200},
				{"id": "m8_score15000", "text": "Score 15000 points in one run",    "type": "run_score",    "target": 15000},
				{"id": "m8_level27",    "text": "Reach Level 27",                   "type": "reach_level",  "target": 27},
				{"id": "m8_wpm124",     "text": "Reach 124 WPM in one run",         "type": "run_wpm",      "target": 124},
				{"id": "m8_weak_keys",  "text": "Complete a full Weak Keys practice run", "type": "use_weak_keys", "target": 1},
			]
		},
		{
			"name": "Map 9 — Transcendent",
			"missions": [
				{"id": "m9_combo225",   "text": "Reach a 225x combo",              "type": "run_combo",    "target": 225},
				{"id": "m9_score17500", "text": "Score 17500 points in one run",    "type": "run_score",    "target": 17500},
				{"id": "m9_level30",    "text": "Reach Level 30",                   "type": "reach_level",  "target": 30},
				{"id": "m9_wpm130",     "text": "Reach 130 WPM in one run",         "type": "run_wpm",      "target": 130},
				{"id": "m9_accuracy100","text": "Finish a run with perfect 100% accuracy", "type": "run_accuracy", "target": 100},
			]
		},
		{
			"name": "Map 10 — Eternal",
			"missions": [
				{"id": "m10_combo250",   "text": "Reach a 250x combo",              "type": "run_combo",    "target": 250},
				{"id": "m10_score20000", "text": "Score 20000 points in one run",    "type": "run_score",    "target": 20000},
				{"id": "m10_level33",    "text": "Reach Level 33",                   "type": "reach_level",  "target": 33},
				{"id": "m10_wpm136",     "text": "Reach 136 WPM in one run",         "type": "run_wpm",      "target": 136},
				{"id": "m10_theme_cyber","text": "Play a run with the Cyber word set", "type": "use_theme", "target": "Cyber"},
			]
		},
		{
			"name": "Map 11 — Cosmic",
			"missions": [
				{"id": "m11_combo275",   "text": "Reach a 275x combo",              "type": "run_combo",    "target": 275},
				{"id": "m11_score22500", "text": "Score 22500 points in one run",    "type": "run_score",    "target": 22500},
				{"id": "m11_level36",    "text": "Reach Level 36",                   "type": "reach_level",  "target": 36},
				{"id": "m11_wpm142",     "text": "Reach 142 WPM in one run",         "type": "run_wpm",      "target": 142},
				{"id": "m11_survive",    "text": "Complete a full run without losing all your lives", "type": "survive_full_run", "target": 1},
			]
		},
		{
			"name": "Map 12 — Ethereal",
			"missions": [
				{"id": "m12_combo300",   "text": "Reach a 300x combo",              "type": "run_combo",    "target": 300},
				{"id": "m12_score25000", "text": "Score 25000 points in one run",    "type": "run_score",    "target": 25000},
				{"id": "m12_level39",    "text": "Reach Level 39",                   "type": "reach_level",  "target": 39},
				{"id": "m12_wpm148",     "text": "Reach 148 WPM in one run",         "type": "run_wpm",      "target": 148},
				{"id": "m12_weak_keys",  "text": "Complete a full Weak Keys practice run", "type": "use_weak_keys", "target": 1},
			]
		},
		{
			"name": "Map 13 — Astral",
			"missions": [
				{"id": "m13_combo325",   "text": "Reach a 325x combo",              "type": "run_combo",    "target": 325},
				{"id": "m13_score27500", "text": "Score 27500 points in one run",    "type": "run_score",    "target": 27500},
				{"id": "m13_level42",    "text": "Reach Level 42",                   "type": "reach_level",  "target": 42},
				{"id": "m13_wpm154",     "text": "Reach 154 WPM in one run",         "type": "run_wpm",      "target": 154},
				{"id": "m13_accuracy100","text": "Finish a run with perfect 100% accuracy", "type": "run_accuracy", "target": 100},
			]
		},
		{
			"name": "Map 14 — Radiant",
			"missions": [
				{"id": "m14_combo350",    "text": "Reach a 350x combo",              "type": "run_combo",    "target": 350},
				{"id": "m14_score30000",  "text": "Score 30000 points in one run",    "type": "run_score",    "target": 30000},
				{"id": "m14_level45",     "text": "Reach Level 45",                   "type": "reach_level",  "target": 45},
				{"id": "m14_wpm160",      "text": "Reach 160 WPM in one run",         "type": "run_wpm",      "target": 160},
				{"id": "m14_theme_aurora","text": "Play a run with the Aurora word set", "type": "use_theme", "target": "Aurora"},
			]
		},
		{
			"name": "Map 15 — Sovereign",
			"missions": [
				{"id": "m15_combo375",   "text": "Reach a 375x combo",              "type": "run_combo",    "target": 375},
				{"id": "m15_score32500", "text": "Score 32500 points in one run",    "type": "run_score",    "target": 32500},
				{"id": "m15_level48",    "text": "Reach Level 48",                   "type": "reach_level",  "target": 48},
				{"id": "m15_wpm166",     "text": "Reach 166 WPM in one run",         "type": "run_wpm",      "target": 166},
				{"id": "m15_survive",    "text": "Complete a full run without losing all your lives", "type": "survive_full_run", "target": 1},
			]
		},
		{
			"name": "Map 16 — Divine",
			"missions": [
				{"id": "m16_combo400",   "text": "Reach a 400x combo",              "type": "run_combo",    "target": 400},
				{"id": "m16_score35000", "text": "Score 35000 points in one run",    "type": "run_score",    "target": 35000},
				{"id": "m16_level51",    "text": "Reach Level 51",                   "type": "reach_level",  "target": 51},
				{"id": "m16_wpm172",     "text": "Reach 172 WPM in one run",         "type": "run_wpm",      "target": 172},
				{"id": "m16_weak_keys",  "text": "Complete a full Weak Keys practice run", "type": "use_weak_keys", "target": 1},
			]
		},
		{
			"name": "Map 17 — Omniscient",
			"missions": [
				{"id": "m17_combo425",   "text": "Reach a 425x combo",              "type": "run_combo",    "target": 425},
				{"id": "m17_score37500", "text": "Score 37500 points in one run",    "type": "run_score",    "target": 37500},
				{"id": "m17_level54",    "text": "Reach Level 54",                   "type": "reach_level",  "target": 54},
				{"id": "m17_wpm178",     "text": "Reach 178 WPM in one run",         "type": "run_wpm",      "target": 178},
				{"id": "m17_accuracy100","text": "Finish a run with perfect 100% accuracy", "type": "run_accuracy", "target": 100},
			]
		},
		{
			"name": "Map 18 — Infinite",
			"missions": [
				{"id": "m18_combo450",     "text": "Reach a 450x combo",              "type": "run_combo",    "target": 450},
				{"id": "m18_score40000",   "text": "Score 40000 points in one run",    "type": "run_score",    "target": 40000},
				{"id": "m18_level57",      "text": "Reach Level 57",                   "type": "reach_level",  "target": 57},
				{"id": "m18_wpm184",       "text": "Reach 184 WPM in one run",         "type": "run_wpm",      "target": 184},
				{"id": "m18_theme_phantom","text": "Play a run with the Phantom word set", "type": "use_theme", "target": "Phantom"},
			]
		},
		{
			"name": "Map 19 — Apex",
			"missions": [
				{"id": "m19_combo475",   "text": "Reach a 475x combo",              "type": "run_combo",    "target": 475},
				{"id": "m19_score42500", "text": "Score 42500 points in one run",    "type": "run_score",    "target": 42500},
				{"id": "m19_level60",    "text": "Reach Level 60",                   "type": "reach_level",  "target": 60},
				{"id": "m19_wpm190",     "text": "Reach 190 WPM in one run",         "type": "run_wpm",      "target": 190},
				{"id": "m19_survive",    "text": "Complete a full run without losing all your lives", "type": "survive_full_run", "target": 1},
			]
		},
		{
			"name": "Map 20 — Ultimate",
			"missions": [
				{"id": "m20_combo500",   "text": "Reach a 500x combo",              "type": "run_combo",    "target": 500},
				{"id": "m20_score45000", "text": "Score 45000 points in one run",    "type": "run_score",    "target": 45000},
				{"id": "m20_level63",    "text": "Reach Level 63",                   "type": "reach_level",  "target": 63},
				{"id": "m20_wpm196",     "text": "Reach 196 WPM in one run",         "type": "run_wpm",      "target": 196},
				{"id": "m20_weak_keys",  "text": "Complete a full Weak Keys practice run", "type": "use_weak_keys", "target": 1},
			]
		},
	]
