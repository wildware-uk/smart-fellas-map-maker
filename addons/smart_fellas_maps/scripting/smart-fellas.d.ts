// Smart Fellas map scripts: the types and docs for everything a map's script can reach.
//
// Keep this file in your map's scripts folder (Export puts a fresh copy there each time), and any
// editor that knows TypeScript completes and checks your scripts as you type. Write each script as a
// .ts file (or plain .js). Export and Test Map turn them into JavaScript for the game.
//
// Where a script runs is the folder it is in:
// - Directly in the scripts folder: in the host's game only, which decides the match. What it
//   changes reaches every player the way everything else does.
// - In client/: on each player's own PC, for that player alone. Its messages and sounds are for
//   that one screen. It can't change the match: anything else it asks for is ignored.
// - In shared/: in the host's game for real, and on each player's own PC to guess ahead, so a door
//   a player pulls starts moving at once on their screen. On a player's PC only its piece moves,
//   turns, shows and hides happen, as a guess the host's game then confirms or puts right. Its
//   messages and sounds come from the host's game. The copy on a player's PC hears only that
//   player using a switch, and game.random() gives it different numbers, so let it guess from
//   what it reads at the moment (where the door is now), not from counts it keeps.
// - On a player's PC a script reads only what that player's game was sent: a player it wasn't sent
//   has no position.
//
// How a script runs:
// - The scripts in one place are loaded at the start of the match, in name order, and share their
//   globals. The host's game loads shared/ first, then its own. There is no import: the game loads
//   them all itself.
// - Register handlers once, at the top of a file. The game calls them each tick (64 a second).
// - Actions such as door.moveTo() are queued and applied after your handlers finish, so what you
//   read stays as the tick began.
// - There is no clock (no Date) and no Math.random: use game.seconds and game.random().
// - A script that runs too long, uses too much memory, or throws and doesn't catch it is switched
//   off for the rest of the match, and the host sees one line saying why.
// - A bad argument (a name that doesn't exist, a point far outside the map) throws an Error you can
//   catch. A handle to something that has gone does nothing and reads as gone.

/** A point in the map, in metres. y is up. */
interface Point {
  readonly x: number;
  readonly y: number;
  readonly z: number;
}

/** A side in a match: the octopuses (Smart Fellas) or the divers (Fart Smellas). */
type Team = "octopus" | "diver";

/** Where a player is in the round. */
type Life = "alive" | "respawning" | "out" | "waiting";

/** Where the match is. */
type Phase = "lobby" | "play" | "results";

/** How a player was caught: in a creature's jaws, or in a diver's net. */
type Catch = "jaws" | "net";

/** Food a player can eat. */
type FoodKind = "crab" | "clam" | "shrimp" | "wrasse" | "lobster";

/** The creatures a script can find with game.creatures(). */
type CreatureKind =
  | "shark"
  | "eel"
  | "groper"
  | "flounder"
  | "lionfish"
  | "crab"
  | "clam"
  | "shrimp";

/** The creatures and food a script can spawn and remove (the map's fish can't be, yet). */
type SpawnKind = "shark" | "eel" | "groper" | "crab" | "clam" | "shrimp";

/** The sounds a map can play. game.sounds() lists them too. */
type SoundName =
  | "groan"
  | "drip"
  | "rockfall"
  | "whale"
  | "boom"
  | "swell"
  | "hiss"
  | "chime"
  | "roar"
  | "thunk";

/** A number after() or every() gave back, for cancel(). */
type TimerId = number;

/**
 * A player in the match. The same player is always the same object, so === works. Once they have
 * left, `gone` is true, what they were reads as null, and what you ask of them does nothing.
 */
interface Player {
  /** Their number in this match. */
  readonly id: number;
  /** The name they play under. */
  readonly name: string;
  /** Whether they have left the match. */
  readonly gone: boolean;
  /** Their side, or null once gone. */
  readonly team: Team | null;
  /** Where they are in the round, or null once gone. */
  readonly life: Life | null;
  /** Whether they are alive and swimming. */
  readonly alive: boolean;
  /** Where they are, or null while they have no body (waiting, respawning, out or gone). */
  readonly position: Point | null;
  /** Their energy, or null while they have no body (and once gone). */
  readonly energy: number | null;

  /** Moves them to a point within 1000 m of the map's middle. */
  moveTo(x: number, y: number, z: number): void;
  /** Kills them, as the game's own kills do: the kill scene, the score and the respawn all happen. */
  kill(): void;
  /** Gives them energy, or takes it away with a negative number: -1000 to 1000. */
  addEnergy(points: number): void;
  /** Shows them alone a message from the map: 1 to 120 characters, a few a second at most. */
  say(text: string): void;
}

/** A trigger box placed on the map, found by name with game.zone(). */
interface Zone {
  /** Its name on the map. */
  readonly name: string;
  /** Every living player inside it now. */
  players(): Player[];
  /** Calls `handler` each time a player swims in. */
  onEnter(handler: (player: Player) => void): void;
  /** Calls `handler` each time a player swims out. */
  onLeave(handler: (player: Player) => void): void;
  /** Calls `handler` when a spear flies in, with who threw it, if anyone still in the match did. */
  onSpearEnter(handler: (thrower: Player | null) => void): void;
  /** Calls `handler` when a spear leaves, with who threw it. */
  onSpearLeave(handler: (thrower: Player | null) => void): void;
}

/**
 * A piece of the map you named for scripts: in the add-on, add it to the group `script` (or
 * `switch`, for one players can use, such as a lever). Its node's name is its name here.
 */
interface Piece {
  /** Its name on the map. */
  readonly name: string;
  /** Whether players can use it (it is in the `switch` group). */
  readonly isSwitch: boolean;
  /** Where it is, or null before the match's first tick. */
  readonly position: Point | null;
  /** Which way it faces, in degrees round the up axis, or null before the first tick. */
  readonly turn: number | null;
  /** Whether it is shown, or null before the first tick. */
  readonly shown: boolean | null;

  /**
   * Moves it to a point within 1000 m of the map's middle, at once or gliding over 0 to 60 seconds.
   * It is solid on its way, like anything else that moves.
   */
  moveTo(x: number, y: number, z: number, seconds?: number): void;
  /** Turns it to face `degrees` round the up axis (-3600 to 3600), at once or over 0 to 60 seconds. */
  turnTo(degrees: number, seconds?: number): void;
  /** Shows it, solid again. */
  show(): void;
  /** Hides it: nobody sees it or bumps into it. */
  hide(): void;
  /**
   * Calls `handler` each time a player uses it: they press Interact (the eat key) within 1.5 m.
   * Only a switch can be used; asking this of any other piece throws.
   */
  onUse(handler: (player: Player) => void): void;
}

/**
 * A creature or food in the match, placed by the map or spawned by a script. The same one is always
 * the same object. Once it has gone (eaten, killed or removed), `gone` is true and it reads as null.
 */
interface Creature {
  /** Its number in this match. */
  readonly id: number;
  /** What it is. */
  readonly kind: CreatureKind;
  /** Whether it is no longer in the match. */
  readonly gone: boolean;
  /** Whether it is alive. */
  readonly alive: boolean;
  /** Where it is, or null once gone. */
  readonly position: Point | null;
  /** Takes it out of the match. The map's fish (flounder, lionfish) can't be removed yet. */
  remove(): void;
}

/** The match, as the script sees it. */
interface Game {
  /** The match's time, in ticks: 64 a second. */
  readonly ticks: number;
  /** The match's time, in seconds. */
  readonly seconds: number;
  /** Where the match is: in the lobby, playing a round, or showing its results. */
  readonly phase: Phase;
  /** How long the round has left, in seconds. */
  readonly timeLeft: number;

  /** Every player in the match, by number. */
  players(): Player[];
  /** A number from 0 up to (not including) 1, the same series for the same match. */
  random(): number;
  /** Ends the round, with `winner` the team that won it. */
  endRound(winner: Team): void;
  /** Adds time to the round, or takes it away with a negative number: -3600 to 3600 seconds. */
  addTime(seconds: number): void;

  /** The trigger zone with this name, or null if the map has none. */
  zone(name: string): Zone | null;
  /** Every trigger zone on the map. */
  zones(): Zone[];
  /** The piece with this name, or null if no piece is named that. */
  piece(name: string): Piece | null;
  /** Every piece named for scripts. */
  pieces(): Piece[];

  /** Every creature and food in the match, or only those of one kind. */
  creatures(kind?: CreatureKind): Creature[];
  /**
   * Asks the game for a creature or food near a point within 1000 m of the map's middle, and gives
   * back its handle at once. The game puts it where such a thing can be:
   * - food grows on the free food spot nearest the point that suits it, if one is within 10 m
   *   (crabs on sand or rock, shrimp on sand, clams on rock), and doesn't grow back once eaten;
   * - a shark joins its loop round the map at the point nearest yours;
   * - an eel or a groper goes beside the rock nearest the point.
   * Sharks, eels and gropers come only while a round is being played. If the game finds no place,
   * the handle reads as gone from the next tick. A script may have at most 1 shark, 4 eels, 4
   * gropers and 256 of each food it spawned alive at once; asking for more throws.
   */
  spawn(kind: SpawnKind, x: number, y: number, z: number): Creature;

  /** Shows everyone a message from the map: 1 to 120 characters, a few a second at most. */
  say(text: string): void;
  /** Shows one team a message from the map. */
  sayToTeam(team: Team, text: string): void;
  /** Plays one of the game's sounds for everyone, wherever they are. A few a second at most. */
  playSound(sound: SoundName): void;
  /** Plays one of the game's sounds at a point, heard by whoever is near. */
  playSoundAt(sound: SoundName, x: number, y: number, z: number): void;
  /** The names of the sounds a map can play. */
  sounds(): SoundName[];

  /** Calls `handler` once, when the match starts. */
  onMatchStart(handler: () => void): void;
  /** Calls `handler` when a round starts. */
  onRoundStart(handler: () => void): void;
  /** Calls `handler` when a round ends, with the team that won it. */
  onRoundEnd(handler: (winner: Team) => void): void;
  /** Calls `handler` when a player joins the match. */
  onJoin(handler: (player: Player) => void): void;
  /** Calls `handler` when a player leaves the match. Their handle reads as gone from then on. */
  onLeave(handler: (player: Player) => void): void;
  /** Calls `handler` when a player finishes eating something. */
  onEat(handler: (player: Player, food: FoodKind) => void): void;
  /** Calls `handler` when a player is caught, with who caught them, if a player did. */
  onCaught(handler: (player: Player, by: Player | null, how: Catch) => void): void;
  /** Calls `handler` when a player is killed, with who killed them, if a player did. */
  onKilled(handler: (player: Player, by: Player | null) => void): void;
}

/** The match. */
declare const game: Game;

/** Calls `handler` once, `seconds` from now (0 to 86400; 0 is the next tick). */
declare function after(seconds: number, handler: () => void): TimerId;
/** Calls `handler` every `seconds` (0 to 86400; 0 is every tick), until cancelled. */
declare function every(seconds: number, handler: () => void): TimerId;
/** Stops a timer after() or every() gave back. Says whether it was still waiting. */
declare function cancel(timer: TimerId): boolean;
