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
   Test Map needs Smart Fellas installed through Steam. The game isn't out yet, so for now only
   playtesters have it. You can still build a map without it. To try yours in the game, join the
   [Smart Fellas Discord](https://discord.gg/TWsP93NA62) and ask to join the playtests.

**The play area** is the blue box in the 3D view: where players can swim, spawn and eat. Press **Fit to map** in the **Map** panel to fit it round your spawns and food, or select **PlayArea** and drag the dots on its faces. Scenery can go anywhere, inside the box or far outside it.

**Export Map** writes your map straight into Smart Fellas: it shows in the game under **Workshop > Maps > My maps**, where you name it, pick its picture and publish it. **Export to Folder...** writes it anywhere you choose, to share it by hand.

**Octopus poses** of your own: in the **Poses** panel, press **Add: Octopus pose**, click where it goes, and shape it with the dials or by dragging its arms' tips. Then select a piece and tick the pose under **Octopus poses** in the Inspector: in the game, an octopus next to that piece can take the pose from its near wheel (Q). The octopus is drawn by the game itself, so this needs Smart Fellas installed too.

## Update it

The **Map** panel says which version you have, under **This add-on**, at the bottom. Once a day, when Godot opens, it asks GitHub whether a newer one is out. If one is, a banner at the top of the **Map** panel says "Update available", with **Update** and **What's new**. Press **Update**, then **Restart Godot**. Only the add-on's own folder (`addons/smart_fellas_maps`) changes: your maps and models stay as they are. If a new version's water needs a setting your `project.godot` lacks, the add-on adds it there itself when Godot starts. Each download is checked against the SHA-256 published with its release, and refused if it doesn't match.

**Check for updates**, under **This add-on**, or **Project > Tools > Smart Fellas: Check for updates** asks straight away. Untick **Check for updates automatically** if you'd rather it didn't ask by itself. With no internet, it says nothing.

If your Map panel has no Update button, your add-on is from before the updater. To update it, once: download the new zip and unzip it somewhere new, copy your maps (your `.tscn` files, and any models of your own) into the new folder, and open its `project.godot`.

Every version, and what changed in it, is on the [releases page](https://github.com/wildware-uk/smart-fellas-map-maker/releases) and in [CHANGELOG.md](CHANGELOG.md).

## Found a problem?

[Open an issue](https://github.com/wildware-uk/smart-fellas-map-maker/issues/new/choose). Say what you pressed, what you expected and what happened instead, and which version the Map panel shows.

For help, and to show off your maps, come to the Smart Fellas Discord, linked from the guide.

## Where this comes from

This repository is published from the game's own code each time the add-on changes, so changes made here directly would be overwritten. Bug reports are very welcome.

## Licence

The add-on's code is under the MIT licence. Its pieces, textures and pictures (the "kit") may be used to make Smart Fellas maps, but not sold or used anywhere else. See [LICENSE](LICENSE) for both, and [CREDITS.txt](CREDITS.txt) for the one file by someone else.

Smart Fellas map maker, by [Wildware Studios](https://wildwarestudios.com).
