#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <shop>

#undef REQUIRE_PLUGIN
#include <JB_SettingsSystem>
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define SETTINGS_LIBRARY_NAME "JB_SettingsSystem"

#define MIN_RPS_BET 1200
#define MAX_RPS_BET 5000000

#define INVITE_EXPIRE_SECONDS 10
#define GAME_DURATION_SECONDS 15

//====================//

enum
{
	Action_Rock, 
	Action_Paper, 
	Action_Scissors, 
	Action_Max
}

enum struct Client
{
	int user_id;
	int rival_user_id;
	int invite_unixstamp;
	int selected_action;
	
	int credits_amount;
	int game_counter;
	
	Handle RpsGameTimer;
	
	void Reset(bool fully_reset = true)
	{
		this.user_id = fully_reset ? 0 : this.user_id;
		this.rival_user_id = 0;
		this.invite_unixstamp = 0;
		this.selected_action = -1;
		
		this.credits_amount = 0;
		this.game_counter = 0;
		
		this.DeleteTimer();
	}
	
	void DeleteTimer()
	{
		if (this.RpsGameTimer != INVALID_HANDLE)
		{
			KillTimer(this.RpsGameTimer);
			this.RpsGameTimer = INVALID_HANDLE;
		}
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

char g_RpsActions[][] = 
{
	"Rock", 
	"Paper", 
	"Scissors"
};

bool g_IsSettingsLoaded;

int g_RpsInvitesSettingIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Rock Paper Scissors", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Client Commands
	RegConsoleCmd("sm_rps", Command_Rps, "Invite a certain player to a rock paper scissors game.");
	
	// Loop thorugh all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

public void OnPluginEnd()
{
	// Loop throgh all the rps games, make sure to retrive their credits and close the game
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsInRpsGame(current_client))
		{
			// Retrive the credits back
			Shop_GiveClientCredits(current_client, g_ClientsData[current_client].credits_amount);
			
			// Reset the data structure
			g_ClientsData[current_client].Reset();
		}
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		JB_CreateSettingCategory("Shop Settings", "This category is associated with settings that related to the shop.", -1);
		
		g_RpsInvitesSettingIndex = JB_CreateSetting("setting_ignore_rps_invites", "Decides whether or not to ignore rock paper scissors game invites. (Bool setting)", "Ignore Rps Invites", "Shop Settings", Setting_Bool, 1, "0");
		
		g_IsSettingsLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		g_IsSettingsLoaded = false;
	}
}

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
	
	// Initialize the client userid
	g_ClientsData[client].user_id = GetClientUserId(client);
}

public void OnClientDisconnect(int client)
{
	// Loop throgh all the rps games, and if the disconnected client, end the game
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsInRpsGame(current_client) && g_ClientsData[client].rival_user_id == g_ClientsData[current_client].user_id)
		{
			// Award the winner
			AwardRpsWinner(current_client, client, true);
			break;
		}
	}
}

public void OnMapEnd()
{
	// Loop throgh all the rps games, and if the timer is running, delete it
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsInRpsGame(current_client))
		{
			g_ClientsData[current_client].DeleteTimer();
		}
	}
}

//================================[ Commands ]================================//

public Action Command_Rps(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// If not enough arguments specified, display the command usage
	if (args != 2)
	{
		PrintToChat(client, "%s \x04/rps\x01 <name> <credits>", PREFIX);
		return Plugin_Handled;
	}
	
	int rival_index;
	
	// Check for the gamble cooldown
	if (GetTime() - g_ClientsData[client].invite_unixstamp < INVITE_EXPIRE_SECONDS && (rival_index = GetClientOfUserId(g_ClientsData[client].rival_user_id)))
	{
		PrintToChat(client, "%s Please wait till your invitation to \x04%N\x01 will be expired.", PREFIX, rival_index);
		return Plugin_Handled;
	}
	
	char current_arg[MAX_NAME_LENGTH];
	GetCmdArg(1, current_arg, sizeof(current_arg));
	
	// Get the specified target index, and make sure the index is valid
	int target_index = FindTarget(client, current_arg, true, false);
	
	if (target_index == -1)
	{
		// Automated message
		return Plugin_Handled;
	}
	
	if (target_index == client)
	{
		PrintToChat(client, "%s You cannot \x10rps\x01 invite yourself!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_IsSettingsLoaded)
	{
		char setting_value[2];
		JB_GetClientSetting(target_index, g_RpsInvitesSettingIndex, setting_value, sizeof(setting_value));
		
		if (setting_value[0] == '1')
		{
			PrintToChat(client, "%s \x07%N\x01 is \x02ignoring\x01 rock paper scissors game invites!", PREFIX_ERROR, target_index);
			return Plugin_Handled;
		}
	}
	
	// Get the specified credits bet amount, and make sure it's valid
	GetCmdArg(2, current_arg, sizeof(current_arg));
	
	int client_credits = Shop_GetClientCredits(client);
	
	// Get the specified credits bet amount, and make sure it's valid
	int credits_amount = (StrEqual(current_arg, "all") ? client_credits : StrContains(current_arg, "k") != -1 ? StringToInt(current_arg) * 1000 : StringToInt(current_arg));
	
	if (!(MIN_RPS_BET <= credits_amount <= MAX_RPS_BET))
	{
		PrintToChat(client, "%s \x10Rps\x01 bet went out of bounds! (Min: \x04%s\x01, Max: \x04%s\x01)", PREFIX_ERROR, AddCommas(MIN_RPS_BET), AddCommas(MAX_RPS_BET));
		return Plugin_Handled;
	}
	
	// Make sure the inviter has enough shop credits
	if (client_credits < credits_amount)
	{
		PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", JB_AddCommas(credits_amount - client_credits));
		return Plugin_Handled;
	}
	
	// Make sure the target rival has enough shop credits
	if (Shop_GetClientCredits(target_index) < credits_amount)
	{
		PrintToChat(client, " \x02%N\x01 doesn't have enough credits for the game.", target_index);
		return Plugin_Handled;
	}
	
	// Make sure the client isn't in a middle of a game
	if (IsInRpsGame(client))
	{
		PrintToChat(client, "%s Inviting players to \x10rps\x01 game is not possible when you're playing this game!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Make sure the target isn't in a middle of a game
	if (IsInRpsGame(target_index))
	{
		PrintToChat(client, "%s \x07%N\x01 is already in a \x10rps\x01 game!", PREFIX_ERROR, target_index);
		return Plugin_Handled;
	}
	
	// Display the invitation menu to the target
	ShowRpsInvitationMenu(target_index, client, credits_amount);
	
	// Notify inviter
	PrintToChat(client, "%s You've invited \x04%N\x01 to a \x10rps\x01 game for \x07%s\x01 credits!", PREFIX, target_index, JB_AddCommas(credits_amount));
	
	// Apply the invite cooldown
	g_ClientsData[client].invite_unixstamp = GetTime();
	
	g_ClientsData[client].rival_user_id = g_ClientsData[target_index].user_id;
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowRpsInvitationMenu(int client, int inviter, int credits_amount)
{
	char item_info[16];
	
	Menu menu = new Menu(Handler_RpsInvitation);
	menu.SetTitle("%s %N is inviting you a rock paper scissors game for %s credits!\n ", PREFIX_MENU, inviter, JB_AddCommas(credits_amount));
	
	IntToString(g_ClientsData[inviter].user_id, item_info, sizeof(item_info));
	menu.AddItem(item_info, "Accept");
	
	IntToString(credits_amount, item_info, sizeof(item_info));
	menu.AddItem(item_info, "Decline");
	
	// Disable the exit button
	menu.ExitButton = false;
	
	// Display the menu to the client
	menu.Display(client, INVITE_EXPIRE_SECONDS);
}

public int Handler_RpsInvitation(Menu menu, MenuAction action, int param1, int param2)
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
			PrintToChat(client, "%s The \x10rps\x01 inviter is no longer in-game.", PREFIX_ERROR);
			return;
		}
		
		// Get the game credits bet amount
		menu.GetItem(1, item_info, sizeof(item_info));
		int credits_amount = StringToInt(item_info);
		
		switch (item_position)
		{
			// The client has accepted the invite
			case 0 : 
			{
				// Make sure the inviter has enough shop credits
				if (Shop_GetClientCredits(inviter_index) < credits_amount)
				{
					PrintToChat(client, " \x02%N\x01 don't has enough credits for the game.", inviter_index);
					return;
				}
				
				// Make sure the client has enough shop credits
				if (Shop_GetClientCredits(client) < credits_amount)
				{
					PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", JB_AddCommas(credits_amount - Shop_GetClientCredits(client)));
					return;
				}
				
				// Make sure the client isn't in a middle of a game
				if (IsInRpsGame(client))
				{
					PrintToChat(client, "%s You're already playing a \x10rps\x01 game!", PREFIX_ERROR);
					return;
				}
				
				// Make sure the inviter isn't in a middle of a game
				if (IsInRpsGame(inviter_index))
				{
					PrintToChat(client, "%s Inviter \x07%N\x01 is already in a \x10rps\x01 game!", PREFIX_ERROR, inviter_index);
					return;
				}
				
				ExecuteRpsGame(client, inviter_index, credits_amount);
			}
			
			// The client has declined the invite
			case 1 : 
			{
				// Notify inviter about the decline
				PrintToChat(inviter_index, "%s \x07%N\x01 has declined your \x10rps\x01 invitation.", PREFIX, client);
				
				g_ClientsData[inviter_index].rival_user_id = 0;
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

void ShowRpsGameMenu(int client)
{
	Menu menu = new Menu(Handler_RpsGame);
	menu.SetTitle("%s Rps vs %N | %s Credits \nChoose An Action - [%ds]\n \n", PREFIX_MENU, GetClientOfUserId(g_ClientsData[client].rival_user_id), JB_AddCommas(g_ClientsData[client].credits_amount * 2), g_ClientsData[client].game_counter);
	
	char item_info[16];
	IntToString(g_ClientsData[client].rival_user_id, item_info, sizeof(item_info));
	
	for (int current_action = 0; current_action < sizeof(g_RpsActions); current_action++)
	{
		menu.AddItem(item_info, g_RpsActions[current_action]);
	}
	
	// Display the menu to the client
	menu.Display(client, 1);
}

public int Handler_RpsGame(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Get the rival client index
		char item_info[16];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int rival_index = GetClientOfUserId(StringToInt(item_info));
		
		if (!rival_index)
		{
			PrintToChat(client, "%s The game rival is no longer in-game.", PREFIX_ERROR);
			
			g_ClientsData[client].Reset(false);
			
			return;
		}
		
		// Apply the selected action by the menu item position
		g_ClientsData[client].selected_action = item_position;
		
		if (g_ClientsData[rival_index].selected_action == -1)
		{
			PrintToChat(client, "%s You have selected \x04%s\x01, waiting for the opponent choice!", PREFIX, g_RpsActions[g_ClientsData[client].selected_action]);
			PrintToChat(rival_index, "%s Opponent chose his action, it's time for your to make a choice!", PREFIX);
			return;
		}
		
		int winner_action = GetWinnerAction(g_ClientsData[client].selected_action, g_ClientsData[rival_index].selected_action);
		
		if (!winner_action)
		{
			PrintToChat(client, "%s Both results are equal, you both chose \x04%s\x01!", PREFIX, g_RpsActions[g_ClientsData[client].selected_action]);
			PrintToChat(rival_index, "%s Both results are equal, you both chose \x04%s\x01!", PREFIX, g_RpsActions[g_ClientsData[client].selected_action]);
			
			// Give the credits back to the competitors
			Shop_GiveClientCredits(client, g_ClientsData[client].credits_amount, CREDITS_BY_LUCK);
			Shop_GiveClientCredits(rival_index, g_ClientsData[client].credits_amount, CREDITS_BY_LUCK);
			
			// Reset the client data structures
			g_ClientsData[client].Reset(false);
			g_ClientsData[rival_index].Reset(false);
			
			return;
		}
		
		int winner_client_index = ((winner_action == 1) ? client : rival_index);
		int loser_client_index = winner_client_index == client ? rival_index : client;
		
		AwardRpsWinner(winner_client_index, loser_client_index);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

//================================[ Timers ]================================//

Action Timer_RpsGame(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client || !IsClientInGame(client))
	{
		g_ClientsData[client].RpsGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	int rival_index = GetClientOfUserId(g_ClientsData[client].rival_user_id);
	
	if (!rival_index || !IsClientInGame(rival_index))
	{
		g_ClientsData[client].RpsGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_ClientsData[client].game_counter <= 1)
	{
		if (g_ClientsData[client].selected_action == -1 && g_ClientsData[rival_index].selected_action == -1)
		{
			PrintToChat(client, "%s You both didn't chose an action, therefore your money is \x02lost\x01!", PREFIX);
			PrintToChat(rival_index, "%s You both didn't chose an action, therefore your money is \x02lost\x01!", PREFIX);
		}
		else
		{
			int winner_client_index = g_ClientsData[client].selected_action == -1 ? rival_index : client;
			
			// Award the winner
			AwardRpsWinner(winner_client_index, winner_client_index == client ? rival_index : client);
		}
		
		g_ClientsData[client].RpsGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_ClientsData[client].game_counter--;
	g_ClientsData[rival_index].game_counter--;
	
	if (g_ClientsData[client].selected_action == -1)
	{
		ShowRpsGameMenu(client);
	}
	
	if (g_ClientsData[rival_index].selected_action == -1)
	{
		ShowRpsGameMenu(rival_index);
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ExecuteRpsGame(int client, int rival, int credits)
{
	g_ClientsData[client].Reset(false);
	g_ClientsData[rival].Reset(false);
	
	g_ClientsData[client].rival_user_id = g_ClientsData[rival].user_id;
	g_ClientsData[rival].rival_user_id = g_ClientsData[client].user_id;
	
	g_ClientsData[client].credits_amount = credits;
	g_ClientsData[rival].credits_amount = credits;
	
	g_ClientsData[client].game_counter = GAME_DURATION_SECONDS;
	g_ClientsData[rival].game_counter = GAME_DURATION_SECONDS;
	
	g_ClientsData[client].RpsGameTimer = CreateTimer(1.0, Timer_RpsGame, g_ClientsData[client].user_id, TIMER_REPEAT);
	
	Shop_TakeClientCredits(client, credits);
	Shop_TakeClientCredits(rival, credits);
	
	if (g_ClientsData[client].selected_action == -1)
	{
		ShowRpsGameMenu(client);
	}
	
	if (g_ClientsData[rival].selected_action == -1)
	{
		ShowRpsGameMenu(rival);
	}
}

void AwardRpsWinner(int winner, int loser, bool disconnected = false)
{
	//Award the winner
	Shop_GiveClientCredits(winner, g_ClientsData[winner].credits_amount * 2, CREDITS_BY_LUCK);
	
	// Notify the server
	if (disconnected)
	{
		PrintToChatAll("%s \x07%N\x01 disconnected in a middle of a \x10rps\x01 game, therefore \x04%N\x01 won \x06%s\x01 credits!", PREFIX, loser, winner, JB_AddCommas(g_ClientsData[winner].credits_amount * 2));
	}
	else
	{
		PrintToChatAll("%s \x04%N\x01 has won \x07%N\x01 in \x10rps\x01 game and won \x06%s\x01 credits!", PREFIX, winner, loser, JB_AddCommas(g_ClientsData[winner].credits_amount * 2));
	}
	
	// Reset the client data structures
	g_ClientsData[winner].Reset(false);
	g_ClientsData[loser].Reset(false);
}

bool IsInRpsGame(int client)
{
	if (!g_ClientsData[client].rival_user_id)
	{
		return false;
	}
	
	return (g_ClientsData[client].RpsGameTimer != INVALID_HANDLE || g_ClientsData[GetClientOfUserId(g_ClientsData[client].rival_user_id)].RpsGameTimer != INVALID_HANDLE);
}

/**
 * Returns the winner action by the rock paper scissors actions enum.
 * 
 * @ 1 = Action 1 won. 
 * @ 0 = Both actions are equal.
 * @ -1 = Action 2 won. 
 */
int GetWinnerAction(int action1, int action2)
{
	return ((action1 + 1) % 3 == action2 ? -1 : action1 == action2 ? 0 : 1);
}

//================================================================//
