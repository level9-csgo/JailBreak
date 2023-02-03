#pragma semicolon 1
#pragma newdecls required
// ◾
#include <sourcemod>
#include <JailBreak>
#include <JB_RunesSystem>
#include <JB_AuctionHouse>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define ABORT_SYMBOL "-1"

#define DEFAULT_AUCTION_DURATION 60 // Default auction duration for the menu item (Minutes) 

//====================//

enum WriteState
{
	Write_None, 
	Write_CreateAuction_Duration, 
	Write_CreateAuction_Value, 
	Write_PlaceBid
}

enum struct Client
{
	char szAuth[32];
	
	Auction MenuAuctionData;
	
	WriteState iWriteState;
	
	void Reset() {
		this.szAuth[0] = '\0';
		
		this.MenuAuctionData.Reset();
		
		this.iWriteState = Write_None;
		
		this.Init();
	}
	
	void Init() {
		this.MenuAuctionData.iAuctionValue = 500;
		this.MenuAuctionData.iAuctionDuration = DEFAULT_AUCTION_DURATION;
	}
}

Client g_esClientsData[MAXPLAYERS + 1];

ArrayList g_arAuctionsData;

ConVar g_cvMinAuctionDuration;
ConVar g_cvMaxAuctionDuration;
ConVar g_cvAuctionValueFeePercent[AuctionType_Max];

int g_iAuctionDurations[] = 
{
	60, 
	360, 
	720, 
	1440, 
	2880
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Auction House", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the active auctions arraylist
	g_arAuctionsData = new ArrayList(sizeof(Auction));
	
	// ConVars Configurate
	g_cvMinAuctionDuration = CreateConVar("jb_ah_min_auction_duration_minutes", "5", "Minimum auction duration in minutes possible to set.", _, true, 1.0, true, 30.0);
	g_cvMaxAuctionDuration = CreateConVar("jb_ah_max_auction_duration_minutes", "20160", "Maximum auction duration in minutes possible to set.", _, true, 10080.0, true, 30240.0);
	
	g_cvAuctionValueFeePercent[AuctionType_Regular] = CreateConVar("jb_ah_starting_bid_fee_percent", "5", "Fee percent to charge from the auction starting bid.", _, true, 1.0, true, 50.0);
	g_cvAuctionValueFeePercent[AuctionType_Bin] = CreateConVar("jb_ah_bin_fee_percent", "5", "Fee percent to charge from the auction BIN item price.", _, true, 1.0, true, 25.0);
	
	AutoExecConfig(true, "AuctionHouse", "JailBreak");
	
	// Client Commands
	RegConsoleCmd("sm_auctionhouse", Command_AuctionHouse, "Access the auction house main menu.");
	RegConsoleCmd("sm_ah", Command_AuctionHouse, "Access the auction house main menu. (An Alias)");
	
	// Loop through all the online clients, for late plugin load
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_esClientsData[client].Reset();
	
	if (!IsFakeClient(client))
	{
		// If we couldn't get the client auth id, we won't be able to fetch the client from the database
		if (!GetClientAuthId(client, AuthId_Steam2, g_esClientsData[client].szAuth, sizeof(g_esClientsData[].szAuth)))
		{
			KickClient(client, "Verification error, please reconnect.");
			return;
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (g_esClientsData[client].iWriteState == Write_None)
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(sArgs, ABORT_SYMBOL))
	{
		// Notify client
		PrintToChat(client, "%s Operation aborted.", PREFIX);
		
		// Display the last menu the client was at
		if (g_esClientsData[client].iWriteState == Write_PlaceBid) {
			
		}
		else {
			showCreateAuctionMenu(client);
		}
		
		// Reset the write status variable
		g_esClientsData[client].iWriteState = Write_None;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	// Convert the typed message into a integer
	int iTypedValue = StringToInt(sArgs);
	
	// Make sure the conversion of the string has succeed
	if (iTypedValue <= 0)
	{
		// Notify client
		PrintToChat(client, "%s You have specified an invalid auction %s. (\x02%s\x01)", PREFIX_ERROR, g_esClientsData[client].iWriteState == Write_CreateAuction_Duration ? "duration" : g_esClientsData[client].iWriteState == Write_CreateAuction_Value ? (g_esClientsData[client].MenuAuctionData.iAuctionType == AuctionType_Regular ? "starting bid" : "item price") : g_esClientsData[client].iWriteState == Write_PlaceBid ? "place bid" : "value", sArgs);
		
		// Display the last menu the client was at
		if (g_esClientsData[client].iWriteState == Write_PlaceBid) {
			
		}
		else {
			showCreateAuctionMenu(client);
		}
		
		// Reset the write status variable
		g_esClientsData[client].iWriteState = Write_None;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	switch (g_esClientsData[client].iWriteState)
	{
		case Write_CreateAuction_Duration:
		{
			if (iTypedValue < g_cvMinAuctionDuration.IntValue)
			{
				PrintToChat(client, "%s Minimum auction duration is \x04%d\x01 minutes!", PREFIX_ERROR, g_cvMinAuctionDuration.IntValue);
			}
			else if (iTypedValue > g_cvMaxAuctionDuration.IntValue)
			{
				PrintToChat(client, "%s Maximum auction duration is \x04%d\x01 minutes!", PREFIX_ERROR, g_cvMaxAuctionDuration.IntValue);
			}
			
			// Set the auction duration by the pressed item duration
			g_esClientsData[client].MenuAuctionData.iAuctionDuration = (iTypedValue < g_cvMinAuctionDuration.IntValue ? g_cvMinAuctionDuration.IntValue : iTypedValue > g_cvMaxAuctionDuration.IntValue ? g_cvMaxAuctionDuration.IntValue : iTypedValue);
			
			// Display the create auction menu
			showCreateAuctionMenu(client);
		}
		case Write_CreateAuction_Value:
		{
			g_esClientsData[client].MenuAuctionData.iAuctionValue = iTypedValue;
			
			// Display the create auction menu
			showCreateAuctionMenu(client);
		}
		case Write_PlaceBid:
		{
			
		}
	}
	
	// Reset the write status variable
	g_esClientsData[client].iWriteState = Write_None;
	
	// Block the message send
	return Plugin_Handled;
}

//================================[ Commands ]================================//

public Action Command_AuctionHouse(int client, int args)
{
	showAuctionHouseMainMenu(client);
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_ShowAuctionHouseMainMenu", Native_ShowAuctionHouseMainMenu);
	
	RegPluginLibrary("JB_AuctionHouse");
	return APLRes_Success;
}

public int Native_ShowAuctionHouseMainMenu(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	showAuctionHouseMainMenu(client);
	
	return 0;
}

//================================[ Menus ]================================//

void showAuctionHouseMainMenu(int client)
{
	Menu menu = new Menu(Handler_AuctionHouseMain);
	menu.SetTitle("%s Auction House - Main Menu \n• Time to get rich!\n ", PREFIX_MENU);
	
	menu.AddItem("", "Auctions Browser");
	menu.AddItem("", "View Bids");
	menu.AddItem("", "Create Auction");
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_AuctionHouseMain(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				// Display the auctions browser menu to the client
				showAuctionsBrowserMenu(client);
			}
			case 1:
			{
				
			}
			case 2:
			{
				// Display the create auction menu to the client
				showCreateAuctionMenu(client);
			}
		}
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void showAuctionsBrowserMenu(int client)
{
	char szItemInfo[8];
	Menu menu = new Menu(Handler_AuctionsBrowser);
	menu.SetTitle("%s Auction House - Auctions Browser\n ", PREFIX_MENU);
	
	menu.AddItem("", "Browser Filters\n ");
	
	Auction CurrentAuctionData;
	
	for (int iCurrentAuction = 0; iCurrentAuction < g_arAuctionsData.Length; iCurrentAuction++)
	{
		CurrentAuctionData = GetAuctionByIndex(iCurrentAuction);
		
		menu.AddItem(szItemInfo, GetAuctionItemName(CurrentAuctionData.AuctionItemData.szAuctionItemUnique, CurrentAuctionData.AuctionItemData.iAuctionItemStar, CurrentAuctionData.AuctionItemData.iAuctionItemLevel));
	}
	
	// Create an extra menu item incase no auctions are active currecly
	if (!g_arAuctionsData.Length)
	{
		menu.AddItem("", "There are no active auctions at the moment!", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_AuctionsBrowser(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		showAuctionHouseMainMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void showCreateAuctionMenu(int client)
{
	char szItem[128];
	Menu menu = new Menu(Handler_CreateAuction);
	menu.SetTitle("%s Auction House - Create Auction\n ", PREFIX_MENU);
	
	Format(szItem, sizeof(szItem), "%s\n ", GetAuctionItemName(
			g_esClientsData[client].MenuAuctionData.AuctionItemData.szAuctionItemUnique, 
			g_esClientsData[client].MenuAuctionData.AuctionItemData.iAuctionItemStar, 
			g_esClientsData[client].MenuAuctionData.AuctionItemData.iAuctionItemLevel)
		);
	
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "%s: %s credits | Extra fee: +%s credits (%d%%)\n ", 
		g_esClientsData[client].MenuAuctionData.iAuctionType == AuctionType_Regular ? "Starting Bid" : "Item Price", 
		JB_AddCommas(g_esClientsData[client].MenuAuctionData.iAuctionValue), 
		JB_AddCommas(GetExtraFee(g_esClientsData[client].MenuAuctionData.iAuctionValue, 
				g_esClientsData[client].MenuAuctionData.iAuctionType)), 
		g_cvAuctionValueFeePercent[g_esClientsData[client].MenuAuctionData.iAuctionType].IntValue
		);
	
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "Duration: %s | Extra fee: +%s credits\n ", GetAuctionDuration(g_esClientsData[client].MenuAuctionData.iAuctionDuration), "1,200");
	menu.AddItem("", szItem);
	
	menu.AddItem("", "Create Auction\n ");
	
	Format(szItem, sizeof(szItem), "Switch To %s", g_esClientsData[client].MenuAuctionData.iAuctionType == AuctionType_Regular ? "BIN" : "Auction");
	menu.AddItem("", szItem);
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CreateAuction(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				showAuctionItemSelectionMenu(client);
			}
			case 1:
			{
				g_esClientsData[client].iWriteState = Write_CreateAuction_Value;
				PrintToChat(client, "%s Type your desired %s, or \x02%s\x01 to abort.", PREFIX, g_esClientsData[client].MenuAuctionData.iAuctionType == AuctionType_Regular ? "starting bid" : "item price", ABORT_SYMBOL);
			}
			case 2:
			{
				showAuctionDurationMenu(client);
			}
			case 3:
			{
				Auction AuctionData; AuctionData = g_esClientsData[client].MenuAuctionData;
				
				AuctionData.auction_seller_account_id = GetSteamAccountID(client);
				
				GetClientName(client, AuctionData.szAuctionSellerName, sizeof(AuctionData.szAuctionSellerName));
				
				AuctionData.Init();
				
				g_arAuctionsData.PushArray(AuctionData, sizeof(AuctionData));
			}
			case 4:
			{
				// Change the auction type to its opposite
				g_esClientsData[client].MenuAuctionData.iAuctionType = g_esClientsData[client].MenuAuctionData.iAuctionType ^ 1;
				
				// Display the menu again
				showCreateAuctionMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		showAuctionHouseMainMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void showAuctionItemSelectionMenu(int client)
{
	// char szItem[64];
	Menu menu = new Menu(Handler_AuctionItemSelection);
	menu.SetTitle("%s Auction House - Item Selection\n ", PREFIX_MENU);
	
	menu.AddItem("", "Runes");
	menu.AddItem("", "Shop Categories", ITEMDRAW_DISABLED);
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_AuctionItemSelection(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				// Dispaly the client runes inventory
				showRunesInventoryMenu(client);
			}
			default:
			{
				
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Display the last menu the client was at
		showCreateAuctionMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void showRunesInventoryMenu(int client)
{
	char szItemInfo[128];
	Menu menu = new Menu(Handler_RunesInventory);
	menu.SetTitle("%s Auction House - Select A Rune\n ", PREFIX_MENU);
	
	Rune RuneData;
	ClientRune ClientRuneData;
	
	// Loop through all the client runes inventory, and add them into the menu
	for (int iCurrentClientRune = 0; iCurrentClientRune < JB_GetClientRunesAmount(client); iCurrentClientRune++)
	{
		JB_GetClientRuneData(client, iCurrentClientRune, ClientRuneData);
		JB_GetRuneData(ClientRuneData.iRuneId, RuneData);
		
		// Convert the current data into a string, required for sending through the menu item info
		Format(szItemInfo, sizeof(szItemInfo), "%s:%d:%d:%d", RuneData.szRuneUnique, ClientRuneData.iRuneStar, ClientRuneData.iRuneLevel, iCurrentClientRune);
		
		menu.AddItem(szItemInfo, GetAuctionItemName(RuneData.szRuneUnique, ClientRuneData.iRuneStar, ClientRuneData.iRuneLevel));
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_RunesInventory(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[128];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		// Get the client rune data by the sent item info
		char szData[4][128];
		ExplodeString(szItem, ":", szData, sizeof(szData), sizeof(szData[]));
		
		// Insert the client rune data into the auction item data
		strcopy(g_esClientsData[client].MenuAuctionData.AuctionItemData.szAuctionItemUnique, sizeof(AuctionItem::szAuctionItemUnique), szData[0]);
		
		g_esClientsData[client].MenuAuctionData.AuctionItemData.iAuctionItemStar = StringToInt(szData[1]);
		g_esClientsData[client].MenuAuctionData.AuctionItemData.iAuctionItemLevel = StringToInt(szData[2]);
		
		// Display the auction creation menu
		showCreateAuctionMenu(client);
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Display the last menu the client was at
		showAuctionItemSelectionMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void showAuctionDurationMenu(int client)
{
	char szItem[64];
	Menu menu = new Menu(Handler_AuctionDuration);
	menu.SetTitle("%s Auction House - Auction Duration\n ", PREFIX_MENU);
	
	// Loop through all the auction duration options, and add them into the menu
	for (int iCurrentDuration = 0; iCurrentDuration < sizeof(g_iAuctionDurations); iCurrentDuration++)
	{
		Format(szItem, sizeof(szItem), "%s | Extra fee: %s credits%s", GetAuctionDuration(g_iAuctionDurations[iCurrentDuration]), "1,200", iCurrentDuration == sizeof(g_iAuctionDurations) - 1 ? "\n " : "");
		menu.AddItem("", szItem);
	}
	
	menu.AddItem("", "Custom Duration");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_AuctionDuration(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (itemNum < sizeof(g_iAuctionDurations))
		{
			// Set the auction duration by the pressed item duration
			g_esClientsData[client].MenuAuctionData.iAuctionDuration = g_iAuctionDurations[itemNum];
			
			// Display the create auction menu
			showCreateAuctionMenu(client);
		}
		else
		{
			// Change the client write status
			g_esClientsData[client].iWriteState = Write_CreateAuction_Duration;
			
			// Notify client
			PrintToChat(client, "%s Type your desired duration in minutes, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Display the last menu the client was at
		showCreateAuctionMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

//================================[ Functions ]================================//

any[] GetAuctionByIndex(int index)
{
	Auction AuctionData;
	g_arAuctionsData.GetArray(index, AuctionData, sizeof(AuctionData));
	return AuctionData;
}

int GetExtraFee(int value, int auction_type)
{
	return (value * g_cvAuctionValueFeePercent[auction_type].IntValue) / 100;
}

char GetAuctionItemName(char[] item_unique, int star, int level)
{
	char szItemName[64];
	
	if (item_unique[0] == '\0')
	{
		Format(szItemName, sizeof(szItemName), "Select An Item");
		return szItemName;
	}
	
	if (star != -1 && level != -1)
	{
		int iRuneIndex = JB_FindRune(item_unique);
		
		if (iRuneIndex != -1)
		{
			Rune RuneData;
			JB_GetRuneData(iRuneIndex, RuneData);
			
			Format(szItemName, sizeof(szItemName), "%s | %d%s(Level %d)", RuneData.szRuneName, star, RUNE_STAR_SYMBOL, level);
		}
	}
	else
	{
		// On development
	}
	
	return szItemName;
}

char GetAuctionDuration(int duration)
{
	char szDuration[32];
	
	if (duration < 60) {
		Format(szDuration, sizeof(szDuration), "%d Minutes", duration);
	}
	else if (60 <= duration < 1440) {
		Format(szDuration, sizeof(szDuration), "%d Hour%s", duration / 60, duration / 60 != 1 ? "s" : "");
	}
	else {
		Format(szDuration, sizeof(szDuration), "%d Day%s", duration / 1440, duration / 1440 != 1 ? "s" : "");
	}
	
	return szDuration;
}

//================================================================//