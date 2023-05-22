#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

int g_HammerIDs[] = 
{
	94706,  // Uptowngood
	69362,  // Uptowngood
	94800,  // Uptowngood
	94797,  // Uptowngood
	1128696 // Tropical
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Button Deleter", 
	author = PLUGIN_AUTHOR, 
	description = "Destroys the forbidden button every map/round starts.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
}

//================================[ Events ]================================//

public void OnMapStart()
{
	char map_name[64];
	GetCurrentMap(map_name, sizeof(map_name));
	
	if (!StrEqual(map_name, "ba_jail_campus_2015") && !StrEqual(map_name, "jb_tropical_island_v2"))
	{
		return;
	}
	
	for (int current_hammer_id = 0, current_entity; current_hammer_id < sizeof(g_HammerIDs); current_hammer_id++)
	{
		current_entity = GetEntityByHammerId(g_HammerIDs[current_hammer_id]);
		
		// Make sure the entity exists and valid
		if (current_entity != -1 && IsValidEntity(current_entity))
		{
			AcceptEntityInput(current_entity, "Kill");
		}
	}
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Repeat the code in OnMapStart()
	OnMapStart();
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