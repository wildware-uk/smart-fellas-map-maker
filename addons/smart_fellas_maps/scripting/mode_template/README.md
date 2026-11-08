# A game mode to start from

A game mode decides the rules of a match: who is on which team, what a catch does, what scores, the
clock, and who wins. Any mode plays on any map. This folder is a small working one, Catch Count, to
change into your own.

## Try it

1. In the game, open **Workshop > Modes > My modes** and press **Open modes folder**.
2. Copy this whole folder into it, and rename the copy (say `my_mode`).
3. Host a game on any map (or press **Test Map** in Godot), and pick **Catch Count** under
   **Game mode** in the lobby.

The game reads the modes folder again each time you open My modes, host, or open the lobby panel. So
change a script, open the lobby panel again (Tab), and pick the mode again under **Game mode**.

## What is in it

- `mode.json`: the mode's name, its description, how many players it is for (bots count), and the
  settings it offers in the lobby. A setting is a `number` (with `min`, `max`, `step`), a `choice`
  (with `choices`), or a `toggle`, each with a `default`.
- `scripts/`: TypeScript (`.ts`) or JavaScript (`.js`). Scripts here run in the host's game. Those in
  `scripts/client/` run on each player's own PC, for what only their screen shows, and those in
  `scripts/shared/` on both.
- `preview.png` (add your own): the picture the Workshop shows, up to 1 MB, 16:9 is best.

For your editor to complete and check your scripts, copy `smart-fellas.d.ts` from the add-on's
`scripting` folder into `scripts/`. It lists every call, and the ones marked "for game modes" change
the round's rules.

## Share it

In **My modes**, your mode is listed. Press **Edit & publish**, give it a title and a
description, and publish it to the Workshop. Players subscribe to it from **Browse** (pick the **Modes**
tab at the top), and a player who joins your game without it can get it from the mode's card in the
lobby.
