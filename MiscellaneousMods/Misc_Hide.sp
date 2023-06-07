#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <misc_ghost>
#include <TransmitManager>

#define PLUGIN_AUTHOR "KoNLiG"

bool g_Hide[MAXPLAYERS + 1];

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
	RegConsoleCmd("sm_hide", Command_Hide, "Toggles the hide state.");
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client) || TransmitManager_IsEntityHooked(client))
	{
		return;
	}
	
	TransmitManager_AddEntityHooks(client);
}

public void OnClientDisconnect(int client)
{
	g_Hide[client] = false;
}

Action Command_Hide(int client, int args)
{
	if (JB_IsClientGhost(client))
	{
		PrintToChat(client, "%s Hide feature is not available while you are a ghost!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	g_Hide[client] = !g_Hide[client];
	UpdateClientHideState(client);
	
	PrintToChat(client, "%s Hide is now %s\x01!", PREFIX, g_Hide[client] ? "\x04enabled":"\x02disabled");
	return Plugin_Handled;
}

void UpdateClientHideState(int client)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (!IsClientInGame(current_client) || IsFakeClient(current_client))
		{
			continue;
		}
		
		TransmitManager_SetEntityState(current_client, client, !g_Hide[client]);
	}
} 