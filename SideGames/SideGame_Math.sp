#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define GAME_NAME "Math"

#define PLUS_MINUS_MIN_NUMBER 125
#define PLUS_MINUS_MAX_NUMBER 755

#define MULTI_DIVIDE_MIN_NUMBER 3
#define MULTI_DIVIDE_MAX_NUMBER 20

//====================//

char g_QuestionSolution[32];

bool g_IsGameRunning = false;

int g_iGameId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...GAME_NAME..." Game", 
	author = PLUGIN_AUTHOR, 
	description = GAME_NAME..." side game.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginEnd()
{
	if (g_IsGameRunning)
	{
		JB_StopGame(g_iGameId, -1);
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GamesSystem"))
	{
		g_iGameId = JB_CreateGame(GAME_NAME);
	}
}

public void JB_OnGameStart(int gameId, int client)
{
	if (g_iGameId == gameId)
	{
		char math_operators[4];
		math_operators[0] = '+';
		math_operators[1] = '-';
		math_operators[2] = '/';
		math_operators[3] = '*';
		
		int operator_index = GetRandomInt(0, sizeof(math_operators) - 1);
		int var1, var2;
				
		switch (operator_index)
		{
			case 0:
			{
				var1 = GetRandomInt(PLUS_MINUS_MIN_NUMBER, PLUS_MINUS_MAX_NUMBER);
				var2 = GetRandomInt(PLUS_MINUS_MIN_NUMBER, PLUS_MINUS_MAX_NUMBER);
				
				IntToString(var1 + var2, g_QuestionSolution, sizeof(g_QuestionSolution));
			}
			case 1:
			{
				var1 = GetRandomInt(PLUS_MINUS_MIN_NUMBER, PLUS_MINUS_MAX_NUMBER);
				var2 = GetRandomInt(PLUS_MINUS_MIN_NUMBER, PLUS_MINUS_MAX_NUMBER);
				
				IntToString(var1 - var2, g_QuestionSolution, sizeof(g_QuestionSolution));
			}
			case 2:
			{
				do
				{
					var1 = GetRandomInt(MULTI_DIVIDE_MIN_NUMBER, MULTI_DIVIDE_MAX_NUMBER);
					var2 = GetRandomInt(MULTI_DIVIDE_MIN_NUMBER, MULTI_DIVIDE_MAX_NUMBER);
				} while (!var2 || var1 % var2 != 0);
				
				IntToString(var1 / var2, g_QuestionSolution, sizeof(g_QuestionSolution));
			}
			case 3:
			{
				var1 = GetRandomInt(MULTI_DIVIDE_MIN_NUMBER, MULTI_DIVIDE_MAX_NUMBER);
				var2 = GetRandomInt(MULTI_DIVIDE_MIN_NUMBER, MULTI_DIVIDE_MAX_NUMBER);
				
				IntToString(var1 * var2, g_QuestionSolution, sizeof(g_QuestionSolution));
			}
		}
		
		ShowAlertPanel("%s Games System - %s\n \nThe first one to answer %d%c%d = ? will win!", PREFIX_MENU, GAME_NAME, var1, math_operators[operator_index], var2);
		
		g_IsGameRunning = true;
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId != gameId || !g_IsGameRunning) {
		return;
	}
	
	g_QuestionSolution = "";
	g_IsGameRunning = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsGameRunning || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || !StrEqual(g_QuestionSolution, sArgs))
	{
		return Plugin_Continue;
	}
	
	JB_StopGame(g_iGameId, client);
	
	g_QuestionSolution = "";
	g_IsGameRunning = false;
	
	return Plugin_Continue;
}

//================================[ Events ]================================//

void ShowAlertPanel(const char[] message, any...)
{
	char formatted_message[256];
	VFormat(formatted_message, sizeof(formatted_message), message, 2);
	
	Panel panel = new Panel();
	panel.DrawText(formatted_message);
	
	panel.CurrentKey = 8;
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			panel.Send(current_client, Handler_DoNothing, MENU_TIME_FOREVER);
		}
	}
	
	delete panel;
}

int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	// Do Nothing
	return 0;
}

//================================================================//
