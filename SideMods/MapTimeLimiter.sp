#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define PREFIX " \x04[Play-IL]\x01"

native void RTV_ForceVote();

ConVar g_LimitHours;

float g_MapEngineTime;

public Plugin myinfo = 
{
	name = "[CS:GO] Map Time Limiter", 
	author = PLUGIN_AUTHOR, 
	description = "Limits the time that a map can be played in a row.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiGrL/ || KoNLiG#2325"
};

public void OnPluginStart()
{
	// ConVars Configuration
	g_LimitHours = CreateConVar("map_time_limiter_hours", "6", "Represents the maximum hours a map can be played. (0 To disable)");
	
	AutoExecConfig(true, "MapTimeLimiter");
	
	// Admin Commands
	RegAdminCmd("sm_resetmaptime", Command_ResetMapTime, ADMFLAG_ROOT, "Resets the map time limit timer.");
	
	// Client Commands
	RegConsoleCmd("sm_timeleft", Command_TimeLeft, "Prints the time left before a map change force.");
}

//================================[ Events ]================================//

public void OnMapStart()
{
	InitMapEngineTime();
}

public void JB_OnVoteCTStart(bool action)
{
	// Make sure the map time limit conditions are valid, and if so, execute a force rtv
	if (RoundToFloor(GetEngineTime() - g_MapEngineTime) > g_LimitHours.IntValue * 3600 && IsServerProcessing() && GetClientCount())
	{
		// Notify the players
		PrintToChatAll("%s The current map ran for more than \x02%d\x01 hour%s, forcing a map change!", PREFIX, g_LimitHours.IntValue, g_LimitHours.IntValue > 1 ? "s" : "");
		
		// Force a map change
		RTV_ForceVote();
		
		// Stop the Vote CT
		JB_StopVoteCT(false);
	}
}

//================================[ Commands ]================================//

Action Command_ResetMapTime(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Notify the admin
	PrintToChat(client, "%s Successfully reset the map limit timer from \x07%.1f\x01 minutes to \x060\x01.", PREFIX, (GetEngineTime() - g_MapEngineTime) / 60.0);
	
	// Reset the timer
	InitMapEngineTime();
	
	return Plugin_Handled;
}

Action Command_TimeLeft(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	int seconds_left = RoundFloat((g_LimitHours.IntValue * 3600) - (GetEngineTime() - g_MapEngineTime));
	
	char time_left[64];
	
	if (seconds_left <= 0)
	{
		Format(time_left, sizeof(time_left), "\x02Next round\x01!");
	}
	else
	{
		Format(time_left, sizeof(time_left), "\x06%d minutes", seconds_left / 60);
		
		if (seconds_left % 60)
		{
			Format(time_left, sizeof(time_left), "%s, %d seconds.", time_left, seconds_left % 60);
		}
		else
		{
			time_left[strlen(time_left)] = '.';
		}
	}
	
	// Notify the client
	PrintToChat(client, "%s Remaining map time: %s", PREFIX, time_left);
	
	return Plugin_Handled;
}

//================================[ Functions ]================================//

void InitMapEngineTime()
{
	g_MapEngineTime = GetEngineTime();
}

//================================================================//