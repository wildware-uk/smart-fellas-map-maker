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
- `icons/` (optional): a picture for an ability the mode gives a team (`game.registerAbility`). A
  square PNG named after the ability's id, such as `icons/quickdash.png`: up to 512 KB and 1024
  pixels across, and 8 in a mode. The game draws it round on that ability's button.
- `preview.png` (add your own): the picture the Workshop shows, up to 1 MB, 16:9 is best.

For your editor to complete and check your scripts, copy `smart-fellas.d.ts` from the add-on's
`scripting` folder into `scripts/`. It lists every call, and the ones marked "for game modes" change
the round's rules.

## Teams, bots and abilities of your own

A mode can add up to two teams whose players each drive a creature, tell their bots how to play, and
give them abilities. All of it is in `smart-fellas.d.ts`; this is the short of it.

```ts
game.onMatchStart(() => {
  // A team of sharks, joined in the lobby like any team.
  game.registerTeam("shark", { name: "Sharks", colour: "#a9d2ec", body: "shark", most: 3 });
  // An ability on the sharks' Dash key: a fast lunge at someone in view, every 8 seconds.
  game.registerAbility("quickdash", {
    team: "shark",
    slot: 1,
    name: "Quick dash",
    cooldown: 8,
    range: 14,
    lunge: { speed: 22, metres: 14 },
  });
});

// What it does is yours to say: here the shark takes an octopus it reaches in its jaws.
game.onAbilityLand((player, ability, target) => {
  if (ability === "quickdash" && target.team === "octopus") {
    player.bite(target);
  }
});

// A bot told to "hunt" plays its creature as a person would, abilities and all.
game.onJoin((player) => {
  if (player.isBot && player.team === "shark") {
    player.setGoal("hunt");
  }
});
```

- The game shows each ability to its team's players as a round button with its key, its name and its
  cooldown, and aims it: it goes off only at someone they can see near the middle of their screen.
- `game.onAbility` hears every use, `game.onAbilityLand` a lunge getting there. Sounds, points and
  what happens to who was hit are up to your handlers.

## Share it

In **My modes**, your mode is listed. Press **Edit & publish**, give it a title and a
description, and publish it to the Workshop. Players subscribe to it from **Browse** (pick the **Modes**
tab at the top), and a player who joins your game without it can get it from the mode's card in the
lobby.
