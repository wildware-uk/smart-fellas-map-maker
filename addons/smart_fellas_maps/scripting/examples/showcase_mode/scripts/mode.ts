// King of the Reef: a game mode that shows off a wide spread of the API.
//
// A hill, shown as a marker and a light, sits on a spot of the map. As each round starts, players
// vote for a big hill or a small one worth more. Every second, each player on the hill scores, more
// if they hold it alone. Every so often the hill glides to a new spot, and whoever is last slips
// away unseen for a few seconds to get there first. The leader wears a crown everyone near can see:
// they swim slower and can't ink. In the last 30 seconds the reef goes dark. The first to the
// lobby's goal wins the round; when time runs out, the top scorer does. Round wins add up over the
// match on the scoreboard.
//
// Every map has food, so the hill goes where the food grows: open spots players can reach.

const MOVE_SECONDS = 4; // how long the hill takes to glide to its next spot
const VOTE_SECONDS = 8; // how long the vote for the hill's size stays open
const GHOST_SECONDS = 6; // how long whoever is last stays unseen when the hill moves
const DARK_SECONDS = 30; // the reef goes dark with this many seconds left
const LEADER_SPEED = 0.8; // the leader swims at this share of normal speed
const GOLD = "#ffcc33";
const BLUE = "#66ccff";
const WHITE = "#ffffff";

// The hills players vote between: how far from its middle counts as on it, and the points a second
// for one player on it alone, or for each of several.
interface HillSize {
  readonly name: string;
  readonly radius: number;
  readonly alone: number;
  readonly shared: number;
}
const SIZES: readonly HillSize[] = [
  { name: "Big hill", radius: 9, alone: 2, shared: 1 },
  { name: "Small hill, double points", radius: 4, alone: 4, shared: 2 },
];

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

// Round wins last the whole match, so they live in each player's own data.
function showWins(player: Player): void {
  player.setCell("Wins", player.data.get("wins", 0));
}

// Where the hill is now, its size this round, and our own random numbers, so pick() is at hand.
let hill: Point = Vec.zero;
let size: HillSize = SIZES[0];
let random = new Random(1);
let leader: Player | null = null;
let ghost: Player | null = null;
let glide: TimerId | null = null;
let votes = 0; // counts votes, so a late answer from an old round is let go

// Keeps a point inside the box players swim in, 5 m from its walls.
function inPlayArea(at: Point): Point {
  const { min, max } = game.playArea;
  return Vec.of(
    Maths.clamp(at.x, min.x + 5, max.x - 5),
    Maths.clamp(at.y, min.y + 5, max.y - 5),
    Maths.clamp(at.z, min.z + 5, max.z - 5),
  );
}

// The next spot: a food item at least 15 m across the map from the hill now, or else where some
// player is. It asks for the food nearest a few random points: listing every food item on a busy
// map and reading where each is would take a big share of a tick's work.
const FOOD: readonly CreatureKind[] = ["crab", "clam", "shrimp"];
function nextSpot(): Point {
  const far = (at: Point) => Vec.distance(Vec.flat(at), Vec.flat(hill)) > 15;
  const { min, max } = game.playArea;
  for (let tries = 0; tries < 8; tries++) {
    const guess = Vec.of(random.range(min.x, max.x), hill.y, random.range(min.z, max.z));
    const at = game.nearestCreature(guess, random.pick(FOOD))?.position;
    if (at && far(at)) {
      return inPlayArea(at);
    }
  }
  const players = game
    .players()
    .map((player) => player.position)
    .filter((at): at is Point => at !== null);
  return inPlayArea(random.pick(players) ?? hill);
}

// The hill's marker, lifted a little off the seabed so it isn't buried in the sand, and its light
// above it. The light burns brighter as the hill's time runs out.
function showHill(colour: string): void {
  game.marker("hill", { at: Vec.add(hill, Vec.scale(Vec.up, 1.5)), label: "Hill", colour });
  const strength =
    phases.state === "hold" ? Maths.remap(phases.seconds, 0, holdSeconds(), 2, 5) : 1.5;
  game.light("hill", { at: Vec.add(hill, Vec.scale(Vec.up, 4)), colour, strength, range: 16 });
}

// A few shrimp grow by the hill as it opens, unless some are there already.
function feedTheHill(): void {
  if (game.creaturesNear(hill, 10, "shrimp").length < 3) {
    for (let i = 0; i < 3; i++) {
      const at = Vec.add(hill, Vec.of(random.range(-4, 4), 0, random.range(-4, 4)));
      game.spawn("shrimp", at.x, at.y, at.z);
    }
  }
}

// The leader swims slower, can't ink, and wears a crown: a marker over them that a screen shows
// only while it can see them anyway. A leading bot plays easy, and gets its own level back after.
function crown(top: Player | null): void {
  if (top === leader) {
    return;
  }
  const old = leader;
  if (old) {
    old.setSpeed(1);
    if (old.allowed("ink") === false) {
      old.allow("ink", true);
    }
    const level = store.get<BotLevel | null>(`level:${old.id}`, null);
    if (level) {
      old.setBotLevel(level);
    }
  }
  leader = top;
  if (!top) {
    game.removeMarker("crown");
    game.removeWidget("leader");
    return;
  }
  top.setSpeed(LEADER_SPEED);
  top.allow("ink", false);
  if (top.isBot && top.botLevel) {
    store.set(`level:${top.id}`, top.botLevel);
    top.setBotLevel("easy");
  }
  game.marker("crown", { on: top, label: "Leader", colour: GOLD });
  top.playSound("roar");
  top.announce("You lead! The crown is heavy", 3);
  game.widget("leader", { kind: "text", label: "Leader", text: top.name, colour: GOLD });
}

// Whoever has the fewest points slips away unseen while the hill moves: nobody else's game is sent
// them. Only with 3 or more in the match, and never the leader.
function hideTheLast(): void {
  const players = game.players().filter((player) => !player.gone && player.alive);
  if (players.length < 3) {
    return;
  }
  const last = players.reduce((low, player) => (pointsOf(player) < pointsOf(low) ? player : low));
  if (last === leader) {
    return;
  }
  ghost = last;
  last.setInvisible(true);
  last.announce("Nobody can see you. Get to the hill!", 3);
  after(GHOST_SECONDS, () => {
    if (ghost === last) {
      last.setInvisible(false);
      ghost = null;
    }
  });
}

// The round's phases. "idle" is between rounds. The machine's type is written out because its
// states call phases.go() themselves.
type HillPhase = "idle" | "vote" | "hold" | "move";
const phases: StateMachine<HillPhase> = new StateMachine<HillPhase>(
  {
    // A state machine goes into its first state at once, while the script loads, when it can't act
    // yet: so "idle" does nothing, and the round's end clears the screen.
    idle: {},
    vote: {
      enter() {
        hill = nextSpot();
        showHill(WHITE);
        game.announce("King of the Reef", 3);
        game.widget("phase", { kind: "timer", label: "Vote ends in", seconds: VOTE_SECONDS });
        // Bots never answer, so a round of bots alone gets the first choice. A vote still open when
        // the round ends closes by itself when its time is up, and its answer is let go.
        const vote = ++votes;
        game
          .vote({ title: "Which hill?", choices: SIZES.map((hill) => hill.name), seconds: VOTE_SECONDS })
          .then((result) => {
            if (vote !== votes || phases.state !== "vote") {
              return;
            }
            size = SIZES[result.index ?? 0];
            log("vote", result.counts, "picked", size.name);
            phases.go("hold");
          });
      },
    },
    hold: {
      enter() {
        showHill(GOLD);
        feedTheHill();
        game.announce(`${size.name}: hold it!`, 2);
        // A timer widget counts down by itself: set it once.
        game.widget("phase", {
          kind: "timer",
          label: "Hill moves in",
          seconds: holdSeconds(),
          colour: GOLD,
        });
        game.playSoundAt("chime", hill.x, hill.y, hill.z);
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
        let to = nextSpot();
        log("hill moves from", from, "to", to);
        // A spot where a player was may be in open water: the ray's answer comes next tick and
        // settles the hill on the ground under it, while it is already gliding there.
        game.groundBelow(Vec.add(to, Vec.scale(Vec.up, 2))).then((ground) => {
          if (ground && ground.normal.y > 0.5) {
            to = ground.point;
          }
        });
        game.announce("The hill is moving!", 2);
        game.widget("phase", { kind: "text", label: "Hill", text: "On the move..." });
        game.playSound("swell");
        hideTheLast();
        // Glide the marker and its light to the new spot, easing in and out, then open it again.
        glide = tween(
          MOVE_SECONDS,
          (t) => {
            hill = Vec.lerp(from, to, t);
            showHill(WHITE);
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
  // The score column shows each player's points; short columns of our own count round wins, dashes
  // and inks.
  game.scoreboard("Wins", "Dash", "Ink");
  // Nobody is out for good: whoever is caught comes back after 5 seconds.
  game.setFate("octopus", "respawn", 5);
  game.setFate("diver", "respawn", 5);
});

game.onRoundStart(() => {
  random = new Random(Math.floor(game.random() * 1000000));
  leader = null;
  ghost = null;
  size = SIZES[0];
  log("round starts; goal", goal(), "hold", holdSeconds());
  game.banner(`Hold the hill. First to ${goal()} points wins`);
  for (const player of game.players()) {
    showWins(player);
    player.setCell("Dash", 0);
    player.setCell("Ink", 0);
  }
  phases.go("vote");
});

game.onRoundEnd((_team, winner) => {
  if (winner) {
    winner.data.add("wins");
    showWins(winner);
  }
  // Give the leader back their speed, ink and bot level, and let the last one be seen again.
  crown(null);
  ghost?.setInvisible(false);
  ghost = null;
  phases.go("idle");
  game.removeMarker("hill");
  game.removeLight("hill");
  game.removeWidget("phase");
  game.removeWidget("points");
  game.resetWater(3);
});

game.onJoin((player) => showWins(player));

game.onLeave((player) => {
  if (player === leader) {
    crown(null);
  }
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

every(1, () => {
  if (game.phase !== "play") {
    return;
  }
  // The last seconds: the water dims and closes in over 5 seconds, once a round.
  if (game.timeLeft <= DARK_SECONDS && !store.has("dark")) {
    store.set("dark", true);
    game.setWater({ light: 0.4, visibility: 35 }, 5);
    game.announce("The reef goes dark...", 3);
  }
  if (phases.state !== "hold") {
    return;
  }
  showHill(GOLD);
  const onHill = game.playersNear(hill, size.radius);
  for (const player of onHill) {
    const points = store.add(`points:${player.id}`, onHill.length === 1 ? size.alone : size.shared);
    player.setScore(points);
    if (points >= goal()) {
      game.announce(`${player.name} is King of the Reef!`, 4);
      game.endRound(player, null, `${player.name} reached ${goal()} points`);
      return;
    }
  }
  crown(topScorer());
  // Each player's own bar: how close they are to the goal. Unchanged bars send nothing.
  for (const player of game.players()) {
    const colour = player === leader ? GOLD : BLUE;
    const value = pointsOf(player);
    game.widget("points", { kind: "bar", label: "Your points", value, max: goal(), colour }, player);
  }
});

game.onTimeUp(() => {
  const top = topScorer();
  if (top) {
    game.endRound(top, null, `${top.name} led when time ran out`);
  } else {
    game.endRound("draw");
  }
});
