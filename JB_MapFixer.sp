#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <JailBreak>
#include <JB_MapFixer>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define ABORT_SYMBOL "-1"

//====================//

enum struct Setting
{
	char szUnique[64];
	char szName[128];
	FixerType iType;
	AdminFlag iAdminFlags;
	any minValue;
	any maxValue;
	any value;
}

ArrayList g_SettingsData;

Database g_Database = null;

GlobalForward g_fwdOnMapFixerChange;

char g_CurrentMapName[128];

int g_iEditSettingId[MAXPLAYERS + 1] =  { -1, ... };

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Map Fixer", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the settings arraylist
	g_SettingsData = new ArrayList(sizeof(Setting));
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null) {
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Admin Commands
	RegAdminCmd("sm_mapfixer", Command_MapFixer, ADMFLAG_BAN, "Access the Map Fixer settings menu.");
	RegAdminCmd("sm_mf", Command_MapFixer, ADMFLAG_BAN, "Access the Map Fixer settings menu. (An Alias)");
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	g_iEditSettingId[client] = -1;
}

public void OnMapStart()
{
	// Initialize the current map name
	GetCurrentMap(g_CurrentMapName, sizeof(g_CurrentMapName));
	
	if (!g_Database)
	{
		return;
	}
	
	// Fetch the current map
	SQL_FetchMap();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// If the client is not in edit state mode, dont continue
	if (g_iEditSettingId[client] == -1)
	{
		return Plugin_Continue;
	}
	
	// If the client wants to abort the current action, abort it
	if (StrEqual(sArgs, ABORT_SYMBOL))
	{
		// Notify client
		PrintToChat(client, "%s Operation aborted.", PREFIX);
		
		// Display the map fixer menu again
		ShowMapFixerMenu(client);
		
		// Send the client edit state global varibale as -1
		g_iEditSettingId[client] = -1;
		return Plugin_Handled;
	}
	
	int setting_value = StringToInt(sArgs);
	Setting SettingData; SettingData = GetSettingByIndex(g_iEditSettingId[client]);
	
	// Make sure the setting value is in the right range
	if (!(SettingData.minValue <= setting_value <= SettingData.maxValue))
	{
		PrintToChat(client, "%s Setting value is out of bounds. [\x02%d - %d\x01]", PREFIX_ERROR, SettingData.minValue, SettingData.maxValue);
		return Plugin_Handled;
	}
	
	// Set the edited setting value
	SetSettingValue(client, g_iEditSettingId[client], setting_value);
	
	ShowMapFixerMenu(client);
	g_iEditSettingId[client] = -1;
	return Plugin_Handled;
}

//================================[ Commands ]================================//

public Action Command_MapFixer(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char name_arg[MAX_NAME_LENGTH];
		GetCmdArg(1, name_arg, sizeof(name_arg));
		int target_index = FindTarget(client, name_arg, true, false);
		
		if (target_index == -1) {
			// Automated message
			return Plugin_Handled;
		}
		
		if (GetUserAdmin(target_index) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s Map Fixer menu allowed for administrators only.", PREFIX_ERROR);
		} else {
			ShowMapFixerMenu(target_index);
		}
	}
	else {
		ShowMapFixerMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowMapFixerMenu(int client)
{
	char item_display[64], item_info[4];
	
	Menu menu = new Menu(Handler_MapFixer);
	menu.SetTitle("%s Map Fixer Menu:\n• %s\n ", PREFIX_MENU, g_CurrentMapName);
	menu.AddItem("", "Save Settings\n ");
	
	Setting CurrentSettingData;
	
	for (int current_setting = 0; current_setting < g_SettingsData.Length; current_setting++)
	{
		CurrentSettingData = GetSettingByIndex(current_setting);
		
		switch (CurrentSettingData.iType)
		{
			case Fixer_Int : IntToString(CurrentSettingData.value, item_display, sizeof(item_display));
			case Fixer_Float : Format(item_display, sizeof(item_display), "%.2f", CurrentSettingData.value);
			case Fixer_Bool : Format(item_display, sizeof(item_display), "%s", CurrentSettingData.value == 1 ? "ON" : "OFF");
		}
		
		Format(item_display, sizeof(item_display), "%s - %s", CurrentSettingData.szName, item_display);
		
		// Convert the current setting index into a string, and insert the item to the menu
		IntToString(current_setting, item_info, sizeof(item_info));
		menu.AddItem(item_info, item_display, GetAdminFlag(GetUserAdmin(client), CurrentSettingData.iAdminFlags) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	// If no mapfixer settings exists, add an extra menu item and notify the client
	if (!g_SettingsData.Length)
	{
		menu.AddItem("", "No map fixer setting was found.", ITEMDRAW_DISABLED);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_MapFixer(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				SQL_UpdateSettings();
				PrintToChat(client, "%s Successfully updated the mapfixer settings for map \"%s\".", PREFIX, g_CurrentMapName);
			}
			default:
			{
				char item_info[4];
				menu.GetItem(itemNum, item_info, sizeof(item_info));
				PerformFixerValueChange(client, StringToInt(item_info));
			}
		}
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateMapFixer", Native_CreateMapFixer);
	CreateNative("JB_GetMapFixer", Native_GetMapFixer);
	CreateNative("JB_FindMapFixer", Native_FindMapFixer);
	
	g_fwdOnMapFixerChange = new GlobalForward("JB_OnMapFixerChange", ET_Event, Param_Cell, Param_Cell, Param_CellByRef, Param_CellByRef);
	
	RegPluginLibrary("JB_MapFixer");
	return APLRes_Success;
}

public int Native_CreateMapFixer(Handle plugin, int numParams)
{
	Setting SettingData;
	GetNativeString(1, SettingData.szUnique, sizeof(SettingData.szUnique));
	
	int setting_index = GetSettingByUnique(SettingData.szUnique);
	if (setting_index != -1) {
		return setting_index;
	}
	
	GetNativeString(2, SettingData.szName, sizeof(SettingData.szName));
	SettingData.iType = view_as<FixerType>(GetNativeCell(3));
	SettingData.iAdminFlags = view_as<AdminFlag>(GetNativeCell(4));
	SettingData.minValue = GetNativeCell(5);
	SettingData.maxValue = GetNativeCell(6);
	SettingData.value = GetNativeCell(7);
	
	return g_SettingsData.PushArray(SettingData);
}

public any Native_GetMapFixer(Handle plugin, int numParams)
{
	// Get and verify the setting index
	int setting_index = GetNativeCell(1);
	
	if (!(0 <= setting_index < g_SettingsData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified setting index. (Got: %d, Max: %d)", setting_index, g_SettingsData.Length);
	}
	
	return GetSettingByIndex(setting_index).value;
}

public int Native_FindMapFixer(Handle plugin, int numParams)
{
	char setting_unique[64];
	GetNativeString(1, setting_unique, sizeof(setting_unique));
	
	// Return the setting index, by the specified setting unique
	return GetSettingByUnique(setting_unique);
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	
	g_Database = view_as<Database>(CloneHandle(db));
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `csgo_mapfixer` (`map` VARCHAR(128) NOT NULL , `unique` VARCHAR(128) NOT NULL, `value` INT NOT NULL, UNIQUE(`map`, `unique`))");
	
	SQL_FetchMap();
}

void SQL_FetchMap()
{
	char szQuery[256];
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `csgo_mapfixer` WHERE `map` = '%s'", g_CurrentMapName);
	g_Database.Query(SQL_FetchMap_CB, szQuery);
}

public void SQL_FetchMap_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	char setting_unique[64];
	int setting_index = -1;
	
	Setting SettingData;
	
	while (results.FetchRow())
	{
		results.FetchString(1, setting_unique, sizeof(setting_unique));
		
		setting_index = GetSettingByUnique(setting_unique);
		
		// Make sure the index is valid
		if (setting_index != -1)
		{
			// Initialize the setting data struct
			SettingData = GetSettingByIndex(setting_index);
			
			// Fetch the value and update it inside the arraylist
			SettingData.value = results.FetchInt(2);
			g_SettingsData.SetArray(setting_index, SettingData);
		}
	}
}

void SQL_UpdateSettings()
{
	char szQuery[256];
	
	for (int current_setting = 0; current_setting < g_SettingsData.Length; current_setting++)
	{
		g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `csgo_mapfixer` WHERE `map` = '%s' AND `unique` = '%s'", g_CurrentMapName, GetSettingByIndex(current_setting).szUnique);
		g_Database.Query(SQL_UpdateSettings_CB, szQuery, current_setting);
	}
}

public void SQL_UpdateSettings_CB(Database db, DBResultSet results, const char[] error, int settingId)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	Setting SettingData; SettingData = GetSettingByIndex(settingId);
	
	char szQuery[256];
	
	if (results.FetchRow()) {
		g_Database.Format(szQuery, sizeof(szQuery), "UPDATE `csgo_mapfixer` SET `value` = %d WHERE `map` = '%s' AND `unique` = '%s'", SettingData.value, g_CurrentMapName, SettingData.szUnique);
	} else {
		g_Database.Format(szQuery, sizeof(szQuery), "INSERT INTO `csgo_mapfixer` (`map`, `unique`, `value`) VALUES ('%s', '%s', %d)", g_CurrentMapName, SettingData.szUnique, SettingData.value);
	}
	
	g_Database.Query(SQL_CheckForErrors, szQuery);
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
}

//================================[ Functions ]================================//

int GetSettingByUnique(const char[] unique)
{
	return g_SettingsData.FindString(unique);
}

any[] GetSettingByIndex(int index)
{
	Setting SettingData;
	g_SettingsData.GetArray(index, SettingData);
	return SettingData;
}

void PerformFixerValueChange(int client, int settingId)
{
	Setting SettingData; SettingData = GetSettingByIndex(settingId);
	
	switch (SettingData.iType)
	{
		case Fixer_Bool:
		{
			// Set the new changed setting value
			SetSettingValue(client, settingId, !SettingData.value);
			
			// Display the menu again
			ShowMapFixerMenu(client);
		}
		default:
		{
			// Notify client
			PrintToChat(client, "%s Type your desired \x0Cfixer\x01 value, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			
			// Change the client setting edit state
			g_iEditSettingId[client] = settingId;
		}
	}
}

bool SetSettingValue(int client, int settingId, any value)
{
	Setting SettingData; SettingData = GetSettingByIndex(settingId);
	
	Action fwdReturn;
	
	//==== [ Execute the rune pickup forward ] =====//
	Call_StartForward(g_fwdOnMapFixerChange);
	Call_PushCell(client); // int client
	Call_PushCell(settingId); // int settingId
	Call_PushCellRef(SettingData.value); // int &oldValue
	Call_PushCellRef(value); // int &newValue
	
	int iError = Call_Finish(fwdReturn);
	
	// Check for forward failure
	if (iError != SP_ERROR_NONE)
	{
		ThrowNativeError(iError, "Map Fixer Forward Failed - Error: %d", iError);
		return false;
	}
	
	// If the forward return is higher then Plugin_Handled, stop the further actions
	if (fwdReturn >= Plugin_Handled)
	{
		return false;
	}
	
	SettingData.value = value;
	
	// Update the edited setting data struct
	g_SettingsData.SetArray(settingId, SettingData);
	
	return true;
}

//================================================================//