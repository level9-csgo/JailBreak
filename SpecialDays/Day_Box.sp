#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define DAY_NAME "Box Day"
#define DAY_WEAPON "weapon_knife"
#define DEFAULT_HEALTH 100

bool g_bIsDayActivated;

int g_iDayId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginEnd()
{
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DEFAULT_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		ToggleRunesState(true);
		
		g_bIsDayActivated = false;
	}
}

//================================[ Functions ]================================//

void ToggleRunesState(bool state)
{
	int crit_rune_index = JB_FindRune("critraterune");
	
	if (crit_rune_index != -1)
	{
		JB_ToggleRune(crit_rune_index, state);
	}
}

//================================================================//