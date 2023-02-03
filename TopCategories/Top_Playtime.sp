#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define TOP_NAME "Top Playtime"

Handle g_hMinuteTimer[MAXPLAYERS + 1] =  { INVALID_HANDLE, ... };

int g_iTopId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Top System - "...TOP_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "Top playtime for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
			OnClientPostAdminCheck(iCurrentClient);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_TopSystem"))
	{
		g_iTopId = JB_CreateTopCategory("playtime", TOP_NAME, "Top playtime in minutes that players have spent on the server.", "Minutes");
	}
}

public void OnMapStart()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			DeleteTimer(iCurrentClient);
		}
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_hMinuteTimer[client] = CreateTimer(60.0, Timer_GivePoint, GetClientSerial(client), TIMER_REPEAT);
}

public void OnClientDisconnect(int client)
{
	DeleteTimer(client);
}

public Action Timer_GivePoint(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want, if not, kill the timer
	if (client != 0 && IsClientInGame(client)) {
		JB_AddTopPoints(client, g_iTopId, 1, false);
	}
	else {
		g_hMinuteTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void DeleteTimer(int client)
{
	if (g_hMinuteTimer[client] != INVALID_HANDLE) {
		KillTimer(g_hMinuteTimer[client]);
		g_hMinuteTimer[client] = INVALID_HANDLE;
	}
} 