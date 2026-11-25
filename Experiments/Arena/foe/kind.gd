extends Resource

## Everything that makes one foe not another. A new enemy is a new one of
## these: how it fights, what it can see coming, and what it wears.

enum Outfit { CLOTH, LIGHT, FULL }

@export var label := ""

@export_group("Fighting")
@export var attacks := true
## Seconds between attacks.
@export var patience := Vector2(1.2, 3.4)
## Blows it'll throw in a row.
@export var most_blows := 99
## Chance of going straight into another run of them.
@export_range(0.0, 1.0, 0.05) var press_on := 0.15
## How drawn out its blows are.
@export var slowness := 1.0
@export_range(0.0, 1.0, 0.05) var counter_chance := 0.9
@export_range(0.0, 1.0, 0.05) var punish_chance := 0.8
## Extra seconds it's open for after a parry, and how fast it backs out of it.
@export var slow_to_recover := 0.0
@export var reel_back := 0.8
## Seconds it's thrown open for by a perfect parry, of any blow at all.
@export var perfect_open := 1.8
## How much it can take, where no one cut has done it already.
@export var health := 3.0

@export_group("To the end")
enum Change { NONE, WILD, VANISH }
## What it becomes once it's really been got to.
@export var changes := Change.NONE
## Is that already.
@export var starts_changed := false
## What it throws besides, once it is.
@export var second_patterns: Array[Resource] = []
## Comes back once it's been killed, and takes this many cuts to put down then.
@export var lives := 0
## Perfect parries it takes, one soon after another, to open it.
@export var parries_to_open := 1
## Bluffs with whatever it keeps having parried.
@export var learns := false
## Throws everything it knows from the start.
@export var fierce := false

@export_group("Guarding on sight")
## For those with no eye of their own: how often they get a guard up at all.
@export_range(0.0, 1.0, 0.05) var guard_chance := 0.25
@export_range(0.0, 1.0, 0.05) var parry_chance := 0.0
@export_range(0.0, 1.0, 0.05) var think_better := 0.15
@export var wariness_per_cut := 0.03
@export var shell_time := 0.0

@export_group("A trained eye")
## Reads what's coming, rather than flinching at it.
@export var reads := false
## Chance of stopping a plain cut.
@export_range(0.0, 1.0, 0.01) var stops := 0.94
## Moves its guard to a line as it's drawn, and so can be led astray.
@export var watches := true
## Tricks it remembers at once. With none, the same one always works.
@export var remembers := 2
## What it can't be fooled by.
@export var knows_hooks := false
@export var knows_feints := false
@export var knows_thrusts := false
## Only a cut that beat its eye does anything to it.
@export var iron := true
## Shakes off an opening after one cut.
@export var springs_back := true
## Steps out of the way instead of putting its sword there, this many times
## before it has to get its breath.
@export var steps := 0
@export var breath := 2.2

@export_group("Looks")
## A rigged model for a body, and more on the same bones. With none it's made
## of plain shapes.
@export var figure: PackedScene
@export var figure_extras: Array[PackedScene] = []
## Plates named for the parts they go on, and what's over its face.
@export var armour: PackedScene
@export var mask: PackedScene
## Ink inside, and not blood.
@export var straw := false
@export var outfit := Outfit.CLOTH
@export var robe := 0.035
@export var lacquer := Color(0.42, 0.025, 0.02)
## Has a mask on.
@export var masked := true
## Has a straw hat on.
@export var hat := false


## Before it's in the world.
func dress(foe: Node) -> void:
	var body := foe.get_node("Body")
	body.figure = figure
	body.figure_extras = figure_extras
	body.armour = armour
	body.mask = mask
	body.straw = straw
	body.outfit = outfit
	body.robe_value = robe
	body.lacquer = lacquer
	body.masked = masked
	body.hat = hat
	foe.get_node("Vitals").max_health = health
	foe.kind = self
	var brain := foe.get_node("Brain")
	brain.peaceful = not attacks
	brain.temper = self
	for what: String in ["patience", "press_on", "guard_chance", "parry_chance", "counter_chance", "punish_chance", "think_better", "wariness_per_cut", "shell_time"]:
		brain.set(what, get(what))
	var reader := foe.get_node("Reader")
	reader.on = reads
	for what: String in ["stops", "watches", "remembers", "knows_hooks", "knows_feints", "knows_thrusts", "iron", "steps", "breath"]:
		reader.set(what, get(what))
