@tool
extends RefCounted
## Whether a character is a letter or digit as the game's name check means it, which is Rust's
## char::is_alphanumeric. Godot has nothing that agrees with it, so name_letters.txt lists the runs of them,
## and the game's own tests hold that list against it.

const LIST := "res://addons/smart_fellas_maps/name_letters.txt"

## The first and last of each run, in order: first, last, first, last.
static var _runs := PackedInt32Array()


static func is_letter_or_digit(code: int) -> bool:
	if _runs.is_empty():
		_read_the_list()
	# The first entry above this code, in a list of firsts and lasts, says whether it's inside a run.
	var above := _runs.bsearch(code + 1)
	return above % 2 == 1


static func _read_the_list() -> void:
	for line in FileAccess.get_file_as_string(LIST).split("\n", false):
		var numbers := line.split(" ")
		_runs.append(numbers[0].to_int())
		_runs.append(numbers[1].to_int() + 1)
