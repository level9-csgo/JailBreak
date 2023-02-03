#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>

//==========[ Settings ]==========//

#define GAME_START_COUNTDOWN 3 

//====================//

GlobalForward g_fwdOnGameStart;
GlobalForward g_fwdOnGameStop;

ArrayList g_GamesData;

Handle g_CountdownTimer = INVALID_HANDLE;

int g_CurrentGame = -1;
int g_Timer;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Games System", 
	author = "KoNLiG", 
	description = "Provides side games system for guards and admins.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the games data arraylist
	g_GamesData = new ArrayList(ByteCountToCells(64));
	
	// Guard & Admin Commands
	RegConsoleCmd("sm_games", Command_Games, "Access the side games menu.");
}

//================================[ Events ]================================//

public void OnMapStart()
{
	DeleteTimer();
}

//================================[ Commands ]================================//

public Action Command_Games(int client, int args)
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
		
		if (!IsClientAllowed(target_index)) {
			PrintToChat(client, "%s Games menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowGamesMenu(target_index);
		}
	}
	else
	{
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Games menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowGamesMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowGamesMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_Games);
	menu.SetTitle("%s Games Menu:\n ", PREFIX_MENU);
	
	menu.AddItem("", "Stop The Current Game!\n ", g_CurrentGame != -1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	for (int current_game = 0; current_game < g_GamesData.Length; current_game++)
	{
		FormatEx(item_display, sizeof(item_display), "%s%s", GetGameName(current_game), g_CurrentGame == current_game ? " [Current]" : "");
		menu.AddItem("", item_display, g_CurrentGame == -1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// If no game was found, add an extra notify menu item
	if (!g_GamesData.Length)
	{
		menu.AddItem("", "No game was found.", ITEMDRAW_DISABLED);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Games(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Games menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
			return;
		}
		
		switch (item_position)
		{
			case 0:
			{
				// Make sure the side game is still running
				if (g_CurrentGame == -1)
				{
					PrintToChat(client, "%s The side game is no longer running!", PREFIX_ERROR);
					return;
				}
				
				// Notify server
				PrintToChatAll("%s %s \x04%N\x01 has stopped the running side game!", PREFIX, GetClientTeam(client) == CS_TEAM_CT ? "Guard" : "Admin", client);
				
				StopGame(INVALID_GAME_WINNER);
			}
			default:
			{
				g_CurrentGame = item_position - 1;
				
				// Create the game countdown timer
				g_Timer = GAME_START_COUNTDOWN;
				g_CountdownTimer = CreateTimer(1.0, Timer_GameCountdown, GetClientSerial(client), TIMER_REPEAT);
				
				// Initialize the game name by the specified index
				char game_name[64];
				strcopy(game_name, sizeof(game_name), GetGameName(g_CurrentGame));
				
				// Notify server
				ShowAlertPanel(1, "%s Games System\n \n%s will start in %d seconds!", PREFIX_MENU, game_name, g_Timer);
				
				PrintToChatAll("%s %s \x04%N\x01 has started \x07%s\x01 game!", PREFIX, GetClientTeam(client) == CS_TEAM_CT ? "Guard" : "Admin", client, game_name);
			}
		}
	}
	if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void ShowAlertPanel(int time, const char[] message, any...)
{
	char formatted_message[256];
	VFormat(formatted_message, sizeof(formatted_message), message, 3);
	
	Panel panel = new Panel();
	panel.DrawText(formatted_message);
	
	panel.CurrentKey = 8;
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			panel.Send(current_client, Handler_DoNothing, time);
		}
	}
	
	delete panel;
}

public int Handler_DoNothing(Menu menu, MenuAction action, int iPlayerIndex, int itemNum)
{
	// Do Nothing
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateGame", Native_CreateGame);
	CreateNative("JB_FindGame", Native_FindGame);
	CreateNative("JB_StopGame", Native_StopGame);
	
	g_fwdOnGameStart = new GlobalForward("JB_OnGameStart", ET_Ignore, Param_Cell, Param_Cell);
	g_fwdOnGameStop = new GlobalForward("JB_OnGameStop", ET_Ignore, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_GamesSystem");
	return APLRes_Success;
}

public int Native_CreateGame(Handle plugin, int numParams)
{
	char game_name[64];
	GetNativeString(1, game_name, sizeof(game_name));
	
	int game_index = GetGameByName(game_name);
	if (game_index != -1)
	{
		return game_index;
	}
	
	return g_GamesData.PushString(game_name);
}

public int Native_FindGame(Handle plugin, int numParams)
{
	char game_name[64];
	GetNativeString(1, game_name, sizeof(game_name));
	return GetGameByName(game_name);
}

public int Native_StopGame(Handle plugin, int numParams)
{
	// Make sure there is a side game running
	if (g_CurrentGame == -1)
	{
		return false;
	}
	
	// Get and verify the the game index
	int game_index = GetNativeCell(1);
	
	if (!(0 <= game_index < g_GamesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified game index. (Got: %d, Max: %d)", game_index, g_GamesData.Length);
	}
	
	// Get and verify the the client index
	int client = GetNativeCell(2);
	
	if (client != INVALID_GAME_WINNER && !(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (client != INVALID_GAME_WINNER && !IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	if (client != INVALID_GAME_WINNER)
	{
		char game_name[64]; game_name = GetGameName(g_CurrentGame);
		
		ShowAlertPanel(5, "%s Games System\n \n%N has won the %s game!", PREFIX_MENU, client, game_name);
		PrintToChatAll("%s \x06%N\x01 has won the \x07%s\x01 game!", PREFIX, client, game_name);
		
		// Glow the winner
		GlowPlayer(client);
	}
	
	// Stop the game
	StopGame(client);
	
	return true;
}

//================================[ Timers ]================================//

public Action Timer_GameCountdown(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is still valid
	if (!client)
	{
		PrintToChatAll("%s The side game has automatically \x02stopped\x01, because the \x0Cguard\x01 who started it has disconnected!", PREFIX);
		
		g_CurrentGame = -1;
		g_CountdownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_Timer <= 1)
	{
		//==== [ Execute the game start forward ] =====//
		Call_StartForward(g_fwdOnGameStart);
		Call_PushCell(g_CurrentGame); // int gameId
		Call_PushCell(client); // int client
		Call_Finish();
		
		g_CountdownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_Timer--;
	
	// Display the alert panel
	ShowAlertPanel(1, "%s Games System\n \n%s will start in %d seconds!", PREFIX_MENU, GetGameName(g_CurrentGame), g_Timer);
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetGameByName(const char[] name)
{
	return g_GamesData.FindString(name);
}

char GetGameName(int index)
{
	char game_name[64];
	g_GamesData.GetString(index, game_name, sizeof(game_name));
	return game_name;
}

void StopGame(int winner)
{
	if (g_CountdownTimer != INVALID_HANDLE)
	{
		DeleteTimer();
	}
	else
	{
		//==== [ Execute the game start forward ] =====//
		Call_StartForward(g_fwdOnGameStop);
		Call_PushCell(g_CurrentGame); // int gameId
		Call_PushCell(winner); // int winner
		Call_Finish();
	}
	
	g_CurrentGame = -1;
}

void DeleteTimer()
{
	if (g_CountdownTimer != INVALID_HANDLE)
	{
		KillTimer(g_CountdownTimer);
		g_CountdownTimer = INVALID_HANDLE;
	}
}

void GlowPlayer(int client)
{
	Protobuf msg = view_as<Protobuf>(StartMessageAll("EntityOutlineHighlight"));
	
	msg.SetInt("entidx", client); // Entity to glow
	
	EndMessage();
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//