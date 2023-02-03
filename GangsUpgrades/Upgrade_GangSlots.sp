#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GangsSystem>
#include <JB_GangsUpgrades>

#define PLUGIN_AUTHOR "KoNLiG"

enum
{
	Item_Price = 0, 
	Item_Slots
}

int g_iUpgradeId = -1;
int g_iLevels[][] = 
{
	{ 100000, 6 }, 
	{ 200000, 8 }, 
	{ 300000, 10 }, 
	{ 400000, 12 }
};

public Plugin myinfo = 
{
	name = "[CS:GO] Gangs Upgrades - Slots", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GangsUpgrades"))
	{
		g_iUpgradeId = JB_CreateGangUpgrade("gangslots", "More Slots", "Grants more available player slots to the gang.");
		for (int iCurrentLevel = 0; iCurrentLevel < sizeof(g_iLevels); iCurrentLevel++)
		{
			JB_CreateGangUpgradeLevel(g_iUpgradeId, g_iLevels[iCurrentLevel][Item_Price]);
		}
	}
}

public void JB_OnUpgradeUpgraded(int client, int upgradeIndex, int level)
{
	if (g_iUpgradeId == upgradeIndex)
	{
		Gangs_SetGangSlots(Gangs_GetPlayerGang(client), g_iLevels[level - 1][Item_Slots]);
	}
}

/*  */
