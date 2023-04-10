#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

#define	HITGROUP_HEAD 1

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Skull Buster", 
	author = PLUGIN_AUTHOR, 
	description = "Daily quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("skullbuster", "Skull Buster", "Hit {progress} headshots.", QuestType_Daily, 7500, 20, 30);
	}
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	
	if ((1 <= attacker_index <= MaxClients) && attacker_index != GetClientOfUserId(event.GetInt("userid")) && event.GetInt("hitgroup") == HITGROUP_HEAD)
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
		reward = RoundToDivider(GetRandomInt(4000, 6000));
	}
} 