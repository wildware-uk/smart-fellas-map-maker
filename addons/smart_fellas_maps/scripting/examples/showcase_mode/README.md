# King of the Reef

A whole game mode that shows off the calls new in API 1.1.0. Copy it and play it, or read it to see
how the parts fit together.

A hill, shown as a marker, sits on a spot of the map. Every second, each player on it scores a point,
or two if they hold it alone. Every so often the hill glides to a new spot. The leader swims a little
slower. The first to the lobby's goal wins the round; when time runs out, the top scorer does.

## What it uses

| Call | For |
| --- | --- |
| `StateMachine` | the round's phases: waiting, the hill open, the hill moving |
| `tween`, `Ease`, `Vec.lerp` | gliding the hill's marker to its next spot |
| `Random` | picking the next spot |
| `store` | each player's points, dashes and inks, emptied each round by itself |
| `game.playersNear` | who is on the hill |
| `game.marker` | the hill, seen through rock |
| `game.widget` | a countdown to the hill moving, the leader's name, and each player's own points bar |
| `game.announce`, `player.announce` | big text as the hill opens and moves, and for a new leader |
| `player.setSpeed` | slowing the leader |
| `game.playSoundForTeam`, `player.playSound` | sounds as the phases change, and for a new leader |
| `game.onDash`, `game.onInk` | counting dashes and inks on the scoreboard |
| `log` | lines in the host's log, to follow what it does |

## Try it

Copy this folder into your modes folder (in the game: **Workshop > Modes > My modes**, then **Open
modes folder**), and copy `smart-fellas.d.ts` into its `scripts/` folder for your editor. Host a game
and pick **King of the Reef** under **Game mode**.
