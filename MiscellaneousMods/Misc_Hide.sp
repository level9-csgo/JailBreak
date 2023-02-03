#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

bool g_bHide[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Hide Operation", 
	author = PLUGIN_AUTHOR, 
	description = "Allows to clients toggle their transmit options, can be disabled through an admin command.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_hide", Command_Hide, "");
	
	AddTempEntHook("Shotgun Shot", Hook_SilenceShots);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

/* Events */

public void OnClientPostAdminCheck(int iPlayerIndex)
{
	SDKHook(iPlayerIndex, SDKHook_SetTransmit, Hook_OnSetTransmit);
	g_bHide[iPlayerIndex] = false;
}

public Action Hook_SilenceShots(const char[] teName, const int[] players, int numClients, float delay)
{
	for (int iCurrentClient = 0; iCurrentClient < numClients; iCurrentClient++)
	{
		if (g_bHide[players[iCurrentClient]]) 
		{
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

/*  */

/* Hooks */

public Action Hook_OnSetTransmit(int entity, int iPlayerIndex)
{
	if (iPlayerIndex != entity && (0 < entity <= MaxClients) && g_bHide[iPlayerIndex] && IsPlayerAlive(entity) && IsPlayerAlive(iPlayerIndex)) 
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*  */

/* Commands */

public Action Command_Hide(int iPlayerIndex, int args)
{
	g_bHide[iPlayerIndex] = !g_bHide[iPlayerIndex];
	PrintToChat(iPlayerIndex, "%s Hide is now %s\x01!", PREFIX, g_bHide[iPlayerIndex] ? "\x04enabled":"\x02disabled");
	return Plugin_Handled;
}

/*  */