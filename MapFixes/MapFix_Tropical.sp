#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_LrSystem>
#include <JB_SpecialDays>

#define PLUGIN_VERSION "1.00"
#define PLUGIN_AUTHOR "KoNLiG"

#define GetEntityHammerId(%1) GetEntProp(%1, Prop_Data, "m_iHammerID")

#define MAP_NAME "jb_tropical_island_v2"

#define WEAPON_PICKUP_COOLDOWN 30.0

enum
{
	// Specifies the hammer ids of certain jetpack entities
	
	Jetpack_Weapon,  // Weapon (weapon_knife)
	Jetpack_Button,  // Button (func_button)
	Jetpack_DynamicProp,  // Jetpack visual dynamic prop
	Jetpack_PushForward,  // The physics (push forward) manager (trigger_push)
	Jetpack_FlyTimer // The physics (fly) manager (trigger_push)
};

int g_JetpacksData[][] = 
{
	{ 666661, 880166, 666657, 880163, 1125268 },  // 'jetpack' [weapon_knife] | 'NULL (^ Button handler)' [func_button]
	{ 693726, 880431, 693742, 880428, 1125220 } // '2jetpack' [weapon_knife],'NULL (^ Button handler)' [func_button] 
};

int g_ArmoryTriggers[] = 
{
	954015, 
	953993, 
	953825
};

float g_NextWeaponPickup[MAXPLAYERS + 1][sizeof(g_ArmoryTriggers)];

public Plugin myinfo = 
{
	name = "[CS:GO] MapFix - Tropical", 
	author = PLUGIN_AUTHOR, 
	description = "General exploits map fixer for the map '"...MAP_NAME..."'.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiGrL/ || KoNLiG#2325"
};

public void OnPluginStart()
{
	// Event Hooks
	HookEvent("round_start", Hook_RoundStart);
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
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "trigger_multiple"))
	{
		SDKHook(entity, SDKHook_Spawn, Hook_Ong_ArmoryTriggerspawn);
	}
}

void Hook_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int current_client; current_client <= MaxClients; current_client++)
	{
		for (int current_index; current_index < sizeof(g_NextWeaponPickup[]); current_index++)
		{
			g_NextWeaponPickup[current_client][current_index] = 0.0;
		}
	}
}

public void JB_OnLrStart(int lrIndex, int prisoner, int guard)
{
	RemoveClientJetpack(prisoner);
	RemoveClientJetpack(guard);
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			RemoveClientJetpack(current_client);
		}
	}
}

//================================[ SDK Hooks ]================================//

Action Hook_Ong_ArmoryTriggerspawn(int entity)
{
	int entity_hammer_id = GetEntityHammerId(entity);
	
	for (int current_index; current_index < sizeof(g_ArmoryTriggers); current_index++)
	{
		if (g_ArmoryTriggers[current_index] == entity_hammer_id)
		{
			SDKHook(entity, SDKHook_StartTouch, Hook_OnTriggerTouch);
		}
	}
	
	return Plugin_Continue;
}

Action Hook_OnTriggerTouch(int entity, int other)
{
	if (!(1 <= other <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	int entity_hammer_id = GetEntityHammerId(entity);
	
	int trigger = -1;
	
	float game_time = GetGameTime();
	
	for (int current_index; current_index < sizeof(g_ArmoryTriggers); current_index++)
	{
		if (g_ArmoryTriggers[current_index] == entity_hammer_id)
		{
			trigger = current_index;
			
			if (g_NextWeaponPickup[other][current_index] > game_time)
			{
				PrintCenterText(other, "You will be able to pick a new weapon in %.1fs", g_NextWeaponPickup[other][current_index] - game_time);
				return Plugin_Handled;
			}
			
			g_NextWeaponPickup[other][current_index] = game_time + WEAPON_PICKUP_COOLDOWN;
			return Plugin_Continue;
		}
	}
	
	if (g_NextWeaponPickup[other][trigger] > game_time)
	{
		PrintCenterText(other, "You will be able to pick a new weapon in %.1fs", g_NextWeaponPickup[other][trigger] - game_time);
		return Plugin_Handled;
	}
	
	g_NextWeaponPickup[other][trigger] = game_time + WEAPON_PICKUP_COOLDOWN;
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void RemoveClientJetpack(int client)
{
	for (int jetpack_id; jetpack_id < sizeof(g_JetpacksData); jetpack_id++)
	{
		int entity = -1;
		
		if ((entity = GetEntityByHammerId(g_JetpacksData[jetpack_id][Jetpack_Weapon])) != -1 && GetEntPropEnt(entity, Prop_Send, "m_hPrevOwner") == client)
		{
			RemovePlayerItem(client, entity);
			AcceptEntityInput(entity, "Kill");
			
			GivePlayerItem(client, "weapon_knife");
		}
		
		for (int current_jetpack = 1; current_jetpack < sizeof(g_JetpacksData[]) - 1; current_jetpack++)
		{
			if ((entity = GetEntityByHammerId(g_JetpacksData[jetpack_id][current_jetpack])) != -1)
			{
				AcceptEntityInput(entity, "Kill");
			}
		}
		
		entity = -1;
		
		while ((entity = FindEntityByClassname2(entity, "logic_timer")) != -1)
		{
			if (g_JetpacksData[jetpack_id][Jetpack_FlyTimer] == GetEntityHammerId(entity))
			{
				AcceptEntityInput(entity, "Kill");
			}
		}
	}
}

int GetEntityByHammerId(int hammer_id)
{
	for (int current_entity = MaxClients + 1; current_entity < GetMaxEntities() * 2; current_entity++)
	{
		if (IsValidEntity(current_entity) && GetEntityHammerId(current_entity) == hammer_id)
		{
			return current_entity;
		}
	}
	
	return -1;
}

int FindEntityByClassname2(int start, const char[] classname)
{
	while (start > -1 && !IsValidEntity(start))
	{
		start--;
	}
	
	return FindEntityByClassname(start, classname);
}

//================================================================//