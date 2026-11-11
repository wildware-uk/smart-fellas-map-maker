// A cave that floods near the end of every round: the water line rises from the floor to the roof
// over the last minute, and anyone caught below it is swept away.
//
// Set FLOOR and ROOF to the heights of your cave, in metres. Players hear the flood come and are told
// how high the water is; the cave's own water doesn't change.
//
// A player who comes back into the round below the water line is swept away again within a second,
// and so on until the round ends. Put the places players come back in above where the water gets
// to, or expect it.

const FLOOR = 0;
const ROOF = 12;
const STARTS_WITH_SECONDS_LEFT = 60;
const RISES_FOR = 50;
const TELLS_EVERY = 10;

let flooding = false;
let risen = 0;

function level(): number {
  return FLOOR + (ROOF - FLOOR) * Math.min(risen / RISES_FOR, 1);
}

game.onRoundStart(() => {
  flooding = false;
  risen = 0;
});

every(1, () => {
  if (game.phase !== "play") {
    return;
  }
  if (!flooding) {
    if (game.timeLeft > STARTS_WITH_SECONDS_LEFT) {
      return;
    }
    flooding = true;
    game.say("The cave is flooding! Get up high!");
    game.playSound("swell");
  }
  risen += 1;
  const line = level();
  if (risen % TELLS_EVERY === 0 && risen <= RISES_FOR) {
    game.say(`The flood is ${Math.round(line - FLOOR)} m deep.`);
  }
  for (const player of game.players()) {
    const at = player.position;
    if (player.alive && at && at.y < line) {
      player.say("The flood swept you away.");
      player.kill();
    }
  }
});
