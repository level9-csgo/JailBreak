#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>
#include <JB_SpecialDays>
#include <JB_GangsSystem>
#include <rtler>

#pragma semicolon 1
#pragma newdecls required

#define TOP_NAME "Top Gang Wins"
#define MENU_ITEM_IDENTIFIER "gang_wins"

ArrayList g_GangEntrys;

Database g_Database;

enum struct GangEntry
{
	// gang name.
	char name[128];
	
	// gang special day win count.
	int wins;
	
	//================================//
	void Init()
	{
		// Store |this| data globally.
		g_GangEntrys.PushArray(this);
		
		// Fetch the gang MySQL information.
		this.FetchMySQLData();
	}
	
	int GetIdx()
	{
		return g_GangEntrys.FindString(this.name);
	}
	
	void FetchMySQLData()
	{
		int idx = this.GetIdx();
		if (idx == -1)
		{
			return;
		}
		
		char query[256];
		g_Database.Format(query, sizeof(query), "SELECT `special_day_wins` FROM `jb_gangs` WHERE `name` = '%s'", this.name);
		g_Database.Query(SQL_FetchGang_CB, query, idx);
	}
	
	void UpdateMySQLData()
	{
		char query[256];
		g_Database.Format(query, sizeof(query), "UPDATE `jb_gangs` SET `special_day_wins` = %d WHERE `name` = '%s'", this.wins, this.name);
		g_Database.Query(SQL_CheckForErrors, query);
	}
	
	void UpdateMyself()
	{
		int idx = this.GetIdx();
		if (idx == -1)
		{
			return;
		}
		
		g_GangEntrys.SetArray(idx, this);
	}
}

bool g_Lateload;

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
	g_GangEntrys = new ArrayList(sizeof(GangEntry));

	if (g_Lateload)
	{
		Lateload();
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Lateload = late;

	return APLRes_Success;
}

void Lateload()
{
	Gangs_GangsLoaded(JB_GetDatabase(), Gangs_GetGangsCount());
}

//================================[ JailBreak Events ]================================//

public void JB_OnTopMenu(int client, Menu menu)
{
	menu.InsertItem(0, MENU_ITEM_IDENTIFIER, TOP_NAME);
}

public void JB_OnTopMenuSelect(int client, int item_pos, Menu menu)
{
	char item_info[16];
	menu.GetItem(item_pos, item_info, sizeof(item_info));

	if (!StrEqual(item_info, MENU_ITEM_IDENTIFIER))
	{
		return;
	}

	DisplayTopGangWinsMenu(client);
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown)
{
	if (winner == INVALID_DAY_WINNER)
	{
		return;
	}

	int gang_id = Gangs_GetPlayerGang(winner);
	if (gang_id == -1)
	{
		return;
	}

	GangEntry gang_entry;
	g_GangEntrys.GetArray(gang_id, gang_entry);

	gang_entry.wins++;

	gang_entry.UpdateMyself();
	gang_entry.UpdateMySQLData();
}

//================================[ Menus ]================================//

void DisplayTopGangWinsMenu(int client)
{
	if (!g_GangEntrys.Length)
	{
		PrintToChat(client, "%s There are no gangs at this moment.", PREFIX);
		return;
	}

	char client_gang_progress[32];
	GangEntry gang_entry;

	int client_gang_id = Gangs_GetPlayerGang(client);
	if (client_gang_id == -1)
	{
		client_gang_progress = "You have no gang.";
	}
	else
	{
		g_GangEntrys.GetArray(client_gang_id, gang_entry);

		Format(client_gang_progress, sizeof(client_gang_progress), "%d wins.", gang_entry.wins);
	}

	Menu menu = new Menu(Handler_TopGangWins);
	menu.SetTitle("%s Top System - Viewing %s\n• Description: Top special day wins of each and every gang in the server!\n• My gang progress: %s\n \n", PREFIX_MENU, TOP_NAME, client_gang_progress);

	char item_display[256];

	ArrayList sorted_gang_entries = g_GangEntrys.Clone();
	sorted_gang_entries.SortCustom(SortGangEntries);

	for (int current_gang; current_gang < sorted_gang_entries.Length; current_gang++)
	{
		sorted_gang_entries.GetArray(current_gang, gang_entry);

		RTLify(item_display, sizeof(item_display), gang_entry.name);
		Format(item_display, sizeof(item_display), "(#%d) %s - %d Wins", current_gang + 1, item_display, gang_entry.wins);

		menu.AddItem("", item_display);
	}

	delete sorted_gang_entries;

	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);

	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_TopGangWins(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1/*, selected_item = param2*/;

			DisplayTopGangWinsMenu(client);
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

/**
 * Sort comparison function for ADT Array elements. Function provides you with
 * indexes currently being sorted, use ADT Array functions to retrieve the
 * index values and compare.
 *
 * @param index1        First index to compare.
 * @param index2        Second index to compare.
 * @param array         Array that is being sorted (order is undefined).
 * @param hndl          Handle optionally passed in while sorting.
 * @return              -1 if first should go before second
 *                      0 if first is equal to second
 *                      1 if first should go after second
 */
int SortGangEntries(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList arr = view_as<ArrayList>(array);
	
	GangEntry first_gang_entry, second_gang_entry;
	arr.GetArray(index1, first_gang_entry);
	arr.GetArray(index2, second_gang_entry);
	
	return FloatCompare(float(second_gang_entry.wins), float(first_gang_entry.wins));
}

//================================[ Gangs Management ]================================//

public void Gangs_GangsLoaded(Database db, int gang_count)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	Gangs_CreateDBColumn("special_day_wins", "INT", "0");
	
	CacheGangEntries(gang_count);
}

public void Gangs_OnGangCreate(int gang_id)
{
	LoadGangEntry(gang_id);
}

public void Gangs_OnGangDelete(int gang_id, char[] gang_name)
{
	if (g_GangEntrys.Length > gang_id)
	{
		g_GangEntrys.Erase(gang_id);
	}
}

void CacheGangEntries(int gang_count)
{
	// Delete old data.
	g_GangEntrys.Clear();
	
	for (int current_gang; current_gang < gang_count; current_gang++)
	{
		LoadGangEntry(current_gang);
	}
}

void LoadGangEntry(int gang_id)
{
	GangEntry new_gang_entry;
	Gangs_GetGangName(gang_id, new_gang_entry.name, sizeof(GangEntry::name));
	
	// Skip invalid gangs.
	if (new_gang_entry.name[0])
	{
		new_gang_entry.Init();
	}
}

//================================[ MySQL ]================================//

void SQL_FetchGang_CB(Database db, DBResultSet results, const char[] error, int gang_id)
{
	if (results.FetchRow())
	{
		g_GangEntrys.Set(gang_id, results.FetchInt(0), GangEntry::wins);
	}
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

//================================================================//