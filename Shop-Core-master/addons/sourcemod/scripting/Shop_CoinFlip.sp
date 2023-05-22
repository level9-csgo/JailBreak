#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.0"

//==========[ Settings ]==========//

#define PREFIX " \x04[Level9]\x01"
#define PREFIX_MENU "[Level9]"
#define PREFIX_ERROR " \x02[Error]\x01"

#define CANCEL_SYMBOL "-1"

#define ROLL_TIMES_ON_EXECUTE 30

//====================//

ArrayList g_LobbiesData;

enum struct Lobby
{
	char lobby_unique_code[16];
	
	bool showing_rival_coin;
	
	int client_userid;
	int rival_userid;
	int held_credits;
	
	int roll_times;
	int winner_userid;
	
	Handle RollEffectTimer;
	
	void Execute(int rival, int lobby_index)
	{
		this.rival_userid = rival;
		this.roll_times = GetRandomInt(ROLL_TIMES_ON_EXECUTE - 10, ROLL_TIMES_ON_EXECUTE);
		this.winner_userid = GetRandomInt(0, 1) ? this.client_userid : this.rival_userid;
		this.showing_rival_coin = true;
		
		this.DeleteTimer();
		
		DataPack dPack = new DataPack();
		this.RollEffectTimer = CreateTimer(0.1, Timer_Coinflip, dPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		dPack.WriteString(this.lobby_unique_code);
		
		g_LobbiesData.SetArray(lobby_index, this);
		
		WriteLogLine("\"%L\" has joined to \"%L\"'s coinflip lobby for %s credits.", GetClientOfUserId(this.rival_userid), GetClientOfUserId(this.client_userid), AddCommas(this.held_credits));
	}
	
	void InitUnique()
	{
		do
		{
			strcopy(this.lobby_unique_code, sizeof(Lobby::lobby_unique_code), GetRandomString());
		} while (GetLobbyByUnique(this.lobby_unique_code) != -1);
	}
	
	void DeleteTimer()
	{
		if (this.RollEffectTimer != INVALID_HANDLE)
		{
			KillTimer(this.RollEffectTimer, true);
			this.RollEffectTimer = INVALID_HANDLE;
		}
	}
	
	bool IsLobbyRolling()
	{
		return this.rival_userid != 0;
	}
}

ConVar g_cvMaxCoinflipBet;
ConVar g_cvMinCoinflipBet;
ConVar g_cvMaxClientCoinflips;

bool g_IsClientWriting[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Coin Flip", 
	author = PLUGIN_AUTHOR, 
	description = "An additional coin flip Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	// Create the coin flips lobbies arraylist
	g_LobbiesData = new ArrayList(sizeof(Lobby));
	
	// ConVars Configurate
	g_cvMaxCoinflipBet = CreateConVar("shop_coinflip_max_bet", "1500000", "Maximum possible bet to set on a coinflip.");
	g_cvMinCoinflipBet = CreateConVar("shop_coinflip_min_bet", "1000", "Minimum possible bet to set on a coinflip.");
	g_cvMaxClientCoinflips = CreateConVar("shop_coinflip_maxclient_lobbies", "3", "Max allowed coinflip lobbies possible to be opened at once.");
	
	AutoExecConfig(true, "Coinflip", "shop");
	
	// If the shop already started, call the started callback, for late plugin load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	// Client Commands
	RegConsoleCmd("sm_coinflip", Command_Coinflip, "Start a coinflip against the server, or fellow players.");
	RegConsoleCmd("sm_cf", Command_Coinflip, "Start a coinflip against the server, or felo a client. (An Alias)");
	
	// Event Hooks
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

public void OnPluginEnd()
{
	// Loop throgh all the coin flip lobbies, make sure to retrive their credits and close the lobby
	Lobby CurrentLobbyData;
	
	for (int current_lobby = g_LobbiesData.Length - 1, current_client_index; current_lobby >= 0; current_lobby--)
	{
		CurrentLobbyData = GetLobbyByIndex(current_lobby);
		
		// If the lobby owner index is valid and online, retrive their credits back
		if ((current_client_index = GetClientOfUserId(CurrentLobbyData.client_userid)))
		{
			Shop_GiveClientCredits(current_client_index, CurrentLobbyData.held_credits);
		}
		
		// If the lobby rival index is valid and online, and the lobby running, retrive their credits back
		if (CurrentLobbyData.IsLobbyRolling() && (current_client_index = GetClientOfUserId(CurrentLobbyData.rival_userid)))
		{
			Shop_GiveClientCredits(current_client_index, CurrentLobbyData.held_credits);
		}
		
		// Erase the current array index from the array list
		g_LobbiesData.Erase(current_lobby--);
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	g_IsClientWriting[client] = false;
}

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(OnCoinflipShopDisplay, OnCoinflipShopSelect);
}

public void OnCoinflipShopDisplay(int client, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "Coinflip\n  > %d Lobbies", g_LobbiesData.Length);
}

public bool OnCoinflipShopSelect(int client)
{
	Command_Coinflip(client, 0);
	return true;
}

Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	// Get the client index from the event structure
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!client || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	// Loop throgh all the coin flip lobbies, and if the disconnected client 
	Lobby CurrentLobbyData;
	
	int lobby_client_index, lobby_rival_index;
	
	for (int current_lobby; current_lobby < g_LobbiesData.Length; current_lobby++)
	{
		CurrentLobbyData = GetLobbyByIndex(current_lobby);
		
		if (!(lobby_client_index = GetClientOfUserId(CurrentLobbyData.client_userid)))
		{
			continue;
		}
		
		if (CurrentLobbyData.rival_userid && !(lobby_rival_index = GetClientOfUserId(CurrentLobbyData.rival_userid)))
		{
			continue;
		}
		
		if (CurrentLobbyData.IsLobbyRolling() && (client == lobby_client_index || client == lobby_rival_index))
		{
			int winner_index = (client == lobby_client_index ? lobby_rival_index : lobby_client_index);
			
			PrintCenterText(winner_index, " <font color='#31ee31'>Coinflip Match:</font>\nAmount: <font color='#FF0000'>%s Credits</font>\nAgainst:<font color='#4DB0A7'>%N</font>\nResult:<font color='#4EB35D'>You Won</font>", AddCommas(CurrentLobbyData.held_credits * 2), client);
			
			PrintToChatAll("%s \x04%N\x01 has been disconnected, therefore \x04%N\x01 won \x02%s credits\x01 as a technical victory!", PREFIX, client, winner_index, AddCommas(CurrentLobbyData.held_credits * 2));
			
			// Award the coinflip winner
			Shop_GiveClientCredits(winner_index, CurrentLobbyData.held_credits * 2, CREDITS_BY_LUCK);
			
			// Before erasing the lobby data, delete the coinflip animation timer
			CurrentLobbyData.DeleteTimer();
			
			// Erase the current array index from the array list
			g_LobbiesData.Erase(current_lobby--);
		}
		else if (lobby_client_index == client)
		{
			// If the lobby owner index is valid and online, retrive their credits back
			Shop_GiveClientCredits(client, CurrentLobbyData.held_credits);
			
			// Erase the current array index from the array list
			g_LobbiesData.Erase(current_lobby--);
		}
	}
	
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsClientWriting[client])
	{
		return Plugin_Continue;
	}
	
	// Set the client writing status as false
	g_IsClientWriting[client] = false;
	
	if (StrEqual(sArgs, CANCEL_SYMBOL))
	{
		PrintToChat(client, "%s Coinflip lobby creation cancelled.", PREFIX);
		return Plugin_Handled;
	}
	
	if (GetClientOwnedLobbies(client) >= g_cvMaxClientCoinflips.IntValue)
	{
		PrintToChat(client, "%s The maximum coinflip lobbies at once is \x04%d\x01 lobbies!", PREFIX_ERROR, g_cvMaxClientCoinflips.IntValue);
		return Plugin_Handled;
	}
	
	// Caulculate the specified coinflip bet amount
	int iBetAmount = StrContains(sArgs, "k") != -1 ? StringToInt(sArgs) * 1000 : StringToInt(sArgs);
	
	// Abort the action if the client has went out of the gamble bounds
	if (!(g_cvMinCoinflipBet.IntValue <= iBetAmount <= g_cvMaxCoinflipBet.IntValue))
	{
		PrintToChat(client, "%s Coinflip bet went out of bounds! \x04(Min: %s, Max: %s)\x01", PREFIX_ERROR, AddCommas(g_cvMinCoinflipBet.IntValue), AddCommas(g_cvMaxCoinflipBet.IntValue));
		
		// Display the coinflip menu again
		ShowCoinflipMainMenu(client);
		
		return Plugin_Handled;
	}
	
	// Make sure the client has enough credits to bet on
	if (Shop_GetClientCredits(client) < iBetAmount)
	{
		PrintToChat(client, "%s You don't have enough credits to coinflip on.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Create the coinflip lobby struct data
	CreateCoinflipLobby(client, iBetAmount);
	
	// Notify every online client
	PrintToChatAll("%s \x04%N\x01 has created new \x0Ecoinflip\x01 for \x07%s credits\x01!", PREFIX, client, AddCommas(iBetAmount));
	
	// Display the coinflip opened lobbies
	ShowCoinflipLobbiesMenu(client);
	
	return Plugin_Handled;
}

//================================[ Commands ]================================//

public Action Command_Coinflip(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for root administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char target_name_arg[MAX_NAME_LENGTH];
		GetCmdArg(1, target_name_arg, sizeof(target_name_arg));
		int target_index = FindTarget(client, target_name_arg, true, false);
		
		if (target_index == -1) {
			// Automated message
			return Plugin_Handled;
		}
		
		ShowCoinflipMainMenu(target_index);
	}
	else {
		ShowCoinflipMainMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowCoinflipMainMenu(int client)
{
	Menu menu = new Menu(Handler_CoinflipMain);
	
	menu.SetTitle("%s Shop System - Coinflip Menu (%d Lobbies)\n ", PREFIX_MENU, g_LobbiesData.Length);
	menu.AddItem("", GetClientOwnedLobbies(client) < g_cvMaxClientCoinflips.IntValue ? "Create Coinflip Lobby" : "Create Coinflip Lobby [3 Per Client]", GetClientOwnedLobbies(client) < g_cvMaxClientCoinflips.IntValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("", "Join Coinflip Lobby", g_LobbiesData.Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.Display(client, 1);
}

public int Handler_CoinflipMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Change the write state to true
				g_IsClientWriting[client] = true;
				
				// Notify client
				PrintToChat(client, "%s Type your desired \x06coinflip bet\x01, or \x02%s\x01 to cancel.", PREFIX, CANCEL_SYMBOL);
			}
			case 1:
			{
				// Check if the lobbies arraylist is empty
				if (!g_LobbiesData.Length)
				{
					// Notify client
					PrintToChat(client, "%s No coinflip lobby is open!", PREFIX_ERROR);
					
					// Display the menu again
					ShowCoinflipMainMenu(client);
					
					return 0;
				}
				
				ShowCoinflipLobbiesMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_Timeout)
	{
		ShowCoinflipMainMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowCoinflipLobbiesMenu(int client)
{
	if (!g_LobbiesData.Length)
	{
		ShowCoinflipMainMenu(client);
		return;
	}
	
	char item_display[MAX_NAME_LENGTH * 2];
	
	Menu menu = new Menu(Handler_CoinflipLobbies);
	menu.SetTitle("%s Shop System - Coinflip Lobbies\n ", PREFIX_MENU);
	
	Lobby CurrentLobbyData;
	
	for (int current_lobby = 0; current_lobby < g_LobbiesData.Length; current_lobby++)
	{
		CurrentLobbyData = GetLobbyByIndex(current_lobby);
		
		int rival_index = GetClientOfUserId(CurrentLobbyData.rival_userid);
		
		// If the rival index is valid, initialize the rival name
		if (rival_index)
		{
			GetClientName(rival_index, item_display, sizeof(item_display));
		}
		
		Format(item_display, sizeof(item_display), "%N vs %s - %s credits [%s]", GetClientOfUserId(CurrentLobbyData.client_userid), !rival_index ? "NONE" : item_display, AddCommas(CurrentLobbyData.held_credits), CurrentLobbyData.IsLobbyRolling() ? "Rolling" : "In Queue");
		
		menu.AddItem(CurrentLobbyData.lobby_unique_code, item_display, !CurrentLobbyData.IsLobbyRolling() ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, 1);
}

public int Handler_CoinflipLobbies(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[16];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int lobby_index = GetLobbyByUnique(item_info);
		
		if (lobby_index == -1)
		{
			PrintToChat(client, "%s The selected lobby is \x02corrupt\x01, sent back to the lobbies menu.", PREFIX_ERROR);
			
			ShowCoinflipLobbiesMenu(client);
			
			return 0;
		}
		
		if (GetClientOfUserId(GetLobbyByIndex(lobby_index).client_userid) == client)
		{
			ShowCancelCoinflipMenu(client, lobby_index);
		}
		else
		{
			ShowConfirmCoinflipMenu(client, lobby_index);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		int client = param1, cancel_reason = param2;
		
		switch (cancel_reason)
		{
			case MenuCancel_ExitBack:ShowCoinflipMainMenu(client);
			case MenuCancel_Timeout:ShowCoinflipLobbiesMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowCancelCoinflipMenu(int client, int lobby_index)
{
	Menu menu = new Menu(Handler_CancelCoinflip);
	
	Lobby LobbyData; LobbyData = GetLobbyByIndex(lobby_index);
	
	menu.SetTitle("%s Do you wish to cancel your coinflip lobby? (%s Held credits)\n ", PREFIX_MENU, AddCommas(LobbyData.held_credits));
	
	menu.AddItem(LobbyData.lobby_unique_code, "Accept");
	menu.AddItem("", "Decline");
	
	menu.ExitButton = false;
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CancelCoinflip(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char item_info[16];
		menu.GetItem(0, item_info, sizeof(item_info));
		int lobby_index = GetLobbyByUnique(item_info);
		
		if (lobby_index == -1)
		{
			PrintToChat(client, "%s The selected lobby is \x02corrupt\x01, sent back to the lobbies menu.", PREFIX_ERROR);
			
			ShowCoinflipLobbiesMenu(client);
			
			return 0;
		}
		
		Lobby LobbyData; LobbyData = GetLobbyByIndex(lobby_index);
		
		if (LobbyData.IsLobbyRolling())
		{
			PrintToChat(client, "%s You can't \x07cancel\x01 a rolling coinflip lobby!", PREFIX_ERROR);
			return 0;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				// Notify client
				PrintToChat(client, "%s you canceled your \x04coinflip\x01 and got your \x02%s credits\x01 back.", PREFIX, AddCommas(LobbyData.held_credits));
				
				// Retrive the client credits
				Shop_GiveClientCredits(client, LobbyData.held_credits);
				
				// Erase the lobby index from the arraylist
				g_LobbiesData.Erase(lobby_index);
			}
			case 1:
			{
				// Dispaly the coinflip lobbies menu
				ShowCoinflipLobbiesMenu(client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowConfirmCoinflipMenu(int client, int lobby_index)
{
	Menu menu = new Menu(Handler_ConfirmCoinflip);
	
	Lobby LobbyData; LobbyData = GetLobbyByIndex(lobby_index);
	
	menu.SetTitle("%s Do you wish to enter the coinflip against %N for %s credits?\n ", PREFIX_MENU, GetClientOfUserId(LobbyData.client_userid), AddCommas(LobbyData.held_credits));
	
	menu.AddItem(LobbyData.lobby_unique_code, "Accept");
	menu.AddItem("", "Decline");
	
	menu.ExitButton = false;
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_ConfirmCoinflip(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char item_info[16];
		menu.GetItem(0, item_info, sizeof(item_info));
		int lobby_index = GetLobbyByUnique(item_info);
		
		if (lobby_index == -1)
		{
			PrintToChat(client, "%s The selected lobby is \x02corrupt\x01, sent back to the lobbies menu.", PREFIX_ERROR);
			return 0;
		}
		
		Lobby LobbyData; LobbyData = GetLobbyByIndex(lobby_index);
		
		if (LobbyData.IsLobbyRolling())
		{
			PrintToChat(client, "%s You can't \x06join\x01 a rolling coinflip lobby!", PREFIX_ERROR);
			return 0;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				// Make sure the client has enough credits to coinflip on
				if (Shop_GetClientCredits(client) < LobbyData.held_credits)
				{
					PrintToChat(client, "%s You don't have enough credits to coinflip on!", PREFIX_ERROR);
					return 0;
				}
				
				int lobby_initiator = GetClientOfUserId(LobbyData.client_userid);
				
				// Notify every online client
				PrintToChatAll("%s \x04%N\x01's \x0Ecoinflip\x01 has started against \x04%N\x01 for \x07%s credits\x01!", PREFIX, lobby_initiator, client, AddCommas(LobbyData.held_credits * 2));
				
				// Take the credits from the rival
				Shop_TakeClientCredits(client, LobbyData.held_credits);
				
				// Execute the coinflip lobby
				LobbyData.Execute(GetClientUserId(client), lobby_index);
			}
			case 1:
			{
				// Dispaly the coinflip lobbies menu
				ShowCoinflipLobbiesMenu(client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Timers ]================================//

public Action Timer_Coinflip(Handle timer, DataPack dp)
{
	dp.Reset();
	
	// Initialize the lobby unique code & lobby index
	char lobby_unique_code[16];
	dp.ReadString(lobby_unique_code, sizeof(lobby_unique_code));
	
	int lobby_index = GetLobbyByUnique(lobby_unique_code);
	
	if (lobby_index == -1)
	{
		return Plugin_Stop;
	}
	
	// Initialize the lobby struct data by the specified index
	Lobby LobbyData; LobbyData = GetLobbyByIndex(lobby_index);
	
	int client_index = GetClientOfUserId(LobbyData.client_userid);
	
	// If the client index is no longer available, stop and delete the timer
	if (!client_index)
	{
		g_LobbiesData.Set(lobby_index, INVALID_HANDLE, Lobby::RollEffectTimer);
		return Plugin_Stop;
	}
	
	int rival_index = GetClientOfUserId(LobbyData.rival_userid);
	
	// If the rival index is no longer available, stop and delete the timer
	if (!rival_index)
	{
		g_LobbiesData.Set(lobby_index, INVALID_HANDLE, Lobby::RollEffectTimer);
		return Plugin_Stop;
	}
	
	LobbyData.showing_rival_coin = !LobbyData.showing_rival_coin;
	LobbyData.roll_times--;
	
	if (LobbyData.roll_times <= 0)
	{
		int winner_index = GetClientOfUserId(LobbyData.winner_userid);
		
		PrintToChatAll("%s %s \x02%N\x01 is the winner of the coinflip against %s \x02%N\x01, he won \x04%s credits\x01.", 
			PREFIX, 
			winner_index == client_index ? "\x0B[CT]\x01" : "\x10[T]\x01", 
			winner_index, 
			winner_index != client_index ? "\x0B[CT]\x01" : "\x10[T]\x01", 
			winner_index == client_index ? rival_index : client_index, 
			AddCommas(LobbyData.held_credits * 2)
			);
		
		// Award the coinflip winner
		Shop_GiveClientCredits(winner_index, LobbyData.held_credits * 2, CREDITS_BY_LUCK);
		
		// Erase the specified lobby index from the arraylist
		g_LobbiesData.Erase(lobby_index);
		
		dp.Close();
		
		ShowCoinPanel(client_index, rival_index, winner_index != client_index);
		
		// Stop the timer
		return Plugin_Stop;
	}
	
	ShowCoinPanel(client_index, rival_index, LobbyData.showing_rival_coin);
	
	// Update the lobby struct inside the array list
	g_LobbiesData.SetArray(lobby_index, LobbyData);
	
	if (LobbyData.roll_times < ROLL_TIMES_ON_EXECUTE / 3)
	{
		g_LobbiesData.Set(lobby_index, CreateTimer(2.0 / float(LobbyData.roll_times), Timer_Coinflip, dp, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE), Lobby::RollEffectTimer);
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetLobbyByUnique(const char[] unique)
{
	return g_LobbiesData.FindString(unique);
}

any[] GetLobbyByIndex(int index)
{
	Lobby LobbyData;
	g_LobbiesData.GetArray(index, LobbyData, sizeof(LobbyData));
	return LobbyData;
}

void CreateCoinflipLobby(int client, int bet_amount)
{
	Shop_TakeClientCredits(client, bet_amount);
	
	Lobby LobbyData;
	LobbyData.InitUnique();
	
	LobbyData.client_userid = GetClientUserId(client);
	LobbyData.held_credits = bet_amount;
	LobbyData.rival_userid = 0;
	
	g_LobbiesData.PushArray(LobbyData);
}

int GetClientOwnedLobbies(int client)
{
	// Declare a local variable that will count the lobbies
	int lobbies_counter;
	
	// Loop throgh all the coin flip lobbies, and search for an index match
	for (int current_lobby = 0; current_lobby < g_LobbiesData.Length; current_lobby++)
	{
		if (GetClientOfUserId(GetLobbyByIndex(current_lobby).client_userid) == client)
		{
			lobbies_counter++;
		}
	}
	
	return lobbies_counter;
}

char[] GetRandomString(int length = 8, char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789")
{
	char szString[32];
	
	for (int iCurrentChar = 0; iCurrentChar < length; iCurrentChar++)
	{
		Format(szString, sizeof(szString), "%s%c", szString, chars[GetRandomInt(0, strlen(chars) - 1)]);
	}
	
	return szString;
}

void ShowCoinPanel(int client, int rival, bool show_rival)
{
	char message[PLATFORM_MAX_PATH];
	Format(message, sizeof(message), "<img src='file://{images}/icons/%st_logo.svg'>", show_rival ? "" : "c");
	
	Event event = CreateEvent("show_survival_respawn_status");
	
	event.SetString("loc_token", message);
	event.SetInt("duration", 2);
	event.SetInt("userid", -1);
	
	event.FireToClient(client);
	event.FireToClient(rival);
	event.Cancel();
}

//================================================================//