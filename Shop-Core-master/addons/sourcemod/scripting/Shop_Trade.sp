#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <shop>

#undef REQUIRE_PLUGIN
#include <JB_RunesSystem>
#include <JB_SettingsSystem>
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

//==========[ Settings ]==========//

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_MENU "[Level9]"
#define PREFIX_ERROR " \x02[Error]\x01"

#define RUNES_LIBRARY_NAME "JB_RunesSystem"
#define SETTINGS_LIBRARY_NAME "JB_SettingsSystem"

#define READY_STATE_CHANGE_SOUND "playil_shop/trade/tradeready.mp3"
#define TRADE_SUCCESS_SOUND "playil_shop/trade/tradesuccess.mp3"

#define INVITE_EXPIRE_SECONDS 10
#define MAX_TRADE_ADDED_ITEMS 5

#define ABORT_SYMBOL "-1"

//====================//

enum struct TradeItem
{
	char ItemUnique[64];
	CategoryId CategoryID;
	
	int ItemStar;
	int ItemLevel;
	
	void InitItem(CategoryId category_id = INVALID_CATEGORY, char[] item_unique, int item_star = -1, int item_level = -1)
	{
		this.CategoryID = category_id;
		strcopy(this.ItemUnique, sizeof(TradeItem::ItemUnique), item_unique);
		this.ItemStar = item_star;
		this.ItemLevel = item_level;
	}
}

enum struct Client
{
	ArrayList AddedItems;
	
	bool IsReadyState;
	bool IsWriting;
	
	int userid;
	int partner_index;
	int inserted_credits;
	
	int invited_userid;
	int invite_unixstamp;
	
	void Reset(bool fully_reset = true)
	{
		delete this.AddedItems;
		
		this.IsReadyState = false;
		this.IsWriting = false;
		
		this.userid = fully_reset ? 0 : this.userid;
		this.partner_index = 0;
		this.inserted_credits = 0;
		
		this.invited_userid = 0;
		this.invite_unixstamp = 0;
	}
	
	void Init()
	{
		delete this.AddedItems;
		this.AddedItems = new ArrayList(sizeof(TradeItem));
	}
	
	bool IsTrading()
	{
		return (this.partner_index != 0 && IsClientInGame(this.partner_index));
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ConVar g_CreditsTaxPercentage;

ConVar g_MaxMoney;
ConVar g_DisableRader;

char g_DefaultMaxMoney[8];

bool g_IsRunesLoaded;
bool g_IsSettingsLoaded;

int g_TradeInvitesSettingIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Trade", 
	author = PLUGIN_AUTHOR, 
	description = "An additional trade Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// ConVars Configurate
	g_CreditsTaxPercentage = CreateConVar("shop_trade_credits_tax_percentage", "5", "Credits percentage to take down when credits being transferred. (0 To disable)", _, true, 0.0, true, 100.0);
	
	g_MaxMoney = FindConVar("mp_maxmoney");
	g_DisableRader = FindConVar("sv_disable_radar");
	
	AutoExecConfig(true, "ShopTrade", "shop");
	
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Client Commands
	RegConsoleCmd("sm_trade", Command_Trade, "Send to a certain player a trade invitation.");
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, RUNES_LIBRARY_NAME))
	{
		g_IsRunesLoaded = true;
	}
	else if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		JB_CreateSettingCategory("Shop Settings", "This category is associated with settings that related to the shop.", -1);
		
		g_TradeInvitesSettingIndex = JB_CreateSetting("setting_ignore_trade_invites", "Decides whether or not to ignore items trade invites. (Bool setting)", "Ignore Trade Invites", "Shop Settings", Setting_Bool, 1, "0");
		
		g_IsSettingsLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, RUNES_LIBRARY_NAME))
	{
		g_IsRunesLoaded = false;
	}
	else if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		g_IsSettingsLoaded = false;
	}
}

public void OnMapStart()
{
	// Initialize the default max money for the current map
	g_MaxMoney.GetString(g_DefaultMaxMoney, sizeof(g_DefaultMaxMoney));
	
	AddFileToDownloadsTable("sound/"...READY_STATE_CHANGE_SOUND);
	AddFileToDownloadsTable("sound/"...TRADE_SUCCESS_SOUND);
	
	PrecacheSound(READY_STATE_CHANGE_SOUND);
	PrecacheSound(TRADE_SUCCESS_SOUND);
}

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
	
	// Initialize the client userid
	g_ClientsData[client].userid = GetClientUserId(client);
}

public void OnClientDisconnect(int client)
{
	if (g_ClientsData[client].IsTrading())
	{
		ShowAlertPanel(g_ClientsData[client].partner_index, "%s Trading With - %N\n \nYour trade partner has disconnected,\ntherefore the trade has been cancelled.", PREFIX_MENU, client);
		
		g_ClientsData[g_ClientsData[client].partner_index].Reset(false);
		delete g_ClientsData[client].AddedItems;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// If the client isn't in writing state, or he's not trading, don't continue
	if (!g_ClientsData[client].IsWriting || !g_ClientsData[client].IsTrading())
	{
		// Set the writing state boolean to false
		g_ClientsData[client].IsWriting = false;
		
		return Plugin_Continue;
	}
	
	// The client wants to abort the credits insert operation
	if (StrEqual(sArgs, ABORT_SYMBOL))
	{
		// Display the trade menu again
		ShowTradeMainMenu(client);
		
		// Set the writing state boolean to false
		g_ClientsData[client].IsWriting = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	int client_credits = Shop_GetClientCredits(client);
	
	// Initialize the specified credits amount, and verify it
	int credits_amount = (StrEqual(sArgs, "all") ? client_credits : StrContains(sArgs, "k") != -1 ? StringToInt(sArgs) * 1000 : StringToInt(sArgs));
	
	if (!credits_amount)
	{
		PrintToChat(client, "%s You have specifed an invalid credits amount. [\x02%s\x01]", PREFIX, sArgs);
		
		// Display the trade menu again
		ShowTradeMainMenu(client);
		
		// Set the writing state boolean to false
		g_ClientsData[client].IsWriting = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	credits_amount += g_ClientsData[client].inserted_credits;
	
	if (credits_amount < 0)
	{
		PrintToChat(client, "%s Inserting credits below \x0B0\x01 is not possible, please try again.", PREFIX);
		
		// Display the trade menu again
		ShowTradeMainMenu(client);
		
		// Set the writing state boolean to false
		g_ClientsData[client].IsWriting = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	// Make sure the client has enough shop credits for the trade
	if (client_credits < credits_amount)
	{
		PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", AddCommas(credits_amount - client_credits));
		
		// Display the trade menu again
		ShowTradeMainMenu(client);
		
		// Set the writing state boolean to false
		g_ClientsData[client].IsWriting = false;
		
		// Block the message send
		return Plugin_Handled;
	}
	
	// Apply the credits change
	g_ClientsData[client].inserted_credits = credits_amount;
	
	// Display the trade menu to the both clients
	ShowTradeMainMenu(client);
	ShowTradeMainMenu(g_ClientsData[client].partner_index);
	
	// Set the writing state boolean to false
	g_ClientsData[client].IsWriting = false;
	
	// Block the message send
	return Plugin_Handled;
}

//================================[ Commands ]================================//

public Action Command_Trade(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure the client is not trading
	if (g_ClientsData[client].IsTrading())
	{
		ShowTradeMainMenu(client);
		return Plugin_Handled;
	}
	
	// If no arguments were detected, print the command usage
	if (args < 1)
	{
		PrintToChat(client, "%s Usage: \x04/trade\x01 <#userid|name>", PREFIX);
		return Plugin_Handled;
	}
	
	int invited_index;
	
	// Check for the gamble cooldown
	if (GetTime() - g_ClientsData[client].invite_unixstamp < INVITE_EXPIRE_SECONDS && (invited_index = GetClientOfUserId(g_ClientsData[client].invited_userid)) != 0)
	{
		PrintToChat(client, "%s Please wait till your invitation to \x04%N\x01 will be expired.", PREFIX, invited_index);
		return Plugin_Handled;
	}
	
	// Initialize the target index, by the specified arguments
	char arg_name[MAX_NAME_LENGTH];
	GetCmdArgString(arg_name, sizeof(arg_name));
	int target_index = FindTarget(client, arg_name, true, false);
	
	// Make sure the target is found and valid
	if (target_index == -1)
	{
		// Automatec message
		return Plugin_Handled;
	}
	
	if (target_index == client)
	{
		PrintToChat(client, "%s You cannot \x10trade\x01 invite yourself!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_IsSettingsLoaded)
	{
		char setting_value[8];
		JB_GetClientSetting(target_index, g_TradeInvitesSettingIndex, setting_value, sizeof(setting_value));
		
		if (StrEqual(setting_value, "1"))
		{
			PrintToChat(client, "%s \x07%N\x01 is \x02ignoring\x01 trade invites!", PREFIX_ERROR, target_index);
			return Plugin_Handled;
		}
	}
	
	// Make sure the target is not trading
	if (g_ClientsData[target_index].IsTrading())
	{
		PrintToChat(client, "%s \x07%N\x01 is currently trading with someone else, please wait till he will finish.", PREFIX_ERROR, target_index);
		return Plugin_Handled;
	}
	
	// Notify the inviter
	PrintToChat(client, "%s Successfully invited \x04%N\x01 for a \x10trade\x01!", PREFIX, target_index);
	
	// Apply the invite cooldown
	g_ClientsData[client].invite_unixstamp = GetTime();
	
	g_ClientsData[client].invited_userid = g_ClientsData[target_index].userid;
	
	ShowTradeInvitationMenu(target_index, client);
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowTradeInvitationMenu(int client, int inviter)
{
	char item_info[16];
	
	Menu menu = new Menu(Handler_TradeInvitation);
	menu.SetTitle("%s %N is inviting you for a trade!\n ", PREFIX_MENU, inviter);
	
	IntToString(g_ClientsData[inviter].userid, item_info, sizeof(item_info));
	menu.AddItem(item_info, "Accept");
	
	menu.AddItem("", "Decline");
	
	// Disable the exit button
	menu.ExitButton = false;
	
	// Display the menu to the client
	menu.Display(client, INVITE_EXPIRE_SECONDS);
}

public int Handler_TradeInvitation(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[16];
		
		// Get the inviter client index
		menu.GetItem(0, item_info, sizeof(item_info));
		int inviter_index = GetClientOfUserId(StringToInt(item_info));
		
		// Make sure the inviter index is still in-game and valid
		if (!inviter_index)
		{
			PrintToChat(client, "%s The \x10trade\x01 inviter is no longer in-game.", PREFIX_ERROR);
			return 0;
		}
		
		switch (item_position)
		{
			// The client has accepted the invite
			case 0:
			{
				// Make sure the client isn't in a middle of a trade
				if (g_ClientsData[client].IsTrading())
				{
					PrintToChat(client, "%s You're already playing a \x10trade\x01 game!", PREFIX_ERROR);
					return 0;
				}
				
				// Make sure the inviter isn't in a middle of a trade
				if (g_ClientsData[inviter_index].IsTrading())
				{
					PrintToChat(client, "%s Inviter \x07%N\x01 is already in a \x10trade\x01 game!", PREFIX_ERROR, inviter_index);
					return 0;
				}
				
				g_ClientsData[client].Reset(false);
				g_ClientsData[inviter_index].Reset(false);
				
				g_ClientsData[client].partner_index = inviter_index;
				g_ClientsData[inviter_index].partner_index = client;
				
				g_ClientsData[client].Init();
				g_ClientsData[inviter_index].Init();
				
				ShowTradeMainMenu(client);
				ShowTradeMainMenu(inviter_index);
			}
			
			// The client has declined the invite
			case 1:
			{
				// Notify the inviter about the decline
				PrintToChat(inviter_index, "%s \x07%N\x01 has declined your \x10trade\x01 invitation.", PREFIX, client);
				
				g_ClientsData[inviter_index].invited_userid = 0;
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowTradeMainMenu(int client)
{
	char item_display[512];
	Menu menu = new Menu(Handler_TradeMain);
	menu.SetTitle("%s Trading With - %N\n%s\nReady State: %s\n ", PREFIX_MENU, g_ClientsData[client].partner_index, GetTradeAddedItems(client), g_ClientsData[client].IsReadyState ? "✔":"✘");
	
	Format(item_display, sizeof(item_display), "Add Items\n %s\n%N's Ready State: %s\n ", GetTradeAddedItems(g_ClientsData[client].partner_index), g_ClientsData[client].partner_index, g_ClientsData[g_ClientsData[client].partner_index].IsReadyState ? "✔":"✘");
	menu.AddItem("", item_display);
	menu.AddItem("", g_ClientsData[client].IsReadyState ? "Unready" : "Ready");
	menu.AddItem("", "Cancel Trade");
	
	// Disable the menu exit button
	menu.ExitButton = false;
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
	
	// Hide the client's hud panel to allow to menu fully visuallize
	HideClientHud(client, true);
}

public int Handler_TradeMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				ShowAddItemsMenu(client);
			}
			case 1:
			{
				g_ClientsData[client].IsReadyState = !g_ClientsData[client].IsReadyState;
				
				EmitSoundToClient(client, READY_STATE_CHANGE_SOUND, .volume = 0.2);
				EmitSoundToClient(g_ClientsData[client].partner_index, READY_STATE_CHANGE_SOUND, .volume = 0.2);
				
				if (g_ClientsData[client].IsReadyState && g_ClientsData[g_ClientsData[client].partner_index].IsReadyState)
				{
					// Make sure the trade is valid
					if (!IsValidTrade(client, g_ClientsData[client].partner_index))
					{
						return 0;
					}
					
					ShowAlertPanel(client, "%s Trading With - %N\n \nTrade has been succeed!", PREFIX_MENU, g_ClientsData[client].partner_index);
					ShowAlertPanel(g_ClientsData[client].partner_index, "%s Trading With - %N\n \nTrade has been succeed!", PREFIX_MENU, client);
					
					ExecuteTrade(client, g_ClientsData[client].partner_index);
					
					EmitSoundToClient(client, TRADE_SUCCESS_SOUND, .volume = 0.2);
					EmitSoundToClient(g_ClientsData[client].partner_index, TRADE_SUCCESS_SOUND, .volume = 0.2);
					
					g_ClientsData[g_ClientsData[client].partner_index].Reset(false);
					g_ClientsData[client].Reset(false);
				}
				else
				{
					ShowTradeMainMenu(client);
					ShowTradeMainMenu(g_ClientsData[client].partner_index);
				}
			}
			case 2:
			{
				ShowAlertPanel(client, "%s Trading With - %N\n \nTrade has been cancelled!", PREFIX_MENU, g_ClientsData[client].partner_index);
				ShowAlertPanel(g_ClientsData[client].partner_index, "%s Trading With - %N\n \nTrade has been cancelled!", PREFIX_MENU, client);
				
				g_ClientsData[g_ClientsData[client].partner_index].Reset(false);
				HideClientHud(g_ClientsData[client].partner_index, false);
				
				g_ClientsData[client].Reset(false);
				HideClientHud(client, false);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// Display the hud panel to the client again
		HideClientHud(param1, false);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowAddItemsMenu(int client)
{
	Menu menu = new Menu(Handler_AddItems);
	menu.SetTitle("%s Trading With - %N\n• Adding Items\n ", PREFIX_MENU, g_ClientsData[client].partner_index);
	
	menu.AddItem("", g_ClientsData[client].AddedItems.Length < MAX_TRADE_ADDED_ITEMS ? "Shop Items" : "Shop Items [Limit Reached]", g_ClientsData[client].AddedItems.Length < MAX_TRADE_ADDED_ITEMS ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("", "Insert Credits");
	
	if (g_IsRunesLoaded)
	{
		menu.AddItem("", g_ClientsData[client].AddedItems.Length < MAX_TRADE_ADDED_ITEMS ? "Personal Runes" : "Personal Runes [Limit Reached]", g_ClientsData[client].AddedItems.Length < MAX_TRADE_ADDED_ITEMS ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
	
	// Hide the client's hud panel to allow to menu fully visuallize
	HideClientHud(client, true);
}

public int Handler_AddItems(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (item_position != 1 && g_ClientsData[client].AddedItems && g_ClientsData[client].AddedItems.Length >= MAX_TRADE_ADDED_ITEMS)
		{
			PrintToChat(client, "%s You've already reached the maximum available trade items.", PREFIX_ERROR);
			ShowTradeMainMenu(client);
			return 0;
		}
		
		switch (item_position)
		{
			case 0:
			{
				// Display the client's shop categories menu
				ShowShopCategoriesMenu(client);
			}
			case 1:
			{
				// Set the writing boolean to true, meaning the client wants to insert credits
				g_ClientsData[client].IsWriting = true;
				
				// Notify the client
				PrintToChat(client, "%s Type your desired insert \x10credits\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 2:
			{
				// Display the client's personal runes inventory
				ShowPersonalRunesMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// Display the hud panel to the client again
		HideClientHud(param1, false);
		
		// Display the last menu the client was in
		if (param2 == MenuCancel_ExitBack)
		{
			ShowTradeMainMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowShopCategoriesMenu(int client)
{
	Menu menu = new Menu(Handler_ShopCategories);
	menu.SetTitle("%s Trading With - %N\n• Adding Shop Items\n ", PREFIX_MENU, g_ClientsData[client].partner_index);
	
	// Make sure the filling has succeed
	if (!FillCategories(client, menu))
	{
		PrintToChat(client, "%s You don't have any shop items!", PREFIX_ERROR);
		ShowTradeMainMenu(client);
		delete menu;
		return;
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
	
	// Hide the client's hud panel to allow to menu fully visuallize
	HideClientHud(client, true);
}

public int Handler_ShopCategories(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (g_ClientsData[client].AddedItems.Length >= MAX_TRADE_ADDED_ITEMS)
		{
			PrintToChat(client, "%s You've already reached the maximum available trade items.", PREFIX_ERROR);
			ShowTradeMainMenu(client);
			return 0;
		}
		
		// Initiailize the category id
		char item_info[64];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		
		CategoryId category_id = Shop_GetCategoryId(item_info);
		
		// Make sure the category id is valid
		if (Shop_IsValidCategory(category_id))
		{
			ShowCategoryItemsMenu(client, category_id);
		}
		else
		{
			// Notify the client
			PrintToChat(client, "%s The selected shop category is \x02invalid\x01, please select another.", PREFIX_ERROR);
			
			// Display the menu again
			ShowShopCategoriesMenu(client);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// Display the hud panel to the client again
		HideClientHud(param1, false);
		
		// Display the last menu the client was in
		if (param2 == MenuCancel_ExitBack)
		{
			ShowAddItemsMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowCategoryItemsMenu(int client, CategoryId category_id)
{
	Menu menu = new Menu(Handler_CategoryItems);
	menu.SetTitle("%s Trading With - %N\n• Adding Shop Items\n ", PREFIX_MENU, g_ClientsData[client].partner_index);
	
	// Make sure the filling has succeed
	if (!FillCategoryItems(client, menu, category_id))
	{
		ShowShopCategoriesMenu(client);
		PrintToChat(client, "%s You don't have any items in this shop category!", PREFIX_ERROR);
		delete menu;
		return;
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
	
	// Hide the client's hud panel to allow to menu fully visuallize
	HideClientHud(client, true);
}

public int Handler_CategoryItems(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (g_ClientsData[client].AddedItems.Length >= MAX_TRADE_ADDED_ITEMS)
		{
			PrintToChat(client, "%s You've already reached the maximum available trade items.", PREFIX_ERROR);
			ShowTradeMainMenu(client);
			return 0;
		}
		
		// Initialize the selected item id
		char item_info[16];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		ItemId item_id = view_as<ItemId>(StringToInt(item_info));
		
		char item_unique[64];
		Shop_GetItemById(item_id, item_unique, sizeof(item_unique));
		
		CategoryId category_id = Shop_GetItemCategoryId(item_id);
		
		// Make sure the client actually has the selected item
		if (!Shop_IsClientHasItem(client, item_id))
		{
			PrintToChat(client, "%s You no longer have the selected shop item, please choose another.", PREFIX_ERROR);
			ShowCategoryItemsMenu(client, category_id);
			return 0;
		}
		
		TradeItem TradeItemData;
		TradeItemData.InitItem(category_id, item_unique);
		g_ClientsData[client].AddedItems.PushArray(TradeItemData);
		
		ShowTradeMainMenu(client);
		ShowTradeMainMenu(g_ClientsData[client].partner_index);
	}
	else if (action == MenuAction_Cancel)
	{
		// Display the hud panel to the client again
		HideClientHud(param1, false);
		
		// Display the last menu the client was in
		if (param2 == MenuCancel_ExitBack)
		{
			ShowShopCategoriesMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowPersonalRunesMenu(int client)
{
	Menu menu = new Menu(Handler_PersonalRunes);
	menu.SetTitle("%s Trading With - %N\n• Adding Personal Runes\n ", PREFIX_MENU, g_ClientsData[client].partner_index);
	
	// Make sure the filling has succeed
	if (!FillPersonalRunes(client, menu) || !menu.ItemCount)
	{
		ShowAddItemsMenu(client);
		PrintToChat(client, "%s You don't have any personal runes in your inventory!", PREFIX_ERROR);
		delete menu;
		return;
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
	
	// Hide the client's hud panel to allow to menu fully visuallize
	HideClientHud(client, true);
}

public int Handler_PersonalRunes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (g_ClientsData[client].AddedItems.Length >= MAX_TRADE_ADDED_ITEMS)
		{
			PrintToChat(client, "%s You've already reached the maximum available trade items.", PREFIX_ERROR);
			ShowTradeMainMenu(client);
			return 0;
		}
		
		// Initialize the selected rune index
		char item_info[4];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int client_rune_index = StringToInt(item_info);
		
		ClientRune ClientRuneData;
		Rune RuneData;
		
		JB_GetClientRuneData(client, client_rune_index, ClientRuneData);
		JB_GetRuneData(ClientRuneData.RuneId, RuneData);
		
		// Make sure the client actually has the selected rune
		if (JB_IsClientHasRune(client, ClientRuneData.RuneId, ClientRuneData.RuneStar, ClientRuneData.RuneLevel) == -1)
		{
			PrintToChat(client, "%s You no longer have the selected rune, please select another.", PREFIX_ERROR);
			ShowPersonalRunesMenu(client);
			return 0;
		}
		
		TradeItem TradeItemData;
		TradeItemData.InitItem(_, RuneData.szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
		g_ClientsData[client].AddedItems.PushArray(TradeItemData);
		
		ShowTradeMainMenu(client);
		ShowTradeMainMenu(g_ClientsData[client].partner_index);
	}
	else if (action == MenuAction_Cancel)
	{
		// Display the hud panel to the client again
		HideClientHud(param1, false);
		
		// Display the last menu the client was in
		if (param2 == MenuCancel_ExitBack)
		{
			ShowAddItemsMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowAlertPanel(int client, const char[] message, any...)
{
	char formatted_message[256];
	VFormat(formatted_message, sizeof(formatted_message), message, 3);
	
	Panel panel = new Panel();
	panel.DrawText(formatted_message);
	
	panel.CurrentKey = 8;
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	panel.Send(client, Handler_DoNothing, 2);
	
	delete panel;
}

int Handler_DoNothing(Menu menu, MenuAction action, int iPlayerIndex, int itemNum)
{
	// Do Nothing
	return 0;
}

//================================[ Functions ]================================//

any[] GetTradeItemByIndex(int client, int index)
{
	TradeItem TradeItemData;
	g_ClientsData[client].AddedItems.GetArray(index, TradeItemData);
	return TradeItemData;
}

char[] GetTradeAddedItems(int client)
{
	char formatted_items[MAX_TRADE_ADDED_ITEMS * 64];
	
	if (g_ClientsData[client].AddedItems == null || !g_ClientsData[client].AddedItems.Length && g_ClientsData[client].inserted_credits <= 0)
	{
		Format(formatted_items, sizeof(formatted_items), "\n• No item was added.");
		return formatted_items;
	}
	
	TradeItem TradeItemData;
	
	for (int current_item = 0; current_item < g_ClientsData[client].AddedItems.Length; current_item++)
	{
		TradeItemData = GetTradeItemByIndex(client, current_item);
		
		if ((TradeItemData.ItemStar == -1 && TradeItemData.ItemLevel == -1 && !Shop_IsClientHasItem(client, Shop_GetItemId(TradeItemData.CategoryID, TradeItemData.ItemUnique)))
			 || (TradeItemData.ItemStar != -1 && TradeItemData.ItemLevel != -1 && JB_IsClientHasRune(client, JB_FindRune(TradeItemData.ItemUnique), TradeItemData.ItemStar, TradeItemData.ItemLevel) == -1))
		{
			g_ClientsData[client].AddedItems.Erase(current_item--);
			continue;
		}
		
		Format(formatted_items, sizeof(formatted_items), "%s\n◾ %s%s", formatted_items, GetTradeItemName(client, current_item), current_item == g_ClientsData[client].AddedItems.Length - 1 && !g_ClientsData[client].inserted_credits ? "\n " : "");
	}
	
	if (g_ClientsData[client].inserted_credits > 0)
	{
		char tax_display[16];
		if (g_CreditsTaxPercentage.IntValue)
		{
			Format(tax_display, sizeof(tax_display), " [-%d%%]", g_CreditsTaxPercentage.IntValue);
		}
		
		Format(formatted_items, sizeof(formatted_items), "%s\n◾ Inserted Credits: %s%s\n ", formatted_items, AddCommas(g_ClientsData[client].inserted_credits), g_CreditsTaxPercentage.IntValue ? tax_display : "");
	}
	
	// Double check after comfirming the added trade items
	if (g_ClientsData[client].AddedItems == null || !g_ClientsData[client].AddedItems.Length && g_ClientsData[client].inserted_credits <= 0)
	{
		Format(formatted_items, sizeof(formatted_items), "\n• No item was added.");
		return formatted_items;
	}
	
	return formatted_items;
}

char[] GetTradeItemName(int client, int item_index)
{
	TradeItem TradeItemData; TradeItemData = GetTradeItemByIndex(client, item_index);
	
	char item_name[64];
	
	if (TradeItemData.ItemStar != -1 && TradeItemData.ItemLevel != -1)
	{
		int rune_index = JB_FindRune(TradeItemData.ItemUnique);
		
		if (rune_index != -1)
		{
			Rune RuneData;
			JB_GetRuneData(rune_index, RuneData);
			
			Format(item_name, sizeof(item_name), "%s | %d%s(Level %d)", RuneData.szRuneName, TradeItemData.ItemStar, RUNE_STAR_SYMBOL, TradeItemData.ItemLevel);
		}
	}
	else
	{
		ItemId item_id = Shop_GetItemId(TradeItemData.CategoryID, TradeItemData.ItemUnique);
		
		Shop_GetItemNameById(item_id, item_name, sizeof(item_name));
		Format(item_name, sizeof(item_name), "%s [%s]", item_name, AddCommas(Shop_GetItemPrice(item_id)));
	}
	
	return item_name;
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
		
		if (Shop_IsValidCategory(category_id) && menu_items.FindValue(category_id) == -1 && g_ClientsData[client].AddedItems.FindString(item_unique) == -1)
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
		
		if (Shop_GetItemCategoryId(item_index) == category_id && Shop_GetItemNameById(item_index, item_name, sizeof(item_name)) && g_ClientsData[client].AddedItems.FindString(item_name) == -1)
		{
			Format(item_name, sizeof(item_name), "[%s] %s", AddCommas(Shop_GetItemPrice(item_index)), item_name);
			
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
	
	ClientRune ClientRuneData;
	Rune RuneData;
	
	ArrayList array = g_ClientsData[client].AddedItems.Clone();
	
	int existing_item_index = -1;
	
	for (int current_client_rune = 0; current_client_rune < client_runes_amount; current_client_rune++)
	{
		JB_GetClientRuneData(client, current_client_rune, ClientRuneData);
		JB_GetRuneData(ClientRuneData.RuneId, RuneData);
		
		if ((existing_item_index = GetTradeItemIndex(RuneData.szRuneUnique, ClientRuneData, array)) != -1)
		{
			array.Erase(existing_item_index);
			continue;
		}
		
		Format(item_name, sizeof(item_name), "%s | %d%s(Level %d)", RuneData.szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel);
		
		IntToString(current_client_rune, item_info, sizeof(item_info));
		menu.AddItem(item_info, item_name);
	}
	
	delete array;
	
	return true;
}

bool IsValidTrade(int client, int partner)
{
	GetTradeAddedItems(client);
	GetTradeAddedItems(partner);
	
	if (g_ClientsData[client].AddedItems.Length)
	{
		// Filter the added trade items
		GetTradeAddedItems(client);
		
		if (!g_ClientsData[client].AddedItems.Length)
		{
			ShowAlertPanel(client, "%s Trading With - %N\n \nOne of you didn't add items to the trade,\ntherefore the trade has cancelled.", PREFIX_MENU, partner);
			ShowAlertPanel(partner, "%s Trading With - %N\n \nOne of you didn't add items to the trade,\ntherefore the trade has cancelled.", PREFIX_MENU, client);
			
			return false;
		}
	}
	
	if (g_ClientsData[partner].AddedItems.Length)
	{
		// Filter the added trade items
		GetTradeAddedItems(partner);
		
		if (!g_ClientsData[partner].AddedItems.Length)
		{
			ShowAlertPanel(partner, "%s Trading With - %N\n \nOne of you didn't add items to the trade,\ntherefore the trade has cancelled.", PREFIX_MENU, client);
			ShowAlertPanel(client, "%s Trading With - %N\n \nOne of you didn't add items to the trade,\ntherefore the trade has cancelled.", PREFIX_MENU, partner);
			
			return false;
		}
	}
	
	if ((g_ClientsData[client].inserted_credits > Shop_GetClientCredits(client)) || (g_ClientsData[partner].inserted_credits > Shop_GetClientCredits(partner)))
	{
		ShowAlertPanel(client, "%s Trading With - %N\n \nOne of you don't have enough credits to trade on,\ntherefore the trade has cancelled.", PREFIX_MENU, partner);
		ShowAlertPanel(partner, "%s Trading With - %N\n \nOne of you don't have enough credits to trade on,\ntherefore the trade has cancelled.", PREFIX_MENU, client);
		
		return false;
	}
	
	if (JB_GetClientRunesAmount(client) + GetTradedRunesCount(partner) > JB_GetClientRunesCapacity(client))
	{
		ShowAlertPanel(client, "%s Trading With - %N\n \nYour runes capacity is maxed out,\ntherefore the trade has cancelled.", PREFIX_MENU, partner);
		ShowAlertPanel(partner, "%s Trading With - %N\n \n%N's runes capacity is maxed out,\ntherefore the trade has cancelled.", PREFIX_MENU, client, client);
		
		return false;
	}
	
	if (JB_GetClientRunesAmount(partner) + GetTradedRunesCount(client) > JB_GetClientRunesCapacity(partner))
	{
		ShowAlertPanel(partner, "%s Trading With - %N\n \nYour runes capacity is maxed out,\ntherefore the trade has cancelled.", PREFIX_MENU, client);
		ShowAlertPanel(client, "%s Trading With - %N\n \n%N's runes capacity is maxed out,\ntherefore the trade has cancelled.", PREFIX_MENU, partner, partner);
		
		return false;
	}
	
	return true;
}

int GetTradeItemIndex(char[] unique, ClientRune data, ArrayList array)
{
	TradeItem TradeItemData;
	
	for (int current_item = 0; current_item < array.Length; current_item++)
	{
		array.GetArray(current_item, TradeItemData);
		
		if (StrEqual(unique, TradeItemData.ItemUnique) && data.RuneStar == TradeItemData.ItemStar && data.RuneLevel == TradeItemData.ItemLevel)
		{
			return current_item;
		}
	}
	
	return -1;
}

void ExecuteTrade(int client, int partner)
{
	WriteLogLine("Trade Succeed | \"%L\" - %s | \"%L\" - %s", client, GetTradeAddedItems(client), partner, GetTradeAddedItems(partner));
	
	TradeItem TradeItemData;
	
	for (int current_item = 0; current_item < g_ClientsData[client].AddedItems.Length; current_item++)
	{
		// Initialize the current item data by the current index
		TradeItemData = GetTradeItemByIndex(client, current_item);
		
		// The current item isn't rune!
		if (TradeItemData.ItemStar == -1 && TradeItemData.ItemLevel == -1)
		{
			ItemId item_id = Shop_GetItemId(TradeItemData.CategoryID, TradeItemData.ItemUnique);
			
			if (Shop_RemoveClientItem(client, item_id) && !Shop_GiveClientItem(partner, item_id))
			{
				WriteLogLine("Item transfer (%d) between \"%L\" to \"%L\" has been failed.", item_id, client, partner);
				Shop_GiveClientItem(client, item_id);
			}
		}
		else
		{
			int rune_index = JB_FindRune(TradeItemData.ItemUnique);
			
			if (JB_AddClientRune(partner, rune_index, TradeItemData.ItemStar, TradeItemData.ItemLevel))
			{
				JB_RemoveClientRune(client, JB_IsClientHasRune(client, rune_index, TradeItemData.ItemStar, TradeItemData.ItemLevel));
			}
		}
	}
	
	for (int current_item = 0; current_item < g_ClientsData[partner].AddedItems.Length; current_item++)
	{
		// Initialize the current item data by the current index
		TradeItemData = GetTradeItemByIndex(partner, current_item);
		
		// The current item isn't rune!
		if (TradeItemData.ItemStar == -1 && TradeItemData.ItemLevel == -1)
		{
			ItemId item_id = Shop_GetItemId(TradeItemData.CategoryID, TradeItemData.ItemUnique);
			
			if (Shop_RemoveClientItem(partner, item_id) && !Shop_GiveClientItem(client, item_id))
			{
				WriteLogLine("Item transfer (%d) between \"%L\" to \"%L\" has been failed.", item_id, partner, client);
				Shop_GiveClientItem(partner, item_id);
			}
		}
		else
		{
			int rune_index = JB_FindRune(TradeItemData.ItemUnique);
			
			if (JB_AddClientRune(client, rune_index, TradeItemData.ItemStar, TradeItemData.ItemLevel))
			{
				JB_RemoveClientRune(partner, JB_IsClientHasRune(partner, rune_index, TradeItemData.ItemStar, TradeItemData.ItemLevel));
			}
		}
	}
	
	if (g_ClientsData[client].inserted_credits)
	{
		Shop_TakeClientCredits(client, g_ClientsData[client].inserted_credits, CREDITS_BY_TRANSFER);
		Shop_GiveClientCredits(partner, RoundToZero(g_ClientsData[client].inserted_credits * (1.0 - (g_CreditsTaxPercentage.FloatValue / 100))), CREDITS_BY_TRANSFER);
	}
	
	if (g_ClientsData[partner].inserted_credits)
	{
		Shop_TakeClientCredits(partner, g_ClientsData[partner].inserted_credits, CREDITS_BY_TRANSFER);
		Shop_GiveClientCredits(client, RoundToZero(g_ClientsData[partner].inserted_credits * (1.0 - (g_CreditsTaxPercentage.FloatValue / 100))), CREDITS_BY_TRANSFER);
	}
}

int GetTradedRunesCount(int client)
{
	int counter;
	
	TradeItem TradeItemData;
	
	for (int current_item = 0; current_item < g_ClientsData[client].AddedItems.Length; current_item++)
	{
		// Initialize the current item data by the current index
		TradeItemData = GetTradeItemByIndex(client, current_item);
		
		// The current item is rune
		if (TradeItemData.ItemStar != -1 && TradeItemData.ItemLevel != -1)
		{
			counter++;
		}
	}
	
	return counter;
}

void HideClientHud(int client, bool mode)
{
	if (IsClientInGame(client))
	{
		g_MaxMoney.ReplicateToClient(client, mode ? "0" : g_DefaultMaxMoney);
		g_DisableRader.ReplicateToClient(client, mode ? "1" : "0");
	}
}

//================================================================//