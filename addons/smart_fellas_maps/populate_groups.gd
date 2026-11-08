@tool
extends RefCounted
## What Populate can place, in groups the map maker ticks in the Map panel: scenery, food, creatures and
## spawns. Apart from populate.gd, so that the panel can show them without Godot compiling all of Populate
## as the editor opens (#291).

const GROUPS := ["scenery", "food", "creatures", "spawns"]
const GROUP_WORDS := {"scenery": "Scenery", "food": "Food", "creatures": "Creatures", "spawns": "Spawns"}
const GROUP_TIPS := {
	"scenery": "Plants, coral and rocks.",
	"food": "Food patches. Leave it off to place food yourself, as part of the map's design.",
	"creatures": "Fish, stingray stops and wrasse spots. Eel and groper holes are left to you: they need a real hole.",
	"spawns": "Octopus and diver spawn points, for a team that has none.",
}
