#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <shop>
#include <shop_premium>
#include <chat-processor>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.0"

//==========[ Settings ]==========//

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_MENU "[Level9]"
#define PREFIX_ERROR " \x02[Error]\x01"

#define DAY_CONVERTED_SECONDS 86400
#define HOUR_CONVERTED_SECONDS 3600

#define MIN_AWARD_MULTIPLY 2
#define MAX_AWARD_MULTIPLY 5

#define DAILY_AWARD_TEXT_TIME 5.0

//====================//

enum struct Client
{
	int account_id;
	int expire_unixstamp;
	int daily_award_unixstamp;
	
	void Reset()
	{
		this.account_id = 0;
		this.expire_unixstamp = 0;
		this.daily_award_unixstamp = 0;
	}
	
	bool IsPremium(int client, bool notify = true)
	{
		if (!this.expire_unixstamp)
		{
			return false;
		}
		else if (this.expire_unixstamp - GetTime() < 0)
		{
			if (notify)
			{
				PrintToChat(client, "%s Your premium has just expired!", PREFIX);
			}
			
			this.expire_unixstamp = 0;
			
			return false;
		}
		
		return true;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

Database g_Database = null;

GlobalForward g_fwdOnPremiumMenuDisplay;
GlobalForward g_fwdOnPremiumMenuPress;

ConVar g_cvDailyAwardCooldown;
ConVar g_cvMinDailyAwardCredits;
ConVar g_cvMaxDailyAwardCredits;

char g_TableName[32];

// Stores the steam account id of authorized clients for commands
int g_AuthorizedClients[] = 
{
	912414245,  // KoNLiG 
	928490446,  // Ravid
	133307701 // Nur
};

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Premium", 
	author = PLUGIN_AUTHOR, 
	description = "An additional premium Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// ConVars Configurate
	g_cvDailyAwardCooldown = CreateConVar("shop_premium_daily_award_cooldown", "12", "Cooldown in hours for the premium daily award.", _, true, 8.0, true, 24.0);
	g_cvMinDailyAwardCredits = CreateConVar("shop_premium_min_daily_award_credits", "1000", "Minimum possible amount of credits to get from the premium daily award. (Not includes the multiply)", _, true, 500.0, true, 2000.0);
	g_cvMaxDailyAwardCredits = CreateConVar("shop_premium_max_daily_award_credits", "6000", "Maximum possible amount of credits to get from the premium daily award. (Not includes the multiply)", _, true, 2500.0, true, 10000.0);
	
	AutoExecConfig(true, "shop_premium", "shop");
	
	// Connect to the shop database in late load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	// Admin Commands
	RegAdminCmd("sm_givepremium", Command_GivePremium, ADMFLAG_ROOT, "Gives a certain client premium for number of days.");
	RegAdminCmd("sm_givep", Command_GivePremium, ADMFLAG_ROOT, "Gives a certain client premium for number of days. (An Alias)");
	RegAdminCmd("sm_removepremium", Command_RemovePremium, ADMFLAG_ROOT, "Removes premium froma certain client for number of days.");
	RegAdminCmd("sm_removep", Command_RemovePremium, ADMFLAG_ROOT, "Removes premium froma certain client for number of days. (An Alias)");
	
	// Client Commands
	RegConsoleCmd("sm_premium", Command_Premium, "Access the premium information menu.");
	RegConsoleCmd("sm_p", Command_Premium, "Access the premium information menu. (An Alias)");
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

public void Shop_Started()
{
	SQL_TryToConnect();
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}
	
	// If we couldn't get the client steam account id, we won't be able to fetch the client from the database
	if (!(g_ClientsData[client].account_id = GetSteamAccountID(client)))
	{
		KickClient(client, "Verification error, please reconnect.");
		return;
	}
	
	// Get the client data from the database
	SQL_FetchClient(client);
}

public void OnClientDisconnect(int client)
{
	// If the client is not fake, send the client data to the database
	if (!IsFakeClient(client))
	{
		SQL_UpdateClient(client);
	}
}

public bool Shop_OnItemDescription(int client, ShopMenu menu_action, CategoryId category_id, ItemId item_id, const char[] description, char[] buffer, int maxlength)
{
	int item_price = Shop_GetItemPrice(item_id);
	
	if (!g_ClientsData[client].IsPremium(client) || Shop_IsClientHasItem(client, item_id) || !item_price)
	{
		return false;
	}
	
	Format(buffer, maxlength, "◾ %d%% Premium Cash-Back - %s Credits!\n \n%s", PREMIUM_SHOP_DISCOUNT_PERCENT, AddCommas(item_price * PREMIUM_SHOP_DISCOUNT_PERCENT / 100), buffer);
	
	return true;
}

public Action Shop_OnItemBuy(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, ItemType type, int &price, int &sell_price, int &value, int &gold_price, int &gold_sell_price)
{
	if (!g_ClientsData[client].IsPremium(client) || !price)
	{
		return Plugin_Continue;
	}
	
	// Notify the client about the cash back
	PrintToChat(client, "%s You've been awarded \x04%s\x01 credits from the \x10Premium Cash - Back\x01!", PREFIX, AddCommas(price * PREMIUM_SHOP_DISCOUNT_PERCENT / 100));
	
	// Discount the percentage from the item price
	price -= price / PREMIUM_SHOP_DISCOUNT_PERCENT;
	
	return Plugin_Changed;
}

public Action CP_OnChatMessage(int &author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool &processcolors, bool &removecolors)
{
	if (!g_ClientsData[author].IsPremium(author, false))
	{
		return Plugin_Continue;
	}
	
	Format(name, MAX_NAME_LENGTH, "\x07[✯]\x03 %s", name);
	Format(message, MAXLENGTH_MESSAGE, "\x07%s\x01", message);
	return Plugin_Changed;
}

//================================[ Commands ]================================//

public Action Command_GivePremium(int client, int args)
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
	
	// Display the command usage if there is no args specified
	if (args != 2)
	{
		PrintToChat(client, "%s Usage:\x04 /givepremium\x01 <name|#userid> <days>", PREFIX);
		return Plugin_Handled;
	}
	
	char arg1[MAX_NAME_LENGTH];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	// Initialize the specified target index and make sure it's valid
	int target_index = FindTarget(client, arg1, true);
	
	if (target_index == -1)
	{
		// Automatic message
		return Plugin_Handled;
	}
	
	char arg2[16];
	GetCmdArg(2, arg2, sizeof(arg2));
	
	// Initialize the specified premium days amount to give, and make sure it's valid
	int days_amount = StringToInt(arg2);
	
	if (days_amount <= 0)
	{
		PrintToChat(client, "%s Invalid specified premium days to give, must be over \x040\x01! (\x02%s\x01)", PREFIX_ERROR, arg2);
		return Plugin_Handled;
	}
	
	bool IsClientPremium = g_ClientsData[client].IsPremium(client);
	
	// Notify the clients
	PrintToChat(client, "%s Successfully gave \x04%N\x01 premium for \x0E%d\x01%s days!", PREFIX, target_index, days_amount, IsClientPremium ? " more" : "");
	PrintToChat(target_index, "%s Admin \x0C%N\x01 has gave you premium for \x0E%d\x01%s days!", PREFIX, client, days_amount, IsClientPremium ? " more" : "");
	
	// Write log a line
	WriteLogLine("Admin \"%L\" has gave \"%L\" %d%s premium days.", client, target_index, days_amount, IsClientPremium ? " more" : "");
	
	// Give the premium to the target by the specified days amount
	GiveClientPremium(target_index, days_amount);
	
	return Plugin_Handled;
}

public Action Command_RemovePremium(int client, int args)
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
	
	// Display the command usage if there is no args specified
	if (args != 2)
	{
		PrintToChat(client, "%s Usage: \x04/removepremium\x01 <name|#userid> <days>", PREFIX);
		return Plugin_Handled;
	}
	
	char arg1[MAX_NAME_LENGTH];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	// Initialize the specified target index and make sure it's valid
	int target_index = FindTarget(client, arg1, true);
	
	if (target_index == -1)
	{
		// Automatic message
		return Plugin_Handled;
	}
	
	if (!g_ClientsData[client].IsPremium(client))
	{
		PrintToChat(client, "%s Player \x02%N\x01 isn't owning premium!", PREFIX_ERROR, target_index);
		return Plugin_Handled;
	}
	
	char arg2[16];
	GetCmdArg(2, arg2, sizeof(arg2));
	
	// Initialize the specified premium days amount to remove, and make sure it's valid
	int premium_days_amount = StringToInt(arg2);
	
	if (premium_days_amount <= 0)
	{
		PrintToChat(client, "%s Invalid specified premium days to remove, must be over \x040\x01! (\x02%s\x01)", PREFIX_ERROR, arg2);
		return Plugin_Handled;
	}
	
	// Give the premium to the target by the specified days amount
	RemoveClientPremium(target_index, premium_days_amount);
	
	// Notify the clients
	if (g_ClientsData[client].expire_unixstamp)
	{
		PrintToChat(client, "%s Successfully removed \x0E%d\x01 days from \x04%N\x01's premium!", PREFIX, premium_days_amount, target_index);
		PrintToChat(target_index, "%s Admin \x0C%N\x01 has removed \x0E%d\x01 days from your premium!", PREFIX, client, premium_days_amount);
	}
	else
	{
		PrintToChat(client, "%s Successfully removed \x04%N\x01's premium!", PREFIX, target_index);
		PrintToChat(target_index, "%s Admin \x0C%N\x01 has removed your premium!", PREFIX, client);
	}
	
	return Plugin_Handled;
}

public Action Command_Premium(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char name_arg[MAX_NAME_LENGTH];
		GetCmdArg(1, name_arg, sizeof(name_arg));
		int target_index = FindTarget(client, name_arg, true, false);
		
		if (target_index == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		if (!g_ClientsData[target_index].IsPremium(target_index)) {
			PrintToChat(client, "%s The specified player isn't owning premium!", PREFIX_ERROR);
		} else {
			ShowPremiumBenefitsMenu(target_index);
		}
	}
	else
	{
		if (!g_ClientsData[client].IsPremium(client)) {
			PrintToChat(client, "%s You aren't a \x04Premium\x01!", PREFIX_ERROR);
		} else {
			ShowPremiumBenefitsMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowPremiumBenefitsMenu(int client)
{
	char item_display[64];
	
	// Create the menu handle and set the title
	Menu menu = new Menu(Handler_PremiumBenefits);
	
	FormatTime(item_display, sizeof(item_display), "%d/%m/%Y - %H:%M:%S", g_ClientsData[client].expire_unixstamp);
	menu.SetTitle("%s Shop System - Premium Benefits\n• Expire Date: %s | %.2f Hours Left\n \n◾ %d Daily Wishes\n◾ +%d%% Gamble Win Chance\n◾ +10%% Shop Cash-Back\n ", PREFIX_MENU, item_display, (g_ClientsData[client].expire_unixstamp - GetTime()) / 3600.0, 1 + PREMIUM_WISHES_BONUS, PREMIUM_GAMBLE_BONUS_CHANCES);
	
	Format(item_display, sizeof(item_display), "Available In %.2f Hours!", (g_ClientsData[client].daily_award_unixstamp - GetTime()) / 3600.0);
	Format(item_display, sizeof(item_display), "Daily Award (%s)", g_ClientsData[client].daily_award_unixstamp - GetTime() <= 0 ? "Ready!" : item_display);
	menu.AddItem("", item_display, g_ClientsData[client].daily_award_unixstamp - GetTime() <= 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	//==== [ Execute the premium menu open forward ] =====//
	Call_StartForward(g_fwdOnPremiumMenuDisplay);
	Call_PushCell(client);
	Call_PushCell(menu);
	Call_Finish();
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_PremiumBenefits(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still a premium
		if (!g_ClientsData[client].IsPremium(client))
		{
			return 0;
		}
		
		if (!item_position)
		{
			ExecuteDailyAward(client);
		}
		
		char item_info[64];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		
		//==== [ Execute the premium menu press forward ] =====//
		Call_StartForward(g_fwdOnPremiumMenuPress);
		Call_PushCell(client);
		Call_PushCell(menu);
		Call_PushString(item_info);
		Call_PushCell(item_position);
		Call_Finish();
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
	CreateNative("Shop_IsClientPremium", Native_IsClientPremium);
	CreateNative("Shop_GivePremium", Native_GivePremium);
	CreateNative("Shop_RemovePremium", Native_RemovePremium);
	
	g_fwdOnPremiumMenuDisplay = new GlobalForward("Shop_OnPremiumMenuDispaly", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnPremiumMenuPress = new GlobalForward("Shop_OnPremiumMenuPress", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	
	RegPluginLibrary("shop_premium");
	return APLRes_Success;
}

public int Native_IsClientPremium(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].IsPremium(client);
}

public int Native_GivePremium(Handle plugin, int numParams)
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
	int days_amount = GetNativeCell(2);
	
	if (days_amount <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified premium days amount, Must be over 0! (Got: %d)", days_amount);
	}
	
	GiveClientPremium(client, days_amount);
	
	return true;
}

public int Native_RemovePremium(Handle plugin, int numParams)
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
	int days_amount = GetNativeCell(2);
	
	if (days_amount <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified premium days amount, Must be over 0! (Got: %d)", days_amount);
	}
	
	RemoveClientPremium(client, days_amount);
	
	return true;
}

//================================[ Database ]================================//

void SQL_TryToConnect()
{
	if (Shop_GetDatabaseType() != DB_MySQL)
	{
		return;
	}
	
	// Free the last used handle
	delete g_Database;
	
	// Connect to the shop database
	g_Database = Shop_GetDatabase();
	
	strcopy(g_TableName, sizeof(g_TableName), GetTableName());
	
	// Format and execute the query
	char query[256];
	g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s`(`account_id` INT NOT NULL, `expire_unixstamp` INT NOT NULL, `daily_award_unixstamp` INT NOT NULL, UNIQUE(`account_id`))", g_TableName);
	g_Database.Query(SQL_CheckForErrors, query);
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

void SQL_FetchClient(int client)
{
	char query[128];
	g_Database.Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `account_id` = %d", g_TableName, g_ClientsData[client].account_id);
	g_Database.Query(SQL_FetchClient_CB, query, GetClientSerial(client));
}

public void SQL_FetchClient_CB(Database db, DBResultSet results, const char[] error, int serial)
{
	// If the string is not empty, an error has occurred
	if (!db || !results || error[0])
	{
		LogError("Client fetch databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (!client)
	{
		return;
	}
	
	if (results.FetchRow())
	{
		g_ClientsData[client].expire_unixstamp = results.FetchInt(1);
		g_ClientsData[client].daily_award_unixstamp = results.FetchInt(2);
	}
	
	g_ClientsData[client].IsPremium(client);
}

void SQL_UpdateClient(int client)
{
	// Update the client premium data
	char query[128];
	g_Database.Format(query, sizeof(query), "SELECT * FROM `%s` WHERE `account_id` = %d", g_TableName, g_ClientsData[client].account_id);
	g_Database.Query(SQL_UpdateClient_CB, query, client);
}

public void SQL_UpdateClient_CB(Database db, DBResultSet results, const char[] error, int client)
{
	// If the string is not empty, an error has occurred
	if (error[0])
	{
		LogError("Client update databse error, %s", error);
		return;
	}
	
	char query[512];
	
	g_Database.Format(query, sizeof(query), "INSERT INTO `%s` (`account_id`, `expire_unixstamp`, `daily_award_unixstamp`) VALUES (%d, %d, %d) ON DUPLICATE KEY UPDATE `account_id` = VALUES(`account_id`), `expire_unixstamp` = VALUES(`expire_unixstamp`), `daily_award_unixstamp` = VALUES(`daily_award_unixstamp`)", 
		g_TableName, 
		g_ClientsData[client].account_id, 
		g_ClientsData[client].expire_unixstamp, 
		g_ClientsData[client].daily_award_unixstamp
		);
	
	g_Database.Query(SQL_CheckForErrors, query);
	
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
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

//================================[ Functions ]================================//

void GiveClientPremium(int client, int days)
{
	g_ClientsData[client].expire_unixstamp += ((!g_ClientsData[client].expire_unixstamp ? GetTime() : 0) + (days * DAY_CONVERTED_SECONDS));
}

void RemoveClientPremium(int client, int days)
{
	if ((g_ClientsData[client].expire_unixstamp -= (days * DAY_CONVERTED_SECONDS)) < GetTime())
	{
		g_ClientsData[client].expire_unixstamp = 0;
	}
}

void ExecuteDailyAward(int client)
{
	int credits_award = GetRandomInt(g_cvMinDailyAwardCredits.IntValue, g_cvMaxDailyAwardCredits.IntValue);
	int credits_multiplier = GetRandomInt(MIN_AWARD_MULTIPLY, MAX_AWARD_MULTIPLY);
	
	// Notify server
	PrintToChatAll("%s Every player in the server got \x04%s credits\x01 thanks to \x03%N\x01 Premium!", PREFIX, AddCommas(credits_award), client);
	PrintToChat(client, "%s You've got \x04%s credits\x01 with a \x0E%d\x01 multiplier!", PREFIX, AddCommas(credits_award), credits_multiplier);
	
	// Award and notify all online clients
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			if (current_client != client)
			{
				Shop_GiveClientCredits(current_client, credits_award);
			}
			
			SetHudTextParams(-1.0, 0.675, DAILY_AWARD_TEXT_TIME, GetRandomInt(1, 255), GetRandomInt(1, 255), GetRandomInt(1, 255), 255);
			ShowHudText(current_client, -1, "Every player in the server got %s credits thanks to %N Premium!", AddCommas(credits_award), client);
		}
	}
	
	// Award the client
	Shop_GiveClientCredits(client, credits_award * credits_multiplier);
	
	// Apply the award cooldown
	g_ClientsData[client].daily_award_unixstamp = (GetTime() + (HOUR_CONVERTED_SECONDS * g_cvDailyAwardCooldown.IntValue));
}

char[] GetTableName()
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
		if (g_ClientsData[client].account_id == g_AuthorizedClients[current_accout_id])
		{
			return true;
		}
	}
	
	// Match has failed
	return false;
}

//================================================================//