#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <JB_LrSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Just For You <3", 
	author = PLUGIN_AUTHOR, 
	description = "Daily quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("justforyou", "Just For You <3", "Give your last requests {progress} times to a prisoner.", QuestType_Daily, 7500, 2, 4);
	}
}

public void JB_OnClientGiveLr(int client, int target)
{
	// Add quest progress points for the client
	JB_AddQuestProgress(client, g_QuestIndex);
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