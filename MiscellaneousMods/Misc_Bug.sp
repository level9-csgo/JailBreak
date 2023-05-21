#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define CONFIG_PATH "addons/sourcemod/configs/ServerBugsData.cfg"

//====================//

ArrayList g_BugsData;

enum struct Bug
{
	char bug_unique[8];
	char bug_context[128];
	char reporter_name[MAX_NAME_LENGTH];
	char reporter_auth_id[32];
	int create_unixstamp;
	
	int Create(char[] reporter_name, char[] reporter_auth_id, char[] bug_context)
	{
		do
		{
			strcopy(this.bug_unique, sizeof(Bug::bug_unique), GetRandomString());
		} while (GetBugByUnique(this.bug_unique) != -1);
		
		strcopy(this.reporter_name, sizeof(Bug::reporter_name), reporter_name);
		strcopy(this.reporter_auth_id, sizeof(Bug::reporter_auth_id), reporter_auth_id);
		strcopy(this.bug_context, sizeof(Bug::bug_context), bug_context);
		
		this.create_unixstamp = GetTime();
		
		int bug_index = g_BugsData.PushArray(this);
		
		// Add the bug to the config file
		KV_AddBugReport(bug_index);
		
		return bug_index;
	}
}

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Bug", 
	author = PLUGIN_AUTHOR, 
	description = "Allows for players to report a server bug with the command '/bug'.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the server bugs arraylist
	g_BugsData = new ArrayList(sizeof(Bug));
	
	// Admin Commands
	RegAdminCmd("sm_bugs", Command_Bugs, ADMFLAG_ROOT, "Access the server bugs reports list menu.");
	
	// Client Commands
	RegConsoleCmd("sm_bug", Command_Bug, "Allows the client to report a server bug.");
	
	// Config file creation
	char file_path[PLATFORM_MAX_PATH];
	strcopy(file_path, sizeof(file_path), CONFIG_PATH);
	BuildPath(Path_SM, file_path, sizeof(file_path), file_path[17]);
	delete OpenFile(file_path, "a+");
}

//================================[ Events ]================================//

public void OnMapStart()
{
	KV_LoadServerBugs();
}

//================================[ Commands ]================================//

public Action Command_Bugs(int client, int args)
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
		
		ShowBugsListMenu(target_index);
	}
	else
	{
		ShowBugsListMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_Bug(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure there is aleast 1 argument in the command
	if (!args)
	{
		PrintToChat(client, "%s Usage: \x04/bug\x01 <context>", PREFIX);
		return Plugin_Handled;
	}
	
	// Initialize the bug context
	char bug_context[128];
	GetCmdArgString(bug_context, sizeof(bug_context));
	
	char client_name[MAX_NAME_LENGTH], client_auth_id[32];
	
	GetClientName(client, client_name, sizeof(client_name));
	GetClientAuthId(client, AuthId_Steam2, client_auth_id, sizeof(client_auth_id));
	
	// Create the bug data struct
	Bug BugData;
	BugData.Create(client_name, client_auth_id, bug_context);
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowBugsListMenu(int client)
{
	char item_display[MAX_NAME_LENGTH * 2];
	Menu menu = new Menu(Handler_BugsList);
	menu.SetTitle("%s Bugs List - Main Menu\n ", PREFIX_MENU);
	
	Bug CurrentBugData;
	
	for (int current_bug = 0; current_bug < g_BugsData.Length; current_bug++)
	{
		CurrentBugData = GetBugByIndex(current_bug);
		
		// Format the item display buffer, and insert the item into the menu
		FormatEx(item_display, sizeof(item_display), "By %s", CurrentBugData.reporter_name);
		menu.AddItem(CurrentBugData.bug_unique, item_display);
	}
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No bug was reported yet.", ITEMDRAW_DISABLED);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_BugsList(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[8];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int bug_index = GetBugByUnique(item_info);
		
		// Make sure the server bug is still valid
		if (bug_index == -1)
		{
			// Notify the client
			PrintToChat(client, "%s The specified server bug is no logner valid.", PREFIX_ERROR);
			
			// Display the list menu again
			ShowBugsListMenu(client);
			
			return 0;
		}
		
		ShowBugDetailMenu(client, bug_index);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowBugDetailMenu(int client, int bug_index)
{
	// Initialize the given bug data
	Bug BugData; BugData = GetBugByIndex(bug_index);
	
	char item_display[32];
	Menu menu = new Menu(Handler_BugDetail);
	
	RTLify(BugData.bug_context, sizeof(BugData.bug_context), BugData.bug_context);
	
	FormatTime(item_display, sizeof(item_display), "%d/%m/%Y %X", BugData.create_unixstamp);
	menu.SetTitle("%s Bugs List - Bug Detail\n \n◾ Reporter Name: %s\n◾ Reporter Auth ID: %s\n◾ Context: %s\n◾ Creation Time: %s\n ", PREFIX_MENU, BugData.reporter_name, BugData.reporter_auth_id, BugData.bug_context, item_display);
	
	menu.AddItem(BugData.bug_unique, "Print Bug Details");
	menu.AddItem("", "Resolve Bug");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_BugDetail(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[8];
		menu.GetItem(0, item_info, sizeof(item_info));
		int bug_index = GetBugByUnique(item_info);
		
		// Make sure the server bug is still valid
		if (bug_index == -1)
		{
			// Notify the client
			PrintToChat(client, "%s The specified server bug is no logner valid.", PREFIX_ERROR);
			
			// Display the list menu again
			ShowBugsListMenu(client);
			
			return 0;
		}
		
		// Initialize the bug data struct by the given index
		Bug BugData; BugData = GetBugByIndex(bug_index);
		
		switch (item_position)
		{
			case 0:
			{
				// Print the bug details
				PrintToChat(client, " \x02Bug Reporter Name:\x01 %s", BugData.reporter_name);
				PrintToChat(client, " \x02Bug Reporter Auth ID:\x01 %s", BugData.reporter_auth_id);
				PrintToChat(client, " \x02Bug Context:\x01 %s", BugData.bug_context);
				
				// Display the same menu again
				ShowBugDetailMenu(client, bug_index);
			}
			case 1:
			{
				// Delete the bug from the config file
				KV_DeleteBug(bug_index);
				
				// Notify the client
				PrintToChat(client, "%s Successfully resolved \x04%s's\x01 bug report. (\x02#%d\x01)", PREFIX, BugData.reporter_name, bug_index + 1);
				
				// If the reporter index is in-game, notify him as well
				int reporter_index = GetClientFromAuthID(BugData.reporter_auth_id);
				
				if (reporter_index != -1)
				{
					PrintToChat(reporter_index, "%s One of your bug reports has been successfully resolved! Thanks for helping the server to grow up (:", PREFIX);
				}
				
				// Display the bugs list menu
				ShowBugsListMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Display the last menu the client was in
		ShowBugsListMenu(param1);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Key Values ]================================//

void KV_LoadServerBugs()
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to locate file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Bugs");
	kv.ImportFromFile(CONFIG_PATH);
	
	g_BugsData.Clear();
	
	if (kv.GotoFirstSubKey())
	{
		Bug CurrentBugData;
		
		do {
			kv.GetString("ReporterName", CurrentBugData.reporter_name, sizeof(CurrentBugData.reporter_name));
			kv.GetString("ReporterAuthID", CurrentBugData.reporter_auth_id, sizeof(CurrentBugData.reporter_auth_id));
			kv.GetString("BugContext", CurrentBugData.bug_context, sizeof(CurrentBugData.bug_context));
			kv.GetString("BugUnique", CurrentBugData.bug_unique, sizeof(CurrentBugData.bug_unique));
			CurrentBugData.create_unixstamp = kv.GetNum("CreateUnixStamp");
			
			g_BugsData.PushArray(CurrentBugData);
		} while (kv.GotoNextKey());
	}
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_AddBugReport(int bug_index)
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Bugs");
	kv.ImportFromFile(CONFIG_PATH);
	
	Bug BugData; BugData = GetBugByIndex(bug_index);
	
	char key[4];
	IntToString(bug_index, key, sizeof(key));
	
	kv.JumpToKey(key, true);
	
	kv.SetString("ReporterName", BugData.reporter_name);
	kv.SetString("ReporterAuthID", BugData.reporter_auth_id);
	kv.SetString("BugContext", BugData.bug_context);
	kv.SetString("BugUnique", BugData.bug_unique);
	kv.SetNum("CreateUnixStamp", BugData.create_unixstamp);
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_DeleteBug(int bug_index)
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Bugs");
	kv.ImportFromFile(CONFIG_PATH);
	
	char key[4];
	
	IntToString(bug_index, key, sizeof(key));
	
	if (kv.JumpToKey(key))
	{
		kv.DeleteThis();
		kv.Rewind();
	}
	
	g_BugsData.Erase(bug_index);
	
	int start_position = bug_index;
	
	kv.GotoFirstSubKey();
	
	do {
		kv.GetSectionName(key, sizeof(key));
		
		if (StringToInt(key) < bug_index)
		{
			continue;
		}
		
		IntToString(start_position, key, sizeof(key));
		kv.SetSectionName(key);
		
		start_position++;
	} while (kv.GotoNextKey());
	
	kv.Rewind();
	
	// In case it will be changed by the index fixer
	kv.SetSectionName("Bugs");
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

//================================[ Functions ]================================//

any[] GetBugByIndex(int index)
{
	Bug BugData;
	g_BugsData.GetArray(index, BugData);
	return BugData;
}

int GetBugByUnique(const char[] unique)
{
	return g_BugsData.FindString(unique);
}

int GetClientFromAuthID(const char[] auth_id)
{
	char current_auth_id[32];
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && GetClientAuthId(current_client, AuthId_Steam2, current_auth_id, sizeof(current_auth_id)) && StrEqual(current_auth_id, auth_id))
		{
			return current_client;
		}
	}
	
	return -1;
}

char[] GetRandomString(char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789")
{
	char randomized_string[8];
	
	for (int current_char = 0; current_char < sizeof(randomized_string); current_char++)
	{
		Format(randomized_string, sizeof(randomized_string), "%s%c", randomized_string, chars[GetRandomInt(0, strlen(chars) - 1)]);
	}
	
	return randomized_string;
}

//================================================================//