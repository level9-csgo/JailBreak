#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GangsSystem>
#include <JB_GangsUpgrades>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

#define GET_CREDITS_REQUIRED_PLAYERS 6

enum
{
	Item_Price = 0, 
	Item_Reward
}

bool g_IsGetCreditsClaimed[MAXPLAYERS + 1] = { true, ... };

int g_UpgradeIndex = -1;
int g_UpgradeLevels[][] = 
{
	{ 150000, 100 }, 
	{ 200000, 200 }, 
	{ 250000, 300 }, 
	{ 300000, 400 }, 
	{ 350000, 500 }, 
	{ 400000, 600 }
};

public Plugin myinfo = 
{
	name = "[CS:GO] Gangs Upgrades - Get Credits", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Client Commands
	RegConsoleCmd("sm_getcredits", Command_GetCredits, "Claims the get credits reward for the round.");
	RegConsoleCmd("sm_gc", Command_GetCredits, "Claims the get credits reward for the round. (An Alias)");
	
	// Event Hooks
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (!StrEqual(name, "JB_GangsUpgrades"))
	{
		return;
	}
	
	g_UpgradeIndex = JB_CreateGangUpgrade("getcredits", "Get Credits", "Get credits each round by typing '/gc', the higher the level the higher the credits award.");
	
	for (int iCurrentLevel = 0; iCurrentLevel < sizeof(g_UpgradeLevels); iCurrentLevel++)
	{
		JB_CreateGangUpgradeLevel(g_UpgradeIndex, g_UpgradeLevels[iCurrentLevel][Item_Price]);
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_IsGetCreditsClaimed[client] = true;
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			if (Gangs_GetPlayerGang(iCurrentClient) != NO_GANG)
			{
				g_IsGetCreditsClaimed[iCurrentClient] = false;
			}
		}
	}
}

//================================[ Commands ]================================//

public Action Command_GetCredits(int client, int args)
{
	if (!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int iClientGangIndex = Gangs_GetPlayerGang(client);
	if (iClientGangIndex == NO_GANG)
	{
		PrintToChat(client, "%s \x0EGet Credits\x01 is available for gang members only.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	int iLevel = JB_GetGangUpgradeLevel(iClientGangIndex, g_UpgradeIndex);
	
	if (!iLevel)
	{
		PrintToChat(client, "%s Your gang has not upgraded \x0EGet Credits\x01.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_IsGetCreditsClaimed[client]) {
		PrintToChat(client, "%s You have already claimed your \x0EGet Credits\x01 this round.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (GetClientCount() < GET_CREDITS_REQUIRED_PLAYERS)
	{
		PrintToChat(client, "%s Claiming get credits is available from \x0F%d\x01 or more players.", PREFIX, GET_CREDITS_REQUIRED_PLAYERS);
		return Plugin_Handled;
	}
	
	int iReward = g_UpgradeLevels[iLevel - 1][Item_Reward];
	g_IsGetCreditsClaimed[client] = true;
	
	Shop_GiveClientCredits(client, iReward);
	PrintToChat(client, "%s You have claimed \x04%s\x01 credits by \x0EGet Credits\x01!", PREFIX, AddCommas(iReward));
	return Plugin_Handled;
}

//================================================================//
