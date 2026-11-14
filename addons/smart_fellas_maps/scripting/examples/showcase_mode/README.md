# King of the Reef

A whole game mode that shows off a wide spread of the API. Copy it and play it, or read it to see
how the parts fit together.

A hill, shown as a marker and a light, sits on a spot of the map. As each round starts, players vote
for a big hill or a small one worth double. Every second, each player on the hill scores a point, or
more if they hold it alone. Every so often the hill glides to a new spot, and whoever is last slips
away unseen for a few seconds to get there first. The leader wears a crown: they swim slower and
can't ink. In the last 30 seconds the reef goes dark. The first to the lobby's goal wins the round;
when time runs out, the top scorer does. Round wins add up over the match on the scoreboard.

## What it uses

| Call | For |
| --- | --- |
| `game.setting` | the lobby's goal and how long the hill stays |
| `StateMachine` | the round's phases: the vote, the hill open, the hill moving |
| `game.vote` | the players' pick of a big or a small hill, as each round starts |
| `tween`, `Ease`, `Vec`, `Maths` | gliding the hill to its next spot, keeping it in the play area, its light's strength |
| `Random` | picking the next spot, and where shrimp grow |
| `game.nearestCreature`, `game.creaturesNear`, `game.spawn` | finding food spots for the hill, and growing shrimp by it |
| `game.playArea`, `game.groundBelow` | keeping the hill inside the map, and settling it on the ground |
| `store` | each player's points, dashes and inks this round, emptied each round by itself |
| `player.data` | each player's round wins, kept for the whole match |
| `game.playersNear` | who is on the hill |
| `game.marker` | the hill, seen through rock, and a crown riding over the leader (`on: player`) |
| `game.light` | a light over the hill, burning brighter as its time runs out |
| `game.setWater`, `game.resetWater` | the reef going dark in the last 30 seconds |
| `game.widget` | a countdown to the vote's end and the hill moving, the leader's name, and each player's own points bar |
| `game.announce`, `player.announce` | big text as the hill opens and moves, and for the leader and the hidden player |
| `player.setSpeed`, `player.allow`, `player.allowed` | slowing the leader, and taking their ink away |
| `player.botLevel`, `player.setBotLevel` | a leading bot plays easy, and gets its own level back after |
| `player.setInvisible` | the player in last place slipping away unseen while the hill moves |
| `game.playSound`, `game.playSoundAt`, `player.playSound` | sounds as the phases change, at the hill, and for a new leader |
| `game.onDash`, `game.onInk` | counting dashes and inks on the scoreboard |
| `game.onRoundEnd`, `game.onJoin`, `game.onLeave` | counting wins, and showing them to players who join |
| `game.endRound` | the winner, with a line of the mode's own on the results |
| `log` | lines in the host's log, to follow what it does |

## Try it

Copy this folder into your modes folder (in the game: **Workshop > Modes > My modes**, then **Open
modes folder**), and copy `smart-fellas.d.ts` into its `scripts/` folder for your editor. Host a game
and pick **King of the Reef** under **Game mode**.
