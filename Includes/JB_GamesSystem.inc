#if defined _JB_GamesSystem_included
 #endinput
#endif
#define _JB_GamesSystem_included

#define INVALID_GAME_WINNER -1

/**
 * Creates a side game item to the core menu.
 * 
 * @param name               Name of the side game.
 *
 * @return                   Game array index.
 */
native int JB_CreateGame(char[] name);

/**
 * Finds and returns the game index, by searching the index with the given name.
 * 
 * @param name               The name for the specified side game.
 *
 * @return                   Game index, or -1 if there is no side game matching the given name.
 */
native int JB_FindGame(char[] name);

/**
 * Sets a client as the side game winner.
 * 
 * @param gameId                   Game index to set the winner to.
 * @param client                   Client index to set as the game winner, -1 if no winner available.
 *
 * @return 						   True if the game successfully stopped, false otherwise.						
 * @error                          If the client is not connected, an error will be thrown.
 */
native bool JB_StopGame(int gameId, int client);

/**
 * Called when a guard/admin has started a side game.
 * 
 * @param gameId                   Game index.
 * @param client              	   Client index who executed the game.
 */
forward void JB_OnGameStart(int gameId, int client);

/**
 * Called when side game has been stopped.
 * 
 * @param gameId                   Game index.
 * @param winner              	   Winner client index.
 */
forward void JB_OnGameStop(int gameId, int winner);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_GamesSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateGame");
	MarkNativeAsOptional("JB_FindGame");
	MarkNativeAsOptional("JB_StopGame");
}
#endif

public SharedPlugin __pl_JB_GamesSystem = 
{
	name = "JB_GamesSystem", 
	file = "JB_GamesSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 