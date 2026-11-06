# Changelog

What changed in each version of the Smart Fellas map maker. A version is the date it was made, then a short code for the exact build, like `2026.11.06-1a2b3c4`. The **Map** panel in Godot shows yours.

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
