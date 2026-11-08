// Scripts in client/ run on each player's own PC, for what only their screen shows and hears.
// A player who joins without the mode can get it from the mode's card in the lobby.

game.onRoundStart(() => {
  game.say("Catch Count: every catch is a point. Good luck!");
});
