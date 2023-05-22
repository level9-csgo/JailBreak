#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_GangsSystem>
#include <JB_GangsUpgrades>

#define PLUGIN_AUTHOR "KoNLiG"

enum
{
	Item_Price = 0, 
	Item_Percent
}

bool g_bIsUpgradeOn = true;

int g_iUpgradeId = -1;
int g_iLevels[][] = 
{
	{ 50000, 20 }, 
	{ 100000, 40 }, 
	{ 150000, 60 }, 
	{ 200000, 80 }, 
	{ 250000, 100 }
};

public Plugin myinfo = 
{
	name = "[CS:GO] Gangs Upgrades - Friendly Fire", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GangsUpgrades"))
	{
		g_iUpgradeId = JB_CreateGangUpgrade("friendlyfire", "Reduced Friendly-Fire Damage", "20% Less friendly-fire damage on each level in special days. (Maximum level equals zero damage)");
		
		for (int iCurrentLevel = 0; iCurrentLevel < sizeof(g_iLevels); iCurrentLevel++)
		{
			JB_CreateGangUpgradeLevel(g_iUpgradeId, g_iLevels[iCurrentLevel][Item_Price]);
		}
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown)
{
	if (!countdown)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			}
		}
	}
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (!g_bIsUpgradeOn)
	{
		return Plugin_Continue;
	}
	
	int iClientGang = Gangs_GetPlayerGang(victim);
	if (iClientGang != NO_GANG && 1 <= attacker <= MaxClients && iClientGang == Gangs_GetPlayerGang(attacker) && !IsGangLastAlive())
	{
		int upgrade_level = JB_GetGangUpgradeLevel(iClientGang, g_iUpgradeId);

		if (upgrade_level)
		{
			damage -= (damage * g_iLevels[upgrade_level - 1][Item_Percent]) / 100;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

bool IsGangLastAlive()
{
	int iLastCheckGang = -2;
	
	for (int iCurrentClient = 1, iCurrentGang; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient))
		{
			iCurrentGang = Gangs_GetPlayerGang(iCurrentClient);
			if (iLastCheckGang != iCurrentGang && iLastCheckGang != -2) {
				return false;
			}
			
			iLastCheckGang = iCurrentGang;
		}
	}
	
	return true;
}

public void JB_OnUpgradeToggle(int upgradeIndex, bool toggleMode)
{
	// Make sure the changed upgrade is the plugin's gang upgrade
	if (upgradeIndex == g_iUpgradeId)
	{
		g_bIsUpgradeOn = toggleMode;
	}
}

/*  */
