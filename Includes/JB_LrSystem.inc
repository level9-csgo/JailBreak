#if defined _JB_LrSystem_included
 #endinput
#endif
#define _JB_LrSystem_included

#define INVALID_LR_WINNER -1
#define INVALID_LR_LOSER -1

#define LRS_PARENT_SOUNDS_DIR "last_request"

enum
{
	Part_Prisoner = 0, 
	Part_Guard,
	Part_Max
}

/**
 * Adds a last request game to the core menu.
 * 
 * @param name               Name of the last request.
 * @param weaponPickup       Allowing game participants to pick up weapons, false to disable.
 * @param weaponDrop         Allowing game participants to drop their weapons, false to disable.
 * @param activateBeacons    If true, beacons will spawn near the participants during the game.
 * @param includeRandom      If true, the game will be included in the random lr chose.
 * @return                Last request game index.
 */
native int JB_AddLr(char[] name, bool weaponPickup, bool weaponDrop, bool activateBeacons, bool includeRandom);

/**
 * Checks if a last request game is running.
 * 
 * @return            True if running, false otherwise.
 */
native bool JB_IsLrRunning();

/**
 * Checks if a the last request period time is running.
 * 
 * @return            True if running, false otherwise.
 */
native bool JB_IsLrPeriodRunning();

/**
 * Finds and returns the last request index, by searching the index with the given name.
 * 
 * @param name               The name for the specified last request.
 * @return                  Last request index, or -1 if there is no last request matching the given name.
 */
native int JB_FindLr(char[] name);

/**
 * Starts the current looking last request game.
 *
 * @param prisoner         Prisoner index.
 * @param guard            Guard index.
 * @param lrWeapon         Lr played weapon, can be replaced with a custom icon name.
 * @param sound            If true, The game will be continued until the end of the round.
 * 						    Also the activated game sound wont be played once the game started.
 * @error                If the one of the client(s) is not connected, an error will be thrown.
 */
native void JB_StartLr(int prisoner, int guard, char[] lrWeapon, bool continued = false);

/**
 * Stops the current activated last request game.
 * 
 * @return 				True if the last request game successfully stopped, false if there is no last request game activated.
 *
 */
native bool JB_StopLr();

/**
 * Shows the last requests list main menu to a specific client, as well as starts the last request countdown.
 * 
 * @param client             Client index.
 * @param perform_countdown  True to perform the countdow, false otherwise.
 *
 * @error                   If the client is not connected, an error will be thrown.
 */
native void JB_ShowLrMainMenu(int client, bool perform_countdown = false);

/**
 * Called when a last request game has selected. 
 * 
 * @param client            Client index that selected the last request.
 * @param lrId              The chosen last request game index.
 */
forward void JB_OnLrSelected(int client, int lrId);

/**
 * Called when a random last request game has selected. 
 * 
 * @param client            Client index that selected the last request.
 * @param selectedLr        The selected last request game index.
 */
forward void JB_OnRandomLrSelected(int client, int selectedLr);

/**
 * Called after the last request information panel has created and displayed.
 * 
 * @param panel               Panel handle, aviliable for panel managment.
 * @param currentLr           The current running last request index.
 */
forward void JB_OnShowLrInfoMenu(Panel panel, int currentLr);

/**
 * Called when a last request game has stopped or ended.
 * 
 * @param currentLr         The current running last request index, or -1 if there is no running lr game.
 * @param lrName            The current running last request name, or null string if there is no running lr game.
 * @param winner            Client index of the winner, INVALID_LR_WINNER if there is no winner.
 * @param loser             Client index of the loser, INVALID_LR_LOSER if there is no loser.
 * @param aborted           True if an admin has typed '/abortlr', false otherwise.
 */
forward void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted);

/**
 * Checks if a last request game is currently available.
 * 
 * @param target             Target index to perform the checks on.
 * @param client             Client index to print a message on error.
 *
 * @return 					 True if a last request game is currently available, false otherwise.
 * @error                    If one of client is not connected, an error will be thrown.
 */
stock bool IsLrAvailable(int target, int client)
{
	if (!IsPlayerAlive(target) || GetClientTeam(target) != CS_TEAM_T)
	{
		PrintToChat(client, "%s Last Request allowed to \x04alive\x01 prisoner only.", PREFIX_ERROR);
		return false;
	}
	
	if (GetOnlineTeamCount(CS_TEAM_T) > 1 || GetOnlineTeamCount(CS_TEAM_CT) < 1)
	{
		PrintToChat(client, "%s Last Request allowed only when there is \x041\x01 prisoner alive and atleast \x041\x01 guard alive.", PREFIX_ERROR);
		return false;
	}
	
	if (JB_IsLrRunning())
	{
		PrintToChat(client, "%s There is another Last Request game running!", PREFIX_ERROR);
		return false;
	}
	
	return true;
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_LrSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_AddLr");
	MarkNativeAsOptional("JB_IsLrRunning");
	MarkNativeAsOptional("JB_FindLr");
	MarkNativeAsOptional("JB_StartLr");
	MarkNativeAsOptional("JB_StopLr");
	MarkNativeAsOptional("JB_ShowLrMainMenu");
}
#endif

public SharedPlugin __pl_JB_LrSystem = 
{
	name = "JB_LrSystem", 
	file = "JB_LrSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 