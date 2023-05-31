#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define MAP_NAME "jb_clouds_final5"
#define MAP2_NAME "jb_dystopian_b6"
#define DEFAULT_AIRACCELERATE 2000

public Plugin myinfo = 
{
	name = "[CS:GO] MapFix - Clouds and Dystopian", 
	author = "1.0.0", 
	description = "General exploits map fixer for the map '"...MAP_NAME..."'.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
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
	if (!StrEqual(map_name, MAP_NAME) && !StrEqual(map_name, MAP2_NAME))
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