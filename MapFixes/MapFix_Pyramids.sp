#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define MAP_NAME "jb_pyramids_final_csgo"

char g_Sounds[][] = 
{
	"doors/door_metal_large_open1.wav", 
	"doors/door_metal_large_close2.wav"
};

public Plugin myinfo = 
{
	name = "[CS:GO] MapFix - Pyramids", 
	author = "KoNLiG", 
	description = "General exploits map fixer for the map '"...MAP_NAME..."'.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	AddNormalSoundHook(OnNormalSound);
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

Action OnNormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], 
	int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, 
	char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (FindStringInStringArray(g_Sounds, sizeof(g_Sounds), sample) == -1)
	{
		return Plugin_Continue;
	}
	
	volume = 0.25;
	return Plugin_Changed;
}

int FindStringInStringArray(const char[][] array, int size, const char[] string)
{
	for (int i; i < size; i++)
	{
		if (StrEqual(array[i], string))
		{
			return i;
		}
	}
	
	return -1;
} 