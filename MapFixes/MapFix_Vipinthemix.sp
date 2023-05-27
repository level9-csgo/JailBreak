#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define GetEntityHammerId(%1) GetEntProp(%1, Prop_Data, "m_iHammerID")

#define MAP_NAME "jb_vipinthemix_csgo_v1-1"

#define DOOR_HAMMER_ID 2246

public Plugin myinfo = 
{
	name = "[CS:GO] MapFix - Tropical", 
	author = "KoNLiG", 
	description = "General exploits map fixer for the map '"...MAP_NAME..."'.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
}

//================================[ Events ]================================//

public void OnMapStart()
{
	char map_name[PLATFORM_MAX_PATH];
	GetCurrentMap(map_name, sizeof(map_name));
	
	if (!StrEqual(map_name, MAP_NAME))
	{
		char plugin_name[PLATFORM_MAX_PATH];
		GetPluginFilename(INVALID_HANDLE, plugin_name, sizeof(plugin_name));
		
		ServerCommand("sm plugins unload %s", plugin_name);
	}
	
	int entity = GetEntityByHammerId(DOOR_HAMMER_ID);
	if (entity != -1)
	{
		DispatchKeyValueFloat(entity, "wait", -1.0);
	}
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Repeat the code in OnMapStart()
	int entity = GetEntityByHammerId(DOOR_HAMMER_ID);
	if (entity != -1)
	{
		DispatchKeyValueFloat(entity, "wait", -1.0);
	}
}

int GetEntityByHammerId(int hammerId)
{
	for (int current_entity = MaxClients + 1; current_entity < GetMaxEntities(); current_entity++)
	{
		if (IsValidEntity(current_entity) && hammerId == GetEntProp(current_entity, Prop_Data, "m_iHammerID"))
		{
			return current_entity;
		}
	}
	
	return -1;
}

//================================================================//