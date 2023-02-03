#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define TOP_NAME "Top Last Request Wins"

int g_iTopId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Top System - "...TOP_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "Top last request wins for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_TopSystem"))
	{
		g_iTopId = JB_CreateTopCategory("lastrequestwins", TOP_NAME, "Top last request wins that players have won.", "Wins");
	}
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (!aborted && winner != INVALID_LR_WINNER) {
		JB_AddTopPoints(winner, g_iTopId, 1);
	}
} 