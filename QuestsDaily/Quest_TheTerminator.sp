#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <JB_SpecialDays>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

#define REPEATED_KILLS 5

int g_QuestIndex = -1;

int g_ClientKillsCounter[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - The Terminator", 
	author = PLUGIN_AUTHOR, 
	description = "Daily quest for the quests system.", 
	version = JAILBREAK_VERSION, 
<<<<<<< HEAD
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
=======
	url = "play-il.co.il"
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("theterminator", "The Terminator", "Eliminate 5 players in {progress} different special days.", QuestType_Daily, 15000, 2, 4);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	g_ClientKillsCounter[client] = 0;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	
	if ((1 <= attacker_index <= MaxClients) && attacker_index != GetClientOfUserId(event.GetInt("userid")) && JB_IsSpecialDayRunning() && ++g_ClientKillsCounter[attacker_index] == REPEATED_KILLS)
	{
		// Add quest progress points for the attacker
		JB_AddQuestProgress(attacker_index, g_QuestIndex);
	}
}

public void JB_OnQuestRewardDisplay(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		QuestStats stats;
		JB_GetClientQuestStats(client, quest_id, stats);
		
		FormatEx(display_text, length, "%s Credits.", JB_AddCommas(stats.reward_amount));
	}
}

public void JB_OnQuestRewardCollect(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		QuestStats stats;
		JB_GetClientQuestStats(client, quest_id, stats);
		
		FormatEx(display_text, length, "%s credits.", JB_AddCommas(stats.reward_amount));
		
		Shop_GiveClientCredits(client, stats.reward_amount);
	}
}

public void JB_OnQuestAssigned(int client, int quest_id, int target_progress, int &reward, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		reward = RoundToDivider(GetRandomInt(8500, 12000));
	}
} 