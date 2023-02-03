#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_TopSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define CONFIG_PATH "addons/sourcemod/configs/TopData.cfg"

//====================//

enum struct LastWinner
{
	char szAuth[64];
	char szName[MAX_NAME_LENGTH];
}

enum struct SQLData
{
	char szName[MAX_NAME_LENGTH];
	int iPoints;
}

enum struct Top
{
	LastWinner WinnerData;
	
	char szUnique[128];
	char szName[128];
	char szDesc[256];
	char szCounter[32];
	int iDefaultPoints;
}

ArrayList g_arTopsData;

ConVar g_cvCategoriesStartPoints;

enum struct Client
{
	char szAuth[32];
	char szName[MAX_NAME_LENGTH];
	ArrayList Points;
	
	void Reset() {
		this.szAuth[0] = '\0';
		this.szName[0] = '\0';
		
		this.Init();
	}
	
	void Init() {
		delete this.Points;
		this.Points = new ArrayList();
		
		for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++) {
			this.Points.Push(g_cvCategoriesStartPoints.IntValue);
		}
	}
}

Client g_esClientData[MAXPLAYERS + 1];

Database g_Database = null;

GlobalForward g_fwdOnTopCategoryReset;

ConVar g_cvTopClientsAmount;
ConVar g_cvDaysUntilReset;
ConVar g_cvPrintProgressMessages;

char g_szAuthorizedGroups[][] = 
{
	"Programmer", 
	"Main Programmer", 
	"Sub Manager", 
	"Manager", 
	"Sub Owner", 
	"Owner"
};

int g_iResetTime;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Top System", 
	author = PLUGIN_AUTHOR, 
	description = "Provides a generic top system, with special feature to automatically reset the top statistics every certain time.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the tops arraylist
	g_arTopsData = new ArrayList(sizeof(Top));
	
	// Configurate ConVars
	g_cvTopClientsAmount = CreateConVar("top_show_clients_amount", "50", "Amount of clients that will be shown on the quests menu.", _, true, 1.0, true, 100.0);
	g_cvDaysUntilReset = CreateConVar("top_days_until_reset", "0", "Amount of days until every top category resets, 0 to disable the reset.", _, true, 0.0, true, 90.0);
	g_cvPrintProgressMessages = CreateConVar("top_print_progress_messages", "0", "If true, every progress change will be print with a chat message, 0 To disable the print.", _, true, 0.0, true, 1.0);
	g_cvCategoriesStartPoints = CreateConVar("top_categories_start_points", "0", "Starting points to set for every category once its created.");
	
	// Store the ConVars values inside an automatic config file
	AutoExecConfig(true, "TopSystem", "JailBreak");
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null) {
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Client Commands
	RegConsoleCmd("sm_tops", Command_Tops, "Access the tops categories list menu.");
	RegConsoleCmd("sm_top", Command_Tops, "Access the tops categories list menu. (An Alias)");
	
	// Build and setup the path to the Key Values file
	char szDirPath[PLATFORM_MAX_PATH];
	strcopy(szDirPath, sizeof(szDirPath), CONFIG_PATH);
	BuildPath(Path_SM, szDirPath, sizeof(szDirPath), szDirPath[17]);
	delete OpenFile(szDirPath, "a+");
}

public void OnPluginEnd()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			OnClientDisconnect(iCurrentClient);
		}
	}
}

//================================[ Events ]================================//

public void OnMapStart()
{
	if (g_cvDaysUntilReset.IntValue)
	{
		// Load and save the tops data from the Key Values file
		KV_LoadTops();
		
		// If we couldn't get the reset time, initialize the time itself. else, reset the tops!
		if (!g_iResetTime) {
			KV_InitData();
		}
		else if (g_iResetTime <= GetTime()) {
			for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
			{
				ResetTop(-1, iCurrentTop);
			}
		}
	}
}

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_esClientData[client].Reset();
	
	if (!IsFakeClient(client))
	{
		if (!GetClientAuthId(client, AuthId_Steam2, g_esClientData[client].szAuth, sizeof(g_esClientData[].szAuth)))
		{
			KickClient(client, "Verification error, please reconnect.");
			return;
		}
		
		GetClientName(client, g_esClientData[client].szName, sizeof(g_esClientData[].szName));
		SQL_FetchClient(client);
	}
}

public void OnClientDisconnect(int client)
{
	if (!IsFakeClient(client))
	{
		// Save the client top statistics in the database
		SQL_UpdateClient(client);
	}
}

//================================[ Commands ]================================//

public Action Command_Tops(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1) {
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		showTopsMainMenu(iTargetIndex);
	}
	else {
		showTopsMainMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateTopCategory", Native_CreateTopCategory);
	CreateNative("JB_FindTopCategory", Native_FindTopCategory);
	CreateNative("JB_GetTopPoints", Native_GetTopPoints);
	CreateNative("JB_AddTopPoints", Native_AddTopPoints);
	CreateNative("JB_TakeTopPoints", Native_TakeTopPoints);
	CreateNative("JB_ShowTopCategoryMenu", Native_ShowTopCategoryMenu);
	
	g_fwdOnTopCategoryReset = CreateGlobalForward("JB_OnTopCategoryReset", ET_Event, Param_Cell);
	
	RegPluginLibrary("JB_TopSystem");
	return APLRes_Success;
}

public int Native_CreateTopCategory(Handle plugin, int numParams)
{
	Top TopData;
	GetNativeString(1, TopData.szUnique, sizeof(TopData.szUnique));
	
	if (GetTopByUnique(TopData.szUnique) != -1)
	{
		return GetTopByUnique(TopData.szUnique);
	}
	
	GetNativeString(2, TopData.szName, sizeof(TopData.szName));
	GetNativeString(3, TopData.szDesc, sizeof(TopData.szDesc));
	GetNativeString(4, TopData.szCounter, sizeof(TopData.szCounter));
	TopData.iDefaultPoints = GetNativeCell(5);
	
	return g_arTopsData.PushArray(TopData, sizeof(TopData));
}

public int Native_FindTopCategory(Handle plugin, int numParams)
{
	char szUnique[64];
	GetNativeString(1, szUnique, sizeof(szUnique));
	return GetTopByUnique(szUnique);
}

public int Native_GetTopPoints(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the top category index
	int iTopId = GetNativeCell(2);
	
	if (!(0 <= iTopId < g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid top index (Got: %d, Max: %d)", iTopId, g_arTopsData.Length);
	}
	
	return g_esClientData[client].Points.Get(iTopId);
}

public int Native_GetCustomTopPoints(Handle plugin, int numParams)
{
	// Get and verify the contestant index
	int iContestantIndex = GetNativeCell(1);
	
	if (!(0 <= iContestantIndex <= g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid contestant index (%d)", iContestantIndex);
	}
	
	// Get and verify the top category index
	int iTopId = GetNativeCell(2);
	
	if (!(0 <= iTopId < g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid top index (Got: %d, Max: %d)", iTopId, g_arTopsData.Length);
	}
	
	return 0;
}

public int Native_AddTopPoints(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the top category index
	int iTopId = GetNativeCell(2);
	
	if (!(0 <= iTopId < g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid top index (Got: %d, Max: %d)", iTopId, g_arTopsData.Length);
	}
	
	// Get and verify the points amount
	int iPoints = GetNativeCell(3);
	
	if (iPoints <= 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid points amount (%d), must be over 0.", iPoints);
	}
	
	// Add the progress to the client data
	g_esClientData[client].Points.Set(iTopId, g_esClientData[client].Points.Get(iTopId) + iPoints);
	
	Top TopData; TopData = GetTopByIndex(iTopId);
	
	if (g_cvPrintProgressMessages.BoolValue && GetNativeCell(4)/* = bool broadcast */) {
		// Notify client
		PrintToChat(client, "%s You have gained \x04+%d\x01 points in \x0E%s\x01 top.", PREFIX, iPoints, TopData.szName);
	}
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("Points of \"%L\" in \"%s\" changed from %s to %s by plugin %s", client, TopData.szName, JB_AddCommas(g_esClientData[client].Points.Get(iTopId) - iPoints), JB_AddCommas(g_esClientData[client].Points.Get(iTopId)), szFileName);
	
	return 0;
}

public int Native_TakeTopPoints(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the top category index
	int iTopId = GetNativeCell(2);
	
	if (!(0 <= iTopId < g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid top index (Got: %d, Max: %d)", iTopId, g_arTopsData.Length);
	}
	
	// Get and verify the points amount
	int iPoints = GetNativeCell(3);
	
	if (iPoints <= 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid points amount (%d), must be over 0.", iPoints);
	}
	
	Top TopData; TopData = GetTopByIndex(iTopId);
	
	// Prevent the client points from being below 0
	if (g_esClientData[client].Points.Get(iTopId) - iPoints <= 0) {
		g_esClientData[client].Points.Set(iTopId, 0);
		return 0;
	}
	
	// Remove the progress from the client data
	g_esClientData[client].Points.Set(iTopId, g_esClientData[client].Points.Get(iTopId) - iPoints);
	
	if (g_cvPrintProgressMessages.BoolValue && GetNativeCell(4)/* = bool broadcast */) {
		// Notify client
		PrintToChat(client, "%s You have lost \x02-%d\x01 points in \x0E%s\x01 top.", PREFIX, iPoints, TopData.szName);
	}
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("Points of \"%L\" in \"%s\" changed from %s to %s by plugin %s", client, TopData.szName, JB_AddCommas(g_esClientData[client].Points.Get(iTopId - iPoints)), JB_AddCommas(g_esClientData[client].Points.Get(iTopId)), szFileName);
	
	return 0;
}

public int Native_ShowTopCategoryMenu(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the top category index
	int iTopId = GetNativeCell(2);
	
	if (!(0 <= iTopId < g_arTopsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid top index (Got: %d, Max: %d)", iTopId, g_arTopsData.Length);
	}
	
	// Shrink the data into a datapack object
	DataPack dPack = new DataPack();
	dPack.WriteCell(GetClientSerial(client));
	dPack.WriteCell(iTopId);
	dPack.Reset();
	
	char szQuery[128];
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `top_stats` WHERE `unique` = '%s'", GetTopByIndex(iTopId).szUnique);
	g_Database.Query(SQL_TopMenu_CB, szQuery, dPack);
	
	return 0;
}

//================================[ Menus ]================================//

void showTopsMainMenu(int client)
{
	char szItem[64], szItemInfo[32];
	
	// Calculate the time until the next reset
	float fResetTime = (float(g_iResetTime) - float(GetTime())) / 86400.0;
	Format(szItemInfo, sizeof(szItemInfo), "%.1f Days", fResetTime);
	Format(szItem, sizeof(szItem), "• Resets In: %s\n ", fResetTime <= 0.09 ? "Next Map!":szItemInfo);
	
	Menu menu = new Menu(Handler_Tops);
	menu.SetTitle("%s Top System - Main Menu\n%s ", PREFIX_MENU, g_cvDaysUntilReset.IntValue ? szItem:"");
	
	// Loop through all the top categories, and add them into the menu
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		IntToString(iCurrentTop, szItemInfo, sizeof(szItemInfo));
		menu.AddItem(szItemInfo, GetTopByIndex(iCurrentTop).szName);
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No top category was found.\n ", ITEMDRAW_DISABLED);
	}
	
	Format(szItem, sizeof(szItem), "Last Top Winners%s", IsClientAllowed(client) ? "\n ":"");
	menu.AddItem("LastWinners", szItem, g_cvDaysUntilReset.IntValue != 0 ? ITEMDRAW_DEFAULT:ITEMDRAW_IGNORE);
	
	// Option for root administrators to reset a certain top category
	menu.AddItem("ResetTop", "Reset A Top", IsClientAllowed(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
	// Display the menu
	menu.Display(client, MENU_TIME_FOREVER);
}

public void SQL_TopMenu_CB(Database db, DBResultSet results, const char[] error, DataPack dPack)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(dPack.ReadCell());
	
	if (!client)
	{
		return;
	}
	
	int iTopId = dPack.ReadCell();
	dPack.Close();
	
	Top TopData; TopData = GetTopByIndex(iTopId);
	
	char szItem[64], szItemInfo[8];
	Menu menu = new Menu(Handler_Tops);
	menu.SetTitle("%s Top System - Viewing %s \n• Description: %s \n• My Progress: %s %s\n ", PREFIX_MENU, 
		TopData.szName, 
		TopData.szDesc, 
		JB_AddCommas(g_esClientData[client].Points.Get(iTopId)), 
		TopData.szCounter
		);
	
	char szAuth[64];
	
	ArrayList arSortedTops = new ArrayList(sizeof(SQLData));
	
	SQLData CurrentSQLData;
	
	while (results.FetchRow())
	{
		results.FetchString(0, szAuth, sizeof(szAuth));
		results.FetchString(1, CurrentSQLData.szName, sizeof(CurrentSQLData.szName));
		
		CurrentSQLData.iPoints = results.FetchInt(3);
		
		int iCurrentClient = GetClientFromAuth(szAuth);
		
		if (iCurrentClient != -1)
		{
			CurrentSQLData.iPoints = g_esClientData[iCurrentClient].Points.Get(iTopId);
		}
		
		arSortedTops.PushArray(CurrentSQLData, sizeof(CurrentSQLData));
	}
	
	arSortedTops.SortCustom(SortADTArrayPoints);
	
	IntToString(iTopId, szItemInfo, sizeof(szItemInfo));
	
	for (int iCurrentIndex = 0; iCurrentIndex < (g_cvTopClientsAmount.IntValue >= arSortedTops.Length ? arSortedTops.Length : g_cvTopClientsAmount.IntValue); iCurrentIndex++)
	{
		arSortedTops.GetArray(iCurrentIndex, CurrentSQLData, sizeof(CurrentSQLData));
		Format(szItem, sizeof(szItem), "(#%d) %s - %s %s", menu.ItemCount + 1, CurrentSQLData.szName, JB_AddCommas(CurrentSQLData.iPoints), TopData.szCounter);
		menu.AddItem(szItemInfo, szItem);
	}
	
	delete arSortedTops;
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No player was found.", ITEMDRAW_DISABLED);
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

// 1 = Index 2 before index 1
// 0 = both equal
// -1 = Index 1 before index 2
public int SortADTArrayPoints(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList arSort = view_as<ArrayList>(array);
	
	SQLData Struct1; arSort.GetArray(index1, Struct1, sizeof(Struct1));
	SQLData Struct2; arSort.GetArray(index2, Struct2, sizeof(Struct2));
	
	if (Struct1.iPoints != Struct2.iPoints)
	{
		return (Struct1.iPoints > Struct2.iPoints) ? -1 : 1;
	}
	
	return 0;
}

public int Handler_Tops(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iTopId = StringToInt(szItem);
		
		if (StrEqual(szItem, "LastWinners")) {
			showLastWinnersMenu(client);
		}
		else if (StrEqual(szItem, "ResetTop")) {
			showResetTopMenu(client);
		}
		else
		{
			DataPack dPack = new DataPack();
			dPack.WriteCell(GetClientSerial(client));
			dPack.WriteCell(iTopId);
			dPack.Reset();
			
			char szQuery[128];
			g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `top_stats` WHERE `unique` = '%s'", GetTopByIndex(iTopId).szUnique);
			g_Database.Query(SQL_TopMenu_CB, szQuery, dPack);
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showTopsMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

void showLastWinnersMenu(int client)
{
	char szItem[32];
	Menu menu = new Menu(Handler_LastWinners);
	menu.SetTitle("%s Top System - Last Top Winners\n ", PREFIX_MENU);
	
	Top TopData;
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		TopData = GetTopByIndex(iCurrentTop);
		Format(szItem, sizeof(szItem), "%s Winner: %s", TopData.szName, TopData.WinnerData.szName[0] == '\0' ? "None":TopData.WinnerData.szName);
		menu.AddItem("", szItem);
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No winner was found.", ITEMDRAW_DISABLED);
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_LastWinners(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select) {
		showLastWinnersMenu(client);
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showTopsMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

void showResetTopMenu(int client)
{
	char szItemInfo[8];
	Menu menu = new Menu(Handler_ResetTop);
	menu.SetTitle("%s Top System - Reset Top \n• Choose a top to reset, or go back to cancel the operation.\n ", PREFIX_MENU);
	
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		IntToString(iCurrentTop, szItemInfo, sizeof(szItemInfo));
		menu.AddItem(szItemInfo, GetTopByIndex(iCurrentTop).szName);
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No top category was found.", ITEMDRAW_DISABLED);
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_ResetTop(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iTopId = StringToInt(szItem);
		
		ResetTop(client, iTopId);
		PrintToChat(client, "%s Succesfully reset the \x04%s\x01!", PREFIX, GetTopByIndex(iTopId));
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showTopsMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `top_stats` (`steam_id` VARCHAR(64) NOT NULL , `name` VARCHAR(128) NOT NULL, `unique` VARCHAR(64) NOT NULL, `points` INT NOT NULL, UNIQUE(`steam_id`, `unique`))");
	
	// Loop through all the online clients, for late plugin load
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

void SQL_FetchClient(int client)
{
	char szQuery[128];
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `top_stats` WHERE `steam_id` = '%s'", g_esClientData[client].szAuth);
	g_Database.Query(SQL_FetchUser_CB, szQuery, GetClientSerial(client));
}

public void SQL_FetchUser_CB(Database db, DBResultSet results, const char[] error, any serial)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	char szUnique[128], szQuery[256];
	int client = GetClientFromSerial(serial);
	
	if (!client) {
		return;
	}
	
	bool[] bIsRowExist = new bool[g_arTopsData.Length];
	
	int iTopId = -1;
	
	while (results.FetchRow())
	{
		results.FetchString(2, szUnique, sizeof(szUnique));
		iTopId = GetTopByUnique(szUnique);
		if (iTopId != -1) {
			bIsRowExist[iTopId] = true;
			g_esClientData[client].Points.Set(iTopId, results.FetchInt(3));
		}
	}
	
	Top TopData;
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		if (bIsRowExist[iCurrentTop]) {
			continue;
		}
		
		TopData = GetTopByIndex(iCurrentTop);
		g_esClientData[client].Points.Set(iCurrentTop, TopData.iDefaultPoints);
		g_Database.Format(szQuery, sizeof(szQuery), "INSERT INTO `top_stats` (`steam_id`, `name`, `unique`, `points`) VALUES ('%s', '%s', '%s', %d)", 
			g_esClientData[client].szAuth, 
			g_esClientData[client].szName, 
			TopData.szUnique, 
			g_esClientData[client].Points.Get(iCurrentTop)
			);
		
		g_Database.Query(SQL_CheckForErrors, szQuery);
	}
}

void SQL_UpdateClient(int client)
{
	if (g_esClientData[client].Points == null || !g_esClientData[client].Points.Length)
	{
		return;
	}
	
	char szQuery[MAX_NAME_LENGTH * 2];
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		g_Database.Format(szQuery, sizeof(szQuery), "UPDATE `top_stats` SET `name` = '%s', `points` = %d WHERE `steam_id` = '%s' AND `unique` = '%s'", 
			g_esClientData[client].szName, 
			g_esClientData[client].Points.Get(iCurrentTop), 
			g_esClientData[client].szAuth, 
			GetTopByIndex(iCurrentTop).szUnique
			);
		
		g_Database.Query(SQL_CheckForErrors, szQuery);
	}
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
}

//================================[ KeyValues ]================================//

void KV_LoadTops()
{
	if (!FileExists(CONFIG_PATH)) {
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	if (!g_arTopsData.Length) {
		return;
	}
	
	KeyValues keyValues = new KeyValues("TopData");
	keyValues.ImportFromFile(CONFIG_PATH);
	g_iResetTime = keyValues.GetNum("GetTime");
	keyValues.GotoFirstSubKey();
	
	Top TopData;
	int iCounter;
	
	do {
		TopData = GetTopByIndex(iCounter);
		keyValues.GetString("Auth", TopData.WinnerData.szAuth, sizeof(LastWinner::szAuth));
		keyValues.GetString("Name", TopData.WinnerData.szName, sizeof(LastWinner::szName));
		iCounter++;
	} while (keyValues.GotoNextKey() && iCounter < g_arTopsData.Length);
	
	keyValues.Rewind();
	keyValues.ExportToFile(CONFIG_PATH);
	delete keyValues;
}

public void KV_SetTopData(Database db, DBResultSet results, const char[] error, int iTopId)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	if (!FileExists(CONFIG_PATH)) {
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	KeyValues keyValues = new KeyValues("TopData");
	keyValues.ImportFromFile(CONFIG_PATH);
	
	keyValues.SetNum("GetTime", GetTime() + (g_cvDaysUntilReset.IntValue * 24 * 60 * 60));
	keyValues.GoBack();
	
	char szAuth[64], szName[MAX_NAME_LENGTH], szKey[8];
	
	while (results.FetchRow())
	{
		results.FetchString(0, szAuth, sizeof(szAuth));
		results.FetchString(1, szName, sizeof(szName));
		
		IntToString(iTopId, szKey, sizeof(szKey));
		
		keyValues.JumpToKey(szKey, true);
		keyValues.SetString("Auth", szAuth);
		keyValues.SetString("Name", szName);
		keyValues.GoBack();
	}
	
	keyValues.Rewind();
	keyValues.ExportToFile(CONFIG_PATH);
	delete keyValues;
	
	Call_StartForward(g_fwdOnTopCategoryReset);
	Call_PushCell(iTopId);
	Call_Finish();
	
	KV_LoadTops();
	
	char szQuery[128];
	g_Database.Format(szQuery, sizeof(szQuery), "DELETE FROM `top_stats` WHERE `unique` = '%s'", GetTopByIndex(iTopId).szUnique);
	g_Database.Query(SQL_CheckForErrors, szQuery);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

void KV_InitData()
{
	if (!FileExists(CONFIG_PATH)) {
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	KeyValues keyValues = new KeyValues("TopData");
	keyValues.ImportFromFile(CONFIG_PATH);
	
	keyValues.SetNum("GetTime", GetTime() + (g_cvDaysUntilReset.IntValue * 24 * 60 * 60));
	
	keyValues.Rewind();
	keyValues.ExportToFile(CONFIG_PATH);
	delete keyValues;
	
	KV_LoadTops();
}

//================================[ Functions ]================================//

int GetTopByUnique(const char[] unique)
{
	Top CurrentTopData;
	for (int iCurrentTop = 0; iCurrentTop < g_arTopsData.Length; iCurrentTop++)
	{
		g_arTopsData.GetArray(iCurrentTop, CurrentTopData, sizeof(CurrentTopData));
		if (StrEqual(CurrentTopData.szUnique, unique, true)) {
			return iCurrentTop;
		}
	}
	
	return -1;
}

any[] GetTopByIndex(int index)
{
	Top TopData;
	g_arTopsData.GetArray(index, TopData, sizeof(TopData));
	return TopData;
}

int GetClientFromAuth(const char[] auth)
{
	char szAuth[64];
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			GetClientAuthId(iCurrentClient, AuthId_Steam2, szAuth, sizeof(szAuth));
			if (StrEqual(szAuth, auth, false)) {
				return iCurrentClient;
			}
		}
	}
	return -1;
}

void ResetTop(int client, int iTopId)
{
	char szQuery[128];
	Top TopData; TopData = GetTopByIndex(iTopId);
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `top_stats` WHERE `unique` = '%s' ORDER BY `points` DESC LIMIT 1", TopData.szUnique);
	g_Database.Query(KV_SetTopData, szQuery, iTopId);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			g_esClientData[iCurrentClient].Points.Set(iTopId, TopData.iDefaultPoints);
		}
	}
	
	if (client != -1)
		JB_WriteLogLine("Player\"%L\" has reset top \"%s\".", client, TopData.szName);
	else
		JB_WriteLogLine("Top \"%s\" has automatically reset.", TopData.szName);
}

/**
 * Return true if the client's steam account id matched one of specified authorized clients.
 * See g_szAuthorizedClients
 * 
 */
bool IsClientAllowed(int client)
{
	char szGroup[64];
	GetAdminGroup(GetUserAdmin(client), 0, szGroup, sizeof(szGroup));
	
	for (int iCurrentGroup = 0; iCurrentGroup < sizeof(g_szAuthorizedGroups); iCurrentGroup++)
	{
		if (StrEqual(szGroup, g_szAuthorizedGroups[iCurrentGroup], true)) {
			return true;
		}
	}
	
	return false;
}

//================================================================//