#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

#define GetEntityHammerId(%1) GetEntProp(%1, Prop_Data, "m_iHammerID")

#define MAP_NAME "jb_clouds_final5"
#define DEFAULT_AIRACCELERATE 2000

int g_WeaponButtons[] = 
{
	712889, 712893, 712898, 712901, 712904, 712907, 712910, 712913, 712916, 712919, 712922, 712925
};

int g_VisualWeapons[] = 
{
	632392, 632394, 632396, 632398, 632400, 632402, 632404, 632406, 632725, 632727, 632729, 632731, 
	628420, 628422, 628424, 628426, 628428, 628430, 628432, 628434, 23546, 23548, 23550, 23552, 23554, 
	23556, 23558, 5644, 5646, 5648, 5650, 5652, 5654, 5656, 3353, 3394, 3396, 3398, 3400, 3402, 3404, 
	3432, 3453, 3455, 3457, 3459, 3461, 3463, 3465, 3844, 3846, 3848, 3886, 3888, 3890, 3892, 3960, 3962, 
	3964, 3966, 3968, 3970, 3972, 3974, 4092, 4094, 4096, 4098, 4100, 4102, 4104, 4106
};

public Plugin myinfo = 
{
	name = "[CS:GO] MapFix - Clouds", 
	author = PLUGIN_AUTHOR, 
	description = "General exploits map fixer for the map '"...MAP_NAME..."'.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiGrL/ || KoNLiG#2325"
};

public void OnPluginStart()
{
	ConVar sv_airaccelerate = FindConVar("sv_airaccelerate");
	
	if (!sv_airaccelerate)
	{
		SetFailState("Unable to find convar 'sv_airaccelerate'.");
	}
	
	sv_airaccelerate.IntValue = DEFAULT_AIRACCELERATE;
	sv_airaccelerate.AddChangeHook(Hook_OnAiraccelerateChange);
}

public void OnMapStart()
{
	// Get the server map name into a string
	char map_name[PLATFORM_MAX_PATH];
	GetCurrentMap(map_name, sizeof(map_name));
	
	// Unload the plugin if the map isn't matching the specified fix map
	if (!StrEqual(map_name, MAP_NAME))
	{
		char plugin_name[PLATFORM_MAX_PATH];
		GetPluginFilename(INVALID_HANDLE, plugin_name, sizeof(plugin_name));
		
		ServerCommand("sm plugins unload %s", plugin_name);
	}
}

public void Hook_OnAiraccelerateChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (newValue[0] != DEFAULT_AIRACCELERATE)
	{
		convar.SetInt(DEFAULT_AIRACCELERATE);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "func_button"))
	{
		SDKHook(entity, SDKHook_SpawnPost, Hook_OnButtonSpawnPost);
	}
	if (StrEqual(classname, "prop_dynamic_override"))
	{
		SDKHook(entity, SDKHook_SpawnPost, Hook_OnVisualWeaponSpawnPost);
	}
}

void Hook_OnButtonSpawnPost(int entity)
{
	int entity_hammer_id = GetEntityHammerId(entity);
	
	for (int current_button = 0; current_button < sizeof(g_WeaponButtons); current_button++)
	{
		if (g_WeaponButtons[current_button] == entity_hammer_id)
		{
			DispatchKeyValue(entity, "wait", "4");
			return;
		}
	}
}

void Hook_OnVisualWeaponSpawnPost(int entity)
{
	int entity_hammer_id = GetEntityHammerId(entity);
	
	for (int current_visual_weapon = 0; current_visual_weapon < sizeof(g_VisualWeapons); current_visual_weapon++)
	{
		if (g_VisualWeapons[current_visual_weapon] == entity_hammer_id)
		{
			DispatchKeyValue(entity, "solid", "0");
			return;
		}
	}
} 