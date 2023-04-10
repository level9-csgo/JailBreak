#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.0"

//==========[ Settings ]==========//

#define SPECIAL_MODS_BUTTON_INFO "special_mods"

#define PANEL_DISPLAY_TIME 7
#define VOTE_DISPLAY_TIME 15

//====================//

enum SpecialModRequirements
{
	REQ_NONE, 
	REQ_NOT_ENOUGH_CREDITS, 
	REQ_NOT_ENOUGH_PRISONERS, 
	REQ_COOLDOWN, 
	REQ_TOO_LATE
}

enum struct SpecialMod
{
	char mod_name[64];
	char mod_desc[128];
}

ArrayList g_SpecialModsData;

GlobalForward g_fwdOnSpecialModExecute;
GlobalForward g_fwdOnSpecialModEnd;

ConVar g_cvPricePerPrisoner;
ConVar g_cvRequiredOnlinePrisoners;
ConVar g_cvSecondsUntilLock;
ConVar g_cvVotePercent;

int g_SpecialModBuyBlockCounter;
int g_CurrentSpecialMod = -1;
int g_RoundStartUnixstamp;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Special Mods", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the special mods data arraylist
	g_SpecialModsData = new ArrayList(sizeof(SpecialMod));
	
	// ConVars Configurate
	g_cvPricePerPrisoner = CreateConVar("jb_special_mod_price_per_prisoner", "5000", "The price per online prisoner. (Calculate: prisoners * convar)", _, true, 2500.0, true, 12500.0);
	g_cvRequiredOnlinePrisoners = CreateConVar("jb_special_mod_required_prisoners", "12", "Required online prisonres for executing a special mod.", _, true, 1.0, true, 16.0);
	g_cvSecondsUntilLock = CreateConVar("jb_special_mod_seconds_until_lock", "30", "Seconds until the main guard will not be able to buy a special mod.", _, true, 10.0, true, 60.0);
	g_cvVotePercent = CreateConVar("jb_special_mod_vote_percent", "70", "Required percentage of positive votes in order for a special mod vote to pass.", .hasMin = true, .hasMax = true, .max = 100.0);
	
	AutoExecConfig(true, "SpecialMods", "JailBreak");
	
	// Event Hooks
	HookEvent("round_prestart", Event_RoundPreStart);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

//================================[ Events ]================================//

public void JB_OnOpenMainGuardMenu(int client, Menu menu)
{
	// Add the item to the main guard menu
	menu.AddItem(SPECIAL_MODS_BUTTON_INFO, "Special Mods\n ");
}

public void JB_OnPressMainGuardMenu(int client, const char[] itemInfo)
{
	if (StrEqual(itemInfo, SPECIAL_MODS_BUTTON_INFO))
	{
		ShowSpecialModsMenu(client);
	}
}

public void JB_OnSpecialDayVoteEnd(int specialDayId)
{
	StopSpecialMod();
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	StopSpecialMod();
}

public void OnMapStart()
{
	StopSpecialMod();
}

public void JB_OnVoteCTStart(bool action)
{
	StopSpecialMod();
	
	switch (g_SpecialModBuyBlockCounter)
	{
		case 1 : g_SpecialModBuyBlockCounter++;
		case 2 : g_SpecialModBuyBlockCounter = 0;
		default : g_SpecialModBuyBlockCounter = 0;
	}
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	// Check if a special mod is running, and there is no guards
	if (g_CurrentSpecialMod != -1 && JB_GetDay() >= Day_Friday)
	{
		StopSpecialMod();
	}
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_RoundStartUnixstamp = GetTime();
}

//================================[ Menus ]================================//

void ShowSpecialModsMenu(int client)
{
	Menu menu = new Menu(Handler_SpecialMods);
	menu.SetTitle("%s Special Mods - Main Menu\n \n• Requirements for execuing a special mod: \n  ◾ %s Credits on every for every prisoner \n  ◾ %d Or more online prisoners \n  ◾ Can be bought only in the first %d seconds of the first round\n  ◾ 1 Guard team swiches between every purchase\n ", PREFIX_MENU, JB_AddCommas(g_cvPricePerPrisoner.IntValue), g_cvRequiredOnlinePrisoners.IntValue, g_cvSecondsUntilLock.IntValue);
	
	// Loop through all the special mods, and add them into the menu
	for (int current_special_mod = 0; current_special_mod < g_SpecialModsData.Length; current_special_mod++)
	{
		menu.AddItem("", GetSpecialModByIndex(current_special_mod).mod_name);
	}
	
	// If no special mod was found, add as extra menu item
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No special mod was found.", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SpecialMods(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still the main guard
		if (JB_GetClientGuardRank(client) != Guard_Main)
		{
			PrintToChat(client, "%s You are no longer the \x0CMain Guard\x01 anymore!", PREFIX_ERROR);
			return 0;
		}
		
		ShowSpecialModDetailMenu(client, item_position);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		FakeClientCommand(param1, "sm_ctlist");
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowSpecialModDetailMenu(int client, int special_mod_index)
{
	// Initialize the special mod struct data
	SpecialMod SpecialModData; SpecialModData = GetSpecialModByIndex(special_mod_index);
	
	// Check if the client is meeting the special mod requirements
	SpecialModRequirements special_mod_req = GetRequirementsStatus(client);
	
	Menu menu = new Menu(Handler_SpecialModDetail);
	menu.SetTitle("%s Special Mods - Viewing %s\n \n• %s\n\%s", PREFIX_MENU, SpecialModData.mod_name, SpecialModData.mod_desc, special_mod_req == REQ_COOLDOWN ? " \n  • Special mods currently in cooldown, try again in the next guards shift •\n " : special_mod_req == REQ_NOT_ENOUGH_CREDITS ? " \n  • Not enough credits •\n " : special_mod_req == REQ_NOT_ENOUGH_PRISONERS ? " \n  • Not enough online prisoners •\n " : special_mod_req == REQ_TOO_LATE ? " \n  • Too late, game already started •\n " : " ");
	
	char item_display[64], item_info[4];
	
	int buy_price = GetSpecialModBuyPrice();
	
	// Convert the specified special mod index to string, and parse it through the first menu item
	IntToString(special_mod_index, item_info, sizeof(item_info));
	
	Format(item_display, sizeof(item_display), "Buy %s [%s Credits]", SpecialModData.mod_name, JB_AddCommas(buy_price >= g_cvPricePerPrisoner.IntValue * g_cvRequiredOnlinePrisoners.IntValue ? buy_price : g_cvPricePerPrisoner.IntValue * g_cvRequiredOnlinePrisoners.IntValue));
	menu.AddItem(item_info, item_display, special_mod_req == REQ_NONE ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(item_display, sizeof(item_display), "Execute A Vote For Free [%d%%+]", g_cvVotePercent.IntValue);
	menu.AddItem("", item_display, (special_mod_req == REQ_NONE || special_mod_req == REQ_NOT_ENOUGH_CREDITS) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SpecialModDetail(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still the main guard
		if (JB_GetClientGuardRank(client) != Guard_Main)
		{
			PrintToChat(client, "%s You're no longer the \x0CMain Guard\x01 anymore!", PREFIX_ERROR);
			return 0;
		}
		
		// Get the special mod index by the item information
		char item_info[4];
		menu.GetItem(0, item_info, sizeof(item_info));
		int special_mod_index = StringToInt(item_info);
		
		// Check if the client is meeting the special mod requirements
		SpecialModRequirements special_mod_req = GetRequirementsStatus(client);
		
		switch (item_position)
		{
			case 0:
			{
				// Make sure the requirements status is valid
				if (special_mod_req != REQ_NONE)
				{
					PrintToChat(client, "%s You're no longer meeting the special mod requirements!", PREFIX_ERROR);
					return 0;
				}
				
				// Execute the special mod!
				ExecuteSpecialMod(client, special_mod_index, true);
				
				// Charge the client for the purchase
				Shop_TakeClientCredits(client, GetSpecialModBuyPrice(), CREDITS_BY_BUY_OR_SELL);
			}
			case 1:
			{
				// Make sure the requirements status is valid
				if (!(special_mod_req == REQ_NONE || special_mod_req == REQ_NOT_ENOUGH_CREDITS))
				{
					PrintToChat(client, "%s You're no longer meeting the special mod requirements!", PREFIX_ERROR);
					return 0;
				}
				
				StartSpecialModVote(special_mod_index);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowSpecialModsMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void StartSpecialModVote(int specialModId)
{
	if (IsVoteInProgress())
	{
		return;
	}
	
	g_SpecialModBuyBlockCounter = 2;
	
	Menu menu = new Menu(Handler_SpecialModVote);
	menu.SetTitle("%s Do you want to play %s mod?", PREFIX_MENU, GetSpecialModByIndex(specialModId).mod_name);
	
	menu.AddItem("1", "Yes");
	menu.AddItem("0", "No");
	
	// Parse the special mod index
	char item_info[4];
	IntToString(specialModId, item_info, sizeof(item_info));
	menu.AddItem(item_info, "", ITEMDRAW_IGNORE);
	
	menu.ExitButton = false;
	
	// Display the vote to everyone
	menu.DisplayVoteToAll(VOTE_DISPLAY_TIME);
}

public int Handler_SpecialModVote(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_VoteEnd)
	{
		// Get the menu votes information
		int positive_votes, total_votes;
		GetMenuVoteInfo(param2, positive_votes, total_votes);
		
		// Initialize the special mod index
		char item_info[32];
		menu.GetItem(2, item_info, sizeof(item_info));
		int special_mod_index = StringToInt(item_info);
		
		menu.GetItem(param1, item_info, sizeof(item_info));
		
		if (StrEqual(item_info, "0") && param1 == 1)
		{
			positive_votes = total_votes - positive_votes; // Reverse the votes to be in relation to the Yes option.
		}
		
		int vote_percent = RoundToFloor(float(positive_votes) / float(total_votes) * 100);
		bool vote_succeed = vote_percent >= g_cvVotePercent.IntValue && StrEqual(item_info, "1");
		
		Format(item_info, sizeof(item_info), "failed. %d%% vote required", g_cvVotePercent.IntValue);
		PrintToChatAll("%s Vote %s. (Received %d%% of %d votes)", PREFIX, vote_succeed ? "successful" : item_info, vote_percent, total_votes);
		
		if (vote_succeed)
		{
			ExecuteSpecialMod(GetMainGuardIndex(), special_mod_index, false);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateSpecialMod", Native_CreateSpecialMod);
	CreateNative("JB_FindSpecialMod", Native_FindSpecialMod);
	CreateNative("JB_GetCurrentSpecialMod", Native_GetCurrentSpecialMod);
	CreateNative("JB_AbortSpecialMod", Native_AbortSpecialMod);
	
	g_fwdOnSpecialModExecute = new GlobalForward("JB_OnSpecialModExecute", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnSpecialModEnd = new GlobalForward("JB_OnSpecialModEnd", ET_Event, Param_Cell);
	
	RegPluginLibrary("JB_SpecialMods");
	return APLRes_Success;
}

int Native_CreateSpecialMod(Handle plugin, int numParams)
{
	SpecialMod SpecialModData;
	GetNativeString(1, SpecialModData.mod_name, sizeof(SpecialModData.mod_name));
	
	int special_mod_index = GetSpecialModByName(SpecialModData.mod_name);
	if (special_mod_index != -1)
	{
		return special_mod_index;
	}
	
	GetNativeString(2, SpecialModData.mod_desc, sizeof(SpecialModData.mod_desc));
	
	return g_SpecialModsData.PushArray(SpecialModData);
}

int Native_FindSpecialMod(Handle plugin, int numParams)
{
	char mod_name[64];
	GetNativeString(1, mod_name, sizeof(mod_name));
	return GetSpecialModByName(mod_name);
}

int Native_GetCurrentSpecialMod(Handle plugin, int numParams)
{
	return g_CurrentSpecialMod;
}

int Native_AbortSpecialMod(Handle plugin, int numParams)
{
	return StopSpecialMod(GetNativeCell(1));
}

//================================[ Functions ]================================//

int GetSpecialModByName(const char[] name)
{
	return g_SpecialModsData.FindString(name);
}

any[] GetSpecialModByIndex(int index)
{
	SpecialMod SpecialModData;
	g_SpecialModsData.GetArray(index, SpecialModData);
	return SpecialModData;
}

// Returns the special mod purchase price by the online prisoners count, and the price per prisoner convar
int GetSpecialModBuyPrice()
{
	return GetOnlineTeamCount(CS_TEAM_T, false) * g_cvPricePerPrisoner.IntValue;
}

void ExecuteSpecialMod(int executer, int special_mod_index, bool bought)
{
	// Initialize the special mod struct data
	SpecialMod SpecialModData; SpecialModData = GetSpecialModByIndex(special_mod_index);
	
	// Notify the server about the execute
	if (bought)
	{
		ShowPanel(PANEL_DISPLAY_TIME, "<font class='fontSize-xl'>Main Guard <font color='#235CB8'>%N</font> has bought the special mod %s!</font>", executer, SpecialModData.mod_name);
		PrintToChatAll("%s Main Guard \x0C%N\x01 has bought the special mod \x03%s\x01!", PREFIX, executer, SpecialModData.mod_name);
	}
	else
	{
		ShowPanel(PANEL_DISPLAY_TIME, "<font class='fontSize-xl'>The majority said his, <font color='#235CB8'>%s</font> mod is activated! </font>", SpecialModData.mod_name);
		PrintToChatAll("%s The majority said his, \x0C%s\x01 mod is activated!", PREFIX, SpecialModData.mod_name);
	}
	
	//==== [ Execute the special mod execute forward ] =====//
	Call_StartForward(g_fwdOnSpecialModExecute);
	Call_PushCell(executer);
	Call_PushCell(special_mod_index);
	Call_PushCell(bought);
	Call_Finish();
	
	// Set the global variable as the specified special mod index
	g_CurrentSpecialMod = special_mod_index;
	
	g_SpecialModBuyBlockCounter = 1;
	
	// Restart the game
	ServerCommand("mp_restartgame 3");
}

bool StopSpecialMod(bool execute_forward = true)
{
	// Check if a special mod is running
	if (g_CurrentSpecialMod == -1)
	{
		return false;
	}
	
	if (execute_forward)
	{
		//==== [ Execute the special mod end forward ] =====//
		Call_StartForward(g_fwdOnSpecialModEnd);
		Call_PushCell(g_CurrentSpecialMod);
		Call_Finish();
	}
	
	// Set the current special mod value as invalid
	g_CurrentSpecialMod = -1;
	
	return true;
}

SpecialModRequirements GetRequirementsStatus(int client)
{
	// Check the online prisoners
	if (GetOnlineTeamCount(CS_TEAM_T, false) < g_cvRequiredOnlinePrisoners.IntValue)
	{
		return REQ_NOT_ENOUGH_PRISONERS;
	}
	
	// Check the round start time
	if ((((GetTime() - g_RoundStartUnixstamp) > g_cvSecondsUntilLock.IntValue) && (GetTeamScore(CS_TEAM_CT) + GetTeamScore(CS_TEAM_T)) == 0 && !JB_IsInvitePeriodRunning()) || (JB_GetDay() >= Day_Tuesday))
	{
		return REQ_TOO_LATE;
	}
	
	// Check the cooldown state
	if (g_SpecialModBuyBlockCounter != 0)
	{
		return REQ_COOLDOWN;
	}
	
	// Initialize the special mod price
	int buy_price = GetSpecialModBuyPrice();
	
	// Check the client shop credits
	if (Shop_GetClientCredits(client) < buy_price)
	{
		return REQ_NOT_ENOUGH_CREDITS;
	}
	
	return REQ_NONE;
}

void ShowPanel(int display_time, const char[] message, any...)
{
	char formatted_message[128];
	VFormat(formatted_message, sizeof(formatted_message), message, 3);
	
	Event event = CreateEvent("show_survival_respawn_status");
	
	if (event != INVALID_HANDLE)
	{
		event.SetString("loc_token", formatted_message);
		event.SetInt("duration", display_time);
		event.SetInt("userid", -1);
		event.Fire();
	}
}

//================================================================//