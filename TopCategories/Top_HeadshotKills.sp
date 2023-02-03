#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define TOP_NAME "Top Headshot Kills"

int g_iTopId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Top System - "...TOP_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "Top headshot kills for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_TopSystem"))
	{
		g_iTopId = JB_CreateTopCategory("headshotkills", TOP_NAME, "Top headshot kills that players have done.", "Kills");
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int iVictimIndex = GetClientOfUserId(event.GetInt("userid"));
	int iAttackerIndex = GetClientOfUserId(event.GetInt("attacker"));
	
	if (iAttackerIndex && iVictimIndex != iAttackerIndex && event.GetBool("headshot")) {
		JB_AddTopPoints(iAttackerIndex, g_iTopId, 1);
	}
} 