#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <shop>

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Record Breaker", 
	author = "KoNLiG", 
	description = "Weekly quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create a one minute repeated timer that will give quest points to every player
	CreateTimer(60.0, Timer_GivePlayMinute, .flags = TIMER_REPEAT);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("recordbreaker", "Record Breaker", "Play {progress} minutes.", QuestType_Weekly, 55000, 480, 840);
	}
}

Action Timer_GivePlayMinute(Handle timer)
{
	// Loop through every online client
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		// Make sure the current client is in-game and he's playing for atleast one minute
		if (IsClientInGame(current_client) && GetClientTime(current_client) >= 60.0)
		{
			// Add quest progress points for the current client
			JB_AddQuestProgress(current_client, g_QuestIndex);
		}
	}
	
	return Plugin_Continue;
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
		reward = RoundToDivider(GetRandomInt(30000, 50000));
	}
} 