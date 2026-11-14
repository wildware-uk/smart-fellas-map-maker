// King of the Reef: a game mode that shows off the helpers and the screen calls.
//
// A hill, shown as a marker, sits on a spot of the map. Every second, each player on it scores a
// point, or two if they hold it alone. Every so often the hill glides to a new spot. The leader
// swims a little slower. The first to the lobby's goal wins the round; when time runs out, the top
// scorer does.
//
// Every map has food, so the hill goes where the food grows: open spots players can reach.

const HILL_RADIUS = 6; // metres from the hill's middle that count as on it
const MOVE_SECONDS = 4; // how long the hill takes to glide to its next spot
const LEADER_SPEED = 0.8; // the leader swims at this share of normal speed
const GOLD = "#ffcc33";

function goal(): number {
  return Number(game.setting("goal") ?? 60);
}

function holdSeconds(): number {
  return Number(game.setting("hold") ?? 25);
}

// Each player's points this round live in the store, which empties itself as each round starts.
function pointsOf(player: Player): number {
  return store.get(`points:${player.id}`, 0);
}

// Where the hill is now, and our own random numbers, so pick() is at hand.
let hill: Point = Vec.zero;
let random = new Random(1);
let leader: Player | null = null;
let glide: TimerId | null = null;

// The next spot: a food item at least 15 m across the map from the hill now, or else where some
// player is. It looks at a few items picked at random, not at every one: reading the position of
// hundreds of items in one tick costs a lot.
function nextSpot(): Point {
  const far = (at: Point) => Vec.distance(Vec.flat(at), Vec.flat(hill)) > 15;
  const food = game.creatures("crab").concat(game.creatures("clam"), game.creatures("shrimp"));
  for (let tries = 0; tries < 8; tries++) {
    const at = random.pick(food)?.position;
    if (at && far(at)) {
      return at;
    }
  }
  const players = game
    .players()
    .map((player) => player.position)
    .filter((at): at is Point => at !== null);
  return random.pick(players) ?? hill;
}

function showHill(colour: string): void {
  // Lift the marker a little off the seabed, so it isn't buried in the sand.
  game.marker("hill", { at: Vec.add(hill, Vec.scale(Vec.up, 1.5)), label: "Hill", colour });
}

// The round's phases. "idle" is between rounds. The machine's type is written out because its
// states call phases.go() themselves.
type HillPhase = "idle" | "warmup" | "hold" | "move";
const phases: StateMachine<HillPhase> = new StateMachine<HillPhase>(
  {
    // A state machine goes into its first state at once, while the script loads, when it can't act
    // yet: so "idle" does nothing, and the round's end clears the screen.
    idle: {},
    warmup: {
      enter() {
        hill = nextSpot();
        showHill("#ffffff");
        game.announce("King of the Reef", 3);
        game.widget("phase", { kind: "timer", label: "Hill opens in", seconds: 5 });
      },
      tick(seconds) {
        if (seconds >= 5) {
          phases.go("hold");
        }
      },
    },
    hold: {
      enter() {
        showHill(GOLD);
        game.announce("The hill is open!", 2);
        // A timer widget counts down by itself: set it once.
        game.widget("phase", {
          kind: "timer",
          label: "Hill moves in",
          seconds: holdSeconds(),
          colour: GOLD,
        });
        game.playSoundForTeam("octopus", "chime");
        game.playSoundForTeam("diver", "chime");
      },
      tick(seconds) {
        if (seconds >= holdSeconds()) {
          phases.go("move");
        }
      },
    },
    move: {
      enter() {
        const from = hill;
        const to = nextSpot();
        log("hill moves from", from, "to", to);
        game.announce("The hill is moving!", 2);
        game.widget("phase", { kind: "text", label: "Hill", text: "On the move..." });
        game.playSoundForTeam("octopus", "swell");
        game.playSoundForTeam("diver", "swell");
        // Glide the marker to the new spot, easing in and out, then open the hill again.
        glide = tween(
          MOVE_SECONDS,
          (t) => {
            hill = Vec.lerp(from, to, t);
            showHill("#ffffff");
          },
          { ease: Ease.inOutSine, done: () => phases.go("hold") },
        );
      },
      leave() {
        // If the round ends mid-glide, stop the glide too.
        if (glide !== null) {
          cancel(glide);
          glide = null;
        }
      },
    },
  },
  "idle",
);

game.onMatchStart(() => {
  // The score column shows each player's points; two short columns of our own count dashes and inks.
  game.scoreboard("Dash", "Ink");
  // Nobody is out for good: whoever is caught comes back after 5 seconds.
  game.setFate("octopus", "respawn", 5);
  game.setFate("diver", "respawn", 5);
});

game.onRoundStart(() => {
  random = new Random(Math.floor(game.random() * 1000000));
  leader = null;
  log("round starts; goal", goal(), "hold", holdSeconds());
  game.banner(`Hold the hill. First to ${goal()} points wins`);
  for (const player of game.players()) {
    player.setCell("Dash", 0);
    player.setCell("Ink", 0);
  }
  phases.go("warmup");
});

game.onRoundEnd(() => {
  phases.go("idle");
  game.removeMarker("hill");
  game.removeWidget("phase");
  game.removeWidget("leader");
  game.removeWidget("points");
});

// Count dashes and inks: just for the scoreboard, to show the events.
game.onDash((player) => player.setCell("Dash", store.add(`dashes:${player.id}`)));
game.onInk((player) => player.setCell("Ink", store.add(`inks:${player.id}`)));

function topScorer(): Player | null {
  let best: Player | null = null;
  for (const player of game.players()) {
    if (!player.gone && pointsOf(player) > (best ? pointsOf(best) : 0)) {
      best = player;
    }
  }
  return best;
}

// The leader swims slower: the crown is heavy.
function crown(top: Player | null): void {
  if (top === leader) {
    return;
  }
  leader?.setSpeed(1);
  leader = top;
  if (top) {
    top.setSpeed(LEADER_SPEED);
    top.playSound("roar");
    top.announce("You lead! The crown slows you down", 3);
    game.widget("leader", { kind: "text", label: "Leader", text: top.name, colour: GOLD });
  }
}

every(1, () => {
  if (game.phase !== "play" || phases.state !== "hold") {
    return;
  }
  const onHill = game.playersNear(hill, HILL_RADIUS);
  for (const player of onHill) {
    const points = store.add(`points:${player.id}`, onHill.length === 1 ? 2 : 1);
    player.setScore(points);
    if (points >= goal()) {
      game.announce(`${player.name} is King of the Reef!`, 4);
      game.endRound(player);
      return;
    }
  }
  crown(topScorer());
  // Each player's own bar: how close they are to the goal. Unchanged bars send nothing.
  for (const player of game.players()) {
    const colour = player === leader ? GOLD : "#66ccff";
    const value = pointsOf(player);
    game.widget("points", { kind: "bar", label: "Your points", value, max: goal(), colour }, player);
  }
});

game.onTimeUp(() => {
  const top = topScorer();
  game.endRound(top ?? "draw");
});
