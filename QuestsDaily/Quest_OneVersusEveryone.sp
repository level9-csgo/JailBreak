#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <JB_GuardsSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - One Versus Everyone", 
	author = PLUGIN_AUTHOR, 
	description = "Daily quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("oneversuseveryone", "One Versus Everyone", "Kill {progress} prisoners as the last guard alive.", QuestType_Daily, 15500, 10, 20);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim_index = GetClientOfUserId(event.GetInt("userid"));
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	
	if (1 <= victim_index <= MaxClients && 1 <= attacker_index <= MaxClients && victim_index != attacker_index && JB_GetClientGuardRank(attacker_index) != Guard_NotGuard && GetClientTeam(victim_index) == CS_TEAM_T && GetOnlineTeamCount(CS_TEAM_CT) == 1)
	{
		// Add quest progress points for the victim
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
		reward = RoundToDivider(GetRandomInt(10000, 14000));
	}
} 