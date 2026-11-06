# Smart Fellas map maker

Everything you need to make your own maps for [Smart Fellas](https://wildwarestudios.com/games/smart-fellas), in [Godot](https://godotengine.org).

It's a Godot project with our add-on already switched on. The add-on gives Godot extra panels for building a map: our coral, rocks and kelp to drag in, a brush to paint them on, spawn points, food, sea life, and buttons to test your map in the game and export it.

**The full guide, with pictures:** <https://wildwarestudios.com/games/smart-fellas/maps>

## Get it

1. Get **Godot 4.7.2**. It's free, and you don't install it: you unzip it and open it.
   <https://github.com/godotengine/godot/releases/tag/4.7.2-stable>
   Take the "stable" zip for your PC (Windows or Linux), not the "mono" one.
2. Download **[smart-fellas-map-maker.zip](https://github.com/wildware-uk/smart-fellas-map-maker/releases/latest/download/smart-fellas-map-maker.zip)**, the newest release, and unzip it.
3. Open Godot, press **Import**, and pick the `project.godot` file in the folder you unzipped.
   The first time it opens, Godot takes a minute or two to read in the pieces.
4. Open `maps/bare_sand.tscn`, or press **Make a new bare map** in the **Paint** panel.
5. Press **Populate** in the **Map** panel, then **Test Map** above the 3D view to swim in it.
   Test Map needs Smart Fellas installed through Steam.

**Export Map** writes your map straight into Smart Fellas: it shows in the game under **Maps > My maps**, where you name it, pick its picture and publish it. **Export to Folder...** writes it anywhere you choose, to share it by hand.

## Update it

The **Map** panel shows which version you have, at the bottom, with a link to the [releases page](https://github.com/wildware-uk/smart-fellas-map-maker/releases). If a newer one is out:

1. Download the new zip and unzip it somewhere new.
2. Copy your maps (your `.tscn` files, and any models of your own) from the old folder into the new one.
3. Open the new `project.godot` in Godot.

What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

## Found a problem?

[Open an issue](https://github.com/wildware-uk/smart-fellas-map-maker/issues/new/choose). Say what you pressed, what you expected and what happened instead, and which version the Map panel shows.

For help, and to show off your maps, come to the Smart Fellas Discord, linked from the guide.

## Where this comes from

This repository is published from the game's own code each time the add-on changes, so changes made here directly would be overwritten. Bug reports are very welcome.

## Licence

The add-on's code is under the MIT licence. Its pieces, textures and pictures (the "kit") may be used to make Smart Fellas maps, but not sold or used anywhere else. See [LICENSE](LICENSE) for both, and [CREDITS.txt](CREDITS.txt) for the one file by someone else.

Smart Fellas map maker, by [Wildware Studios](https://wildwarestudios.com).
