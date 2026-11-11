// A treasure that wakes the shark: each round a crab grows near TREASURE, and whoever eats it during
// the round brings a shark out of the deep.
//
// Food only grows on a map's food spots, so put TREASURE within 10 m of a food patch: the treasure
// grows on the free spot nearest it. The shark joins its loop round the map at the point nearest
// SHARK_FROM. Both are in metres. The treasure looks like any crab, so tell players about it, or hide
// it somewhere worth the swim.
//
// Give the treasure a food patch of its own, away from the map's other food. If the round's own food
// has filled every spot near TREASURE, no treasure grows that round, and nothing is said.

const TREASURE = { x: 0, y: 0, z: 12 };
const SHARK_FROM = { x: 0, y: 8, z: -30 };

let treasure: Creature | null = null;
// Whether this round's treasure has been seen in the water: one the game found no spot for is gone
// too, without anyone eating it.
let lying = false;
let shark: Creature | null = null;
// Whether the shark has been asked for and not yet seen: it's told once it is really there.
let coming = false;

function wake(): void {
  if (game.phase !== "play" || (shark && !shark.gone)) {
    return;
  }
  shark = game.spawn("shark", SHARK_FROM.x, SHARK_FROM.y, SHARK_FROM.z);
  coming = true;
}

game.onRoundStart(() => {
  treasure?.remove();
  treasure = null;
  lying = false;
  // The game sets out the round's own food as it starts, so the treasure comes a moment later.
  after(1, () => {
    treasure = game.spawn("crab", TREASURE.x, TREASURE.y, TREASURE.z);
  });
});

every(0, () => {
  if (coming && shark) {
    if (shark.alive) {
      coming = false;
      game.say("Someone took the treasure... and woke the shark!");
      game.playSound("roar");
    } else if (shark.gone) {
      coming = false;
    }
  }
  if (!treasure) {
    return;
  }
  if (!treasure.gone) {
    lying ||= treasure.alive;
    return;
  }
  treasure = null;
  if (lying) {
    wake();
  }
});
