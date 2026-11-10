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

/** A point in the map, in metres. y is up. */
interface Point {
  readonly x: number;
  readonly y: number;
  readonly z: number;
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
   * "diversLeft" the octopuses'.
   */
  endRound(winner: Team | Player | "draw", why?: EndWhy): void;
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
}

/** The match. */
declare const game: Game;

/** Calls `handler` once, `seconds` from now (0 to 86400; 0 is the next tick). */
declare function after(seconds: number, handler: () => void): TimerId;
/** Calls `handler` every `seconds` (0 to 86400; 0 is every tick), until cancelled. */
declare function every(seconds: number, handler: () => void): TimerId;
/** Stops a timer after() or every() gave back. Says whether it was still waiting. */
declare function cancel(timer: TimerId): boolean;
