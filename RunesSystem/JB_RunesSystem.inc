#if defined _JB_RunesSystem_included
 #endinput
#endif
#define _JB_RunesSystem_included

#define RUNE_STAR_SYMBOL "✰"

enum
{
	RuneStar_1 = 1, 
	RuneStar_2, 
	RuneStar_3, 
	RuneStar_4, 
	RuneStar_5, 
	RuneStar_6, 
	RuneStar_Max
}

enum
{
	RuneLevel_1 = 1, 
	RuneLevel_2, 
	RuneLevel_3, 
	RuneLevel_4, 
	RuneLevel_5, 
	RuneLevel_6, 
	RuneLevel_7, 
	RuneLevel_8, 
	RuneLevel_9, 
	RuneLevel_10, 
	RuneLevel_11, 
	RuneLevel_12, 
	RuneLevel_13, 
	RuneLevel_14, 
	RuneLevel_15, 
	RuneLevel_Max
}

enum RunePickupBlockReasons
{
	RUNE_PICKUP_BLOCK_NONE,		/**< No block occurred */
	RUNE_PICKUP_BLOCK_GUARD,	/**< Block caused due to the client is guard, and there is prisoners alive */
	RUNE_PICKUP_BLOCK_CAPACITY, /**< Block caused due to the client's runes capatity is maxed out */
	RUNE_PICKUP_BLOCK_FORWARD   /**< Block originates from a forward */
}

enum struct Rune
{
	char szRuneUnique[64];
	char szRuneName[64];
	char szRuneDesc[128];
	char szRuneSymbol[32];
	
	ArrayList RuneBenefits;
	char szRuneBenefitText[32];
}

enum struct ClientRune
{
	int iRuneId;
	int iRuneStar;
	int iRuneLevel;
	bool bIsRuneEquipped;
}

/**
 * Creates a rune item inside the core.
 * 
 * @param unique        	Unique name for the rune, used for item locating.
 * @param name        		Rune's dispaly name.
 * @param desc        		Rune's description, will be shown inside the display menu.
 * @param symbol        	A unique rune symbol to be displayed and seperate from other rune items.
 * @param benefits			An arraylist contains the rune benefits.
 * @param benefitText		The benefit text that will be displayed in the rune detail menu.
 * 
 * @return                  Rune index.
 */
native int JB_CreateRune(char[] unique, char[] name, char[] desc, char[] symbol, ArrayList benefits, char[] benefitText);

/**
 * Finds and returns the rune index, by searching the index with the given unique.
 * 
 * @param unique             The unique for the rune.
 *
 * @return                  Rune index, or -1 if there is no rune matching the given unique.
 */
native int JB_FindRune(char[] unique);

/**
 * Gets a rune data struct.
 * 
 * @param runeIndex         Rune index.
 * @param runeData          Destination buffer to store the data inside.
 */
native void JB_GetRuneData(int runeIndex, any[] runeData);

/**
 * Gets the rune types amount.
 * 
 * @return 					Rune types amount.
 */
native int JB_GetRunesAmount(); 

/**
 * Gets a certain rune benefit stats by the specified rune information.
 * 
 * @param runeIndex         Rune index.
 * @param star         		Rune star.
 * @param level         	Rune level.
 * 
 * @return					The rune benefit stats. (May be integer/float)
 * @error					Invalid given rune index, star, or level.
 */
native any JB_GetRuneBenefitStats(int runeIndex, int star, int level);

/**
 * Returns a client rune data struct.
 * 
 * @param client             	Client index.
 * @param clientRuneIndex       Client rune array index to get the data from.
 * @param structData      		Result varrible to store the client rune data struct inside.
 * 
 * @error                       If the client is not connected, or the specified client rune index is invalid, an error will be thrown.
 */
native void JB_GetClientRuneData(int client, int clientRuneIndex, any[] structData);

/**
 * Returns a client rune data struct.
 * 
 * @param client             	Client index.
 * @param clientRuneIndex       Client rune array index to set the data to.
 * @param structData      		Client rune struct to set the data as.
 * 
 * @error                       If the client is not connected, or the specified client rune index is invalid, an error will be thrown.
 */
native void JB_SetClientRuneData(int client, int clientRuneIndex, any[] structData);

/**
 * Returns a equipped client rune index, by searching with a regular rune index.
 * 
 * @param client             	Client index.
 * @param runeIndex       		Rune index to search with.
 *
 * @return					    Client rune index of the equipped rune, or -1 if there is no equipped rune matching the given rune index.
 * @error                       If the client is not connected, an error will be thrown.
 */
native int JB_GetClientEquippedRune(int client, int runeIndex);

/**
 * Adds a rune to the client runes inventory by the specified infromation.
 * 
 * @param client             	Client index.
 * @param runeIndex       		Rune index type to give, or -1 for random rune type.
 * @param star      			Rune star, or 0 to use the regular spawn chances.
 * @param level      			Rune level, or 0 to randomaly generate a rune level.
 * @param amount				Amount of times to add the rune, 1 by default.
 *
 * @return 						True if the client rune has added successfully, false if the client runes capacity is full.
 * @error                       If the client is not connected, or one of specified data is invalid, an error will be thrown.
 */
native bool JB_AddClientRune(int client, int runeIndex, int star, int level, int amount = 1);

/**
 * Removes a rune from the client runes inventory by the specified client rune index.
 * 
 * @param client             	Client index.
 * @param clientRuneIndex      	Client rune index to remove.
 *
 * @error                       If the client is not connected, or the client rune index is invalid, an error will be thrown.
 */
native void JB_RemoveClientRune(int client, int clientRuneIndex);

/**
 * Checks if a client has a certain rune by the given native parameters.
 * 
 * @param client             	Client index.
 * @param runeIndex		      	Rune index.
 * @param star					Rune star, or -1 for local check.
 * @param level					Rune level, or -1 for local check.
 * 
 * @return						Client rune index if the client do have the rune by the given parameters, -1 otherwise.
 * @error                       If the client is not connected, or the rune index is invalid, an error will be thrown.
 */
native int JB_IsClientHasRune(int client, int runeIndex, int star = -1, int level = -1);

/**
 * Gets the runes capacity amount of a certain client.
 * 
 * @param client             	Client index.
 *
 * @return						Client runes capacity amount.	
 * @error                       If the client is not connected, an error will be thrown.
 */
native int JB_GetClientRunesCapacity(int client);

/**
 * Gets the runes inventory items amount of a certain client.
 * 
 * @param client             	Client index.
 *
 * @return						Client runes inventory amount.
 * @error                       If the client is not connected, an error will be thrown.
 */
native int JB_GetClientRunesAmount(int client);

/**
 * Gets the amount of times the client owns the rune by the given native parameters.
 * 
 * @param client             	Client index.
 * @param runeIndex		      	Rune index.
 * @param star					Rune star, or -1 for local check.
 * @param level					Rune level, or -1 for local check.
 * 
 * @return						The amount of times the client owns the rune, or 0 if none.
 * @error                       If the client is not connected, or the rune index is invalid, an error will be thrown.
 */
native int JB_GetClientOwnedRunes(int client, int runeIndex, int star = -1, int level = -1);

/**
 * Performs a rune level upgrade by the given success chances to a certain client rune.
 * 
 * @param client             	Client index.
 * @param clientRuneIndex      	Client rune index to perform the upgrade on.
 * @param successChances		Chances for the upgrade to succeed.
 * @param replicate				If true, the function will call the rune level upgrade forward.
 *
 * @return						True if the upgrade has succeed, false otherwise.
 * @error                       If the client is not connected, the client rune index is invalid, or the rune level is maxed out, an error will be thrown.
 */
native bool JB_PerformRuneLevelUpgrade(int client, int clientRuneIndex, int successChances, bool replicate = true);

/**
 * Toggles a certain rune, controls whenther the rune will function or not.
 * 
 * @param runeIndex		    Rune index to toggle.
 * @param toggleMode        Toggle mode to set the rune as.
 *
 * @return                 True in successful, false if a error has occurred.
 */
native bool JB_ToggleRune(int runeIndex, bool toggleMode);

/**
 * Called on a rune box spawn.
 * 
 * @param entity              Entity index of the rune box.
 * @param runeData            The rune enum struct data.
 * @param runeId              The rune index.
 * @param origin			  The spawn origin vector of the rune box entity.
 * @param star                Rune star 1-6, see the enum above.
 * @param level			      Rune level 1-15, see the enum above.
 * @param natural			  True if the rune did spawn naturally, false otherwise.
 * 
 * @return					Plugin_Handled or higher to block the spawn, and prevent any further actions.
 */
forward Action JB_OnRuneSpawn(int entity, Rune runeData, int &runeId, float origin[3], int &star, int &level, bool natural);

/**
 * Called when a client is picking up a rune box.
 * 
 * @param client              Client index.
 * @param entity              Entity index of the rune box.
 * @param runeData            The rune enum struct data.
 * @param runeId              The picked rune index.
 * @param star                Rune star 1-6, see the enum above.
 * @param level			      Rune level 1-15, see the enum above.
 * @param blockReason		  If the variable isn't equal to RUNE_PICKUP_BLOCK_NONE, the pickup is blocked. For block reason see the enum above.
 * 
 * @return					Plugin_Handled or higher to block the pickup, and prevent any further actions.
 */
forward Action JB_OnRunePickup(int client, int entity, Rune runeData, int &runeId, int &star, int &level, RunePickupBlockReasons blockReason);

/**
 * Called when a client has tries to upgrade his rune level.
 * 
 * @note This forward called before the upgrade animation has started.
 *
 * @param client              Client index.
 * @param clientRuneIndex     Upgraded client rune index.
 * @param targetLevel         Target upgrade level. (Current rune level + 1, if succeed it will be the current rune level)
 * @param succeed 			  True if the rune level upgrade has succeed, false if not.
 *
 * @return					  True to block the rune upgrade and prevent any further actions, false otherwise.
 */
forward bool JB_OnRuneLevelUpgrade(int client, int clientRuneIndex, int targetLevel, bool &succeed);

/**
 * Called when a client has changed a rune equip status.
 *
 * @param client              Client index.
 * @param clientRuneIndex     Client rune index being equipped/unequipped.
 * @param equipped 			  True if the client rune is now equipped, false if not.
 * @param replaced			  True if the current equipped rune has replaced another equipped.
 * @param blocked			  True if the client is trying to change the rune equip state, but he's blocked by the system cooldown.
 *							  Note that if the boolean value is false, the next equip state time will be 'GetGameTime()'.
 * 
 * @return					  True to block the equip change and prevent any further actions, false otherwise.
 */
forward bool JB_OnRuneEquipChange(int client, int clientRuneIndex, bool &equipped, bool &replaced, bool &blocked);

/**
 * Called when a client has expanded his runes capacity.
 *
 * @param client              Client index.
 * @param oldCapacityAmount   The old client's runes capacity amount.
 * @param newCapacityAmount   The new expanded runes capacity amount.
 */
forward void JB_OnRunesCapacityExpand(int client, int oldCapacityAmount, int newCapacityAmount);

/**
 * Called when a client is selling a client rune to the server.
 *
 * @param client              Client index.
 * @param clientRuneIndex     Client rune index being sell.
 * @param profit			  Amount of profit (in credits) the client has made from the rune sell.
 * 
 * @return					  True to block the rune sell and prevent any further actions, false otherwise.
 */
forward bool JB_OnRuneSell(int client, int clientRuneIndex, int profit);

/**
 * Called when a rune has changed his activity mode. (Change by the native 'JB_ToggleRune')
 * 
 * @param runeIndex      	Toggled rune index.
 * @param toggleMode        Toggle mode that has set to the rune.
 */
forward void JB_OnRuneToggle(int runeIndex, bool toggleMode);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_RunesSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateRune");
	MarkNativeAsOptional("JB_FindRune");
	MarkNativeAsOptional("JB_GetRuneData");
	MarkNativeAsOptional("JB_GetRunesAmount");
	MarkNativeAsOptional("JB_GetClientRuneData");
	MarkNativeAsOptional("JB_SetClientRuneData");
	MarkNativeAsOptional("JB_GetClientEquippedRune");
	MarkNativeAsOptional("JB_AddClientRune");
	MarkNativeAsOptional("JB_RemoveClientRune");
	MarkNativeAsOptional("JB_IsClientHasRune");
	MarkNativeAsOptional("JB_GetClientRunesCapacity");
	MarkNativeAsOptional("JB_GetClientRunesAmount");
	MarkNativeAsOptional("JB_GetClientOwnedRunes");
	MarkNativeAsOptional("JB_PerformRuneLevelUpgrade");
	MarkNativeAsOptional("JB_ToggleRune");
}
#endif

public SharedPlugin __pl_JB_RunesSystem = 
{
	name = "JB_RunesSystem", 
	file = "JB_RunesSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
};
