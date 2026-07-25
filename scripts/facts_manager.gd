class_name FactsManager
extends RefCounted

## Deliberately has nothing to do with typing, keyboards, or vocabulary -
## it's a pure "why not" bonus panel (space/animal/ocean trivia + a few
## clean one-liners) for when someone opens the app without wanting to
## practice anything. All original text, no licensing concerns.

const ENTRIES := [
	"A group of flamingos is called a 'flamboyance.'",
	"Honey never spoils — archaeologists have found 3,000-year-old honey that's still edible.",
	"Octopuses have three hearts, and two of them stop beating when it swims.",
	"There are more possible chess games than atoms in the observable universe.",
	"A day on Venus is longer than a year on Venus.",
	"Bananas are berries, but strawberries technically aren't.",
	"Sharks existed before trees did.",
	"Wombat poop is cube-shaped, which stops it from rolling away.",
	"The Eiffel Tower grows about 6 inches taller in summer heat.",
	"Sea otters hold hands while sleeping so they don't drift apart.",
	"A bolt of lightning is about five times hotter than the surface of the sun.",
	"Some cats are actually allergic to humans — mild skin reactions to our dander.",
	"The shortest war on record lasted about 38 minutes.",
	"Butterflies taste with their feet.",
	"There's a species of jellyfish that can bite the age process and revert to a younger stage.",
	"Why don't scientists trust atoms? Because they make up everything.",
	"I told my computer I needed a break, and it said no problem — it'll go to sleep too.",
	"What do you call a fish with no eyes? A fsh.",
	"I used to be a banker, but I lost interest.",
	"Why did the scarecrow win an award? He was outstanding in his field.",
	"Parallel lines have so much in common. It's a shame they'll never meet.",
	"Mount Everest grows about 4 millimeters every year.",
	"A single cloud can weigh more than a million pounds.",
	"Cows have best friends and get stressed when separated from them.",
	"The inventor of the frisbee was turned into a frisbee after he died — his ashes were molded into memorial discs.",
]

static func get_fact(index: int) -> String:
	if ENTRIES.is_empty():
		return ""
	return ENTRIES[abs(index) % ENTRIES.size()]

static func random_fact(rng: RandomNumberGenerator) -> String:
	if ENTRIES.is_empty():
		return ""
	return ENTRIES[rng.randi() % ENTRIES.size()]

static func count() -> int:
	return ENTRIES.size()
