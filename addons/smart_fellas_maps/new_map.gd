@tool
extends RefCounted
## A new bare map's scene: flat sand, spawn points and food. Its text lives here and not in a scene in
## maps/, which a person might open, paint and save.

const BLANK := """[gd_scene format=3]

[ext_resource type="Script" path="res://addons/smart_fellas_maps/map_root.gd" id="1_root"]
[ext_resource type="Script" path="res://addons/smart_fellas_maps/play_area_box.gd" id="2_area"]

[sub_resource type="StandardMaterial3D" id="sand"]
albedo_color = Color(0.76, 0.69, 0.52, 1)

[sub_resource type="PlaneMesh" id="floor"]
material = SubResource("sand")
size = Vector2(240, 240)

[node name="NewMap{number}" type="Node3D"]
script = ExtResource("1_root")
map_name = "New Map {number}"

[node name="PlayArea" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -12, 0)
script = ExtResource("2_area")
size = Vector3(60, 25.5, 60)

[node name="Seabed" type="MeshInstance3D" parent="."]
mesh = SubResource("floor")

[node name="spawn_octopus_1" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10, 1, -24)

[node name="spawn_octopus_2" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 10, 1, -24)

[node name="spawn_diver_1" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, -10, 1.5, 24)

[node name="spawn_diver_2" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 10, 1.5, 24)

[node name="food_patch_1" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -16, 0, 0)

[node name="food_patch_2" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 16, 0, 0)

[node name="food_patch_3" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 8)
"""


## Writes a new bare map in `folder`, under the first free number. Gives back {"path"}, or {"problem"} in
## plain words.
static func write_in(folder: String) -> Dictionary:
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK:
		return {"problem": "Can't make the folder %s: %s." % [folder, error_string(made)]}
	var number := 1
	while FileAccess.file_exists(folder.path_join("new_map_%d.tscn" % number)):
		number += 1
	var path := folder.path_join("new_map_%d.tscn" % number)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"problem": "Can't write %s: %s." % [path, error_string(FileAccess.get_open_error())]}
	file.store_string(BLANK.format({"number": number}))
	file.close()
	return {"path": path}
