#include <sourcemod>
#include <JailBreak>
#include <JB_RunesSystem>
#include <shop>

#pragma semicolon 1
#pragma newdecls required

// #define DEVELOPMENT

// Chat input state of a player.
enum InputState
{
	InputState_None,  // Player input state is disabled.
	InputState_Price,  // Price of an auction item.
	//InputState_Max
}

enum struct AuctionItem
{
	// Data for shop items.
	ItemId shop_item_id;
	
	// Data for rune items.
	int rune_row_id;
	char rune_identifier[64];
	int rune_star;
	int rune_level;
	
	//================================//
	bool IsInitialized()
	{
		return this.shop_item_id != INVALID_ITEM || this.rune_identifier[0];
	}
	
	void InitRuneItem(Rune rune, ClientRune client_rune)
	{
		this.shop_item_id = INVALID_ITEM;
		
		this.rune_row_id = client_rune.RowId;
		strcopy(this.rune_identifier, sizeof(AuctionItem::rune_identifier), rune.szRuneUnique);
		this.rune_star = client_rune.RuneStar;
		this.rune_level = client_rune.RuneLevel;
	}
	
	void Close()
	{
		this.shop_item_id = INVALID_ITEM;
		
		this.rune_row_id = 0;
		this.rune_identifier[0] = '\0';
		this.rune_star = 0;
		this.rune_level = 0;
	}
	
	// Whether this auction item is a shop item.
	// True if this item is a shop item, false if this is a rune item.
	bool IsShopItem()
	{
		return this.shop_item_id != INVALID_ITEM;
	}
	
	void GetName(char[] buffer, int length)
	{
		// Shop item.
		if (this.IsShopItem())
		{
			Shop_GetItemNameById(this.shop_item_id, buffer, length);
		}
		// Rune item.
		else
		{
			int rune_index = JB_FindRune(this.rune_identifier);
			if (rune_index != -1)
			{
				Rune rune_data;
				JB_GetRuneData(rune_index, rune_data);
				
				Format(buffer, length, "%s | %d%s(Level %d)", rune_data.szRuneName, this.rune_star, RUNE_STAR_SYMBOL, this.rune_level);
			}
		}
	}
	
	bool IsClientHasItem(int client)
	{
		if (this.IsShopItem())
		{
			return Shop_IsClientHasItem(client, this.shop_item_id);
		}
		
		ArrayList client_rune_inventory = JB_GetClientRuneInventory(client);
		
		bool has_rune = client_rune_inventory.FindValue(this.rune_row_id) != -1;
		
		delete client_rune_inventory;
		
		return has_rune;
	}
	
	bool RemoveClientItem(int client)
	{
		if (!this.IsClientHasItem(client))
		{
			return false;
		}
		
		if (this.IsShopItem())
		{
			return Shop_RemoveClientItem(client, this.shop_item_id);
		}
		
		ArrayList client_rune_inventory = JB_GetClientRuneInventory(client);
		
		int client_rune_idx = client_rune_inventory.FindValue(this.rune_row_id);
		
		delete client_rune_inventory;
		
		if (client_rune_idx == -1)
		{
			return false;
		}
		
		JB_RemoveClientRune(client, client_rune_idx);
		return true;
	}
	
	bool AddClientItem(int client)
	{
		if (this.IsShopItem() && !Shop_GiveClientItem(client, this.shop_item_id))
		{
			PrintToChat(client, "%s \x07Unable to give you an item you already own!\x01", PREFIX_ERROR);
			return false;
		}
		
		if (!this.IsShopItem())
		{
			int rune_idx = JB_FindRune(this.rune_identifier);
			if (rune_idx == -1)
			{
				PrintToChat(client, "%s Couldn't recognize the rune item. Please contact a server manager.", PREFIX_ERROR);
				return false;
			}
			
			if (!JB_AddClientRune(client, rune_idx, this.rune_star, this.rune_level))
			{
				PrintToChat(client, "%s \x07Unable to give you a rune since your rune capacity is full!\x01", PREFIX_ERROR);
				return false;
			}
		}
		
		return true;
	}
}

ArrayList g_Auctions;

Database g_Database;

// Cvar Handles.
ConVar jb_ah_fee_percent;
ConVar jb_ah_default_value;

// Different durations for auction items.
int g_AuctionDurations[] = 
{
	120,  // 2 hours, this will be the default duration.
	360,  // 6 hours.
	720,  // 12 hours.
	1440,  // 1 day.
	2880,  // 2 days.
	10080 // 7 days.
};

enum struct Auction
{
	// Database unique row id. Used as an identifier to this specific auction.
	int row_id;
	
	// Auction owner account id. (GetSteamAccountID())
	int owner_account_id;
	
	// Auction owner name at the time of creation.
	char owner_name[MAX_NAME_LENGTH];
	
	// Start/end time.
	int start_time;
	int end_time;
	
	// Credits value of the auction item.
	int value;
	
	// Auction item. Can we whether a rune item or a shop item.
	AuctionItem item;
	
	// Timer handle of the cancel function.
	Handle end_timer;
	
	//================================//
	bool IsInitialized()
	{
		return this.value && this.GetDuration();
	}
	
	void Init()
	{
		this.value = jb_ah_default_value.IntValue;
		this.SetDuration(g_AuctionDurations[0]);
	}
	
	void Close()
	{
		this.owner_account_id = 0;
		this.owner_name[0] = '\0';
		this.start_time = 0;
		this.end_time = 0;
		this.value = 0;
		
		this.item.Close();
		
		delete this.end_timer;
	}
	
	bool FindByRowID(int row_id, int &idx = -1)
	{
		if ((idx = g_Auctions.FindValue(row_id)) == -1)
		{
			return false;
		}
		
		g_Auctions.GetArray(idx, this);
		return true;
	}
	
	bool FindNoRowID(int owner_account_id, int start_time, int &idx = -1)
	{
		for (int current_auction; current_auction < g_Auctions.Length; current_auction++)
		{
			g_Auctions.GetArray(current_auction, this);
			
			if (this.owner_account_id == owner_account_id && this.start_time == start_time)
			{
				idx = current_auction;
				return true;
			}
		}
		
		return false;
	}
	
	int GetDuration()
	{
		return (this.end_time - this.start_time) / 60;
	}
	
	// 'duration' is minutes represented.
	void SetDuration(int duration)
	{
		this.start_time = 0;
		this.end_time = duration * 60;
	}
	
	// Minutes retrieval.
	int GetRemainingTime()
	{
		return (this.end_time - GetTime()) / 60;
	}
	
	void List(int client)
	{
		Player player; player = GetPlayer(client);
		
		this.owner_account_id = player.account_id;
		GetClientName(client, this.owner_name, sizeof(Auction::owner_name));
		
		int duration = this.GetDuration();
		
		this.start_time = GetTime();
		this.end_time = this.start_time + (duration * 60);
		
		this.item.rune_row_id = 0;
		
		g_Auctions.PushArray(this);
		
		this.InsertData();
	}
	
	void HandleEndAuctionTimer()
	{
		int remaining_time = this.end_time - GetTime();
		if (remaining_time <= 0)
		{
			Timer_EndAuction(null, this.row_id);
		}
		else
		{
			this.end_timer = CreateTimer(float(remaining_time), Timer_EndAuction, this.row_id);
		}
	}
	
	//================[ Database ]================//
	void FetchData(DBResultSet result)
	{
		this.row_id = result.FetchInt(0);
		this.owner_account_id = result.FetchInt(1);
		result.FetchString(2, this.owner_name, sizeof(Auction::owner_name));
		this.start_time = result.FetchInt(3);
		this.end_time = result.FetchInt(4);
		this.value = result.FetchInt(5);
		this.item.shop_item_id = view_as<ItemId>(result.FetchInt(6));
		result.FetchString(7, this.item.rune_identifier, sizeof(AuctionItem::rune_identifier));
		this.item.rune_star = result.FetchInt(8);
		this.item.rune_level = result.FetchInt(9);
		
		g_Auctions.PushArray(this);
		
		this.HandleEndAuctionTimer();
	}
	
	void InsertData()
	{
		char query[512];
		g_Database.Format(query, sizeof(query), "INSERT INTO `jb_auctions` \
		(`owner_account_id`, `owner_name`, `start_time`, `end_time`, `value`, `shop_item_id`, `rune_identifier`, `rune_star`, `rune_level`) \
		VALUES (%d, '%s', %d, %d, %d, %d, '%s', %d, %d)", this.owner_account_id, this.owner_name, this.start_time, this.end_time, this.value, this.item.shop_item_id, 
			this.item.rune_identifier, this.item.rune_star, this.item.rune_level);
		
		// We can't rely on |this| array index, since queries has delay.
		// Pass the owner account id + start time, which will identify the auction
		// and evetually will find us the correct auction data.
		DataPack dp = new DataPack();
		dp.WriteCell(this.owner_account_id);
		dp.WriteCell(this.start_time);
		
		g_Database.Query(SQL_InsertAuction_CB, query, dp);
	}
	
	void DeleteData()
	{
		char query[64];
		g_Database.Format(query, sizeof(query), "DELETE FROM `jb_auctions` WHERE `id` = %d", this.row_id);
		g_Database.Query(SQL_CheckForErrors, query);
	}
	
	// Returns the item back to its owner.
	void ReturnItemToOwner()
	{
		// Online case:
		int owner = GetClientOfAccountId(this.owner_account_id);
		if (owner)
		{
			if (this.item.AddClientItem(owner))
			{
				char item_name[64];
				this.item.GetName(item_name, sizeof(item_name));
				
				PrintToChat(owner, "%s Returned item (\x03%s\x01) because your auction has been ended.", PREFIX, item_name);
			}
			else
			{
				JB_WriteLogLine("Failed returning item (shop_item_id: %d, rune_identifier: %s, star: %d, level: %d) to account id: %d", 
					this.item.shop_item_id, 
					this.item.rune_identifier, 
					this.item.rune_star, 
					this.item.rune_level, 
					this.owner_account_id);
			}
			
			return;
		}
		
		// Offline case:
		// Shop item.
		if (this.item.IsShopItem())
		{
			char steamid2[MAX_AUTHID_LENGTH];
			AccountIDToSteam2(this.owner_account_id, steamid2);
			
			char query[512];
			g_Database.Format(query, sizeof(query), "INSERT INTO `shop_boughts` \
			(`player_id`, `item_id`, `count`, `duration`, `timeleft`, `buy_price`, `sell_price`, `buy_time`) \
			VALUES ((SELECT `id` FROM `shop_players` WHERE `auth` = '%s'), %d, 1, 0, 0, %d, %d, %d)", 
				steamid2, 
				this.item.shop_item_id, 
				Shop_GetItemPrice(this.item.shop_item_id), 
				Shop_GetItemSellPrice(this.item.shop_item_id), 
				GetTime()
				);
			
			g_Database.Query(SQL_CheckForErrors, query);
		}
		// Rune item.
		else
		{
			char query[256];
			g_Database.Format(query, sizeof(query), "INSERT INTO `jb_runes_inventory`(`account_id`, `unique`, `star`, `level`, `equipped`, `garbage_collected`) \
			VALUES (%d, '%s', %d, %d, 0, 0)", this.owner_account_id, this.item.rune_identifier, this.item.rune_star, this.item.rune_level);
			
			g_Database.Query(SQL_CheckForErrors, query);
		}
	}
	
	// Transfers the credits from both parties.
	void TransferCredits(int client)
	{
		Shop_TakeClientCredits(client, this.value, CREDITS_BY_BUY_OR_SELL);
		
		int owner = GetClientOfAccountId(this.owner_account_id);
		if (owner)
		{
			char item_name[64];
			this.item.GetName(item_name, sizeof(item_name));
			
			Shop_GiveClientCredits(owner, this.value, CREDITS_BY_BUY_OR_SELL);
			
			PrintToChat(owner, "%s \x0E%N\x01 purchased your auction item \x03%s\x01.", PREFIX, client, item_name);
			PrintToChat(owner, "%s You have recieved \x04%s\x01 credits.", PREFIX, JB_AddCommas(this.value));
			return;
		}
		
		char steamid2[MAX_AUTHID_LENGTH];
		AccountIDToSteam2(this.owner_account_id, steamid2);
		
		char query[128];
		g_Database.Format(query, sizeof(query), "UPDATE `shop_players` SET `money` = `money` + %d WHERE `auth` = '%s'", this.value, steamid2);
		g_Database.Query(SQL_CheckForErrors, query);
	}
}

enum struct Player
{
	// Player steam account id.
	int account_id;
	
	// Data of the new auction created by this player.
	Auction new_auction;
	
	// See the enum above.
	InputState input_state;
	
	//================================//
	void Init(int client)
	{
		this.account_id = GetSteamAccountID(client);
	}
	
	void Close()
	{
		this.account_id = 0;
		this.new_auction.Close();
		this.input_state = InputState_None;
	}
	
	int GetAuctionExtraFee()
	{
		return (this.new_auction.value * jb_ah_fee_percent.IntValue) / 100;
	}
}

Player g_Players[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[JailBreak] Auction House", 
	author = "KoNLiG", 
	description = "Provides a market-like system that replicates an auction house.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_Auctions = new ArrayList(sizeof(Auction));
	
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Register cmds.
	RegConsoleCmd("sm_auctionhouse", Command_AuctionHouse, "Access the auction house main menu.");
	RegConsoleCmd("sm_ah", Command_AuctionHouse, "Access the auction house main menu. (alias)");
	
	RegConsoleCmd("sm_market", Command_Market, "Redirets players to the /ah command.");
	
	// Configurate cvars.
	jb_ah_fee_percent = CreateConVar("jb_ah_fee_percent", "5", "Fee percent to charge from the auction item price.", .hasMin = true, .hasMax = true, .max = 100.0);
	jb_ah_default_value = CreateConVar("jb_ah_default_value", "500", "Default auction value in credits.");
	
	#if !defined DEVELOPMENT
	AutoExecConfig();
	#endif
	
	// FIX: Move this to post db connection.
	Lateload();
}

//================================[ Events ]================================//

public void OnClientAuthorized(int client, const char[] auth)
{
	if (!IsFakeClient(client))
	{
		g_Players[client].Init(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_Players[client].Close();
}

// Handle client chat inputs.
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (g_Players[client].input_state == InputState_None)
	{
		return Plugin_Continue;
	}
	
	InputState input_state = g_Players[client].input_state;
	g_Players[client].input_state = InputState_None;
	
	switch (input_state)
	{
		case InputState_Price:
		{
			int value;
			if (!InterceptValueString(client, sArgs, value))
			{
				DisplayCreateAuctionMenu(client);
				return Plugin_Handled;
			}
			
			g_Players[client].new_auction.value = value;
			DisplayCreateAuctionMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Command callbacks ]================================//

Action Command_AuctionHouse(int client, int argc)
{
	if (!client)
	{
		ReplyToCommand(client, "This command is unavailable via the server console.");
		return Plugin_Handled;
	}
	
	#if defined DEVELOPMENT
	if (!(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		ReplyToCommand(client, " \x06This is a project in development, stay tuned!\x01");
		return Plugin_Handled;
	}
	#endif
	
	DisplayAuctionHouseMenu(client);
	return Plugin_Handled;
}

Action Command_Market(int client, int argc)
{
	PrintToChat(client, "%s \x04You meant \x0E/ah\x01?", PREFIX);
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void DisplayAuctionHouseMenu(int client)
{
	Menu menu = new Menu(Handler_AuctionHouseMain);
	menu.SetTitle("%s Auction House - Auctions Browser:\n \nTime to get rich!\n ", PREFIX_MENU);
	
	char item_display[128];
	Format(item_display, sizeof(item_display), "╭Create Auction\n    ╰┄There are %d auctions:\n ", g_Auctions.Length);
	menu.AddItem("", item_display);
	
	Auction auction;
	char item_name[64], item_info[11];
	
	for (int current_auction; current_auction < g_Auctions.Length; current_auction++)
	{
		g_Auctions.GetArray(current_auction, auction);
		
		auction.item.GetName(item_name, sizeof(item_name));
		Format(item_display, sizeof(item_display), "%s [%s credits]", item_name, JB_AddCommas(auction.value));
		
		IntToString(auction.row_id, item_info, sizeof(item_info));
		
		menu.AddItem(item_info, item_display);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_AuctionHouseMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, selected_item = param2;
		
		switch (selected_item)
		{
			// "Create Auction"
			case 0:
			{
				if (!g_Players[client].new_auction.IsInitialized())
				{
					g_Players[client].new_auction.Init();
				}
				
				DisplayCreateAuctionMenu(client);
			}
			default:
			{
				char item_info[11];
				menu.GetItem(selected_item, item_info, sizeof(item_info));
				
				int row_id = StringToInt(item_info);
				
				Auction auction;
				if (!auction.FindByRowID(row_id))
				{
					PrintToChat(client, "%s This auction is no longer exists!", PREFIX_ERROR);
					return 0;
				}
				
				DisplayAuctionOverviewMenu(client, auction);
			}
		}
	}
	else if (action == MenuAction_Select)
	{
		delete menu;
	}
	
	return 0;
}

void DisplayAuctionOverviewMenu(int client, Auction auction)
{
	char item_info[11], item_name[64], remaining_time[64];
	IntToString(auction.row_id, item_info, sizeof(item_info));
	auction.item.GetName(item_name, sizeof(item_name));
	FormatMinutes(auction.GetRemainingTime(), remaining_time, sizeof(remaining_time));
	
	Menu menu = new Menu(Handler_AuctionOverview);
	menu.SetTitle("%s Auction House - Auction Overview:\n \n╭%s\n╰┄%s credits\n \n◾ Auction creator: %s\n◾ Ending in: %s\n ", PREFIX_MENU, item_name, JB_AddCommas(auction.value), auction.owner_name, remaining_time);
	
	menu.AddItem(item_info, "Purchase", g_Players[client].account_id != auction.owner_account_id ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("", "Cancel", g_Players[client].account_id == auction.owner_account_id ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_AuctionOverview(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			char item_info[11];
			menu.GetItem(0, item_info, sizeof(item_info));
			
			int row_id = StringToInt(item_info);
			
			Auction auction;
			int idx;
			
			if (!auction.FindByRowID(row_id, idx))
			{
				PrintToChat(client, "%s This auction is no longer exists!", PREFIX_ERROR);
				return 0;
			}
			
			switch (selected_item)
			{
				// "Purchase"
				case 0:
				{
					int client_credits = Shop_GetClientCredits(client);
					if (client_credits < auction.value)
					{
						PrintToChat(client, "You don't have enough credits to purchase the item. (missing \x02%s\x01)", JB_AddCommas(auction.value - client_credits));
						return 0;
					}
					
					if (!auction.item.AddClientItem(client))
					{
						return 0;
					}
					
					auction.TransferCredits(client);
					auction.DeleteData();
					
					char item_name[64];
					auction.item.GetName(item_name, sizeof(item_name));
					
					PrintToChat(client, "%s Successfully purchased \x03%s\x01 from \x0E%s\x01 auction for \x04%s\x01 credits!", PREFIX, item_name, auction.owner_name, JB_AddCommas(auction.value));
					
					auction.Close();
					g_Auctions.Erase(idx);
				}
				// "Cancel"
				case 1:
				{
					Timer_EndAuction(null, row_id);
					
					PrintToChat(client, "%s Successfully \x06canceled\x01 the auction!", PREFIX);
				}
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayAuctionHouseMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void DisplayCreateAuctionMenu(int client)
{
	Player player; player = g_Players[client];
	
	Menu menu = new Menu(Handler_CreateAuction);
	menu.SetTitle("%s Auction House - Create Auction:\n ", PREFIX_MENU);
	
	char item_display[256];
	
	if (!player.new_auction.item.IsInitialized())
	{
		item_display = "╭Select an item\n    ╰┄You may select any shop item or personal rune you own.\n ";
	}
	else
	{
		player.new_auction.item.GetName(item_display, sizeof(item_display));
		
		if (player.new_auction.item.IsShopItem())
		{
			Format(item_display, sizeof(item_display), "[%s] %s", JB_AddCommas(Shop_GetItemPrice(player.new_auction.item.shop_item_id)), item_display);
		}
		
		StrCat(item_display, sizeof(item_display), "\n◾ Press to choose a different shop item or personal rune.\n ");
	}
	
	menu.AddItem("", item_display);
	
	Format(item_display, sizeof(item_display), "╭Item Price: %s credits\n    ╰┄Extra fee: +%s credits (%d%%)\n ", 
		JB_AddCommas(player.new_auction.value), 
		JB_AddCommas(player.GetAuctionExtraFee()), 
		jb_ah_fee_percent.IntValue
		);
	
	menu.AddItem("", item_display);
	
	FormatMinutes(player.new_auction.GetDuration(), item_display, sizeof(item_display));
	Format(item_display, sizeof(item_display), "╭Duration: %s\n    ╰┄The time until this auction will be taken down.\n ", item_display);
	menu.AddItem("", item_display);
	
	menu.AddItem("", "Create Auction!");
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_CreateAuction(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			switch (selected_item)
			{
				case 0:
				{
					DisplayItemSelectionMenu(client);
				}
				case 1:
				{
					g_Players[client].input_state = InputState_Price;
					PrintToChat(client, "%s Type your desired \x03item price\x01!", PREFIX);
				}
				case 2:
				{
					int duration_idx = GetDurationIndex(g_Players[client].new_auction.GetDuration());
					
					duration_idx = ++duration_idx % sizeof(g_AuctionDurations);
					g_Players[client].new_auction.SetDuration(g_AuctionDurations[duration_idx]);
					DisplayCreateAuctionMenu(client);
				}
				case 3:
				{
					Auction auction; auction = g_Players[client].new_auction;
					
					int credits_fee = g_Players[client].GetAuctionExtraFee(), client_credits = Shop_GetClientCredits(client);
					if (credits_fee && client_credits < credits_fee)
					{
						PrintToChat(client, "You don't have enough credits to pay the extra fee. (missing \x02%s\x01)", JB_AddCommas(credits_fee - client_credits));
						return 0;
					}
					
					Shop_TakeClientCredits(client, credits_fee, CREDITS_BY_BUY_OR_SELL);
					
					if (!auction.item.RemoveClientItem(client))
					{
						PrintToChat(client, "%s \x07You are no longer possess this item!\x01", PREFIX_ERROR);
						return 0;
					}
					
					auction.List(client);
					
					g_Players[client].new_auction.Close();
					
					char item_name[64];
					auction.item.GetName(item_name, sizeof(item_name));
					
					PrintToChatAll("%s \x0E%N\x01 just listed a new auction for \x03%s\x01 at the value of \x04%s credits!\x01", PREFIX, client, item_name, JB_AddCommas(auction.value));
					PrintToChatAll("%s \x09Type \x10/ah\x09 to hop in!", PREFIX);
				}
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayAuctionHouseMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void DisplayItemSelectionMenu(int client)
{
	Menu menu = new Menu(Handler_ItemSelection);
	menu.SetTitle("%s Auction House - Item Selection\n ", PREFIX_MENU);
	
	menu.AddItem("", "Shop Items");
	menu.AddItem("", "Personal Runes");
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_ItemSelection(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			switch (selected_item)
			{
				case 0:
				{
					DisplayShopCategoriesMenu(client);
				}
				case 1:
				{
					DisplayPersonalRunesMenu(client);
				}
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayCreateAuctionMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void DisplayShopCategoriesMenu(int client)
{
	Menu menu = new Menu(Handler_ShopCategories);
	menu.SetTitle("%s Auction House - Selecting Shop Item:\n ", PREFIX_MENU);
	
	// Make sure the filling has succeed
	if (!FillCategories(client, menu) || !menu.ItemCount)
	{
		PrintToChat(client, "%s You don't have any shop items!", PREFIX_ERROR);
		DisplayItemSelectionMenu(client);
		delete menu;
		return;
	}
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_ShopCategories(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			// Initiailize the category id
			char item_info[64];
			menu.GetItem(selected_item, item_info, sizeof(item_info));
			
			CategoryId category_id = Shop_GetCategoryId(item_info);
			
			// Make sure the category id is valid
			if (Shop_IsValidCategory(category_id))
			{
				DisplayCategoryItemsMenu(client, category_id);
			}
			else
			{
				// Notify the client
				PrintToChat(client, "%s The selected shop category is \x02invalid\x01, please select another.", PREFIX_ERROR);
				
				// Display the menu again
				DisplayShopCategoriesMenu(client);
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayItemSelectionMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void DisplayCategoryItemsMenu(int client, CategoryId category_id)
{
	char category_name[64];
	if (!Shop_GetCategoryNameById(category_id, category_name, sizeof(category_name)))
	{
		PrintToChat(client, "%s Failed retrieving category name.", PREFIX_ERROR);
		DisplayShopCategoriesMenu(client);
		return;
	}
	
	Menu menu = new Menu(Handler_CategoryItems);
	menu.SetTitle("%s Auction House: \n \n• Selecting a shop item from %s\n ", PREFIX_MENU, category_name);
	
	// Make sure the filling has succeed
	if (!FillCategoryItems(client, menu, category_id) || !menu.ItemCount)
	{
		PrintToChat(client, "%s You don't have any items in this shop category!", PREFIX_ERROR);
		DisplayShopCategoriesMenu(client);
		delete menu;
		return;
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_CategoryItems(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			// Initialize the selected item id
			char item_info[16];
			menu.GetItem(selected_item, item_info, sizeof(item_info));
			ItemId item_id = view_as<ItemId>(StringToInt(item_info));
			
			char item_unique[64];
			Shop_GetItemById(item_id, item_unique, sizeof(item_unique));
			
			CategoryId category_id = Shop_GetItemCategoryId(item_id);
			
			// Make sure the client actually has the selected item
			if (!Shop_IsClientHasItem(client, item_id))
			{
				PrintToChat(client, "%s You no longer have the selected shop item, please choose another.", PREFIX_ERROR);
				DisplayCategoryItemsMenu(client, category_id);
				return 0;
			}
			
			g_Players[client].new_auction.item.shop_item_id = item_id;
			
			DisplayCreateAuctionMenu(client);
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayShopCategoriesMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void DisplayPersonalRunesMenu(int client)
{
	Menu menu = new Menu(Handler_PersonalRunes);
	menu.SetTitle("%s Auction House - Selecting a Personal Rune:\n ", PREFIX_MENU);
	
	// Make sure the filling has succeed
	if (!FillPersonalRunes(client, menu) || !menu.ItemCount)
	{
		PrintToChat(client, "%s You don't have any personal runes in your inventory!", PREFIX_ERROR);
		DisplayItemSelectionMenu(client);
		delete menu;
		return;
	}
	
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_PersonalRunes(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			// Initialize the selected rune index
			char item_info[4];
			menu.GetItem(selected_item, item_info, sizeof(item_info));
			int client_rune_index = StringToInt(item_info);
			
			ClientRune client_rune;
			JB_GetClientRuneData(client, client_rune_index, client_rune);
			
			// Make sure the client actually has the selected rune
			if (JB_IsClientHasRune(client, client_rune.RuneId, client_rune.RuneStar, client_rune.RuneLevel) == -1)
			{
				PrintToChat(client, "%s You no longer have the selected rune, please select another.", PREFIX_ERROR);
				DisplayPersonalRunesMenu(client);
				return 0;
			}
			
			Rune rune;
			JB_GetRuneData(client_rune.RuneId, rune);
			
			g_Players[client].new_auction.item.InitRuneItem(rune, client_rune);
			
			DisplayCreateAuctionMenu(client);
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayItemSelectionMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

//================================[ Database ]================================//

Action Timer_EndAuction(Handle timer, int row_id)
{
	Auction auction;
	int idx;
	
	if (!auction.FindByRowID(row_id, idx))
	{
		return Plugin_Continue;
	}
	
	auction.ReturnItemToOwner();
	auction.DeleteData();
	
	auction.Close();
	g_Auctions.Erase(idx);
	
	return Plugin_Continue;
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_auctions` \
    ( \
         `id` INT AUTO_INCREMENT NOT NULL, \
         `owner_account_id` INT NOT NULL DEFAULT 0, \
         `owner_name` VARCHAR(128) NOT NULL DEFAULT '', \
         `start_time` INT NOT NULL DEFAULT 0, \
         `end_time` INT NOT NULL DEFAULT 0, \
         `value` INT NOT NULL DEFAULT 0, \
         `shop_item_id` INT NOT NULL DEFAULT 0, \
         `rune_identifier` VARCHAR(64) NOT NULL DEFAULT '', \
         `rune_star` INT NOT NULL DEFAULT 0, \
         `rune_level` INT NOT NULL DEFAULT 0, \
         PRIMARY KEY (`id`) \
    )");
	
	SQL_FetchAuctions();
}

void SQL_FetchAuctions()
{
	g_Database.Query(SQL_FetchAuctions_CB, "SELECT * FROM `jb_auctions`");
}

void SQL_FetchAuctions_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("[SQL_FetchAuctions_CB] %s", error);
	}
	
	while (results.FetchRow())
	{
		Auction new_auction;
		new_auction.FetchData(results);
	}
}

void SQL_InsertAuction_CB(Database db, DBResultSet results, const char[] error, DataPack dp)
{
	if (!db || !results || error[0])
	{
		dp.Close();
		ThrowError("[SQL_InsertAuction_CB] %s", error);
	}
	
	dp.Reset();
	
	int owner_account_id = dp.ReadCell();
	int start_time = dp.ReadCell();
	
	dp.Close();
	
	Auction auction;
	int idx;
	
	if (!auction.FindNoRowID(owner_account_id, start_time, idx))
	{
		ThrowError("[SQL_InsertAuction_CB] Failed to find auction. (owner_account_id: %d, start_time: %d)", owner_account_id, start_time);
		return;
	}
	
	auction.row_id = results.InsertId;
	auction.HandleEndAuctionTimer();
	
	g_Auctions.SetArray(idx, auction);
}

// An error has occurred
void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error (Error: %s)", error);
	}
}

//================================[ Utils ]================================//

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsClientAuthorized(current_client))
		{
			OnClientAuthorized(current_client, "");
		}
	}
}

void AccountIDToSteam2(int account_id, char auth[MAX_AUTHID_LENGTH])
{
	Format(auth, sizeof(auth), "STEAM_1:%d:%d", account_id % 2, account_id / 2);
}

// Param 'duration' is minutes represented.
void FormatMinutes(int minutes, char[] buffer, int length)
{
	if (minutes < 0)
	{
		return;
	}
	
	buffer[0] = '\0';
	
	int totalMinutes = minutes % 60;
	int totalHours = (minutes / 60) % 24;
	int totalDays = (minutes / (60 * 24)) % 7;
	int totalWeeks = minutes / (60 * 24 * 7);
	
	if (totalWeeks > 0)
	{
		Format(buffer, length, "%d Week%s", totalWeeks, totalWeeks != 1 ? "s" : "");
	}
	
	if (totalDays > 0)
	{
		Format(buffer, length, "%s%s%d Day%s", buffer, buffer[0] ? ", " : "", totalDays, totalDays != 1 ? "s" : "");
	}
	
	if (totalHours > 0)
	{
		Format(buffer, length, "%s%s%d Hour%s", buffer, buffer[0] ? ", " : "", totalHours, totalHours != 1 ? "s" : "");
	}
	
	if (totalMinutes > 0)
	{
		Format(buffer, length, "%s%s%d Minute%s", buffer, buffer[0] ? ", " : "", totalMinutes, totalMinutes != 1 ? "s" : "");
	}
}

int GetDurationIndex(int duration)
{
	for (int current_duration; current_duration < sizeof(g_AuctionDurations); current_duration++)
	{
		if (g_AuctionDurations[current_duration] == duration)
		{
			return current_duration;
		}
	}
	
	return -1;
}

bool FillCategories(int client, Menu menu)
{
	ArrayList client_items = Shop_GetClientItems(client);
	
	if (!client_items.Length)
	{
		delete client_items;
		return false;
	}
	
	ItemId item_id;
	
	ArrayList menu_items = new ArrayList();
	
	CategoryId category_id;
	
	char item_unique[64];
	
	for (int current_item = 0; current_item < client_items.Length; current_item++)
	{
		item_id = client_items.Get(current_item);
		
		Shop_GetItemById(item_id, item_unique, sizeof(item_unique));
		
		category_id = Shop_GetItemCategoryId(item_id);
		
		if (Shop_IsValidCategory(category_id) && menu_items.FindValue(category_id) == -1)
		{
			menu_items.Push(category_id);
		}
	}
	
	menu_items.Sort(Sort_Ascending, Sort_Integer);
	
	char category_name[64], category_unique[64];
	
	for (int current_category = 0; current_category < menu_items.Length; current_category++)
	{
		category_id = menu_items.Get(current_category);
		
		Shop_GetCategoryById(category_id, category_unique, sizeof(category_unique));
		Shop_GetCategoryNameById(category_id, category_name, sizeof(category_name));
		
		menu.AddItem(category_unique, category_name);
	}
	
	delete client_items;
	delete menu_items;
	
	return true;
}

bool FillCategoryItems(int client, Menu menu, CategoryId category_id)
{
	ArrayList client_items = Shop_GetClientItems(client);
	
	if (!client_items.Length)
	{
		delete client_items;
		return false;
	}
	
	char item_name[64], item_info[16];
	
	ItemId item_index;
	
	for (int current_item = 0; current_item < client_items.Length; current_item++)
	{
		item_index = client_items.Get(current_item);
		
		if (Shop_GetItemCategoryId(item_index) == category_id && Shop_GetItemNameById(item_index, item_name, sizeof(item_name)))
		{
			Format(item_name, sizeof(item_name), "[%s] %s%s", AddCommas(Shop_GetItemPrice(item_index)), item_name, Shop_IsClientItemToggled(client, item_index) ? " [Toggled]" : "");
			
			IntToString(view_as<int>(item_index), item_info, sizeof(item_info));
			menu.AddItem(item_info, item_name);
		}
	}
	
	delete client_items;
	
	return true;
}

bool FillPersonalRunes(int client, Menu menu)
{
	int client_runes_amount = JB_GetClientRunesAmount(client);
	if (!client_runes_amount)
	{
		return false;
	}
	
	char item_name[64], item_info[4];
	
	ClientRune client_rune;
	Rune rune;
	
	for (int current_client_rune = 0; current_client_rune < client_runes_amount; current_client_rune++)
	{
		JB_GetClientRuneData(client, current_client_rune, client_rune);
		JB_GetRuneData(client_rune.RuneId, rune);
		
		Format(item_name, sizeof(item_name), "%s | %d%s(Level %d)%s", rune.szRuneName, client_rune.RuneStar, RUNE_STAR_SYMBOL, client_rune.RuneLevel, client_rune.IsRuneEquipped ? " [Equipped]" : "");
		
		IntToString(current_client_rune, item_info, sizeof(item_info));
		menu.AddItem(item_info, item_name);
	}
	
	return true;
}

bool InterceptValueString(int client, const char[] value_str, int &result)
{
	if (StrEqual(value_str, "all", false))
	{
		result = Shop_GetClientCredits(client);
		return true;
	}
	
	// Floating point value convertion.
	float fp_value;
	
	if (!StringToFloatEx(value_str, fp_value))
	{
		PrintToChat(client, "%s Invalid price was given. (\x02%s\x01)", PREFIX_ERROR, value_str);
		return false;
	}
	
	if (fp_value <= 0.0)
	{
		PrintToChat(client, "%s The auction price must be greater than 0.", PREFIX_ERROR);
		return false;
	}
	
	char value_multiply_char = value_str[strlen(value_str) - 1];
	switch (value_multiply_char)
	{
		case 'k':
		{
			fp_value *= 1000.0;
		}
		case 'm':
		{
			fp_value *= 1000000.0;
		}
	}
	
	result = RoundToCeil(fp_value);
	return true;
}

// 0 on failure.
int GetClientOfAccountId(int account_id)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_Players[current_client].account_id == account_id)
		{
			return current_client;
		}
	}
	
	return 0;
}

Player GetPlayer(int idx)
{
	return g_Players[idx];
}

//================================================================//