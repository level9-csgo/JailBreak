#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>
#include <shop>
#include <rtler>

#pragma semicolon 1
#pragma newdecls required

#define TOP_NAME "Top Credits"
#define MENU_ITEM_IDENTIFIER "credits"

// An entry for a value in this top category.
enum struct TopEntry
{
	char name[MAX_NAME_LENGTH];
	
	int credits;
}

Database g_Database;

ConVar top_show_clients_amount;

public Plugin myinfo = 
{
	name = "[Top Module] "...TOP_NAME, 
	author = "KoNLiG", 
	description = "Top gang wins module for the top system.", 
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
}

//================================[ JailBreak Events ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
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
	
	ProcessTopCreditsData(client);
}

//================================[ Menus ]================================//

void ProcessTopCreditsData(int client)
{
	char query[128];
	g_Database.Format(query, sizeof(query), "SELECT `name`, `money` FROM `shop_players` ORDER BY `money` DESC LIMIT %d", top_show_clients_amount.IntValue);
	g_Database.Query(SQL_OnTopCreditsResults, query, GetClientUserId(client));
}

void DisplayTopCreditsMenu(int client, ArrayList entries)
{
	Menu menu = new Menu(Handler_TopCredits);
	menu.SetTitle("%s Top System - Viewing %s\n• Description: Top credits for each and every player in the server.\n• My credits: %s\n \n", PREFIX_MENU, TOP_NAME, JB_AddCommas(Shop_GetClientCredits(client)));
	
	char item_display[256];
	TopEntry top_entry;
	
	for (int current_entry; current_entry < entries.Length; current_entry++)
	{
		entries.GetArray(current_entry, top_entry);
		
		RTLify(item_display, sizeof(item_display), top_entry.name);
		Format(item_display, sizeof(item_display), "(#%d) %s - %s Credits", current_entry + 1, item_display, JB_AddCommas(top_entry.credits));
		
		menu.AddItem("", item_display);
	}
	
	delete entries;
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_TopCredits(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1/*, selected_item = param2*/;
			
			ProcessTopCreditsData(client);
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

void SQL_OnTopCreditsResults(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!db || !results || error[0])
	{
		ThrowError("[SQL_OnTopCreditsResults] %s", error);
	}
	
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		return;
	}
	
	ArrayList entries = new ArrayList(sizeof(TopEntry));
	
	while (results.FetchRow())
	{
		TopEntry new_top_entry;
		
		results.FetchString(0, new_top_entry.name, sizeof(TopEntry::name));
		new_top_entry.credits = results.FetchInt(1);
		
		entries.PushArray(new_top_entry);
	}
	
	DisplayTopCreditsMenu(client, entries);
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

//================================[ Utils ]================================//

//================================================================//