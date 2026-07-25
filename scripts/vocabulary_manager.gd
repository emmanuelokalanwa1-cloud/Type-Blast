class_name VocabularyManager
extends RefCounted

## Small curated word + one-line definition list for an optional "Word of
## the Day" panel — leans into this being a *learning* game, not just a
## typing minigame. Deterministic per calendar date (same seeding trick as
## WordBank.get_daily_words() / QuotesManager.quote_of_the_day()), so
## everyone sees the same word on the same day. All definitions written
## fresh for this project, so there's no licensing concern reusing
## dictionary text.

const ENTRIES := [
	{"word": "RESILIENT", "definition": "Able to recover quickly from difficulty."},
	{"word": "METICULOUS", "definition": "Showing great attention to detail."},
	{"word": "LUMINOUS", "definition": "Full of light; glowing brightly."},
	{"word": "TENACIOUS", "definition": "Holding firmly to a course of action."},
	{"word": "SERENE", "definition": "Calm, peaceful, and untroubled."},
	{"word": "VIGILANT", "definition": "Keeping careful watch for danger or difficulty."},
	{"word": "EPHEMERAL", "definition": "Lasting for a very short time."},
	{"word": "CANDID", "definition": "Truthful and straightforward; frank."},
	{"word": "DILIGENT", "definition": "Showing care and effort in work or duties."},
	{"word": "PROLIFIC", "definition": "Producing a great deal of something."},
	{"word": "AUDACIOUS", "definition": "Willing to take bold risks."},
	{"word": "CONCISE", "definition": "Giving information clearly, in few words."},
	{"word": "GENUINE", "definition": "Truly what it is said to be; authentic."},
	{"word": "INTREPID", "definition": "Fearless; adventurous."},
	{"word": "NIMBLE", "definition": "Quick and light in movement or action."},
	{"word": "OPTIMISTIC", "definition": "Hopeful and confident about the future."},
	{"word": "PRAGMATIC", "definition": "Dealing with things sensibly and realistically."},
	{"word": "QUAINT", "definition": "Attractively unusual or old-fashioned."},
	{"word": "ROBUST", "definition": "Strong and healthy; sturdy."},
	{"word": "STEADFAST", "definition": "Firm and unwavering in purpose."},
	{"word": "THOROUGH", "definition": "Complete, with great attention to detail."},
	{"word": "UNIQUE", "definition": "Being the only one of its kind."},
	{"word": "VERSATILE", "definition": "Able to adapt to many different functions."},
	{"word": "WHIMSICAL", "definition": "Playfully quaint or fanciful."},
	{"word": "ZEALOUS", "definition": "Having great energy or enthusiasm."},
	{"word": "AMIABLE", "definition": "Friendly and pleasant in nature."},
	{"word": "BENEVOLENT", "definition": "Kind and generous in spirit."},
	{"word": "CURIOUS", "definition": "Eager to know or learn something."},
	{"word": "DYNAMIC", "definition": "Characterized by constant change or progress."},
	{"word": "EARNEST", "definition": "Sincere and serious in intention."},
]

static func word_of_the_day(date_seed: int) -> Dictionary:
	if ENTRIES.is_empty():
		return {"word": "PRACTICE", "definition": "Repeated exercise to improve a skill."}
	var idx = abs(date_seed) % ENTRIES.size()
	return ENTRIES[idx]

static func count() -> int:
	return ENTRIES.size()
