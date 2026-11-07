# Changelog

What changed in each version of the Smart Fellas map maker. A version is the date it was made, then a short code for the exact build, like `2026.11.06-1a2b3c4`. The **Map** panel in Godot shows yours.

## 2026.11.07-9402c8a

- Small fixes and tidying.

## 2026.11.07-b55bdf9

- Any mesh can now be marked Rock, Sand or Silt in the Map panel's "Your own models" list, not only .glb models, including loose meshes saved as .res files or inside the map. Select a model or mesh in the scene to set it from the line above the list.

## 2026.11.07-f596ca7

- Small fixes and tidying.

## 2026.11.07-3a54cfd

- Small fixes and tidying.

## 2026.11.07-a4fd8b4

- Small fixes and tidying.

## 2026.11.07-437d962

- Fixed Export and Test Map making big and many-material meshes plain white, flickering through the textures beside them.
- Export now warns when two copies of one mesh stand in exactly the same place.

## 2026.11.07-73e6cf0

- Small fixes and tidying.

## 2026.11.07-ed3f367

- Export now checks every model file it writes, and the finished .sfm, the way the game will. If one would be refused, it says so and asks you to report it, instead of the game saying "Export it again".
- Fixed Test Map and Export refusing every scattered mesh (MultiMesh) as "cut short or has extra bytes on the end".
- A mesh with nothing in it no longer stops Export: it is left out, with a note saying so.

## 2026.11.06-9f4bd7d

- Meshes scattered with MultiMesh now come out of Export as placed copies, with their stretch and their tint.
- Materials that look the same, and pictures shared between models, count once against the map's limits.
- Many problems of one kind are said as one line, with a Details button listing each.
- A map's package holds each picture once, however many of its models wear it, so maps download smaller.
- A map may now bring up to 512 models of its own, with 200 different materials, 2 million triangles and 256 MB of pictures between them, drawing up to 4 million triangles.
- Export keeps only the colour picture of each material, the only one the game draws, so bump and shine pictures no longer put a model over its limit.
- A model with more than 8 materials is split into parts by Export.
- Scattered copies and models of your own that stand far outside the map are left out with one warning, instead of stopping Export.
- A map may place up to 12,000 pieces, of which up to 4,096 from the kit, and its own models may have up to 400 different materials.
- A mesh imported from a whole level, far wider than one model, is cut by Export into parts by where they lie, leaving out what is far outside the map.
- Surfaces of a mesh drawn with the same material are joined into one.
- Your models stop being drawn where the water's haze hides them, and small ones past 60 m like the kit's props, so big maps run faster.
- Particles, CSG shapes and other things maps can't use yet no longer stop Export: they're left out, with one short warning line.
- When a map's pictures come to more than the game takes, Export now keeps making them smaller until they fit.
- Many of your models over one limit are said in one clear line naming that limit.
- When a map can't be exported, warnings are listed after the problems and marked as warnings.

## 2026.11.06-5cacae7

- The Map panel can update the add-on for you: it says when a new version is out, and Update puts it in place. Your maps stay as they are.
- A failed update can no longer lose the saved copy of your old add-on.

## 2026.11.06-57c5f01

- Small fixes and tidying.

## 2026.11.06-8f6839e

- Placing pieces, painting, Populate and markers now land on any solid mesh, including your own models: tops, sides and undersides.
- A map can have no seabed at all: untick Seabed in the Map panel and your pieces and models are the floor.
- Your own models can be marked as Sand or Silt in the Map panel, so octopuses can bury themselves in them.
- Populate has tick boxes for Scenery, Food, Creatures and Spawns, remembered for each map. Only Scenery is ticked at first, so markers you place yourself stay yours.
- Moving a rock or model carries the pieces and markers placed on it.
- Export and Test Map say plainly when a map has no spawn points or food, and how to add them.

## 2026.11.06-a8115b5

- Cloning the map maker with git no longer shows Godot's cache and your exported maps as changes.

## 2026.11.06-7782a32

The map maker as it was when it first went public:

- Paint the seabed with pieces, drag single pieces in from the **Pieces** panel, and sculpt the ground.
- **Populate** dresses a bare map with coral, rocks and kelp in one press.
- Spawn points, food patches, sea life and wildlife markers, from the **Map** panel.
- Water and light settings, from the **Water** panel.
- Bring models of your own into a map.
- **Test Map** opens the real game on your map; **Export Map** writes it out.
- Hidden pieces and markers stay out of an export.
- The **Map** panel shows the add-on's version and links to the newest release.
