#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialMods>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define MOD_NAME "Exclude Runes"
#define MOD_DESC "A game without runes, which means no rune drops and no runes benefits are working."

//====================//

bool g_IsModActivated;

int g_SpecialModId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...MOD_NAME..." Mod", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialMods"))
	{
		g_SpecialModId = JB_CreateSpecialMod(MOD_NAME, MOD_DESC);
	}
}

public void JB_OnSpecialModExecute(int client, int specialModId, bool bought)
{
	// Make sure there is mod index match
	if (specialModId == g_SpecialModId)
	{
		ToggleSpecialMod(true);
	}
}

public void JB_OnSpecialModEnd(int specialModId)
{
	if (specialModId == g_SpecialModId && g_IsModActivated)
	{
		ToggleSpecialMod(false);
	}
}

public Action JB_OnRuneSpawn(int entity, Rune runeData, int &runeId, float origin[3], int &star, int &level, bool natural)
{
	return g_IsModActivated ? Plugin_Handled : Plugin_Continue;
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	// Toggle the rune toggle state
	ToggleRunesState(false);
}

//================================[ Functions ]================================//

void ToggleSpecialMod(bool toggle_mode)
{
	if (!toggle_mode && !g_IsModActivated || toggle_mode && g_IsModActivated)
	{
		return;
	}
	
	if (toggle_mode)
	{
		HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Pre);
	}
	else {
		UnhookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Pre);
		JB_AbortSpecialMod(false);
	}
	
	// Toggle the rune toggle state
	ToggleRunesState(!toggle_mode);
	
	// Change the special mod state global variable value
	g_IsModActivated = toggle_mode;
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//