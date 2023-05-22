#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

//==========[ Settings ]==========//

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_ERROR " \x02[Error]\x01"

// Represents the amount of credits once a client has claimed his next credits
#define NEXT_CREDITS_REWARD 2000 

// Represents the amount of time (seconds) for the next credits cooldown
#define NEXT_CREDITS_SECONDS_COOLDOWN 900

#define NEXT_CREDITS_REQUIRED_PLAYERS 6

//====================//

int g_iNextCreditsReception[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Next Credits", 
	author = PLUGIN_AUTHOR, 
	description = "An additional next credits Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Client Commands
	RegConsoleCmd("sm_nextcredits", Command_NextCredits, "Allows players to reception their next credits.");
	RegConsoleCmd("sm_nc", Command_NextCredits, "Allows players to reception their next credits. (An Alias)");
	
	// Event Hooks
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
	
	// If the shop already started, call the started callback, for late plugin load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	// Reset the client cooldown once the client has joined the server
	ResetClientCooldown(client);
}

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(OnNextCreditsShopDisplay, OnNextCreditsShopSelect);
}

public void OnNextCreditsShopDisplay(int client, char[] buffer, int maxlength)
{
	// Calculate the minutes and seconds until the cooldown expired
	int iCooldownMinutes = (g_iNextCreditsReception[client] - GetTime()) / 60, iCooldownSeconds = (g_iNextCreditsReception[client] - GetTime()) % 60;
	
	FormatEx(buffer, maxlength, "Ready In %s%d:%s%d Minutes", iCooldownMinutes < 10 ? "0" : "", iCooldownMinutes, iCooldownSeconds < 10 ? "0" : "", iCooldownSeconds);
	Format(buffer, maxlength, "Next Credits\n  > %s", iCooldownMinutes <= 0 && iCooldownSeconds <= 0 ? "Ready To Claim!" : buffer);
}

public bool OnNextCreditsShopSelect(int client)
{
	Command_NextCredits(client, 0);
	return true;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Make sure there is enough online players for the next credits reception
	if (GetClientCount() < NEXT_CREDITS_REQUIRED_PLAYERS)
	{
		return;
	}
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_iNextCreditsReception[current_client] < GetTime())
		{
			PrintToChat(current_client, "%s \x03Your next credits reception is ready, type \x04/nextcredits\x03 to recive the award!", PREFIX);
		}
	}
}

//================================[ Commands ]================================//

public Action Command_NextCredits(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure there is enough online players for the next credits to be recieved
	if (GetClientCount() < NEXT_CREDITS_REQUIRED_PLAYERS)
	{
		PrintToChat(client, "%s Next credits reception is available from \x0F%d\x01 or more players.", PREFIX, NEXT_CREDITS_REQUIRED_PLAYERS);
		return Plugin_Handled;
	}
	
	// If the client next cash cooldown is still active, abort the action
	if (g_iNextCreditsReception[client] > GetTime())
	{
		// Calculate the minutes and seconds until the cooldown expired
		int iCooldownMinutes = (g_iNextCreditsReception[client] - GetTime()) / 60, iCooldownSeconds = (g_iNextCreditsReception[client] - GetTime()) % 60;
		
		// Notify client for the cooldown
		PrintToChat(client, "%s Next credits reception will be available in \x07%s%d:%s%d\x01 minutes.", PREFIX_ERROR, iCooldownMinutes < 10 ? "0" : "", iCooldownMinutes, iCooldownSeconds < 10 ? "0" : "", iCooldownSeconds);
		return Plugin_Handled;
	}
	
	// Notify client for the award
	PrintToChat(client, "%s You have recieved \x04%d\x01 credits from \x0Enext credits\x01, next next credits in \x07%.1f mintues\x01.", PREFIX, NEXT_CREDITS_REWARD, float(NEXT_CREDITS_SECONDS_COOLDOWN) / 60.0);
	
	// Award the client
	Shop_GiveClientCredits(client, NEXT_CREDITS_REWARD, CREDITS_BY_COMMAND);
	
	// Update the cooldown local varibale
	ResetClientCooldown(client);
	
	return Plugin_Handled;
}

//================================[ Functions ]================================//

void ResetClientCooldown(int client)
{
	g_iNextCreditsReception[client] = GetTime() + NEXT_CREDITS_SECONDS_COOLDOWN;
}

//================================================================//
