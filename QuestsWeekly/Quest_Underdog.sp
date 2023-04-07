#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <shop>

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Underdog", 
	author = "KoNLiG", 
	description = "Weekly quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("underdog", "Underdog", "Win a Jackpot with less than 1% win chance.", QuestType_Weekly, 75000, 1, 1);
	}
}

public void Shop_OnJackpotResults(int winner, float chance, int bet, int prize)
{
	if (chance <= 1.0)
	{
		// Add quest progress points for the winner
		JB_AddQuestProgress(winner, g_QuestIndex);
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
		reward = RoundToDivider(GetRandomInt(50000, 70000));
	}
} 