#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <JB_RunesSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Addicted", 
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
	// Create a one minute repeated timer that will give quest points to every player
	CreateTimer(60.0, Timer_GivePlayMinute, .flags = TIMER_REPEAT);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("addicted", "Addicted", "Play for {progress} minutes.", QuestType_Daily, 9500, 60, 120);
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
		reward = RoundToDivider(GetRandomInt(5000, 7000));
	}
} 