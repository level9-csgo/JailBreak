#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <shop_wish>

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Try Your Luck", 
	author = "KoNLiG", 
	description = "Weekly quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("tryyourluck", "Try Your Luck", "Spin the wish wheel {progress} times.", QuestType_Weekly, 77550, 5, 6);
	}
}

public Action Shop_OnWishAnimationStart(int client, int wishesLeft, int award_index)
{
	// Add quest progress points for the client
	JB_AddQuestProgress(client, g_QuestIndex);
}

public void JB_OnQuestRewardDisplay(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		FormatEx(display_text, length, "Rewish.");
	}
}

public void JB_OnQuestRewardCollect(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		FormatEx(display_text, length, "rewish.");
		
		Shop_GiveClientWish(client);
	}
}