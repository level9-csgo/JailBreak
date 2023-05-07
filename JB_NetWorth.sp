#include <sourcemod>
#include <regex>
#include <JailBreak>
#include <JB_NetWorth>
#include <JB_RunesSystem>

#pragma semicolon 1
#pragma newdecls required

#define LINE_BREAK "\xE2\x80\xA9"

#define SEPERATOR " \x0C\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E" ... \
"\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF"

Database g_Database;
Regex g_Steamid2;

int g_Userid[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[JailBreak] Net Worth", 
	author = "KoNLiG", 
	description = "Calculates a player value by net worth including credits, shop items, and personal runes.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Required for 'FindTarget' responses.
	LoadTranslations("common.phrases");
	
	// Late load database connection.
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Compile a steam id2 regex expression.
	g_Steamid2 = new Regex("^STEAM_[0-5]:[0-1]:[0-9]+$");
	
	// Register commands.
	RegConsoleCmd("sm_networth", Command_NetWorth, "Displays the calculated net worth of a certain player, offline or online.");
	RegConsoleCmd("sm_nw", Command_NetWorth, "Displays the calculated net worth of a certain player, offline or online. (alias)");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	
	RegPluginLibrary(JB_NETWORTH_LIBRARY_NAME);
	return APLRes_Success;
}

public void OnPlayerNetWorthCalculated(int account_id, const char[] target_name, int client, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	PrintToChat(client, "%s", SEPERATOR);
	PrintToChat(client, " \x06%s\x07's Networth:"...LINE_BREAK..."\x0E◾ \x10%s\x01", target_name, JB_AddCommas(total_net_worth));
	PrintToChat(client, " \x0BCredits: \x10%s\x01", JB_AddCommas(credits));
	PrintToChat(client, " \x0BShop Items: \x10%s\x01", JB_AddCommas(shop_items_value));
	PrintToChat(client, " \x0BRunes: \x10%s\x01", JB_AddCommas(runes_value));
	PrintToChat(client, " \x04Processing time \x0E%fs\x01", response_time);
	PrintToChat(client, "%s", SEPERATOR);
}

//================================[ Commands ]================================//

public void OnClientPutInServer(int client)
{
	g_Userid[client] = GetClientUserId(client);
}

public void OnClientDisconnect(int client)
{
	g_Userid[client] = 0;
}

//================================[ Commands ]================================//

Action Command_NetWorth(int client, int argc)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] This command is unavailable via the server console.");
		return Plugin_Handled;
	}
	
	int account_id;
	
	// 0 arguments means client is the target itself.
	if (!argc)
	{
		account_id = GetSteamAccountID(client);
	}
	else
	{
		// Can be whether a steamid, name, or userid.
		char target_arg[MAX_NAME_LENGTH];
		GetCmdArgString(target_arg, sizeof(target_arg));
		
		int matches = g_Steamid2.Match(target_arg);
		if (matches > 1)
		{
			PrintToChat(client, "%s You cannot enter multiple steam id(s)!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		// A single match has been found.
		else if (matches == 1)
		{
			char steamid2[MAX_AUTHID_LENGTH];
			g_Steamid2.GetSubString(0, steamid2, sizeof(steamid2));
			
			account_id = StringToInt(steamid2[10]) * 2 + (steamid2[8] - 48);
		}
		// No steamid matches.
		else
		{
			int target = FindTarget(client, target_arg, true, false);
			if (target != -1)
			{
				account_id = GetSteamAccountID(target);
			}
		}
	}
	
	if (!account_id)
	{
		PrintToChat(client, "%s Failed to initialize an account id, please enter a valid name/steamid2.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	CalculatePlayerNetWorth(account_id, client, INVALID_FUNCTION, INVALID_FUNCTION, null, 0);
	
	return Plugin_Handled;
}

//================================[ API ]================================//

void CreateNatives()
{
	CreateNative("JB_GetPlayerNetWorth", Native_GetPlayerNetWorth);
}

any Native_GetPlayerNetWorth(Handle plugin, int numParams)
{
	int account_id = GetNativeCell(1);
	if (!account_id)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Account id cannot be 0.");
	}
	
	Function success_callback = GetNativeFunction(2);
	Function failure_callback = GetNativeFunction(3);
	
	if (success_callback == INVALID_FUNCTION && failure_callback == INVALID_FUNCTION)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Both callbacks cannot be null.");
	}
	
	any data = GetNativeCell(4);
	
	CalculatePlayerNetWorth(account_id, 0, success_callback, failure_callback, plugin, data);
	
	return 0;
}

void Call_OnPlayerNetWorthSuccess(Function func, Handle plugin, int account_id, const char[] target_name, any data, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	Call_StartFunction(plugin, func);
	Call_PushCell(account_id);
	Call_PushString(target_name);
	Call_PushCell(data);
	Call_PushCell(total_net_worth);
	Call_PushCell(credits);
	Call_PushCell(shop_items_value);
	Call_PushCell(runes_value);
	Call_PushFloat(response_time);
	Call_Finish();
}

void Call_OnPlayerNetWorthFailure(Function func, Handle plugin, int account_id, any data, float response_time)
{
	Call_StartFunction(plugin, func);
	Call_PushCell(account_id);
	Call_PushCell(data);
	Call_PushFloat(response_time);
	Call_Finish();
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	Lateload();
}

void CalculatePlayerNetWorth(int account_id, int client, Function success_callback, Function failure_callback, Handle plugin, any data)
{
	DataPack dp = new DataPack();
	dp.WriteCell(account_id);
	dp.WriteCell(g_Userid[client]);
	dp.WriteFunction(success_callback);
	dp.WriteFunction(failure_callback);
	dp.WriteCell(plugin);
	dp.WriteCell(data);
	dp.WriteFloat(GetGameTime());
	
	char steamid2[MAX_AUTHID_LENGTH];
	GetSteam2FromAccountId(steamid2, sizeof(steamid2), account_id);
	
	char query[256];
	Transaction txn = new Transaction();
	
	// Retrieves an account id's name and credits.
	g_Database.Format(query, sizeof(query), "SELECT `name`, `money` FROM `shop_players` WHERE `auth` = '%s'", steamid2);
	txn.AddQuery(query);
	
	// Retrieves an account id's total shop items value.
	g_Database.Format(query, sizeof(query), "SELECT SUM(`buy_price`) FROM `shop_boughts` WHERE `player_id` = (SELECT `id` FROM `shop_players` WHERE `auth` = '%s')", steamid2);
	txn.AddQuery(query);
	
	// Retrieves a client full rune inventory.
	g_Database.Format(query, sizeof(query), "SELECT `unique`, `star`, `level` FROM `jb_runes_inventory` WHERE `account_id` = %d", account_id);
	txn.AddQuery(query);
	
	g_Database.Execute(txn, OnPlayerNetWorthCalculatedSuccess, OnPlayerNetWorthCalculatedFailed, dp);
}

void OnPlayerNetWorthCalculatedSuccess(Database db, DataPack dp, int numQueries, DBResultSet[] results, any[] queryData)
{
	dp.Reset();
	
	int account_id = dp.ReadCell();
	
	int client = dp.ReadCell(); // userid
	
	// A client issued this nw request, but disconnected.
	if (client && !(client = GetClientOfUserId(client)))
	{
		return;
	}
	
	Function success_callback = dp.ReadFunction();
	Function failure_callback = dp.ReadFunction();
	Handle plugin = dp.ReadCell();
	any data = dp.ReadCell();
	float start_time = dp.ReadFloat();
	
	dp.Close();
	
	// Make sure the client has joined the server at least once.
	if (!results[0].FetchRow())
	{
		if (client)
		{
			PrintToChat(client, "%s No data was found for account id - \x07%d\x01!", PREFIX_ERROR, account_id);
		}
		else if (failure_callback != INVALID_FUNCTION)
		{
			Call_OnPlayerNetWorthFailure(failure_callback, plugin, account_id, data, GetGameTime() - start_time);
		}
		
		return;
	}
	
	// Fetch the target name and credits count.
	char target_name[MAX_NAME_LENGTH];
	int credits;
	results[0].FetchString(0, target_name, sizeof(target_name));
	credits = results[0].FetchInt(1);
	
	// Fetch the target total shop items value.
	int shop_items_value;
	if (results[1].FetchRow())
	{
		shop_items_value = results[1].FetchInt(0);
	}
	
	// Fetch the client rune inventory, and calculate its total market value.
	int runes_value;
	if (results[2].FetchRow())
	{
		char identifier[32];
		int star, level;
		
		do
		{
			results[2].FetchString(0, identifier, sizeof(identifier));
			star = results[2].FetchInt(1);
			level = results[2].FetchInt(2);
			
			runes_value += GetRuneMarketValue(identifier, star, level);
		} while (results[2].FetchRow());
	}
	
	if (success_callback == INVALID_FUNCTION)
	{
		OnPlayerNetWorthCalculated(account_id, target_name, client, credits + shop_items_value + runes_value, credits, shop_items_value, runes_value, GetGameTime() - start_time);
	}
	else
	{
		Call_OnPlayerNetWorthSuccess(success_callback, plugin, account_id, target_name, data, credits + shop_items_value + runes_value, credits, shop_items_value, runes_value, GetGameTime() - start_time);
	}
}

void OnPlayerNetWorthCalculatedFailed(Database db, DataPack dp, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	dp.Reset();
	int account_id = dp.ReadCell();
	
	int client = dp.ReadCell(); // userid
	if (client && (client = GetClientOfUserId(client)))
	{
		PrintToChat(client, "%s %s", PREFIX_ERROR, error);
	}
	
	dp.ReadFunction();
	
	Function failure_callback = dp.ReadFunction();
	if (failure_callback != INVALID_FUNCTION)
	{
		Handle plugin = dp.ReadCell();
		any data = dp.ReadCell();
		float start_time = dp.ReadFloat();
		
		Call_OnPlayerNetWorthFailure(failure_callback, plugin, account_id, data, GetGameTime() - start_time);
	}
	
	dp.Close();
	
	ThrowError("[OnPlayerNetWorthCalculatedFailed] failIndex: %d - %s", failIndex, error);
}

//================================[ Utils ]================================//

// 23456789 (from [U:1:23456789]) to STEAM_1:1:23456789
int GetSteam2FromAccountId(char[] result, int maxlen, int account_id)
{
	return Format(result, maxlen, "STEAM_1:%d:%d", view_as<bool>(account_id % 2), account_id / 2);
}

int GetRuneMarketValue(const char[] identifier, int star, int level)
{
	int starting_value = GetRuneStartingValue(identifier, star);
	
	for (int i = 1; i < level; i++)
	{
		starting_value += starting_value / 10;
	}
	
	return starting_value;
}

int GetRuneStartingValue(const char[] identifier, int star)
{
	if (RuneStar_1 <= star <= RuneStar_3)
	{
		return 5000;
	}
	
	if (StrEqual(identifier, "healthrune") || StrEqual(identifier, "damagerune"))
	{
		switch (star)
		{
			case RuneStar_4:return 25000;
			case RuneStar_5:return 50000;
			case RuneStar_6:return 650000;
		}
	}
	else if (StrEqual(identifier, "flashbangrune") || StrEqual(identifier, "hegrenaderune"))
	{
		switch (star)
		{
			case RuneStar_4:return 10000;
			case RuneStar_5:return 40000;
			case RuneStar_6:return 500000;
		}
	}
	else if (StrEqual(identifier, "critraterune") || StrEqual(identifier, "critdmgrune"))
	{
		switch (star)
		{
			case RuneStar_4:return 5000;
			case RuneStar_5:return 25000;
			case RuneStar_6:return 300000;
		}
	}
	
	return 0;
}

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

//================================================================//