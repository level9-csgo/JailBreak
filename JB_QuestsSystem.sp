#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <regex>
#include <JailBreak>
#include <JB_QuestsSystem>

// Prizes Libraries.
#include <shop>
#include <shop_premium>
#include <shop_wish>

//==========[ Settings ]==========//

#define CONFIG_PATH "addons/sourcemod/configs/QuestsData.cfg"

#define QUEST_COMPLETED_SOUND "quests/questfinish.mp3"
#define FINAL_REWARD_COLLECT "quests/finalreward.mp3"

#define PROGRESS_REPLACE_SYMBOL "{progress}"

#define PROGRESS_LENGTH 20

#define SECONDS_HOUR 3600
#define SECONDS_DAY SECONDS_HOUR * 24
#define SECONDS_WEEK SECONDS_HOUR * 24 * 7

//====================//

enum struct Quest
{
	char unique[64];
	char name[64];
	char desc[256];
	
	int quest_type;
	int skip_price;
	int min_progress;
	int max_progress;
}

enum struct Client
{
	int account_id;
	
	bool is_final_reward_collected[QuestType_Max];
	
	int skips_amount[QuestType_Max];
	int completed_quests[QuestType_Max];
	
	ArrayList QuestsStatsData;
	
	void Reset()
	{
		this.account_id = 0;
		
		for (int current_quest_type = 0; current_quest_type < QuestType_Max; current_quest_type++)
		{
			this.completed_quests[current_quest_type] = 0;
			this.skips_amount[current_quest_type] = 0;
			this.is_final_reward_collected[current_quest_type] = false;
		}
		
		this.Close();
	}
	
	void Init(ArrayList quests_data)
	{
		// Avoid memory leaks
		this.Close();
		
		// Create the arraylist which will store the quests stats data
		this.QuestsStatsData = new ArrayList(sizeof(QuestStats));
		
		QuestStats QuestStatsData;
		for (int current_quest = 0; current_quest < quests_data.Length; current_quest++)
		{
			this.QuestsStatsData.PushArray(QuestStatsData);
		}
	}
	
	void Close()
	{
		delete this.QuestsStatsData;
	}
	
	//=============================================//
	
	// Retrives a certain quest stats data struct.
	//
	// @param index         Quest index.
	// @param first_item    'QuestStats' data struct to as a buffer.
	// @return              Number of cells copied.
	int GetQuestStatsData(int index, any[] buffer)
	{
		return this.QuestsStatsData.GetArray(index, buffer);
	}
	
	// Retrives whether or not a certain quest is completed.
	//
	// @param index         Quest index.
	// @return              True if the quest is completed, false otherwise.
	bool IsQuestCompleted(int quest_index)
	{
		return this.QuestsStatsData.Get(quest_index, QuestStats::quest_progress) >= this.QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress);
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

Database g_Database = null;

GlobalForward g_OnQuestsReset;
GlobalForward g_OnQuestRewardDisplay;
GlobalForward g_OnQuestRewardCollect;
GlobalForward g_OnQuestAssigned;
GlobalForward g_OnQuestCompleted;

ArrayList g_Quests;
ArrayList g_FinalRewards[QuestType_Max];

ConVar g_QuestsPer[QuestType_Max];
ConVar g_DefaultSkips[QuestType_Max];
ConVar g_MinRequiredPlayers;

int g_SwitchUnixstamp[QuestType_Max];

public Plugin myinfo = 
{
	name = "[CS:GO] Quests System - Core", 
	author = "KoNLiG", 
	description = "Quests system that provides a daily & weekly missions with custom rewards.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnPluginStart()
{
	// Initialize global variables.
	g_Quests = new ArrayList(sizeof(Quest));
	g_FinalRewards[QuestType_Daily] = new ArrayList();
	g_FinalRewards[QuestType_Weekly] = new ArrayList();
	
	// ConVars Configurate
	g_QuestsPer[QuestType_Daily] = CreateConVar("quests_per_day", "5", "Amount of quests to appear every daily reset.");
	g_QuestsPer[QuestType_Weekly] = CreateConVar("quests_per_week", "5", "Amount of quests to appear every weekly reset.");
	
	g_DefaultSkips[QuestType_Daily] = CreateConVar("quests_default_skips_daily", "2", "Default amount of skips for daily quests.", _, true, 0.0, true, g_QuestsPer[QuestType_Daily].FloatValue);
	g_DefaultSkips[QuestType_Weekly] = CreateConVar("quests_default_skips_weekly", "2", "Default amount of skips for weekly quests.", _, true, 0.0, true, g_QuestsPer[QuestType_Weekly].FloatValue);
	
	g_MinRequiredPlayers = CreateConVar("quests_min_players", "1", "Minimum players required for quest progress to be achieved.", _, true, 0.0, true, float(MAXPLAYERS));
	
	// AutoExecConfig(true, "QuestsSystem", "JailBreak");
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Client Commands
	RegConsoleCmd("sm_quests", Command_Quests, "Access the quests list menu.");
	RegConsoleCmd("sm_q", Command_Quests, "Access the quests list menu. (An alias)");
	
	char file_path[PLATFORM_MAX_PATH];
	strcopy(file_path, sizeof(file_path), CONFIG_PATH);
	BuildPath(Path_SM, file_path, sizeof(file_path), file_path[17]);
	delete OpenFile(file_path, "a+");
}

public void OnPluginEnd()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientDisconnect(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnMapStart()
{
	KV_LoadQuests();
	
	AddFileToDownloadsTable("sound/"...QUEST_COMPLETED_SOUND);
	PrecacheSound(QUEST_COMPLETED_SOUND);
	AddFileToDownloadsTable("sound/"...FINAL_REWARD_COLLECT);
	PrecacheSound(FINAL_REWARD_COLLECT);
	
	// 'OnMapStart()' is too early to use 'g_Database' handle. (Still 'null')
	CheckForQuestsSwitch();
}

void CheckForQuestsSwitch()
{
	if (!g_Database)
	{
		return;
	}
	
	if (g_SwitchUnixstamp[QuestType_Daily] <= GetTime())
	{
		SwitchQuests(QuestType_Daily);
	}
	
	if (g_SwitchUnixstamp[QuestType_Weekly] <= GetTime())
	{
		SwitchQuests(QuestType_Weekly);
	}
<<<<<<< HEAD
=======
	
	AddFileToDownloadsTable("sound/"...QUEST_COMPLETED_SOUND);
	PrecacheSound(QUEST_COMPLETED_SOUND);
	AddFileToDownloadsTable("sound/"...FINAL_REWARD_COLLECT);
	PrecacheSound(FINAL_REWARD_COLLECT);
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
}

public void OnClientPutInServer(int client)
{
	// If the authorized client is fake or we couldn't get the client steam account id, don't continue
	if (IsFakeClient(client) || !(g_ClientsData[client].account_id = GetSteamAccountID(client)))
	{
		return;
	}
	
	g_ClientsData[client].Init(g_Quests);
	
	// Fetch the client data from the database
	SQL_FetchClient(client);
}

public void OnClientDisconnect(int client)
{
	// Validate the client steam account id, which means the client isn't a bot and his data has been loaded
	if (!g_ClientsData[client].account_id)
	{
		return;
	}
	
	// Update the client data inside the database
	SQL_UpdateClient(client);
}

//================================[ Commands ]================================//

Action Command_Quests(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	ShowQuestsMainMenu(client);
	return Plugin_Handled;
}

//================================[ API ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	CreateForwards();
	
	RegPluginLibrary("JB_QuestsSystem");
	
	return APLRes_Success;
}

void CreateNatives()
{
	// int JB_CreateQuest(char[] unique, char[] name, char[] desc, int type, int skip_price, int min_progress, int max_progress)
	CreateNative("JB_CreateQuest", Native_CreateQuest);
	
	// int JB_FindQuest(char[] unique)
	CreateNative("JB_FindQuest", Native_FindQuest);
	
	// int JB_GetQuestProgress(int client, int quest_id)
	CreateNative("JB_GetQuestProgress", Native_GetQuestProgress);
	
	// bool JB_AddQuestProgress(int client, int quest_id, int progress = 1)
	CreateNative("JB_AddQuestProgress", Native_AddQuestProgress);
	
	// bool JB_TakeQuestProgress(int client, int quest_id, int progress = 1)
	CreateNative("JB_TakeQuestProgress", Native_TakeQuestProgress);
	
	// bool JB_SetQuestProgress(int client, int quest_id, int progress)
	CreateNative("JB_SetQuestProgress", Native_SetQuestProgress);
	
	// void JB_GetClientQuestStats(int client, int quest_id, any[] buffer)
	CreateNative("JB_GetClientQuestStats", Native_GetClientQuestStats);
}

void CreateForwards()
{
	g_OnQuestsReset = new GlobalForward(
		"JB_OnQuestsReset", 
		ET_Ignore,  // Always return 0.
		Param_Cell // int quests_type
		);
	
	g_OnQuestRewardDisplay = new GlobalForward(
		"JB_OnQuestRewardDisplay", 
		ET_Ignore,  // Always return 0.
		Param_Cell,  // int client
		Param_Cell,  // int quest_id
		Param_String,  // char[] display_text
		Param_Cell,  // int length
		Param_Cell // ExecuteType execute_type
		);
	
	g_OnQuestRewardCollect = new GlobalForward(
		"JB_OnQuestRewardCollect", 
		ET_Ignore,  // Always return 0.
		Param_Cell,  // int client
		Param_Cell,  // int quest_id
		Param_String,  // char[] display_text
		Param_Cell,  // int length
		Param_Cell // ExecuteType execute_type
		);
	
	g_OnQuestAssigned = new GlobalForward(
		"JB_OnQuestAssigned", 
		ET_Ignore,  // Always return 0.
		Param_Cell,  // int client
		Param_Cell,  // int quest_id
		Param_Cell,  // int target_progress
		Param_CellByRef,  // int &reward
		Param_Cell // ExecuteType execute_type
		);
	
	g_OnQuestCompleted = new GlobalForward(
		"JB_OnQuestCompleted", 
		ET_Ignore,  // Always return 0.
		Param_Cell,  // int client
		Param_Cell,  // int quest_id
		Param_Cell,  // int quest_type
		Param_Cell // int quests_left
		);
}

// Natives.
int Native_CreateQuest(Handle plugin, int numParams)
{
	Quest QuestData;
	GetNativeString(1, QuestData.unique, sizeof(Quest::unique));
	
	// Initialize the quest id by the specified quest unique, and if it is already exists, return the given index
	int quest_index = GetQuestByUnique(QuestData.unique);
	if (quest_index != -1)
	{
		return quest_index;
	}
	
	GetNativeString(2, QuestData.name, sizeof(Quest::name));
	GetNativeString(3, QuestData.desc, sizeof(Quest::desc));
	
	QuestData.quest_type = GetNativeCell(4);
	QuestData.skip_price = GetNativeCell(5);
	QuestData.min_progress = GetNativeCell(6);
	QuestData.max_progress = GetNativeCell(7);
	
	// Push the quest data struct to the last array in the array list, and return the quest index
	return g_Quests.PushArray(QuestData);
}

int Native_FindQuest(Handle plugin, int numParams)
{
	// Get the given quest unique string
	char quest_unique[64];
	GetNativeString(1, quest_unique, sizeof(quest_unique));
	
	// Search and return the quest index by the given unique
	return GetQuestByUnique(quest_unique);
}

int Native_GetQuestProgress(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the quest index
	int quest_index = GetNativeCell(2);
	
	if (!(0 <= quest_index < g_Quests.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified quest index (Got: %d, Max: %d)", quest_index, g_Quests.Length);
	}
	
	// Return the client quest progress
	return g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_progress);
}

any Native_AddQuestProgress(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the quest index
	int quest_index = GetNativeCell(2);
	
	if (!(0 <= quest_index < g_Quests.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified quest index (Got: %d, Max: %d)", quest_index, g_Quests.Length);
	}
	
	Quest QuestData; QuestData = GetQuestByIndex(quest_index);
	
	// Not enough online players
	if (GetOnlineClientCount() < g_MinRequiredPlayers.IntValue)
	{
		return false;
	}
	
	// The quest is currently not active for the client
	int target_progress = g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress);
	if (target_progress <= 0)
	{
		return false;
	}
	
	// The client already completed the quest
	if (g_ClientsData[client].IsQuestCompleted(quest_index))
	{
		return false;
	}
	
	// Get and verify the progress amount
	int progress = GetNativeCell(3);
	
	if (progress <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid progress amount (%d), must be over 0.", progress);
	}
	
	int client_quest_progress = g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_progress) + progress;
	
	// Add the progress to the client data
	g_ClientsData[client].QuestsStatsData.Set(quest_index, client_quest_progress, QuestStats::quest_progress);
	
	// Check if the client has just completed the quest
	if (client_quest_progress >= target_progress)
	{
		// Prevent overflowing the quest progress, can lead to displaying invalid quest information
		g_ClientsData[client].QuestsStatsData.Set(quest_index, target_progress, QuestStats::quest_progress);
		
		// Increase the completed quests that the client has done
		g_ClientsData[client].completed_quests[QuestData.quest_type]++;
		
		// Play the quest complete sound effect
		EmitSoundToClient(client, QUEST_COMPLETED_SOUND);
		
		// Notify the client
		PrintToChat(client, "%s You have \x04completed\x01 a \x0E%s\x01 quest, type \x0C/quests\x01 to collect your reward!", PREFIX, QuestData.quest_type == QuestType_Daily ? "daily" : "weekly");
		
		Call_OnQuestCompleted(client, quest_index, QuestData.quest_type, g_QuestsPer[QuestData.quest_type].IntValue - g_ClientsData[client].completed_quests[QuestData.quest_type]);
	}
	
	return true;
}

int Native_TakeQuestProgress(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the quest index
	int quest_index = GetNativeCell(2);
	
	if (!(0 <= quest_index < g_Quests.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified quest index (Got: %d, Max: %d)", quest_index, g_Quests.Length);
	}
	
	// Get and verify the progress amount
	int progress = GetNativeCell(3);
	
	if (progress <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid progress amount (%d), must be over 0.", progress);
	}
	
	// Not enough online players
	if (GetOnlineClientCount() < g_MinRequiredPlayers.IntValue)
	{
		return false;
	}
	
	// The quest is currently not active
	if (g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress) <= 0)
	{
		return false;
	}
	
	// The client already completed the quest
	if (g_ClientsData[client].IsQuestCompleted(quest_index))
	{
		return false;
	}
	
	int client_quest_progress = g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_progress);
	
	// Take the progress from the client data
	if (client_quest_progress - progress <= 0)
	{
		g_ClientsData[client].QuestsStatsData.Set(quest_index, 0, QuestStats::quest_progress);
	}
	else
	{
		g_ClientsData[client].QuestsStatsData.Set(quest_index, client_quest_progress - progress, QuestStats::quest_progress);
	}
	
	return true;
}

int Native_SetQuestProgress(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the quest index
	int quest_index = GetNativeCell(2);
	
	if (!(0 <= quest_index < g_Quests.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified quest index (Got: %d, Max: %d)", quest_index, g_Quests.Length);
	}
	
	// Get and verify the progress amount
	int progress = GetNativeCell(3);
	
	if (progress < 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid progress amount (%d), must be over -1.", progress);
	}
	
	// Not enough online players
	if (GetOnlineClientCount() < g_MinRequiredPlayers.IntValue)
	{
		return false;
	}
	
	// The quest is currently not active
	if (g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress) <= 0)
	{
		return false;
	}
	
	// The client already completed the quest
	if (g_ClientsData[client].IsQuestCompleted(quest_index))
	{
		return false;
	}
	
	// Set the progress
	g_ClientsData[client].QuestsStatsData.Set(quest_index, progress, QuestStats::quest_progress);
	
	return true;
}

int Native_GetClientQuestStats(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the quest index
	int quest_index = GetNativeCell(2);
	
	if (!(0 <= quest_index < g_Quests.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified quest index (Got: %d, Max: %d)", quest_index, g_Quests.Length);
	}
	
	// Get the quest stats data by the given quest index
	QuestStats stats;
	g_ClientsData[client].GetQuestStatsData(quest_index, stats);
	
	// Store it inside the given buffer
	SetNativeArray(3, stats, sizeof(stats));
	
	return 0;
}

// Forwards.
void Call_OnQuestsReset(int quests_type)
{
	Call_StartForward(g_OnQuestsReset);
	Call_PushCell(quests_type);
	
	int errors = Call_Finish();
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Quests reset forward failed - Error: (%d)", errors);
	}
}

void Call_OnQuestRewardDisplay(int client, int quest_id, ExecuteType execute_type, char[] display_text, int length)
{
	Call_StartForward(g_OnQuestRewardDisplay);
	
	Call_PushCell(client); // int client
	Call_PushCell(quest_id); // int quest_id
	
	Call_PushStringEx(display_text, length, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK); // char[] display_text
	Call_PushCell(length); // int length
	
	Call_PushCell(execute_type); // ExecuteType execute_type
	
	int errors = Call_Finish();
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Quest reward display forward failed - Error: (%d)", errors);
	}
}

void Call_OnQuestRewardCollect(int client, int quest_id, ExecuteType execute_type, char[] display_text, int length)
{
	Call_StartForward(g_OnQuestRewardCollect);
	
	Call_PushCell(client); // int client
	Call_PushCell(quest_id); // int quest_id
	Call_PushStringEx(display_text, length, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK); // char[] display_text
	Call_PushCell(length); // int length
	Call_PushCell(execute_type); // ExecuteType execute_type
	
	int errors = Call_Finish();
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Quest reward collect forward failed - Error: (%d)", errors);
	}
}

void Call_OnQuestAssigned(int client, int quest_id, int target_progress, int &reward, ExecuteType execute_type)
{
	Call_StartForward(g_OnQuestAssigned);
	
	Call_PushCell(client); // int client
	Call_PushCell(quest_id); // int quest_id
	Call_PushCell(target_progress); // target_progress
	Call_PushCellRef(reward); // reward
	
	Call_PushCell(execute_type); // ExecuteType execute_type
	
	int errors = Call_Finish();
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Quest assigned forward failed - Error: (%d)", errors);
	}
}

void Call_OnQuestCompleted(int client, int quest_id, int quest_type, int quests_left)
{
	Call_StartForward(g_OnQuestCompleted);
	
	Call_PushCell(client); // int client
	Call_PushCell(quest_id); // int quest_id
	Call_PushCell(quest_type); // quest_type
	Call_PushCell(quests_left); // quests_left
	
	int errors = Call_Finish();
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Quest completed forward failed - Error: (%d)", errors);
	}
}

//================================[ Menus ]================================//

void ShowQuestsMainMenu(int client)
{
	char item_display[32];
	Menu menu = new Menu(Handler_QuestsMain, MenuAction_Select);
	menu.SetTitle("%s Quests System - Main Menu\n \n*Quests points gathering available from %d or more players.\n ", PREFIX_MENU, g_MinRequiredPlayers.IntValue);
	
	Format(item_display, sizeof(item_display), "Daily Quests [%d/%d Completed]", g_ClientsData[client].completed_quests[QuestType_Daily], GetFixedQuestsCount(QuestType_Daily));
	menu.AddItem("", item_display);
	Format(item_display, sizeof(item_display), "Weekly Quests [%d/%d Completed]", g_ClientsData[client].completed_quests[QuestType_Weekly], GetFixedQuestsCount(QuestType_Weekly));
	menu.AddItem("", item_display);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_QuestsMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		ShowQuestsListMenu(client, item_position);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void ShowQuestsListMenu(int client, int quests_type)
{
	char item_display[128], item_info[4];
	
	// Calculate the time until the next reset for the given quests type
	float quests_reset_time = (float(g_SwitchUnixstamp[quests_type]) - float(GetTime())) / (quests_type == QuestType_Daily ? float(SECONDS_HOUR):float(SECONDS_DAY));
	
	// Format the reset time display buffer
	Format(item_display, sizeof(item_display), "%.1f %s", quests_reset_time, quests_type == QuestType_Daily ? "Hours" : "Days");
	
	Menu menu = new Menu(Handler_QuestsList);
	menu.SetTitle("%s Quests System - %s Quests (%d/%d Completed)\n \n• Next reset: %s\n* Complete each quest, to recive these rewards:\n   [???????]\n ", 
		PREFIX_MENU, 
		quests_type == QuestType_Daily ? "Daily" : "Weekly", 
		g_ClientsData[client].completed_quests[quests_type], 
		g_QuestsPer[quests_type].IntValue, 
		quests_reset_time <= 0.09 ? "Next Map!" : item_display
		);
	
	menu.AddItem("", g_ClientsData[client].is_final_reward_collected[quests_type] ? "Final Reward Collected\n " : "Collect Final Reward!\n ", g_ClientsData[client].completed_quests[quests_type] >= g_QuestsPer[quests_type].IntValue && !g_ClientsData[client].is_final_reward_collected[quests_type] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Quest CurrentQuestData;
	bool is_quest_skipped;
	
	// Loop through all the active quests, and insert them into the menu
	for (int current_quest = 0; current_quest < g_Quests.Length; current_quest++)
	{
		// Initialize the current quest data struct
		CurrentQuestData = GetQuestByIndex(current_quest);
		
		if (g_ClientsData[client].QuestsStatsData.Get(current_quest, QuestStats::quest_target_progress) > 0 && CurrentQuestData.quest_type == quests_type)
		{
			// Convert the current quest index into a string, and parse it through the menu item
			IntToString(current_quest, item_info, sizeof(item_info));
			
			is_quest_skipped = g_ClientsData[client].QuestsStatsData.Get(current_quest, QuestStats::is_quest_skipped);
			
			// Format the quest display buffer, and insert it into the menu
			Format(item_display, sizeof(item_display), "%s %s", CurrentQuestData.name, is_quest_skipped ? "[Skipped]" : g_ClientsData[client].IsQuestCompleted(current_quest) ? "[Completed]" : g_ClientsData[client].QuestsStatsData.Get(current_quest, QuestStats::quest_progress) > 0 ? "[In Progress]" : "");
			menu.AddItem(item_info, item_display, !is_quest_skipped ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		}
	}
	
	// If no quest was found for the given quests type, add an extra notify menu item
	if (!GetQuestsCount(quests_type))
	{
		menu.AddItem("", "No quest was found.", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_QuestsList(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Initialize the quest index by the selected menu item info
		char item_info[4];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int quest_index = StringToInt(item_info);
		
		switch (item_position)
		{
			// The client pressed on the collect final reward button
			case 0:
			{
				menu.GetItem(1, item_info, sizeof(item_info));
				
				// Initialize the final reward type
				int quests_type = g_Quests.Get(StringToInt(item_info), Quest::quest_type);
				
				Quest QuestData; QuestData = GetQuestByIndex(quest_index);
				
				g_ClientsData[client].is_final_reward_collected[quests_type] = true;
				
				// Display the quests list menu again by the given quests type
				ShowQuestsListMenu(client, quests_type);
				
				// Give the final reward to the client
				PerformFinalReward(client, quests_type);
				
				// Write a log line
				WriteLogLine("\"%L\" has collected his %s final reward.", client, quests_type == QuestType_Daily ? "daily" : "weekly");
			}
			
			// The client pressed on a quest
			default:
			{
				// Display the selected quest detail menu
				ShowQuestDetailMenu(client, quest_index);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Display the last menu the client was in
		ShowQuestsMainMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void ShowQuestDetailMenu(int client, int quest_index)
{
	char item_display[128], item_info[4];
	
	// Convert the given quest index into a string, and parse it through the first menu item
	IntToString(quest_index, item_info, sizeof(item_info));
	
	// Initialize the quest data struct by the given quest index
	Quest QuestData; QuestData = GetQuestByIndex(quest_index);
	
	int target_progress = g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress);
	
	// Replace the {progress} to the real quest progress
	char progress_str[32];
	IntToString(target_progress, progress_str, sizeof(progress_str));
	ReplaceString(QuestData.desc, sizeof(QuestData.desc), PROGRESS_REPLACE_SYMBOL, progress_str);
	
	char quest_reward[64];
	Call_OnQuestRewardDisplay(client, quest_index, ExecuteType_Pre, quest_reward, sizeof(quest_reward));
	
	Menu menu = new Menu(Handler_QuestDetail);
	menu.SetTitle("%s Quests Menu - %s Quest Details\n \n╭%s\n╰┄%s\n \n◾ Reward: %s\n ", PREFIX_MENU, 
		QuestData.quest_type == QuestType_Daily ? "Daily":"Weekly", 
		QuestData.name, 
		QuestData.desc, 
		quest_reward
		);
	
	Call_OnQuestRewardDisplay(client, quest_index, ExecuteType_Post, quest_reward, sizeof(quest_reward));
	
	// Get some information about the selected quest
	QuestStats stats;
	g_ClientsData[client].GetQuestStatsData(quest_index, stats);
	
	bool is_quest_completed = g_ClientsData[client].IsQuestCompleted(quest_index);
	
	Format(item_display, sizeof(item_display), "Progress: %.1f%", (float(stats.quest_progress) / float(target_progress)) * 100.0);
	menu.AddItem(item_info, item_display);
	
	Format(item_display, sizeof(item_display), "%s/%s", AddCommas(stats.quest_progress), AddCommas(target_progress));
	Format(item_display, sizeof(item_display), "%s [%s]\n ", GetProgressBar(stats.quest_progress, target_progress), is_quest_completed ? "Completed" : item_display);
	menu.AddItem("", item_display);
	
	Format(item_display, sizeof(item_display), stats.is_quest_reward_collected ? "Reward Collected" : "Collect Reward!");
	menu.AddItem("", item_display, is_quest_completed && !stats.is_quest_reward_collected ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(item_display, sizeof(item_display), "Skip Quest (%s credits) [%d Uses Left]", AddCommas(QuestData.skip_price), g_ClientsData[client].skips_amount[QuestData.quest_type]);
	menu.AddItem("", item_display, !is_quest_completed && g_ClientsData[client].skips_amount[QuestData.quest_type] > 0 && Shop_GetClientCredits(client) >= QuestData.skip_price ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_QuestDetail(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		// Initialize the quest index by the first menu item info
		char item_info[4];
		menu.GetItem(0, item_info, sizeof(item_info));
		int quest_index = StringToInt(item_info);
		
		// Initialize the quest data struct by the given quest index
		Quest QuestData; QuestData = GetQuestByIndex(quest_index);
		
		switch (param2)
		{
			case 2:
			{
				g_ClientsData[client].QuestsStatsData.Set(quest_index, true, QuestStats::is_quest_reward_collected);
				
				char reward_dispaly_text[64];
				Call_OnQuestRewardCollect(client, quest_index, ExecuteType_Pre, reward_dispaly_text, sizeof(reward_dispaly_text));
				
				PrintToChat(client, "%s You've \x04collected\x01 your \x0EReward\x01, and received \x0C%s\x01!", PREFIX, reward_dispaly_text);
				
				Call_OnQuestRewardCollect(client, quest_index, ExecuteType_Post, reward_dispaly_text, sizeof(reward_dispaly_text));
				
				WriteLogLine("Player \"%L\" has collected his reward (%s) for quest \"%s\".", client, reward_dispaly_text, QuestData.name);
				ShowQuestDetailMenu(client, quest_index);
			}
			case 3:
			{
				int client_credits = Shop_GetClientCredits(client);
				if (client_credits < QuestData.skip_price)
				{
					PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", AddCommas(QuestData.skip_price - client_credits));
					ShowQuestDetailMenu(client, quest_index);
					
					return;
				}
				
				
				Shop_TakeClientCredits(client, QuestData.skip_price);
				
				int target_progress = g_ClientsData[client].QuestsStatsData.Get(quest_index, QuestStats::quest_target_progress);
				
				QuestStats stats;
				
				stats.is_quest_reward_collected = true;
				stats.is_quest_skipped = true;
				stats.quest_progress = target_progress;
				stats.quest_target_progress = target_progress;
				
				g_ClientsData[client].QuestsStatsData.SetArray(quest_index, stats);
				
				g_ClientsData[client].completed_quests[QuestData.quest_type]++;
				g_ClientsData[client].skips_amount[QuestData.quest_type]--;
				
				//PrintToChat(client, "%s You have \x0Dskipped\x01 quest \x0E%s\x01, and you received \x04%s\x01 %s for the quest reward!", PREFIX, QuestData.name, AddCommas(QuestData.iReward), QuestData.iRewardType == Reward_Cash ? "cash":"rank points");
				//WriteLogLine("Player \"%L\" has skipped quest \"%s\" for %s cash.", client, QuestData.name, AddCommas(QuestData.skip_price));
				ShowQuestsListMenu(client, QuestData.quest_type);
			}
			default:
			{
				ShowQuestDetailMenu(client, quest_index);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		char item_info[4];
		menu.GetItem(0, item_info, sizeof(item_info));
		
		// Display the last menu the client was in
		ShowQuestsListMenu(client, g_Quests.Get(StringToInt(item_info), Quest::quest_type));
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `quests_clients_progress`( \
									     `account_id` INT NOT NULL, \
									     `unique` VARCHAR(128) NOT NULL,  \
									     `progress` INT NOT NULL,  \
									     `target_progress` INT NOT NULL,  \
									     `reward_amount` INT NOT NULL, \
									     `reward_collected` INT(1) NOT NULL,  \
									     `quest_skipped` INT(1) NOT NULL, \
									     UNIQUE(`account_id`, `unique`))");
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `quests_clients_data`( \
									     `account_id` INT NOT NULL, \
									     `skips_daily` INT NOT NULL, \
									     `skips_weekly` INT NOT NULL, \
									     `final_collected_daily` INT(1) NOT NULL, \
									     `final_collected_weekly` INT(1) NOT NULL,\
									     UNIQUE (`account_id`))");
	
	CheckForQuestsSwitch();
	
	CreateTimer(0.5, Timer_LateClientsLoop, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

void SQL_FetchClient(int client)
{
	// Get the client user id, and parse it through the queries data
	int client_userid = GetClientUserId(client);
	
	char query[128];
	
	// Execute the 
	FormatEx(query, sizeof(query), "SELECT * FROM `quests_clients_progress` WHERE `account_id` = %d", g_ClientsData[client].account_id);
	g_Database.Query(SQL_FetchClientProgress_CB, query, client_userid, DBPrio_High);
	
	// Execute the 
	FormatEx(query, sizeof(query), "SELECT * FROM `quests_clients_data` WHERE `account_id` = %d", g_ClientsData[client].account_id);
	g_Database.Query(SQL_FetchClientData_CB, query, client_userid);
}

void SQL_FetchClientProgress_CB(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!db || !results || error[0])
	{
		ThrowError("Client progress fetching error, %s", error);
		return;
	}
	
	// Initialize the client index by the passed query data, and make sure it's valid
	int client = GetClientOfUserId(userid);
	
	if (!client)
	{
		return;
	}
	
	// If the client quests progress data is already exists inside the database, fetch it
	if (results.FetchRow())
	{
		int quest_index = -1;
		
		char quest_unique[64];
		
		do
		{
			// Fetch the current quest unique string, and get the quest index from it
			results.FetchString(1, quest_unique, sizeof(quest_unique));
			
			// Make sure the quest index is valid
			if ((quest_index = GetQuestByUnique(quest_unique)) == -1)
			{
				continue;
			}
			
			// Fetch the rest quest data
			QuestStats stats;
			
			stats.is_quest_reward_collected = results.FetchInt(5) == 1;
			stats.is_quest_skipped = results.FetchInt(6) == 1;
			stats.reward_amount = results.FetchInt(4);
			stats.quest_progress = results.FetchInt(2);
			stats.quest_target_progress = results.FetchInt(3);
			
			// Set the quest stats to the updated database data
			g_ClientsData[client].QuestsStatsData.SetArray(quest_index, stats);
			
			// If the current quest is completed, inscrease the completed quests variable value
			if (g_ClientsData[client].IsQuestCompleted(quest_index))
			{
				g_ClientsData[client].completed_quests[GetQuestByIndex(quest_index).quest_type]++;
			}
		} while (results.FetchRow());
	}
	
	// If the client quests data data isn't exists inside the database, insert it
	else
	{
		// Create the arraylist that will store the selected quests indexes
		ArrayList selected_quests = new ArrayList();
		
		int daily_quests = GetFixedQuestsCount(QuestType_Daily);
		
		char query[256];
		
		// Initialize daily quests for the clients
		while (daily_quests && selected_quests.Length != daily_quests)
		{
			int quest_index;
			
			Quest QuestData;
			
			do
			{
				quest_index = GetRandomInt(0, g_Quests.Length - 1);
				
				QuestData = GetQuestByIndex(quest_index);
			} while (selected_quests.FindValue(quest_index) != -1 || QuestData.quest_type != QuestType_Daily);
			
			selected_quests.Push(quest_index);
			
			QuestStats stats;
			
			stats.is_quest_reward_collected = false;
			stats.is_quest_skipped = false;
			stats.quest_progress = 0;
			stats.quest_target_progress = RoundToDivider(GetRandomInt(QuestData.min_progress, QuestData.max_progress));
			
			Call_OnQuestAssigned(client, quest_index, stats.quest_target_progress, stats.reward_amount, ExecuteType_Pre);
			
			g_ClientsData[client].QuestsStatsData.SetArray(quest_index, stats);
			
			// Insert the client's quest progress data into the database
			g_Database.Format(query, sizeof(query), "INSERT INTO `quests_clients_progress` (`account_id`, `unique`, `progress`, `target_progress`, `reward_amount`, `reward_collected`, `quest_skipped`) VALUES (%d, '%s', %d, %d, %d, %d, %d)", 
				g_ClientsData[client].account_id, 
				QuestData.unique, 
				stats.quest_progress, 
				stats.quest_target_progress, 
				stats.reward_amount, 
				stats.is_quest_reward_collected, 
				stats.is_quest_skipped
				);
			
			g_Database.Query(SQL_CheckForErrors, query);
			
			Call_OnQuestAssigned(client, quest_index, stats.quest_target_progress, stats.reward_amount, ExecuteType_Post);
		}
		
		// Clear the entries of the selected quests
		selected_quests.Clear();
		
		int weekly_quests = GetFixedQuestsCount(QuestType_Weekly);
		
		// Initialize weekly quests for the clients
		while (weekly_quests && selected_quests.Length != weekly_quests)
		{
			int quest_index;
			
			Quest QuestData;
			
			do
			{
				quest_index = GetRandomInt(0, g_Quests.Length - 1);
				
				QuestData = GetQuestByIndex(quest_index);
			} while (selected_quests.FindValue(quest_index) != -1 || QuestData.quest_type != QuestType_Weekly);
			
			selected_quests.Push(quest_index);
			
			QuestStats stats;
			
			stats.is_quest_reward_collected = false;
			stats.is_quest_skipped = false;
			stats.quest_progress = 0;
			stats.quest_target_progress = RoundToDivider(GetRandomInt(QuestData.min_progress, QuestData.max_progress));
			
			Call_OnQuestAssigned(client, quest_index, stats.quest_target_progress, stats.reward_amount, ExecuteType_Pre);
			
			g_ClientsData[client].QuestsStatsData.SetArray(quest_index, stats);
			
			// Insert the client's quest progress data into the database
			g_Database.Format(query, sizeof(query), "INSERT INTO `quests_clients_progress` (`account_id`, `unique`, `progress`, `target_progress`, `reward_amount`, `reward_collected`, `quest_skipped`) VALUES (%d, '%s', %d, %d, %d, %d, %d)", 
				g_ClientsData[client].account_id, 
				QuestData.unique, 
				stats.quest_progress, 
				stats.quest_target_progress, 
				stats.reward_amount, 
				stats.is_quest_reward_collected, 
				stats.is_quest_skipped
				);
			
			g_Database.Query(SQL_CheckForErrors, query);
			
			Call_OnQuestAssigned(client, quest_index, stats.quest_target_progress, stats.reward_amount, ExecuteType_Post);
		}
		
		// Don't leak handles.
		delete selected_quests;
	}
}

void SQL_FetchClientData_CB(Database db, DBResultSet results, const char[] error, int userid)
{
	// Make sure no error was occurded
	if (!db || !results || error[0])
	{
		ThrowError("Client data fetching error, %s", error);
		return;
	}
	
	// Get the client index by the parsed query data
	int client = GetClientOfUserId(userid);
	
	// Make sure the client index is valid
	if (!client)
	{
		return;
	}
	
	// If the client data is already exists inside the database, fetch it
	if (results.FetchRow())
	{
		g_ClientsData[client].skips_amount[QuestType_Daily] = results.FetchInt(1);
		g_ClientsData[client].skips_amount[QuestType_Weekly] = results.FetchInt(2);
		g_ClientsData[client].is_final_reward_collected[QuestType_Daily] = results.FetchInt(3) == 1;
		g_ClientsData[client].is_final_reward_collected[QuestType_Weekly] = results.FetchInt(4) == 1;
	}
	
	// If the client data isn't exists inside the database, insert it
	else
	{
		// Set the client local data as the default
		g_ClientsData[client].skips_amount[QuestType_Daily] = g_DefaultSkips[QuestType_Daily].IntValue;
		g_ClientsData[client].skips_amount[QuestType_Weekly] = g_DefaultSkips[QuestType_Weekly].IntValue;
		
		char query[256];
		
		// Insert the client's local data into the database
		FormatEx(query, sizeof(query), "INSERT INTO `quests_clients_data` (`account_id`, `skips_daily`, `skips_weekly`, `final_collected_daily`, `final_collected_weekly`) VALUES (%d, %d, %d, %d, %d)", 
			g_ClientsData[client].account_id, 
			g_ClientsData[client].skips_amount[QuestType_Daily], 
			g_ClientsData[client].skips_amount[QuestType_Daily], 
			g_ClientsData[client].is_final_reward_collected[QuestType_Daily], 
			g_ClientsData[client].is_final_reward_collected[QuestType_Weekly]
			);
		
		g_Database.Query(SQL_CheckForErrors, query);
	}
}

void SQL_UpdateClient(int client)
{
	char query[256];
	QuestStats stats;
	
	for (int current_quest = 0; current_quest < g_Quests.Length; current_quest++)
	{
		g_ClientsData[client].GetQuestStatsData(current_quest, stats);
		
		g_Database.Format(query, sizeof(query), "UPDATE `quests_clients_progress` SET `progress` = %d, `target_progress` = %d, `reward_collected` = %d, `quest_skipped` = %d WHERE `account_id` = %d AND `unique` = '%s'", 
			stats.quest_progress, 
			stats.quest_target_progress, 
			stats.is_quest_reward_collected, 
			stats.is_quest_skipped, 
			g_ClientsData[client].account_id, 
			GetQuestByIndex(current_quest).unique
			);
		
		g_Database.Query(SQL_CheckForErrors, query);
	}
	
	FormatEx(query, sizeof(query), "UPDATE `quests_clients_data` SET `skips_daily` = %d, `skips_weekly` = %d, `final_collected_daily` = %d, `final_collected_weekly` = %d WHERE `account_id` = %d", 
		g_ClientsData[client].skips_amount[QuestType_Daily], 
		g_ClientsData[client].skips_amount[QuestType_Weekly], 
		g_ClientsData[client].is_final_reward_collected[QuestType_Daily], 
		g_ClientsData[client].is_final_reward_collected[QuestType_Weekly], 
		g_ClientsData[client].account_id
		);
	
	g_Database.Query(SQL_CheckForErrors, query, DBPrio_Low);
	
	// Make sure to reset the client data, to avoid data override
	g_ClientsData[client].Reset();
}

void SQL_ResetUserData(int quests_type)
{
	char query[128];
	g_Database.Format(query, sizeof(query), "UPDATE `quests_clients_data` SET `final_collected_%s` = 0, `skips_%s` = %d", quests_type == QuestType_Daily ? "daily" : "weekly", quests_type == QuestType_Daily ? "daily":"weekly", g_DefaultSkips[quests_type].IntValue);
	g_Database.Query(SQL_CheckForErrors, query);
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

//================================[ Key Values ]================================//

void KV_LoadQuests()
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to locate file (%s)", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("QuestsData");
	kv.ImportFromFile(CONFIG_PATH);
	
	kv.SetEscapeSequences(true);
	
	// Get the quests reset unix stamps from the key values file
	g_SwitchUnixstamp[QuestType_Daily] = kv.GetNum("Daily_Reset");
	g_SwitchUnixstamp[QuestType_Weekly] = kv.GetNum("Weekly_Reset");
	
	if (kv.JumpToKey("Final_Rewards"))
	{
		if (kv.JumpToKey("Daily") && kv.GotoFirstSubKey())
		{
			do
			{
				StringMap context = new StringMap();
				
				char key[32], value[64];
				
				kv.GotoFirstSubKey(false);
				do
				{
					kv.GetSectionName(key, sizeof(key));
					kv.GetString(NULL_STRING, value, sizeof(value));
					
					context.SetString(key, value);
				} while (kv.GotoNextKey(false));
				
				g_FinalRewards[QuestType_Daily].Push(context);
				
				kv.GoBack();
			} while (kv.GotoNextKey());
		}
		
		kv.GoBack();
		kv.GoBack();
		
		char str[128];
		kv.GetSectionName(str, sizeof(str));
		
		if (kv.JumpToKey("Weekly") && kv.GotoFirstSubKey())
		{
			do
			{
				StringMap context = new StringMap();
				
				char key[32], value[64];
				
				kv.GotoFirstSubKey(false);
				do
				{
					kv.GetSectionName(key, sizeof(key));
					kv.GetString(NULL_STRING, value, sizeof(value));
					
					context.SetString(key, value);
				} while (kv.GotoNextKey(false));
				
				g_FinalRewards[QuestType_Weekly].Push(context);
				
				kv.GoBack();
			} while (kv.GotoNextKey());
		}
	}
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	
	// Don't leak handles!
	kv.Close();
}

void KV_SetQuestsData(int quests_type)
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to locate file (%s)", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("QuestsData");
	kv.ImportFromFile(CONFIG_PATH);
	
	// Set the updated quests reset unix stamps
	kv.SetNum(quests_type == QuestType_Daily ? "Daily_Reset" : "Weekly_Reset", GetTime() + (quests_type == QuestType_Daily ? SECONDS_DAY : SECONDS_WEEK));
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	
	// Don't leak handles!
	kv.Close();
	
	KV_LoadQuests();
}

Action Timer_LateClientsLoop(Handle timer)
{
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

//================================[ Functions ]================================//

int GetQuestByUnique(const char[] unique)
{
	return g_Quests.FindString(unique);
}

any[] GetQuestByIndex(int index)
{
	Quest QuestData;
	g_Quests.GetArray(index, QuestData, sizeof(QuestData));
	return QuestData;
}

int GetQuestsCount(int quests_type)
{
	int counter = 0;
	
	for (int current_quest = 0; current_quest < g_Quests.Length; current_quest++)
	{
		if (GetQuestByIndex(current_quest).quest_type == quests_type)
		{
			counter++;
		}
	}
	
	return counter;
}

int GetFixedQuestsCount(int quests_type)
{
	int quests_count = GetQuestsCount(quests_type);
	
	return quests_count < g_QuestsPer[quests_type].IntValue ? quests_count : g_QuestsPer[quests_type].IntValue;
}

char GetProgressBar(int value, int all)
{
	char progress_str[PROGRESS_LENGTH * 6];
	int length = PROGRESS_LENGTH;
	
	for (int current_char = 0; current_char <= (float(value) / float(all) * PROGRESS_LENGTH) - 1; current_char++)
	{
		length--;
		StrCat(progress_str, sizeof(progress_str), "•");
	}
	
	for (int current_char = 0; current_char < length; current_char++)
	{
		StrCat(progress_str, sizeof(progress_str), "⬛");
	}
	
	StripQuotes(progress_str);
	TrimString(progress_str);
	
	return progress_str;
}

void PerformFinalReward(int client, int quests_type)
{
	// Play the final reward collect sound effect
	EmitSoundToClient(client, FINAL_REWARD_COLLECT);
	
	// Store the final reward as a string.
	char reward[64];
	
	reward = AwardClient(client, quests_type);
	
	// Notify the client
	PrintToChat(client, "%s You have \x04collected\x01 your \x0E%s\x01 final reward and received: %s", PREFIX, quests_type == QuestType_Daily ? "daily" : "weekly", reward);
}

// Awards a client with this final reward prizes.
//
// @param client         Client index.
// 
// @return				 Formatted awards string.
char AwardClient(int client, int quests_type)
{
	StringMap rewards = g_FinalRewards[quests_type].Get(GetRandomInt(0, g_FinalRewards[quests_type].Length - 1));
	
	StringMapSnapshot rewards_snapshot = rewards.Snapshot();
	
	char temp[32], exploded_range[2][32], randomized_award_str[11], awards_str[64];
	
	rewards.GetString("text", awards_str, sizeof(awards_str));
	
	for (int current_key, buffer_size, randomized_award, range[2]; current_key < rewards_snapshot.Length; current_key++)
	{
		// Get the buffer size for the current Key.
		buffer_size = rewards_snapshot.KeyBufferSize(current_key);
		
		// Create a buffer to store the current Key.
		char[] buffer = new char[buffer_size];
		
		// Get the current Snapshot.
		rewards_snapshot.GetKey(current_key, buffer, buffer_size);
		
		if (StrEqual(buffer, "text"))
		{
			continue;
		}
		
		rewards.GetString(buffer, temp, sizeof(temp));
		
		// Retrieve the prize available ranges.
		ExplodeString(temp, "-", exploded_range, sizeof(exploded_range), sizeof(exploded_range[]));
		range[0] = StringToInt(exploded_range[0]);
		range[1] = StringToInt(exploded_range[1]);
		
		randomized_award = range[0] != range[1] ? GetRandomInt(range[0], range[1]) : range[0];
		
		switch (buffer[0])
		{
			// 'Credits'
			case 'c':
			{
				Shop_GiveClientCredits(client, randomized_award);
			}
			// 'Premium'
			case 'p':
			{
				Shop_GivePremium(client, randomized_award);
			}
			// 'Wish'
			case 'w':
			{
				Shop_GiveClientWish(client, randomized_award);
			}
		}
		
		// Replace the awards string token.
		FormatEx(temp, sizeof(temp), "{value_%s}", buffer);
		IntToString(randomized_award, randomized_award_str, sizeof(randomized_award_str));
		ReplaceString(awards_str, sizeof(awards_str), temp, randomized_award_str);
	}
	
	// Delete the Snapshot.
	delete rewards_snapshot;
	
	return awards_str;
}

int GetOnlineClientCount()
{
	int counter;
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			counter++;
		}
	}
	
	return counter;
}

void SwitchQuests(int quests_type)
{
	SQL_ResetUserData(quests_type);
	
	g_Database.Query(SQL_CheckForErrors, "DELETE FROM `quests_clients_progress`");
	
	KV_SetQuestsData(quests_type);
	
	Call_OnQuestsReset(quests_type);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			g_ClientsData[current_client].Reset();
			
			OnClientPutInServer(current_client);
		}
	}
	
	WriteLogLine("%s quests has automatically reset.", quests_type == QuestType_Daily ? "Daily" : "Weekly");
}

//================================================================//