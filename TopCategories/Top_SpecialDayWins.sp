#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>
#include <JB_SpecialDays>

#pragma semicolon 1
#pragma newdecls required

#define TOP_NAME "Top Special Day Wins"

int g_iTopId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Top System - "...TOP_NAME, 
	author = "KoNLiG", 
	description = "Top special day wins for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_TopSystem"))
	{
		g_iTopId = JB_CreateTopCategory("specialdaywins", TOP_NAME, "Top special day winners.", "Wins");
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown)
{
	if (winner != INVALID_DAY_WINNER)
	{
		JB_AddTopPoints(winner, g_iTopId, 1);
	}
}

