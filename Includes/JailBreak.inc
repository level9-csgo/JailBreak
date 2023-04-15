#if defined _JailBreak_included
 #endinput
#endif
#define _JailBreak_included

#include <sdktools>
#include <Regex>

#define JAILBREAK_VERSION "1.0"

#define DATABASE_ENTRY "playil_jailbreak"
#define PARENT_SOUNDS_DIR "playil_jailbreak"
#define DB_CLIENTS_TABLE "jb_clients_data"

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_MENU "[Level9]"
#define PREFIX_ERROR " \x02[Error]\x01"

#define MAX_DAYS 7

enum
{
	Day_Sunday = 0, 
	Day_Monday, 
	Day_Tuesday, 
	Day_Wednesday, 
	Day_Thursday, 
	Day_Friday, 
	Day_Saturday
}

/**
 * Gets the current day
 *
 * @return Current day.
 */
native int JB_GetDay();

/**
 * Sets the current day
 *
 * @noreturn
 */
native int JB_SetDay(int day);

/**
 * Toggle prisoners mute.
 *
 * @param mode             Mute mode to set, true to enable the mute, false to disable it.
 * @param broadcast        True to print a broadcast chat message, false to not.
 *
 */
native void JB_TogglePrisonersMute(bool mode, bool broadcast);

/**
 * Returns the jailbreak core database handle, or null if the connection hans'nt made yet.
 *
 */
native Database JB_GetDatabase();

/**
 * Called when once the core has successfully connected to the JailBreak database.
 * 
 * @param db            Database handle the connection made with.
 */
forward void JB_OnDatabaseConnected(Database db);

stock void JB_WriteLogLine(const char[] log, any...)
{
	char szLogLine[512];
	VFormat(szLogLine, sizeof(szLogLine), log, 2);
	
	static char szPath[128];
	if (strlen(szPath) < 1)
	{
		char szFileName[64];
		GetPluginFilename(INVALID_HANDLE, szFileName, sizeof(szFileName));
		ReplaceString(szFileName, sizeof(szFileName), ".smx", "");
		
		FormatTime(szPath, sizeof(szPath), "%Y%m%d", GetTime());
		BuildPath(Path_SM, szPath, sizeof(szPath), "logs/%s_%s.log", szFileName, szPath);
	}
	
	LogToFile(szPath, szLogLine);
}

stock char[] JB_AddCommas(int value, const char[] seperator = ",")
{
	// Static regex insted of a global one.
	static Regex rgxCommasPostions = null;
	
	// Complie our regex only once.
	if (!rgxCommasPostions)
		rgxCommasPostions = CompileRegex("\\d{1,3}(?=(\\d{3})+(?!\\d))");
	
	// The buffer that will store the number so we can use the regex.
	char buffer[MAX_NAME_LENGTH];
	IntToString(value, buffer, MAX_NAME_LENGTH);
	
	// perform the regex.
	rgxCommasPostions.MatchAll(buffer);
	
	// Loop through all Offsets
	for (int iCurrentOffset = 0; iCurrentOffset < rgxCommasPostions.MatchCount(); iCurrentOffset++)
	{
		// Get the offset.
		int offset = rgxCommasPostions.MatchOffset(iCurrentOffset);
		
		offset += iCurrentOffset;
		
		// Insert seperator.
		Format(buffer[offset], sizeof(buffer) - offset, "%c%s", seperator, buffer[offset]);
	}
	
	// Return buffer
	return buffer;
}

stock void DisarmPlayer(int client)
{
    static int max_weapons;
    
    if (!max_weapons)
    {
        max_weapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    }
    
    int ent = -1;
    
    for (int current_index = 0; current_index < max_weapons; current_index++)
    {
        if ((ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", current_index)) != -1)
        {
            RemovePlayerItem(client, ent);
            AcceptEntityInput(ent, "Kill");
        }
    }
}

stock void JB_FixMenuGap(Menu menu)
{
	int iItemCount = menu.ItemCount;
	for (int iCurrentItem = 0; iCurrentItem < (6 - iItemCount); iCurrentItem++) {
		menu.AddItem("", "", ITEMDRAW_NOTEXT); // Fix the back button gap.
	}
}

stock int GetOnlineTeamCount(int team, bool alive = true)
{
	int iCounter = 0;
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && GetClientTeam(iCurrentClient) == team && !IsFakeClient(iCurrentClient)) {
			if (alive) {
				if (IsPlayerAlive(iCurrentClient)) {
					iCounter++;
				}
			} else {
				iCounter++;
			}
		}
	}
	return iCounter;
}

stock void PrintToAdmins(const char[] message, any...)
{
	char szMessage[256];
	VFormat(szMessage, sizeof(szMessage), message, 2);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && GetUserAdmin(iCurrentClient) != INVALID_ADMIN_ID) {
			PrintToChat(iCurrentClient, "%s %s", PREFIX, szMessage);
		}
	}
}

stock void ToggleParachute(bool mode)
{
	static ConVar cvEnableParachute;
	
	if (cvEnableParachute == null) {
		cvEnableParachute = FindConVar("sm_parachute_enabled");
	}
	
	if (cvEnableParachute != null) {
		cvEnableParachute.SetBool(mode);
	}
}

stock void ToggleBunnyhop(bool mode)
{
	static ConVar cvEnableAbner, cvEnableRealbhop, cvEnableBunnyhop;
	
	if (cvEnableAbner == null) {
		cvEnableAbner = FindConVar("abner_bhop_enabled");
	}
	
	if (cvEnableRealbhop == null) {
		cvEnableRealbhop = FindConVar("sm_realbhop_enabled");
	}
	
	if (cvEnableBunnyhop == null) {
		cvEnableBunnyhop = FindConVar("sv_enablebunnyhopping");
	}
	
	if (cvEnableAbner != null) {
		cvEnableAbner.SetBool(mode);
	}
	
	if (cvEnableRealbhop != null) {
		cvEnableRealbhop.SetBool(mode);
	}
	
	if (cvEnableBunnyhop != null) {
		cvEnableBunnyhop.SetBool(mode);
	}
}

#if !defined REQUIRE_PLUGIN
public void __pl_JailBreak_SetNTVOptional()
{
	MarkNativeAsOptional("JB_GetDay");
	MarkNativeAsOptional("JB_SetDay");
	MarkNativeAsOptional("JB_TogglePrisonersMute");
}
#endif

public SharedPlugin __pl_JailBreak = 
{
	name = "JailBreak", 
	file = "JB_Core.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 