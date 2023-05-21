#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RUNE_NAME "Health Rune"

bool g_IsRuneEnabled = true;

int g_RuneIndex = -1;

int g_HealthBonus[][] = 
{
	{ 1, 3, 5, 6, 7, 8, 10, 12, 13, 14, 15, 16, 17, 18, 20 },  // Star 1
	{ 2, 4, 6, 8, 10, 11, 12, 13, 14, 15, 17, 19, 21, 23, 25 },  // Star 2
	{ 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 30 },  // Star 3
	{ 4, 6, 8, 10, 12, 14, 16, 19, 21, 24, 27, 29, 31, 33, 35 },  // Star 4
	{ 5, 8, 10, 12, 14, 16, 18, 21, 23, 26, 29, 32, 35, 38, 40 },  // Star 5
	{ 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 43, 45 } // Star 6
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...RUNE_NAME, 
	author = PLUGIN_AUTHOR, 
	description = RUNE_NAME..." perk module for the runes system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_RunesSystem"))
	{
		ArrayList ar = new ArrayList(RuneLevel_Max - 1);
		
		for (int current_benefit = 0; current_benefit < sizeof(g_HealthBonus); current_benefit++)
		{
			ar.PushArray(g_HealthBonus[current_benefit], sizeof(g_HealthBonus[]));
		}
		
		g_RuneIndex = JB_CreateRune("healthrune", RUNE_NAME, "Extra health bonus every start of round.", "⛨", ar, "+{int} HP");
		
		delete ar;
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_IsRuneEnabled)
	{
		RequestFrame(RF_GiveBenefit, GetClientSerial(client));
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_IsRuneEnabled)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if (client)
		{
			ApplyRuneBenefit(client);
		}
	}
}

void RF_GiveBenefit(int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is in-game and valid
	if (client)
	{
		ApplyRuneBenefit(client);
	}
}

public void JB_OnRuneToggle(int runeIndex, bool toggleMode)
{
	// Make sure the changed rune is the plugin's rune index
	if (runeIndex == g_RuneIndex)
	{
		g_IsRuneEnabled = toggleMode;
	}
}

void ApplyRuneBenefit(int client)
{
	int iEquippedRune = JB_GetClientEquippedRune(client, g_RuneIndex);
	
	if (iEquippedRune != -1)
	{
		ClientRune ClientRuneData;
		
		JB_GetClientRuneData(client, iEquippedRune, ClientRuneData);
		
		SetEntityHealth(client, GetClientHealth(client) + g_HealthBonus[ClientRuneData.RuneStar - 1][ClientRuneData.RuneLevel - 1]);
	}
}

//================================================================//
