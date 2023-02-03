#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RUNE_NAME "Damage Rune"

bool g_bIsRuneEnabled = true;

int g_iRuneId = -1;

int g_iDamageBonus[][] = 
{
	{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },  // Star 1
	{ 2, 3, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 },  // Star 2
	{ 3, 5, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22 },  // Star 3
	{ 4, 6, 8, 10, 12, 14, 15, 16, 17, 18, 19, 20, 22, 24, 26 },  // Star 4
	{ 5, 7, 9, 11, 13, 15, 17, 18, 19, 20, 22, 24, 26, 28, 30 },  // Star 5
	{ 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34 } // Star 6
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
	// Loop through all online clients, for late load support
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_RunesSystem"))
	{
		ArrayList ar = new ArrayList(RuneLevel_Max - 1);
		
		for (int current_benefit = 0; current_benefit < sizeof(g_iDamageBonus); current_benefit++)
		{
			ar.PushArray(g_iDamageBonus[current_benefit], sizeof(g_iDamageBonus[]));
		}
		
		g_iRuneId = JB_CreateRune("damagerune", RUNE_NAME, "Extra damage bonus for every knife attack.", "☠", ar, "+{int} Damage");
	}
}

public void OnClientPostAdminCheck(int iPlayerIndex)
{
	SDKHook(iPlayerIndex, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bIsRuneEnabled || weapon == -1)
	{
		return Plugin_Continue;
	}
	
	int iEquippedRune = JB_GetClientEquippedRune(attacker, g_iRuneId);
	
	if (iEquippedRune == -1)
	{
		return Plugin_Continue;
	}
	
	char szWeaponName[32];
	GetEntityClassname(weapon, szWeaponName, sizeof(szWeaponName));
	
	// Make sure the attacker is attacking with a knife
	if (StrContains(szWeaponName, "knife") != -1 || StrContains(szWeaponName, "bayonet") != -1)
	{
		ClientRune ClientRuneData;
		
		JB_GetClientRuneData(attacker, iEquippedRune, ClientRuneData);
		
		// Add the damage bonus to the attack
		damage += float(g_iDamageBonus[ClientRuneData.RuneStar - 1][ClientRuneData.RuneLevel - 1]);
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public void JB_OnRuneToggle(int runeIndex, bool toggleMode)
{
	// Make sure the changed rune is the plugin's rune index
	if (runeIndex == g_iRuneId)
	{
		g_bIsRuneEnabled = toggleMode;
	}
}

//================================================================//
