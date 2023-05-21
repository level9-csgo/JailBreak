#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <mapchooser>
#include <customvotes>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

#define PREFIX " \x04[Level9]\x01"

ConVar g_NextMap;

char g_ChosenMapName[PLATFORM_MAX_PATH];

bool g_IsCmInProgress;

public Plugin myinfo = 
{
	name = "[CS:GO] Change Map", 
	author = PLUGIN_AUTHOR, 
	description = "Provies a change map custom vote.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Requried translation for chat messages
	LoadTranslations("common.phrases");
	
	// ConVars Configurate
	g_NextMap = FindConVar("sm_nextmap");
	
	// Admin Commands
	RegAdminCmd("sm_changemap", Command_ChangeMap, ADMFLAG_BAN, "Executes the change map vote.");
	RegAdminCmd("sm_cm", Command_ChangeMap, ADMFLAG_BAN, "Executes the change map vote.");
}

//================================[ Events ]================================//

public int OnMapVoteEnd(const char[] map)
{
	if (!g_IsCmInProgress)
	{
		return 0;
	}
	
	strcopy(g_ChosenMapName, sizeof(g_ChosenMapName), map);
	CreateTimer(4.0, Timer_ForceChangeLevel, .flags = TIMER_FLAG_NO_MAPCHANGE);
	
	CS_TerminateRound(4.0, CSRoundEnd_Draw, false);
	
	return 0;
}

//================================[ Commands ]================================//

public Action Command_ChangeMap(int client, int args)
{
	// If a regular vote is currently in progress, don't continue 
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "%s %t", PREFIX, "Vote in Progress");
		return Plugin_Handled;
	}
	
	int vote_delay = CheckVoteDelay();
	if (vote_delay)
	{
		ReplyToCommand(client, "%s %t", PREFIX, "Vote Delay Seconds", vote_delay);
		return Plugin_Handled;
	}
	
	// If a custom vote is currently in progress, don't continue 
	if (CustomVotes_IsVoteInProgress())
	{
		ReplyToCommand(client, "%s Another custom vote is currently in progress.", PREFIX);
		return Plugin_Handled;
	}
	
	PrintToChatAll("%s Admin: \x0C%N\x01 Initiated a \x04Change Map\x01 vote.", PREFIX, client);
	
	PrepareChangeMapVote(client);
	return Plugin_Handled;
}

//================================[ Timers ]================================//

Action Timer_ForceChangeLevel(Handle timer)
{
	ForceChangeLevel(g_ChosenMapName, "Voted for map change.");
	
	g_IsCmInProgress = false;
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void PrepareChangeMapVote(int initiator)
{
	CustomVoteSetup setup;
	
	setup.team = CS_TEAM_NONE;
	setup.initiator = initiator;
	setup.issue_id = VOTE_ISSUE_CHANGELEVEL;
	strcopy(setup.dispstr, sizeof(CustomVoteSetup::dispstr), "<font color='#E14A00' class='fontSize-m'>Do you want to change map?</font>");
	strcopy(setup.disppass, sizeof(CustomVoteSetup::disppass), "<font color='#FFFFFF' class='fontSize-xxs'>Vote Passed!</font><br/><font color='#53DB44'>Select your favorite map</font>");
	
	CustomVotes_Execute(setup, 15, OnVotePassed, OnVoteFailed);
}

void OnVotePassed(int results[MAXPLAYERS + 1])
{
	PrintToChatAll("%s Change Map vote has been finished! The result is \x04Yes\x01!", PREFIX);
	
	g_IsCmInProgress = true;
	
	if (CanMapChooserStartVote() && !HasEndOfMapVoteFinished())
	{
		InitiateMapChooserVote(MapChange_MapEnd);
	}
	else if (HasEndOfMapVoteFinished())
	{
		char next_map[PLATFORM_MAX_PATH];
		g_NextMap.GetString(next_map, sizeof(next_map));
		
		strcopy(g_ChosenMapName, sizeof(g_ChosenMapName), next_map);
		CreateTimer(4.0, Timer_ForceChangeLevel, .flags = TIMER_FLAG_NO_MAPCHANGE);
		
		CS_TerminateRound(4.0, CSRoundEnd_Draw);
		
		PrintToChatAll("%s Changing map to \x04%s\x01...", PREFIX, next_map);
	}
}

void OnVoteFailed(int results[MAXPLAYERS + 1])
{
	PrintToChatAll("%s Change Map vote has been finished! The result is \x02No\x01!", PREFIX);
}

//================================================================//