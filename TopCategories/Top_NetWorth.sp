#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>
#include <JB_NetWorth>
#include <shop>
#include <rtler>

#pragma semicolon 1
#pragma newdecls required

#define TOP_NAME "Top Net-Worth"
#define MENU_ITEM_IDENTIFIER "networth"

// An entry for a value in this top category.
enum struct TopEntry
{
	int account_id;
	
	char name[MAX_NAME_LENGTH];
	
	int networth;
}

Database g_Database;

enum struct Player
{
	int account_id;
	int userid;
	
	//================================//
	void Init(int account_id, int userid)
	{
		this.account_id = account_id;
		this.userid = userid;
	}
	
	void Close()
	{
		this.account_id = 0;
		this.userid = 0;
	}
}

Player g_Players[MAXPLAYERS + 1];

ConVar top_show_clients_amount;

public Plugin myinfo = 
{
	name = "[Top Module] "...TOP_NAME, 
	author = "KoNLiG", 
	description = "Top net worth module for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	if (!(top_show_clients_amount = FindConVar("top_show_clients_amount")))
	{
		SetFailState("Failed to find cvar 'top_show_clients_amount'.");
	}
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// 'OnClientAuthorized'/'OnClientDisconnect' replacements.
	HookEvent("player_connect", Event_PlayerConnect);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
}

void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	char networkid[MAX_AUTHID_LENGTH];
	event.GetString("networkid", networkid, sizeof(networkid));
	
	int client = event.GetInt("index") + 1;
	
	OnPlayerConnect(client, GetAccountIdFromSteam2(networkid), event.GetInt("userid"));
}

void OnPlayerConnect(int client, int account_id, int userid)
{
	g_Players[client].Init(account_id, userid);
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		OnPlayerDisconnect(client);
	}
}

void OnPlayerDisconnect(int client)
{
	JB_GetPlayerNetWorth(g_Players[client].account_id, OnPlayerNetWorthSuccess, INVALID_FUNCTION);
	
	g_Players[client].Close();
}

//================================[ JailBreak Events ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `top_networth`(`account_id` INT NOT NULL DEFAULT 0, `name` VARCHAR(128) NOT NULL DEFAULT '', `net_worth` INT NOT NULL DEFAULT 0, PRIMARY KEY(`account_id`))");
	
	Lateload();
}

public void JB_OnTopMenu(int client, Menu menu)
{
	menu.InsertItem(1, MENU_ITEM_IDENTIFIER, TOP_NAME);
}

public void JB_OnTopMenuSelect(int client, int item_pos, Menu menu)
{
	char item_info[16];
	menu.GetItem(item_pos, item_info, sizeof(item_info));
	
	if (!StrEqual(item_info, MENU_ITEM_IDENTIFIER))
	{
		return;
	}
	
	ProcessTopNetWorthData(client);
}

//================================[ Menus ]================================//

void ProcessTopNetWorthData(int client)
{
	char query[128];
	
	Transaction txn = new Transaction();
	
	g_Database.Format(query, sizeof(query), "SELECT * FROM `top_networth` WHERE `account_id` != 912414245 AND `account_id` != 928490446 ORDER BY `net_worth` DESC LIMIT %d", top_show_clients_amount.IntValue);
	txn.AddQuery(query);
	
	g_Database.Format(query, sizeof(query), "SELECT `net_worth` FROM `top_networth` WHERE `account_id` = %d", g_Players[client].account_id);
	txn.AddQuery(query);
	
	g_Database.Execute(txn, SQL_OnTopNetWorthResults, .data = g_Players[client].userid);
}

void DisplayTopNetWorthMenu(int client, int my_networth, ArrayList entries)
{
	Menu menu = new Menu(Handler_TopNetWorth);
	menu.SetTitle("%s Top System - Viewing %s\n• Description: Top Net-Worth for each and every player in the server.\n• My Net-Worth: %s\n \n", PREFIX_MENU, TOP_NAME, JB_AddCommas(my_networth));
	
	char item_display[256], item_info[16];
	TopEntry top_entry;
	
	for (int current_entry; current_entry < entries.Length; current_entry++)
	{
		entries.GetArray(current_entry, top_entry);
		
		RTLify(item_display, sizeof(item_display), top_entry.name);
		Format(item_display, sizeof(item_display), "(#%d) %s - %s", current_entry + 1, item_display, JB_AddCommas(top_entry.networth));
		
		IntToString(top_entry.account_id, item_info, sizeof(item_info));
		
		menu.AddItem(item_info, item_display);
	}
	
	delete entries;
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_TopNetWorth(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			char item_info[16];
			menu.GetItem(selected_item, item_info, sizeof(item_info));
			
			int account_id = StringToInt(item_info);
			
			char steamid2[MAX_AUTHID_LENGTH];
			GetSteam2FromAccountId(steamid2, sizeof(steamid2), account_id);
			
			ClientCommand(client, "sm_networth %s", steamid2);
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				ClientCommand(client, "sm_top");
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

//================================[ MySQL ]================================//

void OnPlayerNetWorthSuccess(int account_id, const char[] target_name, any data, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	SQL_UpdatePlayerNetWorth(account_id, target_name, total_net_worth);
}

void SQL_UpdatePlayerNetWorth(int account_id, const char[] name, int net_worth)
{
	char query[256];
	g_Database.Format(query, sizeof(query), "INSERT INTO `top_networth`(`account_id`, `name`, `net_worth`) VALUES(%d, '%s', %d) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `net_worth` = VALUES(`net_worth`)", account_id, name, net_worth);
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_OnTopNetWorthResults(Database db, int userid, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		return;
	}
	
	ArrayList entries = new ArrayList(sizeof(TopEntry));
	
	TopEntry new_top_entry;
	while (results[0].FetchRow())
	{
		new_top_entry.account_id = results[0].FetchInt(0);
		results[0].FetchString(1, new_top_entry.name, sizeof(TopEntry::name));
		new_top_entry.networth = results[0].FetchInt(2);
		
		entries.PushArray(new_top_entry);
	}
	
	int my_networth;
	if (results[1].FetchRow())
	{
		my_networth = results[1].FetchInt(0);
	}
	
	DisplayTopNetWorthMenu(client, my_networth, entries);
}

void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

//================================[ Utils ]================================//

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsClientAuthorized(current_client))
		{
			OnPlayerConnect(current_client, GetSteamAccountID(current_client), GetClientUserId(current_client));
		}
	}
}

// STEAM_1:1:23456789 to 23456789
int GetAccountIdFromSteam2(const char[] steam_id)
{
	return StringToInt(steam_id[10]) * 2 + (steam_id[8] - 48);
}

// 23456789 (from [U:1:23456789]) to STEAM_1:1:23456789
int GetSteam2FromAccountId(char[] result, int maxlen, int account_id)
{
	return Format(result, maxlen, "STEAM_1:%d:%d", view_as<bool>(account_id % 2), account_id / 2);
}

//================================================================//