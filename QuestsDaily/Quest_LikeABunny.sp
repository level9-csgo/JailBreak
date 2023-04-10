#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

#define BHOP_REQUIRED_SPEED 550.0

<<<<<<< HEAD
int g_TickInterval;
=======
float g_TickInterval;
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab

int g_QuestIndex = -1;

int m_vecVelocityOffset;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Like A Bunny", 
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
<<<<<<< HEAD
	g_TickInterval = RoundFloat(1.0 / GetTickInterval());
=======
	g_TickInterval = GetTickInterval();
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
	
	m_vecVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("likeabunny", "Like A Bunny", "Bunnyhop for {progress} seconds straight.", QuestType_Daily, 6500, 300, 600);
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!buttons || !IsPlayerAlive(client))
	{
		return;
	}
	
	// Get the client velocity
	float client_vel[3];
	GetEntDataVector(client, m_vecVelocityOffset, client_vel);
	
<<<<<<< HEAD
	if (GetVectorLength(client_vel) > BHOP_REQUIRED_SPEED && !(tickcount % g_TickInterval))
=======
	if (GetVectorLength(client_vel) > BHOP_REQUIRED_SPEED && tickcount % RoundToZero(1.0 / g_TickInterval) == 0)
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
	{
		// Add quest progress points for the client
		JB_AddQuestProgress(client, g_QuestIndex);
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
		reward = RoundToDivider(GetRandomInt(3000, 5000));
	}
} 