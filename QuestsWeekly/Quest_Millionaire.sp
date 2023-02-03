#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_QuestsSystem>
#include <JB_RunesSystem>
#include <shop>

int g_QuestIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Millionaire", 
	author = "KoNLiG", 
	description = "Weekly quest for the quests system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_QuestsSystem"))
	{
		g_QuestIndex = JB_CreateQuest("millionaire", "Millionaire", "Earn {progress} credits.", QuestType_Weekly, 375000, 1500000, 2000000);
	}
}

public void Shop_OnCreditsGiven_Post(int client, int credits, int by_who)
{
	// Add quest progress points for the client
	JB_AddQuestProgress(client, g_QuestIndex, credits);
}

public void JB_OnQuestRewardDisplay(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		FormatEx(display_text, length, "Free Rune Upgrade.");
	}
}

public void JB_OnQuestRewardCollect(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type)
{
	if (g_QuestIndex == quest_id && execute_type == ExecuteType_Pre)
	{
		FormatEx(display_text, length, "free rune upgrade.");
		
		ShowRunesInventoryMenu(client);
	}
}

void ShowRunesInventoryMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_RunesInventory);
	menu.SetTitle("%s Quests System - Choose a rune to upgrade for free: \n ", PREFIX_MENU);
	
	Rune CurrentRuneData;
	ClientRune CurrentClientRune;
	
	int counter;
	
	for (int current_client_rune = 0; current_client_rune < JB_GetClientRunesAmount(client); current_client_rune++)
	{
		JB_GetClientRuneData(client, current_client_rune, CurrentClientRune);
		JB_GetRuneData(CurrentClientRune.RuneId, CurrentRuneData);
		
		if (CurrentClientRune.RuneLevel >= RuneLevel_Max - 1)
		{
			counter++;
		}
		
		FormatEx(item_display, sizeof(item_display), "%s | %d%s(Level %d)%s", CurrentRuneData.szRuneName, CurrentClientRune.RuneStar, RUNE_STAR_SYMBOL, CurrentClientRune.RuneLevel, CurrentClientRune.RuneLevel >= RuneLevel_Max - 1 ? " [Maxed Out]" : "");
		menu.AddItem("", item_display, CurrentClientRune.RuneLevel < RuneLevel_Max - 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// The client has no runes to be upgraded
	if (menu.ItemCount == counter)
	{
		// Notify the client
		PrintToChat(client, "%s You don't have any runes to be upgraded, therefore the award is lost.", PREFIX);
		
		// Free the menu handle
		delete menu;
		
		return;
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_RunesInventory(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, client_rune_index = param2;
		
		ClientRune ClientRuneData;
		JB_GetClientRuneData(client, client_rune_index, ClientRuneData);
		
		Rune RuneData;
		JB_GetRuneData(ClientRuneData.RuneId, RuneData);
		
		// Notify client
		PrintToChat(client, "%s You've selected to upgrade \x02%s\x01 \x0C%d%s \x10[Level %d]\x01 to \x10level %d\x01!", PREFIX, RuneData.szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel, ClientRuneData.RuneLevel + 1);
		
		// Perform the rune level upgrade
		JB_PerformRuneLevelUpgrade(client, client_rune_index);
	}
	else if (action == MenuAction_Cancel)
	{
		int client = param1;
		
		if (!IsClientInGame(client))
		{
			return;
		}
		
		RequestFrame(RF_DisplayMenu, GetClientSerial(client));
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void RF_DisplayMenu(int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client is valid
	if (!client)
	{
		return;
	}
	
	// Notify client
	PrintToChat(client, "%s You can't close this menu until you will select a \x10rune\x01 to upgrade!", PREFIX);
	
	// Display the menu again
	ShowRunesInventoryMenu(client);
} 