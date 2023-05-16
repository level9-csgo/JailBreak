#if defined _JB_GangsSystem_included
 #endinput
#endif
#define _JB_GangsSystem_included

#define NO_GANG -1
#define MAX_GANG_SLOTS 12
#define DEFAULT_GANG_SLOTS 3

enum
{
	Color_Rgb = 0, 
	Color_Name
}

enum
{
	Rank_NoGang = NO_GANG, 
	Rank_Member, 
	Rank_Manager, 
	Rank_Deputy_Leader, 
	Rank_Leader
}

stock char g_szColors[][][] = 
{
	{ "255,0,0,255", "Red" }, 
	{ "0,255,0,255", "Green" }, 
	{ "0,0,255,255", "Blue" }, 
	{ "255,255,0,255", "Gold" }, 
	{ "255,0,255,255", "Purple" }, 
	{ "0,255,255,255", "Mint" }, 
	{ "255,128,0,255", "Orange" }, 
	{ "255,0,128,255", "Pink" }, 
	{ "128,255,0,255", "Olive" }, 
	{ "0,255,128,255", "Slate" }, 
	{ "128,0,255,255", "Lime" }, 
	{ "0,128,255,255", "Menta" }, 
	{ "0,0,0,255", "Black" }, 
	{ "139,69,19,255", "Brown" }, 
	{ "128,0,0,255", "Maroon" }, 
	{ "128,0,255,255", "Vaiolet" }, 
	{ "240,50,230,255", "Magenta" }
};

#define MAX_GANGS sizeof(g_szColors) // Should be enough

/**
 * Gets the amount of cash a gang has.
 * 
 * @param gang		index of the gang
 * @return the amount of cash the gang has
 */
native int Gangs_GetGangCash(int gang);

/**
 * Sets the amount of cash on a gang.
 * @param gang		index of the gang.
 * @param cash		new amount of cash.
 * @noreturn
 */
native void Gangs_SetGangCash(int gang, int cash);

/**
 * Gets the amount of coins a gang has.
 * 
 * @param gang		index of the gang
 * @return the amount of coins the gang has
 */
native int Gangs_GetGangSlots(int gang);

/**
 * Sets the amount of coins on a gang.
 * @param gang		index of the gang.
 * @param slots		new amount of slots.
 * @noreturn
 */
native void Gangs_SetGangSlots(int gang, int slots);

/**
* Gets the name of a gang by it's index.
*
* @param gang				gang index.
* @param buffer				string to store the name on.
* @param maxlength			max length of the string
* @noreturn 
*/
native void Gangs_GetGangName(int gang, char[] buffer, int maxlength);

/**
 * Gets the color of a gang by it's index.
 *
 * @param gang			gang index.
 *
 * @return the id of the color
 */
native int Gangs_GetGangColor(int gang);

/**
 * Gets the amount of gangs.
 * @return		amount of gangs
 */
native int Gangs_GetGangsCount();

/**
* Gets the index of a player's gang.
*
* @param client		index of the player.
* @return 			index of the gang or -1 if the player is not in a gang.
*/
native int Gangs_GetPlayerGang(int client);

/**
 * Gets the rank of a player in his gang.
 *
 * @param client		index of the player.
 * @return 			the rank of the player or -1 if the player is not in a gang.
 */
native int Gangs_GetPlayerGangRank(int client);

/**
 * Sends a message to a gang.
 *
 * @param gang		index of the gang.
 * @param message	message to send
 * @noreturn
 */
native void Gangs_SendMessageToGang(int gang, char[] message);

/**
 * Shows the main menu.
 *
 * @param client		index of the client.
 * @noreturn
 */
native void Gangs_ShowMainMenu(int client);

/**
 * Shows the gang's details.
 *
 * @param client		index of the client.
 * @param gang		index of the gang.
 * @noreturn
 */
native void Gangs_ShowGangDetails(int client, int gang);

/**
 * Creates a new column to the gang data table.
 *
 * @param columnName             Column name.
 * @param columnType       		 Column stored value type. (SQL Types)
 * @param defaultValue           Default value to be created and set to the column once it created.
 *
 */
native void Gangs_CreateDBColumn(char[] columnName, char[] columnType, char[] defaultValue = "");

/**
 * Called when the gangs are loaded from the database
 */
forward void Gangs_GangsLoaded(Database db, int numOfGangs);

/**
 * Called when a player has been loaded
 * 
 * @param client	index of the player.
 * @param gang		index of the player's gang or -1.
 */
forward void Gangs_GangsUserLoaded(int client, int gang);

/**
 * Called when a user opens the main menu.
 *
 * @param client	 	index of the user.
 * @param menu		the menu - aviliable to add items or manage.
 */
forward void Gangs_GangsUserOpenMainMenu(int client, Menu menu);

/**
 * Called when a player pressed the item in the main menu
 *
 * @param client		index of the client.
 * @param info			the dev info of the item.
 */
forward void Gangs_GangsUserPressMainMenu(int client, char[] info);

/**
 * Called when a user opens the gang details.
 *
 * @param client	 	index of the user.
 * @param menu		the menu - aviliable to add items or manage.
 */
forward void Gangs_GangsUserOpenGangDetails(int client, Menu menu);

/**
 * Called when a player pressed the item in the gang details.
 *
 * @param client		index of the client.
 * @param gang			index of the gang.
 * @param info			the dev info of the item.
 */
forward void Gangs_GangsUserPressGangDetails(int client, int gangId, char[] info);

/**
 * Called when a gang's name is changed
 *
 * @param gang			index of the gang.
 * @param oldName		the name before the change.
 * @param newName		the name after the change.
 */
forward void Gangs_GangNameUpdated(int gang, char[] oldName, char[] newName);

/**
 * Called when a gang is deleted
 *
 * @param gang			index of the gang.
 * @param name		the name before the change.
 */
forward void Gangs_OnGangCreate(int gang);

/**
 * Called when a gang is deleted
 *
 * @param gang			index of the gang.
 * @param name		the name before the change.
 */
forward void Gangs_OnGangDelete(int gang, char[] name);

stock void GetColorRGB(char[] color, int buffer[4])
{
	char exploded_color[4][10];
	ExplodeString(color, ",", exploded_color, sizeof(exploded_color), sizeof(exploded_color[]));
	
	int iColor[4];
	
	for (int i = 0; i < 4; i++)
	{
		iColor[i] = StringToInt(exploded_color[i]);
	}
	
	buffer = iColor;
}

stock void HideHud(int client, bool bHide)
{
	if (IsClientInGame(client))
	{
		SendConVarValue(client, FindConVar("mp_maxmoney"), bHide ? "0":"16000");
		SendConVarValue(client, FindConVar("sv_disable_radar"), bHide ? "1":"0");
	}
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_GangsSystem_SetNTVOptional()
{
	MarkNativeAsOptional("Gangs_GetGangName");
	MarkNativeAsOptional("Gangs_GetPlayerGang");
	MarkNativeAsOptional("Gangs_GetPlayerGangRank");
}
#endif

public SharedPlugin __pl_JB_GangsSystem = 
{
	name = "JB_GangsSystem", 
	file = "JB_GangsSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
