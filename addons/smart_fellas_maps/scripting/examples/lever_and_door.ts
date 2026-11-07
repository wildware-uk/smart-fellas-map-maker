// A lever that opens a door for 20 seconds.
//
// In the add-on: put the door's piece in the group `script` and call its node "door". Put the
// lever's piece in the group `switch` and call its node "lever". A player pulls the lever by pressing
// Interact (the eat key) next to it.

const door = game.piece("door");
const lever = game.piece("lever");
const OPEN_FOR = 20;
const RISE = 4;

// Where the door stands shut. Pieces have no place until the match's first tick, so it is read then.
let shut: Point | null = null;
let closing: TimerId | null = null;

function close(): void {
  if (door && shut) {
    door.moveTo(shut.x, shut.y, shut.z, 2);
    game.playSoundAt("thunk", shut.x, shut.y, shut.z);
  }
  closing = null;
}

lever?.onUse((player: Player) => {
  if (!door) {
    return;
  }
  shut ??= door.position;
  if (!shut) {
    return;
  }
  if (closing !== null) {
    player.say("The door is already open.");
    return;
  }
  door.moveTo(shut.x, shut.y + RISE, shut.z, 2);
  game.playSoundAt("rockfall", shut.x, shut.y, shut.z);
  game.say(`The door is open for ${OPEN_FOR} seconds!`);
  closing = after(OPEN_FOR, close);
});

// Every round starts with the door shut.
game.onRoundStart(() => {
  if (closing !== null) {
    cancel(closing);
    close();
  }
});
