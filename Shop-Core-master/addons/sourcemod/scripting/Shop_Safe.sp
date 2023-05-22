#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <shop>
#include <shop_safe>

#undef REQUIRE_PLUGIN
#include <JB_RunesSystem>
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

//==========[ Settings ]==========//

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_MENU "[Level9]"
#define PREFIX_ERROR " \x02[Error]\x01"

#define CONFIG_PATH "addons/sourcemod/configs/SafeBoxData.cfg"

#define SAFE_CORRENT_SOUND "playil_shop/safe/correct.mp3"
#define SAFE_FAILURE_SOUND "playil_shop/safe/failure.mp3"

#define ABORT_SYMBOL "-1"

// Runes Stuff
#define RUNES_LIBRARY_NAME "JB_RunesSystem"
#define RUNES_AWARD_STAR RuneStar_6

//====================//

ArrayList g_FailuresData;

enum struct Failure
{
	int combination;
	char failler_name[MAX_NAME_LENGTH];
	
	int Add(int combination, int client)
	{
		this.combination = combination;
		GetClientName(client, this.failler_name, sizeof(Failure::failler_name));
		return g_FailuresData.PushArray(this);
	}
}

SafeBox g_SafeBoxData;

GlobalForward g_ClientSafeGuess;
GlobalForward g_ClientSafeGuessPost;

ConVar g_StartCombinationCodeRange;
ConVar g_EndCombinationCodeRange;
ConVar g_StartingSafeAward;
ConVar g_CombinationGuessPrice;
ConVar g_FailuresForClue;

bool g_IsRunesLoaded;

bool g_IsClientGuessing[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Safe Box", 
	author = PLUGIN_AUTHOR, 
	description = "An additional safe box Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the failures arraylist
	g_FailuresData = new ArrayList(sizeof(Failure));
	
	// ConVars Configurate
	g_StartCombinationCodeRange = CreateConVar("shop_safe_start_combination_code_range", "1000", "The lowest possible number of the combination code.", _, true, 1000.0, true, 5000.0);
	g_EndCombinationCodeRange = CreateConVar("shop_safe_end_combination_code_range", "9999", "The highest possible number of the combination code.", _, true, 1500.0, true, 9999.0);
	g_StartingSafeAward = CreateConVar("shop_safe_starting_award", "500000", "The starting safe credits award, once a player has cracked the safe box combination, or the plugin has just loaded for the first time.", _, true, 500.0, true, 10000000.0);
	g_CombinationGuessPrice = CreateConVar("shop_safe_combination_guess_price", "1500", "The price for a player to guess the safe box combination code.", _, true, 100.0, true, 10000.0);
	g_FailuresForClue = CreateConVar("shop_safe_failures_for_clue", "500", "Crack failures for one combination number to be revealed.", _, true, 350.0, true, 750.0);
	
	AutoExecConfig(true, "ShopSafe", "shop");
	
	// Client Commands
	RegConsoleCmd("sm_safe", Command_Safe, "Access the safe box main menu.");
	
	// Config Creation
	char file_path[PLATFORM_MAX_PATH];
	strcopy(file_path, sizeof(file_path), CONFIG_PATH);
	BuildPath(Path_SM, file_path, sizeof(file_path), file_path[17]);
	delete OpenFile(file_path, "a+");
	
	// Load the safe box data from the configuration file
	KV_LoadSafeData();
}

public void OnPluginEnd()
{
	KV_SetSafeData();
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, RUNES_LIBRARY_NAME))
	{
		g_IsRunesLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, RUNES_LIBRARY_NAME))
	{
		g_IsRunesLoaded = false;
	}
}

public void OnMapStart()
{
	// Set the safe box data
	KV_SetSafeData();
	
	AddFileToDownloadsTable("sound/"...SAFE_CORRENT_SOUND);
	AddFileToDownloadsTable("sound/"...SAFE_FAILURE_SOUND);
	
	PrecacheSound(SAFE_CORRENT_SOUND);
	PrecacheSound(SAFE_FAILURE_SOUND);
}

public void OnClientPostAdminCheck(int client)
{
	g_IsClientGuessing[client] = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// If the client isn't guessing a combination at all, don't continue
	if (!g_IsClientGuessing[client])
	{
		return Plugin_Continue;
	}
	
	// Make sure the client has enough shop credits for the combination guess
	if (Shop_GetClientCredits(client) < g_CombinationGuessPrice.IntValue)
	{
		PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", AddCommas(g_CombinationGuessPrice.IntValue - Shop_GetClientCredits(client)));
		ShowSafeBoxMenu(client);
		
		g_IsClientGuessing[client] = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	if (StrEqual(sArgs, ABORT_SYMBOL))
	{
		PrintToChat(client, "%s Operation aborted.", PREFIX);
		ShowSafeBoxMenu(client);
		
		g_IsClientGuessing[client] = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	// Get and verify the typed combination code
	int combination_code = StringToInt(sArgs);
	
	if (!(g_StartCombinationCodeRange.IntValue <= combination_code <= g_EndCombinationCodeRange.IntValue))
	{
		PrintToChat(client, "%s Combination code range is %d ~ %d!", PREFIX_ERROR, g_StartCombinationCodeRange.IntValue, g_EndCombinationCodeRange.IntValue);
		
		// Block the message send
		return Plugin_Handled;
	}
	
	bool is_succeeded = combination_code == g_SafeBoxData.code;
	
	if (Call_ClientSafeGuess(client, combination_code, is_succeeded) > Plugin_Continue)
	{
		// If the forward return is higher then Plugin_Continue, stop the further actions
		return Plugin_Handled;
	}
	
	// Take the client's credits from the guess cost
	Shop_TakeClientCredits(client, g_CombinationGuessPrice.IntValue, CREDITS_BY_BUY_OR_SELL);
	
	if (is_succeeded)
	{
		char award[32];
		
		if (g_IsRunesLoaded)
		{
			int randomized_rune_index = GetRandomInt(0, JB_GetRunesAmount() - 1);
			
			// Award the winner with a randomized 6 star rune, and if he's not have enough capacity space, award him with credits.
			if (!JB_AddClientRune(client, randomized_rune_index, RUNES_AWARD_STAR, 1))
			{
				Format(award, sizeof(award), "%s Credits", AddCommas(g_SafeBoxData.credits));
				
				// Award the client
				Shop_GiveClientCredits(client, g_SafeBoxData.credits, CREDITS_BY_LUCK);
			}
			else
			{
				Rune RuneData;
				JB_GetRuneData(randomized_rune_index, RuneData);
				
				Format(award, sizeof(award), "%s | %d%s", RuneData.szRuneName, RUNES_AWARD_STAR, RUNE_STAR_SYMBOL);
			}
		}
		else
		{
			Format(award, sizeof(award), "%s Credits", AddCommas(g_SafeBoxData.credits));
			
			// Award the client
			Shop_GiveClientCredits(client, g_SafeBoxData.credits, CREDITS_BY_LUCK);
		}
		
		SetHudTextParams(-1.0, 0.2, 10.0, GetRandomInt(1, 255), GetRandomInt(1, 255), GetRandomInt(1, 255), 1);
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				ShowHudText(current_client, -1, "%N has cracked the safe combination with the code %d!\nHe got awarded with %s", client, combination_code, award);
			}
		}
		
		PrintToChat(client, "%s Congratulations! You've opened the safe box and got awarded with \x10%s\x01!", PREFIX, award);
		
		// Reset the safe box data
		g_SafeBoxData.code = GenerateCombinationCode();
		g_SafeBoxData.credits = g_StartingSafeAward.IntValue;
		g_SafeBoxData.failures = 0;
		GetClientName(client, g_SafeBoxData.last_winner_name, sizeof(g_SafeBoxData.last_winner_name));
		
		// Write a log line
		WriteLogLine("\"%L\" has opened the safe box with the code %d! (Award: %s)", client, combination_code, award);
		
		// Play the corrent sound
		EmitSoundToAll(SAFE_CORRENT_SOUND, .volume = 0.2);
	}
	else
	{
		// Add the current failure to the recent failures list
		Failure FailureData;
		FailureData.Add(combination_code, client);
		
		g_SafeBoxData.failures++;
		g_SafeBoxData.credits += g_CombinationGuessPrice.IntValue;
		
		ShowSafeBoxMenu(client);
		
		// Notify the client about the failure
		PrintToChat(client, "%s You've tried to crack the safe with the combination \x03%d\x01 and \x07failed\x01!", PREFIX, combination_code);
		
		// Write a log line
		WriteLogLine("\"%L\" has failed to open the safe box with the code %d.", client, combination_code);
		
		// Play the corrent sound
		EmitSoundToClient(client, SAFE_FAILURE_SOUND, .volume = 0.2);
	}
	
	Call_ClientSafeGuessPost(client, combination_code, is_succeeded);
	
	g_IsClientGuessing[client] = false;
	
	// Block the message send
	return Plugin_Handled;
}

//================================[ API ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegisterNatives();
	RegisterForwards();
	
	// Register the plugin as a library
	RegPluginLibrary("shop_safe");
	
	return APLRes_Success;
}

// Natives
void RegisterNatives()
{
	CreateNative("Shop_GetSafeBoxData", Native_GetSafeBoxData);
}

any Native_GetSafeBoxData(Handle plugin, int numParams)
{
	// Store the safe box data inside the given buffer
	SetNativeArray(1, g_SafeBoxData, sizeof(g_SafeBoxData));
	
	return 0;
}

// Forwards
void RegisterForwards()
{
	g_ClientSafeGuess = new GlobalForward("Shop_OnClientSafeGuess", ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef);
	g_ClientSafeGuessPost = new GlobalForward("Shop_OnClientSafeGuessPost", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

Action Call_ClientSafeGuess(int client, int &code, bool &succeed)
{
	//==== [ Execute the client safe guess forward ] =====//
	Call_StartForward(g_ClientSafeGuess);
	Call_PushCell(client); // int client
	Call_PushCellRef(code); // int &code
	Call_PushCellRef(succeed); // int &succeed
	
	Action fwd_return;
	
	int error = Call_Finish(fwd_return);
	
	// Check for a forward failure
	if (error != SP_ERROR_NONE)
	{
		ThrowNativeError(error, "Client safe guess forward failed - Error: %d", error);
		return Plugin_Handled;
	}
	
	return fwd_return;
}

void Call_ClientSafeGuessPost(int client, int code, bool succeed)
{
	//==== [ Execute the client safe guess post forward ] =====//
	Call_StartForward(g_ClientSafeGuessPost);
	Call_PushCell(client); // int client
	Call_PushCell(code); // int code
	Call_PushCell(succeed); // int succeed
	
	int error = Call_Finish();
	
	// Check for a forward failure
	if (error != SP_ERROR_NONE)
	{
		ThrowNativeError(error, "Client safe guess post forward failed - Error: %d", error);
	}
}

//================================[ Commands ]================================//

Action Command_Safe(int client, int args)
{
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char arg_name[MAX_NAME_LENGTH];
		GetCmdArgString(arg_name, sizeof(arg_name));
		int target_index = FindTarget(client, arg_name, true, false);
		
		if (target_index == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		ShowSafeBoxMenu(target_index);
	}
	else
	{
		ShowSafeBoxMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowSafeBoxMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_SafeBox);
	
	if (g_IsRunesLoaded)
	{
		Format(item_display, sizeof(item_display), "Random %d%sRune", RUNES_AWARD_STAR, RUNE_STAR_SYMBOL);
	}
	else
	{
		Format(item_display, sizeof(item_display), "%s Credits", AddCommas(g_SafeBoxData.credits));
	}
	
	menu.SetTitle("%s Shop System - Safe Box \n• Crack the combination to get the award inside the box!\n \n◾ Award: %s\n◾ Combination Clue: %s\n◾ Combinations Failures: %s\n◾ Last Winner: %s\n\n ", PREFIX_MENU, item_display, GetCombinationClue(), AddCommas(g_SafeBoxData.failures), g_SafeBoxData.last_winner_name);
	
	Format(item_display, sizeof(item_display), "Guess A Combination [%s Credits]", AddCommas(g_CombinationGuessPrice.IntValue));
	menu.AddItem("", item_display, Shop_GetClientCredits(client) >= g_CombinationGuessPrice.IntValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.AddItem("", "Recent Failures List");
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_SafeBox(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Make sure the client has enough shop credits for the combination guess
				if (Shop_GetClientCredits(client) < g_CombinationGuessPrice.IntValue)
				{
					PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", AddCommas(g_CombinationGuessPrice.IntValue - Shop_GetClientCredits(client)));
					ShowSafeBoxMenu(client);
					return 0;
				}
				
				// Set the client guess state to true
				g_IsClientGuessing[client] = true;
				
				// Notify the client
				PrintToChat(client, "%s Type a combination guess, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 1:
			{
				// Display the recent failures list menu
				ShowRecentFailuresMenu(client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowRecentFailuresMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_RecentFailures);
	menu.SetTitle("%s Safe Box - Recent Failures List\n ", PREFIX_MENU);
	
	Failure CurrentFailureData;
	
	for (int current_failure = 0; current_failure < g_FailuresData.Length; current_failure++)
	{
		// Initialize the current failure data by the current array index
		g_FailuresData.GetArray(current_failure, CurrentFailureData);
		
		FormatEx(item_display, sizeof(item_display), "%s - %d", CurrentFailureData.failler_name, CurrentFailureData.combination);
		menu.AddItem("", item_display);
	}
	
	// If no recent failure was found, add an extra notify menu item
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No recent failure was found.", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_RecentFailures(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		ShowRecentFailuresMenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Display the last menu the client was in
		ShowSafeBoxMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Key Values ]================================//

void KV_LoadSafeData()
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("SafeBox");
	kv.ImportFromFile(CONFIG_PATH);
	
	g_SafeBoxData.code = kv.GetNum("code"); // Safe combination code
	g_SafeBoxData.credits = kv.GetNum("credits"); // Safe credits award
	g_SafeBoxData.failures = kv.GetNum("failures"); // Safe crack failures
	
	kv.GetString("last_winner_name", g_SafeBoxData.last_winner_name, sizeof(g_SafeBoxData.last_winner_name)); // Last safe winner
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	
	// Dont leak handles
	kv.Close();
}

void KV_SetSafeData()
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("SafeBox");
	kv.ImportFromFile(CONFIG_PATH);
	
	kv.SetNum("code", !g_SafeBoxData.code ? GenerateCombinationCode() : g_SafeBoxData.code);
	kv.SetNum("credits", !g_SafeBoxData.credits ? g_StartingSafeAward.IntValue : g_SafeBoxData.credits);
	kv.SetNum("failures", g_SafeBoxData.failures);
	
	kv.SetString("last_winner_name", g_SafeBoxData.last_winner_name[0] == '\0' ? "None" : g_SafeBoxData.last_winner_name);
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	
	// Dont leak handles
	kv.Close();
	
	// Load the safe box data from the configuration file
	KV_LoadSafeData();
}

//================================[ Functions ]================================//

int GenerateCombinationCode()
{
	return GetRandomInt(g_StartCombinationCodeRange.IntValue, g_EndCombinationCodeRange.IntValue);
}

char[] GetCombinationClue()
{
	char combination_clue[8];
	IntToString(g_SafeBoxData.code, combination_clue, sizeof(combination_clue));
	
	for (int current_digit = 0; current_digit < (COMBINATION_DIGITS - (g_SafeBoxData.failures / g_FailuresForClue.IntValue > COMBINATION_DIGITS - 1 ? COMBINATION_DIGITS - 1 : g_SafeBoxData.failures / g_FailuresForClue.IntValue)); current_digit++)
	{
		combination_clue[current_digit] = 'X';
	}
	
	return combination_clue;
}

//================================================================//