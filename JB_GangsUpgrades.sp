#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GangsSystem>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define ITEM_POSITION 3
#define DEFAULT_LEVEL 0

//====================//

enum struct Upgrade
{
	char upgrade_unique[32];
	char upgrade_name[64];
	char upgrade_desc[128];
	
	ArrayList levels_prices;
	
	void InitLevels()
	{
		delete this.levels_prices;
		this.levels_prices = new ArrayList();
	}
}

ArrayList g_UpgradesData;

enum struct Gang
{
	char szName[64];
	ArrayList UpgradesLevel;
	
	void Reset()
	{
		this.szName[0] = '\0';
		this.Init();
	}
	
	void Init()
	{
		delete this.UpgradesLevel;
		this.UpgradesLevel = new ArrayList();
		
		for (int current_upgrade = 0; current_upgrade < g_UpgradesData.Length; current_upgrade++)
		{
			this.UpgradesLevel.Push(DEFAULT_LEVEL);
		}
	}
}

ArrayList g_GangsData;

Database g_Database = null;

GlobalForward g_fwdOnUpgradeUpgraded;
GlobalForward g_fwdOnUpgradeToggle;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Gangs Upgrades", 
	author = PLUGIN_AUTHOR, 
	description = "Additional perks feature for the gangs system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_UpgradesData = new ArrayList(sizeof(Upgrade));
	g_GangsData = new ArrayList(sizeof(Gang));
}

//================================[ Events ]================================//

public void Gangs_GangsLoaded(Database db, int gangs_count)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	SQL_AfterGangsLoaded(gangs_count);
}

public void Gangs_OnGangCreate(int gangId)
{
	Gang GangData;
	GangData.Init();
	
	char szGangName[128];
	Gangs_GetGangName(gangId, szGangName, sizeof(szGangName));
	
	if (szGangName[0] != '\0')
	{
		strcopy(GangData.szName, sizeof(GangData.szName), szGangName);
		g_GangsData.PushArray(GangData, sizeof(GangData));
	}
}

public void Gangs_OnGangDelete(int gangId, char[] name)
{
	if (g_GangsData.Length > gangId)
	{
		g_GangsData.Erase(gangId);
	}
}

public void Gangs_GangNameUpdated(int gang, char[] oldName, char[] newName)
{
	Gang gang_data; gang_data = GetGangByIndex(gang);
	strcopy(gang_data.szName, sizeof(gang_data.szName), newName);
	g_GangsData.SetArray(gang, gang_data);
}

public void Gangs_GangsUserOpenMainMenu(int client, Menu menu)
{
	menu.InsertItem(ITEM_POSITION, "gangupgrades", "Gang Upgrades", Gangs_GetPlayerGang(client) != NO_GANG ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
}

public void Gangs_GangsUserPressMainMenu(int client, char[] itemInfo)
{
	if (StrEqual(itemInfo, "gangupgrades"))
	{
		showGangUpgradesMenu(client, Gangs_GetPlayerGang(client));
	}
}

public void Gangs_GangsUserOpenGangDetails(int client, Menu menu)
{
	menu.AddItem("gangupgrades", "Gang Upgrades");
}

public void Gangs_GangsUserPressGangDetails(int client, int gangId, char[] itemInfo)
{
	if (StrEqual(itemInfo, "gangupgrades"))
	{
		showGangUpgradesMenu(client, gangId);
	}
}

//================================[ Menus ]================================//

void showGangUpgradesMenu(int client, int gangId, int upgradeIndex = 0)
{
	char szGangName[128], szItem[128], szItemInfo[16];
	Gangs_GetGangName(gangId, szGangName, sizeof(szGangName));
	RTLify(szGangName, sizeof(szGangName), szGangName);
	
	Menu menu = new Menu(Handler_GangUpgrades);
	menu.SetTitle("%s Gangs Menu - %s's Gang Upgrades\n• Gang Bank: %s\n ", PREFIX_MENU, szGangName, JB_AddCommas(Gangs_GetGangCash(gangId)));
	
	Upgrade UpgradeData; UpgradeData = GetUpgradeByIndex(upgradeIndex);
	Gang GangData; GangData = GetGangByIndex(gangId);
	
	int iGangLevel = GangData.UpgradesLevel.Get(upgradeIndex);
	
	IntToString(upgradeIndex, szItemInfo, sizeof(szItemInfo));
	Format(szItem, sizeof(szItem), "Upgrade - %s (%d/%d)\n• %s", UpgradeData.upgrade_name, iGangLevel, UpgradeData.levels_prices.Length, UpgradeData.upgrade_desc);
	menu.AddItem(szItemInfo, szItem);
	
	IntToString(gangId, szItemInfo, sizeof(szItemInfo));
	
	if (iGangLevel < UpgradeData.levels_prices.Length)
	{
		Format(szItem, sizeof(szItem), "%s Cash", JB_AddCommas(UpgradeData.levels_prices.Get(iGangLevel)));
	}
	
	Format(szItem, sizeof(szItem), "Upgrade! (%s)", iGangLevel >= UpgradeData.levels_prices.Length ? "Max Level Reached" : szItem);
	menu.AddItem(szItemInfo, szItem, Gangs_GetPlayerGang(client) == gangId && Gangs_GetPlayerGangRank(client) > Rank_Manager && iGangLevel < UpgradeData.levels_prices.Length ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_GangUpgrades(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[128];
		menu.GetItem(0, szItem, sizeof(szItem));
		int iUpgradeIndex = StringToInt(szItem);
		menu.GetItem(1, szItem, sizeof(szItem));
		int iGangIndex = StringToInt(szItem);
		
		switch (itemNum)
		{
			case 0:
			{
				iUpgradeIndex = ++iUpgradeIndex % g_UpgradesData.Length;
				showGangUpgradesMenu(client, iGangIndex, iUpgradeIndex);
			}
			case 1:
			{
				Upgrade UpgradeData; UpgradeData = GetUpgradeByIndex(iUpgradeIndex);
				Gang GangData; GangData = GetGangByIndex(iGangIndex);
				
				int iUpgradeLevel = GangData.UpgradesLevel.Get(iUpgradeIndex);
				int iUpgradePrice = UpgradeData.levels_prices.Get(iUpgradeLevel);
				
				int iClientGangRank = Gangs_GetPlayerGangRank(client);
				
				if (iClientGangRank > Rank_Manager)
				{
					if (Gangs_GetGangCash(iGangIndex) < iUpgradePrice)
					{
						PrintToChat(client, "%s Your gang doesn't have enough bank cash. (missing \x02%s\x01).", PREFIX_ERROR, JB_AddCommas(iUpgradePrice - Gangs_GetGangCash(iGangIndex)));
						return;
					}
					
					if (iUpgradeLevel == UpgradeData.levels_prices.Length)
					{
						PrintToChat(client, "%s The gang upgrade is already at the maximum level.", PREFIX_ERROR);
						return;
					}
					
					Gangs_SetGangCash(iGangIndex, Gangs_GetGangCash(iGangIndex) - iUpgradePrice);
					
					GangData.UpgradesLevel.Set(iUpgradeIndex, iUpgradeLevel + 1);
					g_GangsData.SetArray(iGangIndex, GangData, sizeof(GangData));
					
					SQL_UpdateUpgradeLevel(iGangIndex, iUpgradeIndex);
					
					showGangUpgradesMenu(client, iGangIndex, iUpgradeIndex);
					
					Format(szItem, sizeof(szItem), "\x10%s\x01 has been upgraded by \x04%N\x01 to level \x07%d\x01!", UpgradeData.upgrade_name, client, iUpgradeLevel + 1);
					Gangs_SendMessageToGang(iGangIndex, szItem);
					
					Gangs_GetGangName(iGangIndex, szItem, sizeof(szItem));
					JB_WriteLogLine("\"%L\" has upgraded their %s: %s, payed: %s", client, UpgradeData.upgrade_name, szItem, JB_AddCommas(iUpgradePrice));
					
					Call_StartForward(g_fwdOnUpgradeUpgraded);
					Call_PushCell(client);
					Call_PushCell(iUpgradeIndex);
					Call_PushCell(iUpgradeLevel + 1);
					Call_Finish();
				}
			}
		}
	}
	else if (action == MenuAction_Cancel) {
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack) {
			Gangs_ShowMainMenu(client);
		}
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateGangUpgrade", Native_CreateGangUpgrade);
	CreateNative("JB_CreateGangUpgradeLevel", Native_CreateGangUpgradeLevel);
	CreateNative("JB_GetGangUpgradeLevel", Native_GetGangUpgradeLevel);
	CreateNative("JB_FindGangUpgrade", Native_FindGangUpgrade);
	CreateNative("JB_ToggleGangUpgrade", Native_ToggleGangUpgrade);
	
	g_fwdOnUpgradeUpgraded = new GlobalForward("JB_OnUpgradeUpgraded", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnUpgradeToggle = new GlobalForward("JB_OnUpgradeToggle", ET_Event, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_GangsUpgrades");
	return APLRes_Success;
}

public int Native_CreateGangUpgrade(Handle plugin, int numParams)
{
	// Create the upgrade data struct
	Upgrade UpgradeData;
	UpgradeData.InitLevels();
	
	GetNativeString(1, UpgradeData.upgrade_unique, sizeof(UpgradeData.upgrade_unique));
	
	// If any upgrade with the given unique string is already exists, return the existing index
	int upgrade_index = GetUpgradeByUnique(UpgradeData.upgrade_unique);
	if (upgrade_index != -1)
	{
		return upgrade_index;
	}
	
	// Initialize the upgrade data
	GetNativeString(2, UpgradeData.upgrade_name, sizeof(UpgradeData.upgrade_name));
	GetNativeString(3, UpgradeData.upgrade_desc, sizeof(UpgradeData.upgrade_desc));
	
	// Store the upgrade data struct inside the global upgrades arraylist
	return g_UpgradesData.PushArray(UpgradeData);
}

public int Native_CreateGangUpgradeLevel(Handle plugin, int numParams)
{
	int upgrade_index = GetNativeCell(1);
	
	if (!(0 <= upgrade_index < g_UpgradesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid upgrade index (Got: %d | Max: %d)", upgrade_index, g_UpgradesData.Length);
	}
	
	int level_price = GetNativeCell(2);
	
	if (level_price < 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid upgrade level price, must be over 0!");
	}
	
	return GetUpgradeByIndex(upgrade_index).levels_prices.Push(level_price);
}

public int Native_GetGangUpgradeLevel(Handle plugin, int numParams)
{
	int iGangIndex = GetNativeCell(1);
	if (iGangIndex < 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang index (Get: %d | Max: %d)", iGangIndex, MAX_GANGS);
	}
	
	int iUpgradeIndex = GetNativeCell(2);
	if (!(0 <= iUpgradeIndex < g_UpgradesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid upgrade index (Get: %d | Max: %d)", iUpgradeIndex, g_UpgradesData.Length);
	}
	
	return GetGangByIndex(iGangIndex).UpgradesLevel.Get(iUpgradeIndex);
}

public int Native_FindGangUpgrade(Handle plugin, int numParams)
{
	char upgrade_unique[32];
	GetNativeString(1, upgrade_unique, sizeof(upgrade_unique));
	return GetUpgradeByUnique(upgrade_unique);
}

public int Native_ToggleGangUpgrade(Handle plugin, int numParams)
{
	int iUpgradeIndex = GetNativeCell(1);
	
	if (!(0 <= iUpgradeIndex < g_UpgradesData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified upgrade index (Get: %d | Max: %d)", iUpgradeIndex, g_UpgradesData.Length);
	}
	
	bool bToggleMode = GetNativeCell(2);
	
	Call_StartForward(g_fwdOnUpgradeToggle);
	Call_PushCell(iUpgradeIndex);
	Call_PushCell(bToggleMode);
	Call_Finish();
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	
	JB_WriteLogLine("Gang upgrade toggle has \"%s\" has changed to mode %s by plugin \"%s\"", GetUpgradeByIndex(iUpgradeIndex).upgrade_name, bToggleMode ? "True":"False", szFileName);
	return true;
}

//================================[ Database ]================================//

void SQL_AfterGangsLoaded(int gangsCount)
{
	char szName[64];
	for (int iCurrentUpgrade = 0; iCurrentUpgrade < g_UpgradesData.Length; iCurrentUpgrade++)
	{
		FormatEx(szName, sizeof(szName), "upgrade_%s", GetUpgradeByIndex(iCurrentUpgrade).upgrade_unique);
		Gangs_CreateDBColumn(szName, "INT", "0");
	}
	
	g_GangsData.Clear();
	
	for (int iCurrentGang = 0; iCurrentGang < gangsCount; iCurrentGang++)
	{
		Gang CurrentGangData;
		CurrentGangData.Init();
		Gangs_GetGangName(iCurrentGang, szName, sizeof(szName));
		
		if (szName[0] != '\0')
		{
			strcopy(CurrentGangData.szName, sizeof(CurrentGangData.szName), szName);
			g_GangsData.PushArray(CurrentGangData);
			SQL_FetchGang(iCurrentGang);
		}
	}
}

void SQL_FetchGang(int gangId)
{
	char szQuery[256];
	
	for (int iCurrentUpgrade = 0; iCurrentUpgrade < g_UpgradesData.Length; iCurrentUpgrade++)
	{
		FormatEx(szQuery, sizeof(szQuery), "%s%s`upgrade_%s`", szQuery, !iCurrentUpgrade ? "":", ", GetUpgradeByIndex(iCurrentUpgrade).upgrade_unique);
	}
	
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT %s FROM `jb_gangs` WHERE `name` = '%s'", szQuery, GetGangByIndex(gangId).szName);
	g_Database.Query(SQL_FetchGang_CB, szQuery, gangId);
}

public void SQL_FetchGang_CB(Database db, DBResultSet results, const char[] error, int gangId)
{
	if (results.FetchRow())
	{
		Gang GangData; GangData = GetGangByIndex(gangId);
		
		for (int iCurrentUpgrade = 0; iCurrentUpgrade < g_UpgradesData.Length; iCurrentUpgrade++)
		{
			GangData.UpgradesLevel.Set(iCurrentUpgrade, results.FetchInt(iCurrentUpgrade));
		}
		
		g_GangsData.SetArray(gangId, GangData);
	}
}

void SQL_UpdateUpgradeLevel(int gangId, int upgradeId)
{
	char szQuery[256];
	Gang GangData; GangData = GetGangByIndex(gangId);
	g_Database.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `upgrade_%s` = %d WHERE `name` = '%s'", GetUpgradeByIndex(upgradeId).upgrade_unique, GangData.UpgradesLevel.Get(upgradeId), GangData.szName);
	g_Database.Query(SQL_CheckForErrors, szQuery);
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

//================================[ Functions ]================================//

int GetUpgradeByUnique(const char[] unique)
{
	return g_UpgradesData.FindString(unique);
}

any[] GetUpgradeByIndex(int index)
{
	Upgrade UpgradeData;
	g_UpgradesData.GetArray(index, UpgradeData);
	return UpgradeData;
}

any[] GetGangByIndex(int index)
{
	Gang GangData;
	g_GangsData.GetArray(index, GangData);
	return GangData;
}

//================================================================//