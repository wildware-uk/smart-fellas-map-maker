// Smart Fellas map scripts: the types and docs for everything a map's script can reach.
//
// Keep this file in your map's scripts folder (Export puts a fresh copy there each time), and any
// editor that knows TypeScript completes and checks your scripts as you type. Write each script as a
// .ts file (or plain .js). Export and Test Map turn them into JavaScript for the game.
//
// The modding wiki has a guide to every part, with examples to copy:
// https://github.com/wildware-uk/smart-fellas-modding/wiki
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
// - There is no clock (no Date) and no Math.random: use game.seconds and game.random(), or a
//   Random of your own.
// - Every script also has the helpers at the end of this file: Vec, Maths, Random, Ease, tween,
//   StateMachine, store and log.
// - A script that runs too long, uses too much memory, or throws and doesn't catch it is switched
//   off for the rest of the match, and the host sees one line saying why.
// - A bad argument (a name that doesn't exist, a point far outside the map) throws an Error you can
//   catch. A handle to something that has gone does nothing and reads as gone.
//
// Game modes use the same calls. A mode is a folder with a mode.json (its name, description, player
// counts and the lobby settings it offers) and a scripts/ folder laid out as a map's. The host picks
// the mode in the lobby, apart from the map, and the mode's scripts run beside the map's in a world
// of their own: each numbers the players for itself. The mode's run first each tick.
// Every round is played by a mode, Classic and Infected included: they ship as modes in the same
// shape. The game has no win checks of its own: the mode ends the round with game.endRound(). A
// round can't start until the mode's script is running. When the clock runs out (and isn't held),
// the mode hears onTimeUp; if it doesn't end the round on that tick, the round ends as a draw. A
// mode whose script stops ends a round being played as a draw, and the match goes back to Classic.
//
// mode.json may also say, each optional:
// - "minDivers", "minOctopuses": the fewest players on each team a round may start with (0);
// - "teamLines": { "octopus": "...", "diver": "..." }, the lines under each team's name in the
//   lobby (a team the mode adds says its own, in game.registerTeam), and "startLines" the same shape, the lines under the banner as the hunt starts (1 to 60
//   characters each);
// - "look": "catches" or "turns" for the game's own octopuses-left count and results (Classic's,
//   Infected's), or left out for the mode's own scoreboard and banner;
// - "revives": true if the lobby's Revives setting applies: a netted octopus may be freed.
// The calls marked "for game modes" change the round's rules. A map's script may use them too, and
// the mode then hears what happened through its own events (onTeamChange, onRoundEnd).
// The calls marked "on the host only" work only in the host's game: a client/ script's call does
// nothing. The host's game decides them and sends them to the players they are for.
// An object a call takes (a spec, a point) is read for the values it holds itself, as an object
// literal or a Vec point does: a value from a getter, from its prototype or through a Proxy reads as
// left out, so none of the script's own code runs inside a call.

/** A point in the map, in metres. y is up. */
interface Point {
  readonly x: number;
  readonly y: number;
  readonly z: number;
}

/** Where a ray first met the map: from `game.raycast` and `game.groundBelow`. */
interface RayHit {
  /** The point it met the map's rock, sand or pieces. */
  readonly point: Point;
  /** Which way that surface faces, one metre long: straight up on flat ground. */
  readonly normal: Point;
  /** How far from the ray's start, in metres. */
  readonly distance: number;
}

/** The box players swim in, from its lowest corner to its highest. */
interface PlayArea {
  readonly min: Point;
  readonly max: Point;
}

/**
 * A side in a match: the octopuses (Smart Fellas), the divers (Fart Smellas), or a team the game
 * mode added with game.registerTeam, by the id it gave it.
 */
type Team = "octopus" | "diver" | (string & {});

/** A team a game mode adds of its own (game.registerTeam). */
interface TeamSpec {
  /** What players read, 1 to 24 characters. */
  name: string;
  /** Its colour, "#rrggbb". */
  colour: string;
  /** The creature its players drive, with their own keys and mouse; a bot's swims on its own. */
  body: "shark";
  /** The most players it may have, people and bots, 1 to 32. */
  most: number;
  /** Whose start points it comes in at: "octopus" (all over the map, the default) or "diver". */
  spawns?: "octopus" | "diver";
  /** The line under its name in the lobby, at most 60 characters. */
  line?: string;
  /** The line under the banner its players see as the hunt starts, at most 60 characters. */
  startLine?: string;
}
/**
 * An ability a game mode gives one of its own teams (game.registerAbility). The game shows it on
 * the HUD of that team's players with its key, its name and its cooldown, and aims it for them: it
 * goes off only when someone they can see (not hidden, behind rock or in ink) is near the middle
 * of their screen and within `range`.
 */
interface AbilitySpec {
  /** The team whose players have it: one the mode added with game.registerTeam. */
  team: Team;
  /** Which of the team's two ability keys it is on: 1 is the player's Dash key, 2 their Ink key. */
  slot: 1 | 2;
  /** What players read under its button, 1 to 16 characters. */
  name: string;
  /** Seconds from one use to the next, up to 600 (at least a quarter of a second). */
  cooldown: number;
  /** How far off whoever it is aimed at may be, 1 to 60 metres. */
  range: number;
  /**
   * If given, the user's creature darts straight at whoever it was aimed at: at `speed` (1 to 40
   * metres a second) for at most `metres` (1 to 60). Rock stops it. game.onAbilityLand hears it
   * get there.
   */
  lunge?: { speed: number; metres: number };
}

/** A tool a diver may carry (game.loadout). */
type Tool = "spear" | "net" | "sensor" | "torch";

/**
 * Something a player does that a script may switch off for them alone, with player.allow(): an
 * octopus's dash, ink, grab and smell, and a diver's gun ("shoot", whichever gun they carry).
 */
type Skill = "dash" | "ink" | "grab" | "smell" | "shoot";

/** Where a player is in the round. */
type Life = "alive" | "respawning" | "out" | "waiting";

/** Where the match is. */
type Phase = "lobby" | "play" | "results";

/** How a player was caught: in a creature's jaws, or in a diver's net. */
type Catch = "jaws" | "net";

/** Food a player can eat. */
type FoodKind = "crab" | "clam" | "shrimp" | "wrasse" | "lobster";

/** The creatures and food a script can find with game.creatures(), spawn and remove. */
type CreatureKind =
  | "shark"
  | "eel"
  | "groper"
  | "flounder"
  | "lionfish"
  | "crab"
  | "clam"
  | "shrimp";

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
 * What being caught or killed does to a player of a team (for game modes):
 * - "out": out for the rest of the round;
 * - "held": out, and a netted octopus stays in its net where a teammate could free it;
 * - "respawn": back after the wait, at the team's spawn;
 * - "turn": back after the wait, on the other team.
 */
type Fate = "out" | "held" | "respawn" | "turn";

/**
 * What a bot is after (for game modes). The bot's own brain still swims it there.
 * - "own": its usual play: an octopus hides, a diver hunts;
 * - "hide": an octopus hides as usual; a diver keeps still;
 * - "flee": away from the nearest foe it can see;
 * - "roam": wanders about;
 * - "hunt": a diver hunts as usual; an octopus goes after the nearest diver it can see;
 * - "goTo": swims to a point and stays there.
 *
 * A bot on a team the mode added (game.registerTeam) heeds "own" and "hunt" only. With "own" its
 * creature swims on its own brain, as a wild one does. With "hunt" the bot plays it as a person
 * would, through the same controls: it goes for the nearest player of another team it can see
 * (nobody hidden, behind rock or in ink), bites when it is close, uses its team's abilities
 * (game.registerAbility) when they are ready, and between chases looks round the food patches that
 * have food on them.
 */
type Goal = "own" | "hide" | "flee" | "roam" | "hunt" | "goTo";

/**
 * One of the game's own lines for why a round ended, for game.endRound():
 * - "allCaught": every octopus was caught (speared, netted, starved or eaten);
 * - "allTurned": every octopus was caught and turned into a diver;
 * - "timeUp": time ran out and the octopuses survived;
 * - "diversLeft": every diver left;
 * - "octopusesLeft": every octopus left.
 */
type EndWhy = "allCaught" | "allTurned" | "timeUp" | "diversLeft" | "octopusesLeft";

/** The value of one of a game mode's lobby settings: a number, a choice's name, or a toggle. */
type SettingValue = number | string | boolean;

/**
 * Who sees something on screen (game.announce, game.widget, game.marker): one team, or one player.
 * Leave it out for everyone.
 */
type Viewers = Team | Player;

/** One HUD widget (game.widget), drawn in a column on the left of the screen, under the banner. */
interface WidgetSpec {
  /** "text": a line of text; "bar": a filling bar; "counter": a number; "timer": a countdown. */
  kind: "text" | "bar" | "counter" | "timer";
  /** The small label above it, 0 to 24 characters. */
  label?: string;
  /** "text": what it says, 0 to 40 characters. */
  text?: string;
  /** "bar": how full, 0 to max; "counter": the number shown (whole numbers shown without decimals). */
  value?: number;
  /** "bar": the value that fills it (1 if left out). */
  max?: number;
  /** "timer": the seconds it counts down from, now (0 to 86400). Shown as m:ss, stops at 0:00. */
  seconds?: number;
  /** Its colour, "#rrggbb" (white if left out). */
  colour?: string;
}

/**
 * A menu (game.menu): a card on the right of the screen with a title over 2 to 5 choices. Players
 * pick one with the number keys 1 to 5 (on the top row or the number pad), or on a controller move
 * along it with the D-pad's up and down and pick with right. Those keys and buttons do nothing else
 * while it shows. Picking closes it for them.
 */
interface MenuSpec {
  /** The question or heading, 1 to 60 characters. */
  title: string;
  /** 2 to 5 choices, each 1 to 30 characters, in the order of the keys that pick them. */
  choices: string[];
  /** How long it stays open by itself, in seconds (above 0, up to 600, counted down under it). Left out, it stays until picked from or closed. */
  seconds?: number;
}

/** How a vote (game.vote) came out. */
interface VoteResult {
  /** The choice with the most answers, or null when nobody answered or the most are tied. */
  readonly winner: string | null;
  /** Where the winner is in the vote's choices (0 for the first), or null as for `winner`. */
  readonly index: number | null;
  /** How many answered each choice, in the order of the choices. */
  readonly counts: readonly number[];
}

/** What game.vote asks: like a menu, but `seconds` must be given, from 1 to 600. */
interface VoteSpec {
  title: string;
  choices: string[];
  seconds: number;
}

/** A marker (game.marker) at a point in the world, seen through rock, with its distance under it. */
interface MarkerSpec {
  /** Where it is, within 1000 m of the map's middle. Give this or `on`, not both. */
  at?: Point;
  /**
   * The player it rides over, moving with them, in place of `at`. A screen shows it only while that
   * screen is sent the player's body, as when they are near enough to see, so it never shows anyone
   * more than their own game knows. Not shown while the player has no body (waiting, respawning, out
   * or gone). New in 1.6.0.
   */
  on?: Player;
  /** The text over it, 0 to 24 characters. */
  label?: string;
  /** Its colour, "#rrggbb" (white if left out). */
  colour?: string;
}

/**
 * The water as game.setWater changes it. Anything left out stays as the map has it.
 */
interface WaterSpec {
  /** The colour far things fade into, "#rrggbb". */
  colour?: string;
  /** How far anyone sees through it, in metres, from 5 to 300. Bots see through it as far. */
  visibility?: number;
  /**
   * How bright it is, as a share of the map's own light, from 0 to 2: 0.2 is dim, 1 is as the
   * map has it, 2 twice as bright. Unless `colour` is given too, the haze dims or brightens with it.
   */
  light?: number;
}

/** A light (game.light) at a point in the world, lighting what is near it. */
interface LightSpec {
  /** Where it is, within 1000 m of the map's middle. */
  at: Point;
  /** Its colour, "#rrggbb" (white if left out). */
  colour?: string;
  /** How strong it is, from 0 to 10: 1, the default, is about as bright as a diver's torch. */
  strength?: number;
  /** How far it reaches, in metres, from 1 to 40 (10 if left out). */
  range?: number;
}

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

  /** Whether the player is one of the game's bots. */
  readonly isBot: boolean;
  /** Their score this round, as the match's scripts set it (0 at the start of each round). */
  readonly score: number;
  /**
   * Their role this round, as the match's scripts set it ("" for none). Only the host's scripts know
   * it: it is never sent to players, so a mode can keep roles secret.
   */
  readonly role: string;

  /**
   * Moves them to the other team, at any time (for game modes). One alive gets a fresh body at the
   * new team's start at once (from onRoundStart, at the start the round gives that team, as if they
   * had chosen it); one waiting for a round waits on the new team. They go back to the team they
   * chose when the lobby comes back. It takes effect after this tick: until the next one they still
   * read as on their old team.
   */
  setTeam(team: Team): void;
  /**
   * Gives them a role for this round, kept on the host and shown nowhere by itself: 0 to 24
   * characters, "" for none (for game modes).
   */
  setRole(role: string): void;
  /** Sets their score: a whole number from -1000000000 to 1000000000 (for game modes). */
  setScore(points: number): void;
  /** Adds to their score, or takes away with a negative number (for game modes). */
  addScore(points: number): void;
  /**
   * Brings them back now, if they are out or waiting to respawn in a round being played: at a point
   * within 1000 m of the map's middle, or where their team comes back (for game modes).
   */
  respawn(x?: number, y?: number, z?: number): void;
  /** Takes this bot out of the match, and one fewer of its team's bots is asked for (bots only). */
  removeBot(): void;
  /** Gives this bot something to be after; "goTo" takes a point (bots only, for game modes). */
  setGoal(goal: Goal, x?: number, y?: number, z?: number): void;
  /**
   * The creature they drive takes `target` in its jaws, as its own bite landing does: the catch, the
   * kill and its credit all happen, wherever the two are. Nothing happens unless both are alive in
   * a round being played, they drive a creature that bites (a shark), and its mouth is empty (for
   * game modes).
   */
  bite(target: Player): void;
  /**
   * Sets their cell under one of the columns game.scoreboard() named: a number, or text of 0 to 16
   * characters (for game modes).
   */
  setCell(column: string, value: number | string): void;
  /**
   * Shows them alone a line under the banner, until it is changed or a round starts, or the lobby
   * comes back: 0 to 80 characters, "" to clear it. It is on screen, not in chat (for game modes).
   */
  setLine(text: string): void;

  /**
   * Their speed as a share of normal: 1 is normal, 0 held still; null once gone. On the host it is
   * what scripts set; on a player's PC it is what that PC was sent for them (1 if nothing).
   */
  readonly speed: number | null;
  /**
   * Sets their speed as a share of normal, 0 to 3: 0 holds them still (they can still look round and
   * use abilities), 1 is normal, 3 is three times as fast. It works for octopuses and divers: it
   * scales swimming and crawling, while dashes keep their own pace. A creature a player drives (a
   * shark on a mode's team) keeps its own speed. It stays until changed, and goes back to normal
   * when a round starts and when the lobby comes back (on the host only).
   */
  setSpeed(share: number): void;
  /** Plays one of the game's sounds for them alone, wherever they are (in a client/ script, on that player's own screen only). */
  playSound(sound: SoundName): void;
  /**
   * Shows them alone big text in the middle of the screen, as game.announce does for more players:
   * 1 to 60 characters, for 0.5 to 15 seconds (3 if left out). It counts as a message from the map,
   * with the same limits as game.say (in a client/ script, on that player's own screen only).
   */
  announce(text: string, seconds?: number): void;

  /**
   * Switches one of their skills off, or on again with true. A skill switched off does nothing when
   * they use it: pressing it (or starting to hold smell) plays a soft "no", an octopus's button for
   * it shows faint, and a diver's crosshair dot dims. Switching grab off lets go of whatever they hold, and stops a grab on its way. Ink or a shot already on
   * its way finishes. It stays until changed, through deaths and respawns, and every skill comes
   * back as a round starts and when the lobby comes back, so switch them off in onRoundStart (on
   * the host only).
   */
  allow(skill: Skill, allowed: boolean): void;
  /**
   * Whether a skill works for them (true unless a script switched it off); null once gone. On a
   * player's PC it is what that PC was sent for them.
   */
  allowed(skill: Skill): boolean | null;

  /**
   * A store of values of their own, kept from round to round for the whole match. It is let go at
   * the first round start after they leave, so onLeave can still read it. Each set of scripts has
   * its own, as with store.
   */
  readonly data: Store;
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
  /** Takes it out of the match, on every player's screen. */
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
  /**
   * Ends the round, with `winner` the team that won it, or one player (where everyone plays for
   * themselves, in a game mode), or "draw" for nobody. The results say why with the game's own line
   * named by `why`, or else that the map (or the game mode) decided. `why` must fit the winning
   * team: "allCaught", "allTurned" and "octopusesLeft" are the divers' wins, "timeUp" and
   * "diversLeft" the octopuses'. Give `text` (up to 80 characters) to say why in your own words
   * instead; pass null for `why` to give only that: game.endRound("red", null, "Red held the reef").
   */
  endRound(winner: Team | Player | "draw", why?: EndWhy | null, text?: string): void;
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
   * - an eel or a groper goes beside the rock nearest the point;
   * - a lionfish hovers at the point, lifted clear of any rock, and a flounder lies on the seabed
   *   under it, if the seabed is within 50 m. Every player sees them, players who join later too.
   * Sharks, eels and gropers come only while a round is being played. If the game finds no place,
   * the handle reads as gone from the next tick. A script may have at most 1 shark, 4 eels, 4
   * gropers, 256 of each food and 256 fish it spawned alive at once; asking for more throws.
   */
  spawn(kind: CreatureKind, x: number, y: number, z: number): Creature;

  /**
   * Living players with a position within `radius` metres of `point`, nearest first; only `team`'s if
   * given. On a player's PC it finds only the players that PC was sent.
   */
  playersNear(point: Point, radius: number, team?: Team): Player[];
  /**
   * The nearest living player with a position, of `team` if given, leaving out `except` (say, the
   * player asking); or null if there is none.
   */
  nearestPlayer(point: Point, team?: Team, except?: Player): Player | null;
  /** Living creatures and food within `radius` metres of `point`, nearest first; only `kind`'s if given. */
  creaturesNear(point: Point, radius: number, kind?: CreatureKind): Creature[];
  /** The nearest living creature or food, of `kind` if given; or null if there is none. */
  nearestCreature(point: Point, kind?: CreatureKind): Creature | null;

  /** The box players swim in. Fixed for the match. */
  readonly playArea: PlayArea;
  /**
   * Casts a ray from `from` to `to` through the map and settles with where it first met the map's
   * rock, sand or pieces, or null if nothing is in the way. It meets only the map: players,
   * creatures, plants and the play area's edge are let through. The answer comes on the next tick
   * (a sixty-fourth of a second), so `await` it. Both ends must be within 1000 m of the map's
   * middle. At most 32 rays a tick; asking for more throws. Every script can use it.
   */
  raycast(from: Point, to: Point): Promise<RayHit | null>;
  /** Whether nothing of the map stands between `a` and `b`: true when a ray between them meets nothing. One ray. */
  lineOfSight(a: Point, b: Point): Promise<boolean>;
  /** The ground straight under `point`, down to under the play area's floor; or null if there is none. One ray. */
  groundBelow(point: Point): Promise<RayHit | null>;

  /** Shows everyone a message from the map: 1 to 120 characters, a few a second at most. */
  say(text: string): void;
  /** Shows one team a message from the map. */
  sayToTeam(team: Team, text: string): void;
  /** Plays one of the game's sounds for everyone, wherever they are. A few a second at most. */
  playSound(sound: SoundName): void;
  /** Plays one of the game's sounds for one team only, wherever they are (in a client/ script, on that player's own screen only). */
  playSoundForTeam(team: Team, sound: SoundName): void;
  /** Plays one of the game's sounds at a point, heard by whoever is near. */
  playSoundAt(sound: SoundName, x: number, y: number, z: number): void;
  /** The names of the sounds a map can play. */
  sounds(): SoundName[];

  /**
   * The value of the game mode's lobby setting with this name in its mode.json, as the host chose
   * it, or null if it has none (for game modes; a map's script reads null).
   */
  setting(name: string): SettingValue | null;
  /** A team's score this round, as the match's scripts set it. */
  teamScore(team: Team): number;
  /** Sets a team's score: a whole number from -1000000000 to 1000000000 (for game modes). */
  setTeamScore(team: Team, points: number): void;
  /** Adds to a team's score, or takes away with a negative number (for game modes). */
  addTeamScore(team: Team, points: number): void;
  /**
   * Everyone plays for themselves: nobody is anyone's teammate. No names over rivals' heads, no
   * shared pings, team chat or diver radio, every diver may hurt every other whatever the lobby's
   * friendly fire says, and diver bots fight rival divers as well as hunting octopuses (for game
   * modes).
   */
  freeForAll(on: boolean): void;
  /**
   * What divers carry, from "spear" (the spear gun), "net" (the net gun), "sensor" (motion sensors)
   * and "torch" (the lamp), each once, with at least one gun. With one gun only, divers get that gun
   * whatever the lobby's Gun setting, and the lobby shows it as set by the mode. What they lack isn't
   * on their screen. Until a script calls it, divers carry everything (for game modes).
   */
  loadout(team: "diver", ...tools: Tool[]): void;
  /**
   * Closes a team to people in the lobby: its Join button greys out with `why` (1 to 60 characters)
   * under it, and asking to join it is refused. Nobody already on it is moved; use setTeam for that
   * (for game modes).
   */
  closeTeam(team: Team, why: string): void;
  /** Opens a team closed by closeTeam again (for game modes). */
  openTeam(team: Team): void;
  /**
   * Adds a team of the mode's own, or changes one it added: `id` (1 to 16 lower-case letters) is
   * what every call that takes a team calls it from then on. Its players each drive a creature of
   * `team.body`; bots fill it with setBots, and people join it in the lobby like any team. A mode may
   * add 2. Call it from onMatchStart: a mode being left takes its teams with it, and anyone on one
   * goes back to the octopuses or the divers (for game modes).
   */
  registerTeam(id: string, team: TeamSpec): void;
  /**
   * Gives a team the mode added an ability, or changes one it gave: `id` (1 to 16 lower-case
   * letters) is what onAbility and onAbilityLand call it. A team may have 2, one in each slot. The
   * game does the key, the HUD button, the cooldown and the aiming; what the ability does is up to
   * the handlers. Call it from onMatchStart, after registerTeam (for game modes).
   *
   * For a picture of its own on the button, put a square PNG named after the id in the mode's
   * `icons` folder, beside `scripts`: `icons/quickdash.png` for the id "quickdash". Up to 512 KB
   * and 1024 pixels across each, and 8 in a mode; it is drawn round, so keep what matters away from the corners. Without
   * one the button shows a plain arrow.
   */
  registerAbility(id: string, ability: AbilitySpec): void;
  /**
   * The mode alone decides how many bots a team has, with setBots: the lobby hides the host's bot
   * count for that team and says the mode sets it (for game modes).
   */
  modeBots(team: Team, on: boolean): void;
  /**
   * Asks for `count` bots on a team, 0 to 32. The lobby keeps that many, and a round being played
   * gets or loses them at once. People always keep their places: no more bots join than the
   * team's cap in the lobby, the game's 32 players and the mode's maxPlayers have room for (for
   * game modes).
   */
  setBots(team: Team, count: number): void;
  /**
   * What being caught or killed does to a team's players, with the wait for "respawn" and "turn": 0
   * to 600 seconds, or the lobby's respawn time when left out (for game modes). Until a script sets
   * it, octopuses are "held" and divers "respawn". A player who turns is marked as turned for the
   * rest of the round, on the scoreboard and the results.
   */
  setFate(team: Team, fate: Fate, seconds?: number): void;
  /** Where a team's players come back, at a point within 1000 m of the map's middle (for game modes). */
  setSpawn(team: Team, x: number, y: number, z: number): void;
  /** A team's players come back at their own start points again (for game modes). */
  clearSpawn(team: Team): void;
  /** Sets the time left in a round being played: 0 to 86400 seconds (for game modes). */
  setTimeLeft(seconds: number): void;
  /** Holds the round's clock still, or lets it run again (for game modes). */
  holdClock(held: boolean): void;
  /**
   * Names the live scoreboard's columns, up to 6 of 1 to 16 characters, each once, shown beside each
   * player's name and score during the round and on the results. None hides it (for game modes).
   * Every person is listed; a bot only once the match's scripts give it a score or a cell
   * (setScore, addScore, setCell), even 0 or "", so bots a mode leaves alone stay off.
   */
  scoreboard(...columns: string[]): void;
  /** Shows everyone a banner across the top: 0 to 80 characters, "" to clear it (for game modes). */
  banner(text: string): void;

  /**
   * Shows big text in the middle of the screen: 1 to 60 characters, for `seconds` (0.5 to 15, 3 if
   * left out). A new one replaces the one showing. It counts as a message from the map, towards the
   * same limits as game.say: at most 3 a tick and 6 a second for any one player, and a call that
   * would go over throws. `viewers` is one team or one player; leave it out for everyone (in a
   * client/ script, on that player's own screen only).
   */
  announce(text: string, seconds?: number, viewers?: Viewers): void;
  /**
   * Shows a HUD widget in the column on the left of the screen, under the banner, or changes the
   * one with this id: `id` is 1 to 16 letters, digits, - or _. At most 8 widgets show on any
   * player's screen: a 9th isn't shown on that screen (no error), and changing or removing those
   * already there always works. They stay until removed, or until the lobby comes back. A call that
   * changes nothing sends nothing, so it is fine to call it every tick; when a script changes a lot
   * at once, each player is sent a few changes a tick and the latest of each wins. A "timer" counts
   * down by itself: asking for it again with the same seconds doesn't restart it; new seconds do.
   * A player who joins later sees what is showing for everyone and for their team, and one who
   * moves to another team swaps the old team's for the new one's. A map's and a mode's widgets
   * never share an id, and a client/ script's own widgets have their own room of 8. `viewers` is one team or one player; leave it out for
   * everyone (in a client/ script, on that player's own screen only).
   */
  widget(id: string, spec: WidgetSpec, viewers?: Viewers): void;
  /**
   * Takes the widget with this id off the screens of `viewers`, or everyone's if left out
   * (in a client/ script, on that player's own screen only).
   */
  removeWidget(id: string, viewers?: Viewers): void;
  /**
   * Shows a marker in the world, or moves or changes the one with this id (ids as for widget). At
   * most 16 show on any player's screen: a 17th isn't shown on that screen (no error), and changing
   * or removing those already there always works. Like widgets, it reaches players who join later.
   * `viewers` is one team or one player; leave it out for everyone (in a client/ script, on that player's own screen only).
   */
  marker(id: string, spec: MarkerSpec, viewers?: Viewers): void;
  /**
   * Takes the marker with this id off the screens of `viewers`, or everyone's if left out
   * (in a client/ script, on that player's own screen only).
   */
  removeMarker(id: string, viewers?: Viewers): void;
  /**
   * Opens a menu (ids as for widget) on the screens of `viewers`, or everyone's if left out. A
   * player has one menu at a time: a new one takes the place of the one they have. A pick calls
   * game.onChoose's handlers and closes the menu for that player; open it again to let them pick
   * again. It is shown to who is in the match now, not to players who join later, and the lobby
   * closes every menu. Host scripts only: in a client/ script it does nothing. At most 16 menu
   * and removeMenu calls a tick; more throws.
   */
  menu(id: string, spec: MenuSpec, viewers?: Viewers): void;
  /** Closes the menu with this id for `viewers`, or everyone, if they still have it. */
  removeMenu(id: string, viewers?: Viewers): void;
  /**
   * Puts a question to `viewers` (or everyone) as a menu, and settles with how it came out once
   * `seconds` are up or every person shown it has answered, whichever comes first. Each person's
   * first pick counts; bots never answer and aren't waited for. Its menu's id is "vote-" and a
   * number, and its picks reach game.onChoose too. Host scripts only.
   */
  vote(spec: VoteSpec, viewers?: Viewers): Promise<VoteResult>;

  /**
   * Changes the water for everyone: its colour, how far anyone sees through it and how bright it
   * is, each left as the map has it when left out. It fades in over `seconds` (0 to 60; at once if
   * left out). A new call takes the place of the last, from the water shown then. Players who join
   * later get it, and the lobby gives back the map's own. Host scripts only: in a client/ script it
   * does nothing.
   */
  setWater(spec: WaterSpec, seconds?: number): void;
  /** Gives back the map's own water, fading over `seconds` (0 to 60; at once if left out). */
  resetWater(seconds?: number): void;
  /**
   * Puts up a light for everyone, or moves or changes the one with this id (ids as for widget). At
   * most 16 are up at once, the map's and the mode's together: a 17th isn't put up (no error), and
   * changing or removing those already up always works. Lights cast no shadows. Players who join
   * later get them, and the lobby takes them all down. Host scripts only.
   */
  light(id: string, spec: LightSpec): void;
  /** Takes down the light with this id, if it is up. */
  removeLight(id: string): void;

  /** Calls `handler` once, when the match starts. */
  onMatchStart(handler: () => void): void;
  /** Calls `handler` when a round starts. */
  onRoundStart(handler: () => void): void;
  /**
   * Calls `handler` when a round ends, with the team that won it, or null and the player who won it,
   * or null and null for a draw.
   */
  onRoundEnd(handler: (winner: Team | null, player: Player | null) => void): void;
  /**
   * Calls `handler` when a player comes back in a round being played, after being out or waiting
   * to respawn. The lobby's warm-up bodies aren't respawns.
   */
  onRespawn(handler: (player: Player) => void): void;
  /** Calls `handler` when a player moves to the other team, whatever moved them. */
  onTeamChange(handler: (player: Player, from: Team, to: Team) => void): void;
  /**
   * Calls `handler` when the round's clock runs out, in a game mode. End the round on that tick, or
   * it ends as a draw.
   */
  onTimeUp(handler: () => void): void;
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
  /**
   * Calls `handler` when a player uses one of the mode's abilities (game.registerAbility), with its
   * id and who it was aimed at. Its cooldown has started; a lunge, if it has one, is on its way.
   */
  onAbility(handler: (player: Player, ability: string, target: Player) => void): void;
  /** Calls `handler` when an ability's lunge reaches who it was aimed at. */
  onAbilityLand(handler: (player: Player, ability: string, target: Player) => void): void;
  /**
   * Calls `handler` when a player dashes (octopuses only). Heard on the host only. onDash, onInk and onGrab are
   * for octopuses only: a mode's own team's ability keys are heard with onAbility.
   */
  onDash(handler: (player: Player) => void): void;
  /** Calls `handler` when an octopus squirts ink. Heard on the host only. */
  onInk(handler: (player: Player) => void): void;
  /** Calls `handler` when an octopus grabs at something. Heard on the host only. */
  onGrab(handler: (player: Player) => void): void;
  /** Calls `handler` when a diver fires either gun. Heard on the host only. */
  onShoot(handler: (player: Player) => void): void;
  /**
   * Calls `handler` when a player picks from a menu this script opened (game.menu), with the menu's
   * id, where the choice is in its list (0 for the first) and the choice's text. Each menu a player
   * is shown is picked from once at most; a pick after it closed is never heard.
   */
  onChoose(handler: (player: Player, menu: string, choice: number, text: string) => void): void;
}

/** The match. */
declare const game: Game;

/** Calls `handler` once, `seconds` from now (0 to 86400; 0 is the next tick). */
declare function after(seconds: number, handler: () => void): TimerId;
/** Calls `handler` every `seconds` (0 to 86400; 0 is every tick), until cancelled. */
declare function every(seconds: number, handler: () => void): TimerId;
/** Stops a timer after() or every() gave back. Says whether it was still waiting. */
declare function cancel(timer: TimerId): boolean;

// Helpers: plain JavaScript every script has, on the host and on players' PCs alike. They change
// nothing in the match by themselves.

/** Vector maths on points ({x, y, z}). Every call gives back a new point and leaves its inputs alone. */
declare const Vec: {
  /** A point from its three parts. */
  of(x: number, y: number, z: number): Point;
  /** The point {0, 0, 0}. */
  readonly zero: Point;
  /** The point {0, 1, 0}: one metre straight up. */
  readonly up: Point;
  /** a and b added together. */
  add(a: Point, b: Point): Point;
  /** b taken away from a: the way from b to a. */
  sub(a: Point, b: Point): Point;
  /** a made `by` times as long. */
  scale(a: Point, by: number): Point;
  /** How long a is, in metres. */
  length(a: Point): number;
  /** How far apart a and b are, in metres. */
  distance(a: Point, b: Point): number;
  /** a made 1 long, pointing the same way; or Vec.zero if a has no length. */
  normalize(a: Point): Point;
  /** The dot product of a and b. */
  dot(a: Point, b: Point): number;
  /** The cross product of a and b: a point at right angles to both. */
  cross(a: Point, b: Point): Point;
  /** The point `t` of the way from a to b: t 0 is a, 1 is b, 0.5 halfway. */
  lerp(a: Point, b: Point, t: number): Point;
  /** a with y set to 0: for distances across the map, ignoring depth. */
  flat(a: Point): Point;
};

/** Number helpers the built-in Math lacks. */
declare const Maths: {
  /** value kept from low to high. */
  clamp(value: number, low: number, high: number): number;
  /** The number `t` of the way from `from` to `to`: t 0 is from, 1 is to. */
  lerp(from: number, to: number, t: number): number;
  /** How far value is from `from` to `to`, as 0 to 1 (not clamped: it can be below 0 or above 1). */
  inverseLerp(from: number, to: number, value: number): number;
  /** value moved from the range inLow to inHigh into the range outLow to outHigh. */
  remap(value: number, inLow: number, inHigh: number, outLow: number, outHigh: number): number;
  /** Degrees to radians. */
  toRadians(degrees: number): number;
  /** Radians to degrees. */
  toDegrees(radians: number): number;
  /** degrees brought into the range above -180 and up to 180. */
  wrapDegrees(degrees: number): number;
  /** current moved towards target by at most step, never past it. */
  approach(current: number, target: number, step: number): number;
};

/**
 * Random numbers from a seed of your own: the same seed gives the same numbers, in the same order,
 * on every PC. Use game.random() for numbers nobody can guess ahead.
 */
declare class Random {
  /** A series of random numbers that starts from `seed`. */
  constructor(seed: number);
  /** A number from 0 up to (not including) 1. */
  next(): number;
  /** A number from low up to (not including) high. */
  range(low: number, high: number): number;
  /** A whole number from low to high, both included. */
  int(low: number, high: number): number;
  /** true with the chance `p`: 0 never, 1 always, 0.25 one time in four. */
  chance(p: number): boolean;
  /** One item of the list, or undefined if it is empty. */
  pick<T>(list: readonly T[]): T | undefined;
  /** Shuffles the list in place and gives it back. */
  shuffle<T>(list: T[]): T[];
}

/** An easing curve: takes t from 0 to 1 and gives back the eased value (0 at 0, 1 at 1). */
type Easing = (t: number) => number;

/**
 * Easing curves, for tween() or to call yourself, as in Maths.lerp(a, b, Ease.outQuad(t)). "in"
 * starts slow, "out" ends slow, "inOut" does both. outBack goes a little past the end and settles
 * back, outBounce bounces, outElastic wobbles.
 */
declare const Ease: {
  linear: Easing;
  inQuad: Easing;
  outQuad: Easing;
  inOutQuad: Easing;
  inCubic: Easing;
  outCubic: Easing;
  inOutCubic: Easing;
  inSine: Easing;
  outSine: Easing;
  inOutSine: Easing;
  outBack: Easing;
  outBounce: Easing;
  outElastic: Easing;
};

/**
 * Calls `step` every tick for `seconds` (0 to 86400; anything else throws), with how far along it
 * is: 0 to 1, eased (Ease.linear if left out). The last call is always with 1, then `done` is
 * called. Gives back a timer: cancel() it to stop it early.
 */
declare function tween(
  seconds: number,
  step: (t: number) => void,
  options?: { ease?: Easing; done?: () => void },
): TimerId;

/** One state of a StateMachine. Each part is optional. */
interface State {
  /** Called when the machine goes into this state. */
  enter?(): void;
  /** Called every tick while in this state, with the seconds since it went in. */
  tick?(seconds: number): void;
  /** Called when the machine leaves this state. */
  leave?(): void;
}

/**
 * A set of named states, in one at a time, ticked every tick by itself, whatever the match's phase
 * (in the lobby too). It goes into `start` at once. If a state calls go() on its own machine, give the machine's type by hand:
 * `const phases: StateMachine<"wait" | "play"> = new StateMachine({ ... }, "wait");`.
 */
declare class StateMachine<S extends string = string> {
  /** The states by name, and the one to start in. */
  constructor(states: Record<S, State>, start: S);
  /** The state it is in. */
  readonly state: S;
  /** Seconds since it went into the state it is in. */
  readonly seconds: number;
  /** Leaves the state it is in and goes into `state`. Going into the same one starts it again. */
  go(state: S): void;
  /** Stops ticking it, for good. */
  stop(): void;
}

/** Values kept by name: the round's store, and each player's data. */
interface Store {
  /** The value kept under `key`, or `fallback` if there is none. */
  get<T = unknown>(key: string, fallback?: T): T;
  /** Keeps `value` under `key`. */
  set(key: string, value: unknown): void;
  /** Adds `by` (1 if left out) to the number kept under `key` (0 if none) and gives back the sum. */
  add(key: string, by?: number): number;
  /** Whether anything is kept under `key`. */
  has(key: string): boolean;
  /** Forgets `key`. Says whether anything was kept under it. */
  delete(key: string): boolean;
  /** Every key with something kept under it. */
  keys(): string[];
  /** Forgets everything. */
  clear(): void;
}

/**
 * A store of values by name, for this round: it is emptied as each round starts, before your
 * onRoundStart runs. Each set of scripts has its own: the map's and the mode's don't share one, and
 * each PC's scripts have their own. For values about one player that last the match, use
 * player.data.
 */
declare const store: Store;

/**
 * Writes a line to the game's log on the PC the script runs on: the host's for scripts on the host,
 * that player's own for client/ scripts. The log is the console, and the log file in the logs folder
 * beside the game's settings. Each line starts "map script:" or "mode script:", then the values
 * joined by spaces, objects as JSON. At most 20 lines a second; more are dropped. Each line is cut
 * at 200 characters.
 */
declare function log(...values: unknown[]): void;
