#if defined _JB_GuardsSystem_included
 #endinput
#endif
#define _JB_GuardsSystem_included

enum GuardRank
{
	Guard_NotGuard = 0, 
	Guard_Normal, 
	Guard_Main
}

/**
 * Adds a vote ct game item to the core menu.
 * 
 * @param name               Name of the vote ct.
 * @param description        Description of the vote ct.
 * @return                  Vote CT index.
 */
native int JB_AddVoteCT(char[] name, char[] description);

/**
 * Gets a client's guard rank.
 * 
 * @param client             Client index.
 * @return                  The client's guard rank.
 * @error                  If the client is not connected, an error will be thrown.
 */
native GuardRank JB_GetClientGuardRank(int client);

/**
 * Sets a client's guard rank.
 * 
 * @param client             Client index.
 * @param rank               Guard rank to set.
 * @error                  If the client is not connected, an error will be thrown.
 */
native void JB_SetClientGuardRank(int client, GuardRank rank);

/**
 * Finds and returns the vote ct index, by searching the index with the given name.
 * 
 * @param name               The name for the specified vote ct.
 * @return                  Vote CT index, or -1 if there is no vote ct matching the given name.
 */
native int JB_FindVoteCT(char[] name);

/**
 * Sets a client as the vote ct winner, as well as sets him the main guard.
 * 
 * @param voteId                   Vote CT index to set the winner to.
 * @param client                   Client index to set as the main guard, -1 if no winner available.
 * @param additionalText           Additional text to be shown on on the menu.
 * @error                         If the client is not connected, an error will be thrown.
 */
native void JB_SetVoteCTWinner(int voteId, int client, const char[] additionalText = "");

/**
 * Starts a new vote ct.
 * 
 * @param broadcast					If true, a note message will be printed at the moment the vote started.
 * @return 						   True if the Vote CT successfully executed, false otherwise.
 * 
 * @note							False will be thrown for the next reasons: 
 *									1. A special day is running.
 *									2. A last request game is running.
 *									3. Another Vote CT is already activated.
 */
native bool JB_StartVoteCT(bool broadcast = true);

/**
 * Stops the current active vote ct.
 * 
 * @param broadcast					If true, a note message will be printed at the moment the vote stopped.
 * @return 						   True if the Vote CT successfully stopped, false if there is no Vote CT activated.
 */
native bool JB_StopVoteCT(bool broadcast = true);

/**
 * Checks if a vote ct is running.
 * 
 * @return            True if running, false otherwise.
 */
native bool JB_IsVoteCTRunning();

/**
 * Checks if the main guard is in the middle of the invite period.
 * 
 * @return            True if the invite period is running, false otherwise.
 */
native bool JB_IsInvitePeriodRunning();

/**
 * Adds a ban ct to a specific client.
 * 
 * @param client                   Client index to add the ban ct to.
 * @param client                   Admin index the banned has added by, or -1 if not valid.
 * @param length                   Amount of minutes for the ban ct.
 * @param reason                   Reason for the ban ct, optional. 
 * @error                         If the client/admin is not connected, an error will be thrown.
 */
native void JB_AddBanCT(int client, int admin, int length, const char[] reason = "");

/**
 * Checks if a client is banned from being a guard.
 * 
 * @param client                   Client index.
 * @return                 	      True if the client is banned from being a guard, false otherwise.
 * @error                        If the client is not connected, an error will be thrown.
 */
native bool JB_IsClientBannedCT(int client);

/**
 * Called when the vote ct has just started.
 * 
 * @param action            True if the initial vote is an action vote, false otherwise.
 */
forward void JB_OnVoteCTStart(bool action);

/**
 * Called when a vote ct method has selected. (Vote CT has ended)
 * 
 * @param voteId              The chosen Vote CT method index, or -1 if remain the same has chosen.
 */
forward void JB_OnVoteCTEnd(int voteId);

/**
 * Called once the current active vote ct should be stopped. (An admin typed /stopvotect)
 * 
 * 
 */
forward void JB_OnVoteCTStop();

/**
 * Called when an admin has banned a client from being a guard.
 * 
 * @param client              Client index that the ban ct was executed on.
 * @param admin               Admin index who executed the action, or -1 if not valid.
 * @param length              Time in minutes for the exclusion.
 * @param reason              Ban reason.
 */
forward void JB_OnBanCTExecuted(int client, int admin, int length, const char[] reason);

/**
 * Called when a client opens the main menu.
 * 
 * @param client              Client index.
 * @param menu                Menu handle, aviliable for menu managment.
 */
forward void JB_OnOpenMainGuardMenu(int client, Menu menu);

/**
 * Called when a client pressed on a item in the main menu.
 * 
 * @param client              Client index.
 * @param itemInfo            Menu item's info.
 */
forward void JB_OnPressMainGuardMenu(int client, const char[] itemInfo);

stock int GetRandomGuard(bool bAlive = true, bool includeMainGuard = true)
{
	int iCounter = 0;
	int[] iClients = new int[MaxClients];
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && JB_GetClientGuardRank(iCurrentClient) != Guard_NotGuard && !IsFakeClient(iCurrentClient))
		{
			if (!includeMainGuard && JB_GetClientGuardRank(iCurrentClient) == Guard_Main) {
				continue;
			}
			
			if (bAlive) {
				if (IsPlayerAlive(iCurrentClient)) {
					iClients[iCounter++] = iCurrentClient;
				}
			} else {
				iClients[iCounter++] = iCurrentClient;
			}
		}
	}
	
	return iCounter ? iClients[GetRandomInt(0, iCounter - 1)]:-1;
}

stock int GetMainGuardIndex()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && JB_GetClientGuardRank(iCurrentClient) == Guard_Main && !IsFakeClient(iCurrentClient)) {
			return iCurrentClient;
		}
	}
	
	return -1;
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_GuardsSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_AddVoteCT");
	MarkNativeAsOptional("JB_GetClientGuardRank");
	MarkNativeAsOptional("JB_SetClientGuardRank");
	MarkNativeAsOptional("JB_FindVoteCT");
	MarkNativeAsOptional("JB_SetVoteCTWinner");
	MarkNativeAsOptional("JB_IsVoteCTRunning");
	MarkNativeAsOptional("JB_AddBanCT");
	MarkNativeAsOptional("JB_IsClientBannedCT");
}
#endif

public SharedPlugin __pl_JB_GuardsSystem = 
{
	name = "JB_GuardsSystem", 
	file = "JB_GuardsSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 