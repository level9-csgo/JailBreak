#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <shop>
#include <shop_wish>
#include <shop_premium>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG & IlayBro"

//==========[ Settings ]==========//

#define DAY_CONVERTED_SECONDS 86400
#define HOUR_CONVERTED_SECONDS 3600

#define OVERLAY_TEXTURES_DIR "playil_jailbreak/wish/"

#define WISH_ROLL_SOUND "playil_jailbreak/wish/roll.mp3"
#define WISH_SHOT_SOUND "playil_jailbreak/wish/shot.mp3"
#define REWISH_ATTETION_SOUND "playil_jailbreak/wish/rewish.mp3"

#define REWISH_SCHEDULE_TIME 0800 // Means 08:00 in the morning

#define SECONDS_IN_DAY 86400

#define HIDEHUD_CROSSHAIR (1 << 8)

//====================//

enum struct Client
{
	int account_id;
	int wishes_amount;
	int roll_times;
	int full_cycle;
	int generated_award;
	
	Handle WishAnimationTimer;
	
	void Reset()
	{
		this.account_id = 0;
		this.wishes_amount = 0;
		this.roll_times = 0;
		this.full_cycle = 0;
		this.generated_award = 0;
		
		this.DeleteTimer();
	}
	
	void DeleteTimer(bool award = false)
	{
		if (this.WishAnimationTimer != INVALID_HANDLE)
		{
			KillTimer(this.WishAnimationTimer);
			this.WishAnimationTimer = INVALID_HANDLE;
			
			if (award)
			{
				this.wishes_amount++;
			}
		}
	}
	
	bool IsWishRolling()
	{
		return (this.WishAnimationTimer != INVALID_HANDLE);
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

Database g_Database = null;

GlobalForward g_fwdOnRewishExecuted;
GlobalForward g_fwdOnWishAnimationStart;
GlobalForward g_fwdOnWishAnimationEnd;

int m_iHideHUDOffset;

// Stores the steam account id of authorized clients for commands
int g_AuthorizedClients[] = 
{
	912414245,  // KoNLiG 
	420568778,  // Hispter
	105469958, // Actually Hacking
	100689172, // Toster
	457166215 // Daniel;
};

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Wish", 
	author = PLUGIN_AUTHOR, 
	description = "An additional wish Add-On to the shop system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	if ((m_iHideHUDOffset = FindSendPropInfo("CBasePlayer", "m_iHideHUD")) <= 0)
	{
		SetFailState("Failed to find offset CBasePlayer::m_iHideHUD");
	}
	
	// Create the connection to the database
	Database.Connect(SQL_OnDatabaseConnected_CB, DATABASE_ENTRY);
	
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	CreateTimer(float(CalculateRewishDuration()), Timer_Rewish);
	
	// Admin Commands
	RegAdminCmd("sm_rewish", Command_Rewish, ADMFLAG_ROOT, "Awards a certain group of clients in a wish.");
	
	// Client Commands
	RegConsoleCmd("sm_wish", Command_Wish, "Allows client to claim a wish.");
	
	// Event Hooks
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void OnPluginEnd()
{
	// Loop throgh all the online clients, make sure to send their data to the database
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientDisconnect(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
	
	if (!IsFakeClient(client))
	{
		// If we couldn't get the client steam account id, we won't be able to fetch the client from the database
		if (!(g_ClientsData[client].account_id = GetSteamAccountID(client)))
		{
			KickClient(client, "Verification error, please reconnect.");
			return;
		}
		
		// Get the client data from the database
		SQL_FetchClient(client);
	}
}

public void OnClientDisconnect(int client)
{
	// FIX: Set the timers handle back to invalid to avoid connection error
	g_ClientsData[client].DeleteTimer(true);
	
	// If the client is not fake, send the client data to the database
	if (!IsFakeClient(client))
	{
		SQL_UpdateClient(client);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (g_ClientsData[client].wishes_amount)
	{
		PrintToChat(client, "%s You've got a \x0Bwish\x01 to spend! Claim it by typing \x04/wish\x01!", PREFIX);
	}
}

//================================[ Commands ]================================//

Action Command_Rewish(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Block the command access if the client isn't allowed
	if (!IsClientAllowed(client))
	{
		PrintToChat(client, "%s You do not have access to this command.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (args != 1)
	{
		PrintToChat(client, "%s Usage: \x04/rewish\x01 <#userid|name>", PREFIX);
		return Plugin_Handled;
	}
	
	// Get the client index by the specified name/user id
	char arg_name[MAX_NAME_LENGTH];
	GetCmdArg(1, arg_name, sizeof(arg_name));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(arg_name, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int current_target = 0; current_target < target_count; current_target++)
	{
		if (IsClientInGame(target_list[current_target]))
		{
			Call_OnRewishExecuted(target_list[current_target], client, false);
			
			GiveClientWish(target_list[current_target]);
			EmitSoundToClient(target_list[current_target], REWISH_ATTETION_SOUND, .volume = 0.3);
			
			// Notify the client
			PrintToChat(target_list[current_target], "%s Admin \x04%N\x01 has awarded you in a \x10rewish\x01!", PREFIX, client);
		}
	}
	
	// Notify the admin
	PrintToChat(client, "%s You've awarded \x04%s\x01 in a \x10rewish\x01!", PREFIX, target_name);
	
	// Write a log line
	WriteLogLine("Admin \"%L\" has awarded %s in a rewish.", client, target_name);
	
	return Plugin_Handled;
}

Action Command_Wish(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure the client isn't rolling a wish
	if (g_ClientsData[client].IsWishRolling())
	{
		PrintToChat(client, "%s You're already rolling a wish, please wait!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Make sure the client has wishes to spend
	if (!g_ClientsData[client].wishes_amount)
	{
		PrintToChat(client, "%s Your wish isn't ready yet! next wish in \x10%.2f hours\x01.", PREFIX_ERROR, float(CalculateRewishDuration()) / 3600.0);
		return Plugin_Handled;
	}
	
	// Execute the wish animation
	ExecuteWishAnimation(client);
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowRunesInventoryMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_RunesInventory);
	menu.SetTitle("%s Wish System - Choose A Rune To Upgrade\n ", PREFIX_MENU);
	
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
		JB_PerformRuneLevelUpgrade(client, client_rune_index, 100);
	}
	else if (action == MenuAction_Cancel)
	{
		int client = param1;
		
		if (!IsClientInGame(client))
		{
			return 0;
		}
		
		RequestFrame(RF_DisplayMenu, GetClientSerial(client));
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
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

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shop_GetClientWishes", Native_GetClientWishes);
	CreateNative("Shop_GiveClientWish", Native_GiveClientWish);
	CreateNative("Shop_RemoveClientWish", Native_RemoveClientWish);
	
	g_fwdOnRewishExecuted = new GlobalForward("Shop_OnRewishExecuted", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnWishAnimationStart = new GlobalForward("Shop_OnWishAnimationStart", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnWishAnimationEnd = new GlobalForward("Shop_OnWishAnimationEnd", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	
	RegPluginLibrary("shop_wish");
	return APLRes_Success;
}

void Call_OnRewishExecuted(int client, int giver, bool natural)
{
	Call_StartForward(g_fwdOnRewishExecuted);
	Call_PushCell(client);
	Call_PushCell(giver);
	Call_PushCell(natural);
	Call_Finish();
}

int Native_GetClientWishes(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].wishes_amount;
}

int Native_GiveClientWish(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the amount of wishes to give
	int wishes_amount = GetNativeCell(2);
	
	if (wishes_amount <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified wishes amount, Must be over 0! (Got: %d)", wishes_amount);
	}
	
	GiveClientWish(client, wishes_amount);
	
	return true;
}

int Native_RemoveClientWish(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the amount of days to give
	int wishes_amount = GetNativeCell(2);
	
	if (wishes_amount <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified wishes amount, Must be over 0! (Got: %d)", wishes_amount);
	}
	
	RemoveClientWish(client, wishes_amount);
	
	return true;
}

//================================[ Database ]================================//

void SQL_OnDatabaseConnected_CB(Database db, const char[] error, any data)
{
	if (db == null)
	{
		SetFailState("Unable to maintain connection to MySQL Server! | (%s)", error);
	}
	
	g_Database = db;
	
	// Create the shop wish sql table
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_wish_data`(`account_id` INT NOT NULL, `wishes_amount` INT NOT NULL, UNIQUE(`account_id`))");
	
	// Loop through all the online clients once the database has made the connection, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

void SQL_FetchClient(int client)
{
	char query[128];
	g_Database.Format(query, sizeof(query), "SELECT * FROM `jb_wish_data` WHERE `account_id` = %d", g_ClientsData[client].account_id);
	g_Database.Query(SQL_FetchClient_CB, query, GetClientSerial(client));
}

void SQL_FetchClient_CB(Database db, DBResultSet results, const char[] error, int serial)
{
	// If the string is not empty, an error has occurred
	if (error[0])
	{
		LogError("Client fetch Databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index isn't invalid
	if (!client)
	{
		return;
	}
	
	if (results.FetchRow())
	{
		g_ClientsData[client].wishes_amount = results.FetchInt(1);
	}
	else
	{
		char query[256];
		
		g_Database.Format(query, sizeof(query), "INSERT INTO `jb_wish_data` (`account_id`, `wishes_amount`) VALUES (%d, %d)", 
			g_ClientsData[client].account_id, 
			g_ClientsData[client].wishes_amount
			);
		
		g_Database.Query(SQL_CheckForErrors, query);
	}
}

void SQL_UpdateClient(int client)
{
	char query[128];
	g_Database.Format(query, sizeof(query), "UPDATE `jb_wish_data` SET `wishes_amount` = %d WHERE `account_id` = %d", g_ClientsData[client].wishes_amount, g_ClientsData[client].account_id);
	g_Database.Query(SQL_CheckForErrors, query);
}

public void SQL_OnPremiumsFetch_CB(Database db, DBResultSet results, const char[] error, int serial)
{
	// If the string is not empty, an error has occurred
	if (error[0])
	{
		LogError("Client fetch Databse error, %s", error);
		return;
	}
	
	char Query[128];
	
	int wishes_amount;
	
	while (results.FetchRow())
	{
		wishes_amount = (1 + (results.FetchInt(1) > GetTime() ? PREMIUM_WISHES_BONUS : 0));
		g_Database.Format(Query, sizeof(Query), "UPDATE `jb_wish_data` SET `wishes_amount` = %d WHERE `account_id` = %d AND `wishes_amount` < %d", wishes_amount, results.FetchInt(0), wishes_amount);
		g_Database.Query(SQL_CheckForErrors, Query);
	}
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	// If the string is not empty, an error has occurred
	if (error[0])
	{
		LogError("General databse error, (%s)", error);
		return;
	}
}

//================================[ Timers ]================================//

Action Timer_WishAnimation(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want from the serial
	if (!client)
	{
		return Plugin_Stop;
	}
	
	if (g_ClientsData[client].roll_times == ((g_ClientsData[client].generated_award - 1) + (g_ClientsData[client].full_cycle * 12)))
	{
		ClientCommand(client, "r_screenoverlay \"%s%d_hit\"", OVERLAY_TEXTURES_DIR, g_ClientsData[client].generated_award);
		
		CreateTimer(3.0, Timer_ClearOverlay, GetClientSerial(client));
		
		EmitSoundToClient(client, WISH_SHOT_SOUND);
		
		//==== [ Execute the wish animation end forward ] =====//
		Call_StartForward(g_fwdOnWishAnimationEnd);
		Call_PushCell(client);
		Call_PushCell(g_ClientsData[client].wishes_amount);
		Call_PushCell(g_ClientsData[client].generated_award);
		Call_Finish();
		
		GiveWishAward(client, g_ClientsData[client].generated_award);
		
		g_ClientsData[client].WishAnimationTimer = INVALID_HANDLE;
		
		// Stop the timer
		return Plugin_Stop;
	}
	
	g_ClientsData[client].roll_times++;
	
	ClientCommand(client, "r_screenoverlay \"%s%d\"", OVERLAY_TEXTURES_DIR, g_ClientsData[client].roll_times % 12);
	
	EmitSoundToClient(client, WISH_ROLL_SOUND);
	
	if (g_ClientsData[client].roll_times && g_ClientsData[client].roll_times % 7 == 0)
	{
		g_ClientsData[client].WishAnimationTimer = CreateTimer(0.25 + ((g_ClientsData[client].roll_times / 7) * 0.05), Timer_WishAnimation, GetClientSerial(client), TIMER_REPEAT);
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

Action Timer_Rewish(Handle timer)
{
	// Award the online clients
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			if (g_ClientsData[current_client].wishes_amount == 0)
			{
				Call_OnRewishExecuted(current_client, 0, false);
				
				GiveClientWish(current_client);
			}
			
			if (g_ClientsData[current_client].wishes_amount == 1 && Shop_IsClientPremium(current_client))
			{
				Call_OnRewishExecuted(current_client, 0, false);
				
				GiveClientWish(current_client);
			}
		}
	}
	
	// Play the rewish sound effect
	EmitSoundToAll(REWISH_ATTETION_SOUND, .volume = 0.3);
	
	// Notify the online clients
	char current_time[8];
	FormatTime(current_time, sizeof(current_time), "%H:%M");
	PrintToChatAll("%s The time is \x04%s\x01, all of the server has been awarded in a rewish!", PREFIX, current_time);
	
	char Query[128];
	g_Database.Format(Query, sizeof(Query), "SELECT `account_id`, `expire_unixstamp` FROM `%s`", GetPremiumTableName());
	g_Database.Query(SQL_OnPremiumsFetch_CB, Query);
	
	// Recreate the rewish timer 24 hours from now
	CreateTimer(float(SECONDS_IN_DAY), Timer_Rewish);
	
	return Plugin_Continue;
}

Action Timer_ClearOverlay(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want from the serial
	if (!client || g_ClientsData[client].IsWishRolling())
	{
		return Plugin_Continue;
	}
	
	ClientCommand(client, "r_screenoverlay \"\"");
	TogglePlayerCrosshair(client, false);
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void GiveClientWish(int client, int amount = 1)
{
	g_ClientsData[client].wishes_amount += amount;
}

void RemoveClientWish(int client, int amount = 1)
{
	if ((g_ClientsData[client].wishes_amount -= amount) < 0)
	{
		g_ClientsData[client].wishes_amount = 0;
	}
}

void ExecuteWishAnimation(int client)
{
	g_ClientsData[client].generated_award = GenerateWishAward();
	
	//==== [ Execute the wish animation start forward ] =====//
	Call_StartForward(g_fwdOnWishAnimationStart);
	Call_PushCell(client);
	Call_PushCell(g_ClientsData[client].wishes_amount - 1);
	Call_PushCell(g_ClientsData[client].generated_award);
	
	Action result;
	Call_Finish(result);
	
	if (result >= Plugin_Handled)
	{
		g_ClientsData[client].generated_award = 0;
		return;
	}
	
	g_ClientsData[client].roll_times = -1;
	g_ClientsData[client].full_cycle = GetRandomInt(2, 3);
	g_ClientsData[client].wishes_amount--;
	
	g_ClientsData[client].WishAnimationTimer = CreateTimer(0.25, Timer_WishAnimation, GetClientSerial(client), TIMER_REPEAT);
	
	TogglePlayerCrosshair(client, true);
}

void GiveWishAward(int client, int index)
{
	int wish_award;
	
	char formatted_wish_context[32], award_color[4] = "\x03"; formatted_wish_context = GetFormattedWishAward(index, wish_award);
	
	// Award the client with premium days
	if (StrContains(formatted_wish_context, "Premium", false) != -1)
	{
		Shop_GivePremium(client, wish_award);
	}
	
	// Award the client with credits
	else if (StrContains(formatted_wish_context, "Credits", false) != -1)
	{
		Shop_GiveClientCredits(client, wish_award, CREDITS_BY_LUCK);
	}
	
	// Award the client with more wishes
	else if (StrContains(formatted_wish_context, "Wish", false) != -1)
	{
		GiveClientWish(client, wish_award);
	}
	
	// Award the client with guaranteed rune level upgrade
	else if (StrContains(formatted_wish_context, "Rune Upgrade", false) != -1)
	{
		award_color = "\x0B";
		
		ShowRunesInventoryMenu(client);
	}
	
	// Award the client with randomized star rune
	else if (StrContains(formatted_wish_context, "Rune", false) != -1)
	{
		if (wish_award >= RuneStar_6)
		{
			award_color = "\x0B";
		}
		
		if (!JB_AddClientRune(client, -1, wish_award, 1))
		{
			GiveClientWish(client);
			
			PrintToChat(client, "%s You have got a \x02%d%s\x01 rune, but sadly your runes capacity is maxed out. Therefore, you have awarded in an extra wish to spend!", PREFIX, wish_award, RUNE_STAR_SYMBOL);
			
			return;
		}
	}
	
	PrintToChatAll(" \x04%N\x01 made a wish and won %s%s\x01!", client, award_color, formatted_wish_context);
}

int GenerateWishAward()
{
	float random_winner = GetRandomFloat(0.0, 100.0);
	
	for (int current_wish_award = 0; current_wish_award < sizeof(g_WishAwards); current_wish_award++)
	{
		random_winner -= Shop_GetWishAwardPercent(current_wish_award);
		if (random_winner <= 0.0)
		{
			return current_wish_award;
		}
	}
	
	return -1;
}

int CalculateRewishDuration()
{
	char current_time_str[8];
	FormatTime(current_time_str, sizeof(current_time_str), "%H%M");
	
	int current_time = StringToInt(current_time_str);
	
	int current_time_hours = current_time / 100;
	int current_time_minutes = current_time % 100;
	
	int target_time_hours = REWISH_SCHEDULE_TIME / 100;
	int target_time_minutes = REWISH_SCHEDULE_TIME % 100;
	
	int hours_dif = Math_Max(current_time_hours, target_time_hours) - Math_Min(current_time_hours, target_time_hours);
	int minutes_dif = Math_Max(current_time_minutes, target_time_minutes) - Math_Min(current_time_minutes, target_time_minutes);
	
	if (current_time_hours >= target_time_hours)
	{
		hours_dif = 24 - hours_dif;
	}
	
	if ((minutes_dif = 60 - minutes_dif))
	{
		hours_dif--;
	}
	
	return hours_dif * 60 * 60 + minutes_dif * 60;
}

any Math_Min(any value, any minv)
{
	return value < minv ? value : minv;
}

any Math_Max(any value, any maxv)
{
	return value > maxv ? value : maxv;
}

char[] GetPremiumTableName()
{
	char table_name[32];
	Shop_GetDatabasePrefix(table_name, sizeof(table_name));
	
	Format(table_name, sizeof(table_name), "%spremium_data", table_name);
	return table_name;
}

/**
 * Return true if the client's steam account id matched one of specified authorized clients.
 * See g_szAuthorizedClients
 * 
 */
bool IsClientAllowed(int client)
{
	for (int current_accout_id = 0; current_accout_id < sizeof(g_AuthorizedClients); current_accout_id++)
	{
		// Check for a match
		if (g_ClientsData[client].account_id == g_AuthorizedClients[current_accout_id]) {
			return true;
		}
	}
	
	// Match has failed
	return false;
}

void TogglePlayerCrosshair(int client, bool state)
{
	if (IsPlayerCrosshairHidden(client) == state)
	{
		return;
	}
	
	if (state)
	{
		SetEntData(client, m_iHideHUDOffset, GetEntData(client, m_iHideHUDOffset) | HIDEHUD_CROSSHAIR);
	}
	else
	{
		SetEntData(client, m_iHideHUDOffset, GetEntData(client, m_iHideHUDOffset) ^ HIDEHUD_CROSSHAIR);
	}
}

// Retrieves whether a client crosshair is hidden.
bool IsPlayerCrosshairHidden(int client)
{
	return (GetEntData(client, m_iHideHUDOffset) & HIDEHUD_CROSSHAIR) != 0;
}

//================================================================//