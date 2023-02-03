#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_GangsSystem>
#include <JB_GangsUpgrades>

#define PLUGIN_AUTHOR "KoNLiG"

enum
{
	Item_Price = 0, 
	Item_Health
}

bool g_bIsUpgradeOn = true;

int g_iUpgradeId = -1;
int g_iLevels[][] = 
{
	{ 75000, 10 }, 
	{ 150000, 20 }, 
	{ 225000, 30 }, 
	{ 300000, 40 }, 
	{ 375000, 50 }
};

public Plugin myinfo = 
{
	name = "[CS:GO] Gangs Upgrades - Health Points", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GangsUpgrades"))
	{
		g_iUpgradeId = JB_CreateGangUpgrade("healthpoints", "Health Points Bonus", "Grants a bonus 10 HP for every level in Special Days.");
		for (int iCurrentLevel = 0; iCurrentLevel < sizeof(g_iLevels); iCurrentLevel++)
		{
			JB_CreateGangUpgradeLevel(g_iUpgradeId, g_iLevels[iCurrentLevel][Item_Price]);
		}
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_bIsUpgradeOn)
	{
		int iClientGang = Gangs_GetPlayerGang(client);
		
		if (iClientGang != NO_GANG)
		{
			int upgrade_level = JB_GetGangUpgradeLevel(iClientGang, g_iUpgradeId);
			
			if (upgrade_level)
			{
				SetEntityHealth(client, GetClientHealth(client) + g_iLevels[upgrade_level - 1][Item_Health]);
			}
		}
	}
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
