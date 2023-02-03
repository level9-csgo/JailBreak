#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialMods>
#include <JB_SpecialDays>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define MOD_NAME "Crazy Knife"
#define MOD_WEAPON "weapon_knife"

#define MOD_DESC "A game of none but only knives against the prisoners, no weapons allowed!"

#define GUARDS_HEALTH 250

//====================//

ConVar g_AllowWeaponsPlaced;

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

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
	
	g_AllowWeaponsPlaced = FindConVar("mp_weapons_allow_map_placed");
}

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

public void OnClientPostAdminCheck(int client)
{
	if (g_IsModActivated)
	{
		SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
	}
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_IsModActivated)
	{
		return Plugin_Continue;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (GetClientTeam(client) == CS_TEAM_CT)
	{
		SetEntityHealth(client, GUARDS_HEALTH);
	}
	
	return Plugin_Continue;
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnWeaponCanUse(int client, int weapon)
{
	char weapon_name[32];
	GetEntityClassname(weapon, weapon_name, sizeof(weapon_name));
	
	if (!JB_IsLrRunning() && !JB_IsLrPeriodRunning() && !JB_IsSpecialDayRunning() && !JB_IsSpecialDayVoteRunning() && !JB_IsVoteCTRunning() && StrContains(weapon_name, "knife") == -1 && StrContains(weapon_name, "bayonet") == -1)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ToggleSpecialMod(bool toggle_mode)
{
	if (!toggle_mode && !g_IsModActivated || toggle_mode && g_IsModActivated)
	{
		return;
	}
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			if (toggle_mode) {
				SDKHook(current_client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
			}
			else {
				SDKUnhook(current_client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
			}
		}
	}
	
	// Change the special mod state global variable value
	g_IsModActivated = toggle_mode;
	
	if (!toggle_mode)
	{
		JB_AbortSpecialMod(false);
	}
	
	// Change the allow map weapons place value
	g_AllowWeaponsPlaced.BoolValue = !toggle_mode;
}

//================================================================//