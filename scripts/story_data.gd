class_name StoryData
extends RefCounted

## "DEEP SIGNAL" — Type Blast's Story Mode.
##
## Same structural idea as a fighting game's story mode (Mortal Kombat's
## in particular): a short arc told through text-panel "cutscenes" between
## challenges, one location per chapter, background changes every chapter
## so it visually reads as moving somewhere new. Here the "fight" is a
## typing challenge instead of combat.
##
## The challenge itself types whole sentences (via SentenceBank), not
## single words — each "transmission" reads like an actual message you're
## transcribing, which fits the story far better than isolated words
## would. Uses SentenceBank exactly as SentenceModeScreen does (same
## exact-match rules), just strung into a per-chapter queue.
##
## Fully original text written for this project — no existing characters,
## IP, or real people. Six chapters ("Transmissions"), building lightly in
## length/difficulty. `bg_theme` indexes into the existing
## BackgroundThemes.THEMES (0-3), reused/cycled rather than duplicated.
##
## --- Decode Threshold -----------------------------------------------
## Every chapter's `outro` is the surface-level version of what happened -
## always shown, regardless of performance. Each chapter also has a
## `decoded` array: one or two extra lines, ONLY shown if the player
## cleared that transmission cleanly (see meets_decode_threshold()).
## Mechanically this ties the actual typing skill to how much of the real
## story you get, instead of typing accuracy being invisible once you've
## passed/failed a chapter - a sloppy clear still finishes the chapter and
## unlocks the next one, but only a clean one reveals what's really going
## on. Together the six `decoded` fragments build a second, hidden throughline
## underneath the surface plot (deliberately not spoiled in comments here -
## read them in order once you've decoded a few chapters).

const DECODE_MIN_ACCURACY := 96.0
const DECODE_MAX_MISSES := 1

## A transmission is fully decoded when it's typed clean - not just fast.
## Deliberately stricter than a "pass" (which only requires finishing the
## chapter, misses and all): the point is that decoding requires care, not
## just speed, so a rushed-but-technically-cleared run still leaves the
## deeper fragment locked as a reason to come back and type it properly.
static func meets_decode_threshold(accuracy: float, misses: int) -> bool:
	return accuracy >= DECODE_MIN_ACCURACY and misses <= DECODE_MAX_MISSES

const CHAPTERS := [
	{
		"id": 1,
		"title": "Dead Air",
		"location": "Listening Post Kestrel",
		"bg_theme": 0,
		"intro": [
			"Three days of static. Then, at 03:14, something answers back.",
			"You're the only operator still awake on the Kestrel tonight. Whatever this signal is, you're the one who has to read it.",
			"Type each line exactly as it arrives — the channel drops if you fall too far behind.",
		],
		"outro": [
			"The fragments resolve into coordinates. Somewhere out past the debris field, something is still broadcasting.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] One more fragment resolves, one you almost missed: the reply isn't using standard Kestrel protocol. It's using YOUR call sign. It knew who'd be listening before you ever answered.",
		],
		"theme": "General", "max_sentence_len": 55,
		"line_count": 5, "lives": 0,
	},
	{
		"id": 2,
		"title": "The Relay",
		"location": "Orbital Relay 7",
		"bg_theme": 1,
		"intro": [
			"Relay 7 hasn't answered a single ping in six years. Now its old transmitter is wide open, screaming data into empty space.",
			"You patch in. The lines come faster here — six years of backlog, all trying to clear the queue at once.",
		],
		"outro": [
			"Buried in the backlog: a maintenance log, and a name you don't recognize, repeated over and over.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] The name in the log matches a Kestrel duty roster - from thirty-one years ago. Same shift. Same console. According to the log, that operator never signed off.",
		],
		"theme": "Tech", "max_sentence_len": 55,
		"line_count": 6, "lives": 0,
	},
	{
		"id": 3,
		"title": "Drift Station",
		"location": "Derelict Station Amaranth",
		"bg_theme": 2,
		"intro": [
			"Amaranth Station has been adrift for a decade. Its beacon still repeats one message, over and over, in every language it knows.",
			"You start transcribing the beacon's feed line by line, hunting for whatever it's trying to say before its batteries finally die.",
		],
		"outro": [
			"The beacon cuts out mid-sentence. Whatever finished that message, it wasn't the beacon.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] You pull the raw waveform before it clears the buffer. The last line wasn't sent in the beacon's voice. It was sent in yours - your cadence, your exact typing rhythm, finishing your own sentence for you.",
		],
		"theme": "Space", "max_sentence_len": 65,
		"line_count": 6, "lives": 0,
	},
	{
		"id": 4,
		"title": "Radio Silence",
		"location": "Blackout Sector",
		"bg_theme": 3,
		"intro": [
			"Something is jamming every frequency except one — yours. Every dropped line here costs the connection for good.",
			"Three strikes. That's all the jammer gives you before it locks you out completely. Make every line count.",
		],
		"outro": [
			"The jamming stops as suddenly as it started. In the silence that follows, one clear transmission finally gets through.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] The clear transmission is a warning, and it's timestamped six hours from now: DO NOT RUN THE MANUAL SHUTDOWN AS WRITTEN. It's signed with your own operator ID.",
		],
		"theme": "Adventure", "max_sentence_len": 70,
		"line_count": 6, "lives": 3, "duration": 45.0,
	},
	{
		"id": 5,
		"title": "The Core",
		"location": "Kestrel Reactor Core",
		"bg_theme": 0,
		"intro": [
			"The clear transmission was a warning: the Kestrel's own reactor core is failing, and only a full manual shutdown sequence can stop it.",
			"The sequence has to be typed exactly, against the reactor's own failing countdown. No pressure.",
		],
		"outro": [
			"The core powers down with seconds to spare. Whatever's out past the debris field will have to wait a little longer.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] The reactor logs tell a different story than the countdown did: nothing was actually failing. The countdown was injected from outside, timed to the second - built to see if you'd shut it down anyway. You did.",
		],
		"theme": "Nature", "max_sentence_len": 80,
		"line_count": 7, "lives": 3, "duration": 40.0,
	},
	{
		"id": 6,
		"title": "Signal Home",
		"location": "Kestrel Comms Array",
		"bg_theme": 1,
		"intro": [
			"With the reactor stable, there's power to spare for one more thing: a full-strength broadcast, aimed at everything that answered you tonight.",
			"Whoever — or whatever — is out there past the debris field is about to hear you loud and clear.",
		],
		"outro": [
			"The broadcast goes out. Somewhere in the dark, several things start broadcasting back at once.",
			"DEEP SIGNAL — END OF PART ONE.",
		],
		"decoded": [
			"[SIGNAL FULLY DECODED] Not several things. One thing, arriving from several directions at once - like an echo takes several paths back to the same source. You check the broadcast's origin timestamp against your own console clock. They match. It hasn't been talking to you tonight. It's been replaying tonight, waiting for you to answer it correctly.",
		],
		"theme": "General", "max_sentence_len": 90,
		"line_count": 8, "lives": 3,
	},
]

## Returns a copy of `chapter` with sentence length/count, lives and
## duration scaled for the chosen difficulty. Intro/outro text, title,
## location and background stay the same — only the challenge changes.
static func apply_difficulty(chapter: Dictionary, difficulty: String) -> Dictionary:
	var c: Dictionary = chapter.duplicate(true)
	var max_sentence_len: int = c.get("max_sentence_len", 70)
	var line_count: int = c.get("line_count", 6)
	var lives: int = c.get("lives", 0)
	var duration: float = c.get("duration", 0.0)

	match difficulty:
		"easy":
			max_sentence_len = max(30, max_sentence_len - 10)
			line_count = max(4, line_count - 2)
			if lives > 0:
				lives += 1
			if duration > 0.0:
				duration *= 1.35
		"hard":
			max_sentence_len += 15
			line_count += 2
			if lives > 0:
				lives = max(1, lives - 1)
			else:
				lives = 2   # even the "no-fail" early chapters get real stakes on Hard
			if duration > 0.0:
				duration *= 0.75

	c["max_sentence_len"] = max_sentence_len
	c["line_count"] = line_count
	c["lives"] = lives
	c["duration"] = duration
	c["difficulty"] = difficulty
	return c


static func chapter_count() -> int:
	return CHAPTERS.size()

static func get_chapter(id: int) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		if c.get("id", -1) == id:
			return c
	return {}

## Builds the "transmission" queue for a chapter: a shuffled set of whole
## sentences from SentenceBank, filtered to the chapter's max length (and
## widened, then finally un-filtered, if that leaves too few candidates —
## some theme pools are short).
static func sentence_queue_for(chapter: Dictionary, rng: RandomNumberGenerator) -> Array:
	var theme_name: String = chapter.get("theme", "General")
	var max_len: int = chapter.get("max_sentence_len", 70)
	var needed: int = max(chapter.get("line_count", 6), 3)

	var pool: Array = SentenceBank.get_theme_sentences(theme_name)
	var filtered: Array = pool.filter(func(s): return String(s).length() <= max_len)
	if filtered.size() < needed:
		filtered = pool.filter(func(s): return String(s).length() <= max_len + 25)
	if filtered.size() < needed:
		filtered = pool

	var shuffled: Array = filtered.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled.slice(0, min(needed, shuffled.size()))
