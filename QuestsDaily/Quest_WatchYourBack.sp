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
	name = "[CS:GO] Quests System - Watch Your Back", 
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
	HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("watchyourback", "Watch Your Back", "Hit {progress} players with backstab.", QuestType_Daily, 8500, 25, 35);
	}
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim_index = GetClientOfUserId(event.GetInt("userid"));
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	
	if (1 <= attacker_index <= MaxClients && 1 <= victim_index <= MaxClients && attacker_index != victim_index)
	{
		char weapon_name[32];
		event.GetString("weapon", weapon_name, sizeof(weapon_name));
		
		if (StrEqual(weapon_name, "knife") && event.GetInt("dmg_health") >= (90.0 + GetAddedDamage(attacker_index)))
		{
			// Add quest progress points for the attacker
			JB_AddQuestProgress(attacker_index, g_QuestIndex);
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
		reward = RoundToDivider(GetRandomInt(4000, 7000));
	}
}

float GetAddedDamage(int client)
{
	int rune_index = JB_FindRune("damagerune");
	
	if (rune_index == -1)
	{
		return 0.0;
	}
	
	int equipped_rune_index = JB_GetClientEquippedRune(client, rune_index);
	
	if (equipped_rune_index == -1)
	{
		return 0.0;
	}
	
	ClientRune ClientRuneData;
	JB_GetClientRuneData(client, equipped_rune_index, ClientRuneData);
	
	return float(JB_GetRuneBenefitStats(ClientRuneData.RuneId, ClientRuneData.RuneStar, ClientRuneData.RuneLevel));
} 