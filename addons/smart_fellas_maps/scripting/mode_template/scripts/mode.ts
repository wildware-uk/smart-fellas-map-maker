// A starter game mode. It runs in the host's game and decides the rules: here, every catch is a
// point for the diver who made it, the first diver to the lobby's goal wins the round alone, and the
// octopuses win if time runs out. Change it however you like: smart-fellas.d.ts lists every call.

game.onMatchStart(() => {
  game.scoreboard("Catches");
});

// Each diver's catches this round, by player id.
let catches = new Map<number, number>();

function goal(): number {
  return Number(game.setting("goal") ?? 3);
}

game.onRoundStart(() => {
  catches = new Map();
  game.banner("First diver to " + goal() + " catches wins");
});

game.onCaught((_octopus, by) => {
  if (by === null || by.team !== "diver") {
    return;
  }
  const made = (catches.get(by.id) ?? 0) + 1;
  catches.set(by.id, made);
  by.setScore(made);
  by.setCell("Catches", made);
  if (made >= goal()) {
    game.endRound(by);
  }
});

game.onTimeUp(() => {
  game.endRound("octopus", "timeUp");
});
