#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar sm_noblock;

bool g_isHooked;

public Plugin myinfo = 
{
	name = "No Block", 
	author = "sslice", 
	description = "Removes player collisions...useful for mod-tastic servers running surf maps, etc.", 
	version = "1.0.0.0", 
	url = "http://www.steamfriends.com/"
};

public void OnPluginStart()
{
	g_isHooked = true;
	HookEvent("player_spawn", OnSpawn, EventHookMode_Post);
	
	sm_noblock = CreateConVar("sm_noblock", "1", "Removes player vs. player collisions", FCVAR_NOTIFY | FCVAR_REPLICATED);
	HookConVarChange(sm_noblock, OnConVarChange);
}

public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int value = !!StringToInt(newValue);
	if (value == 0)
	{
		if (g_isHooked == true)
		{
			g_isHooked = false;
			
			UnhookEvent("player_spawn", OnSpawn, EventHookMode_Post);
		}
	}
	else
	{
		g_isHooked = true;
		
		HookEvent("player_spawn", OnSpawn, EventHookMode_Post);
	}
}

public Action OnSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	SetEntityCollisionGroup(client, 2);
	EntityCollisionRulesChanged(client);
}
