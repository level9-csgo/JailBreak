#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define GAME_NAME "First Write"

//====================//

char g_RandomWrite[32];

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
		g_RandomWrite = GetRandomString(6, "abcdefghijklmnopqrstuvwxyz01234556789");
		
		ShowAlertPanel("%s Games System - %s\n \nThe first one to write %s will win!", PREFIX_MENU, GAME_NAME, g_RandomWrite);
		
		g_IsGameRunning = true;
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId != gameId || !g_IsGameRunning) {
		return;
	}
	
	g_RandomWrite = "";
	g_IsGameRunning = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsGameRunning || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || !StrEqual(g_RandomWrite, sArgs))
	{
		return Plugin_Continue;
	}
	
	JB_StopGame(g_iGameId, client);
	
	g_RandomWrite = "";
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
	/* Do Nothing */
	return 0;
}

//================================[ Functions ]================================//

char[] GetRandomString(int length = 32, char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789")
{
	char szString[32];
	
	for (int iCurrentChar = 0; iCurrentChar < length; iCurrentChar++)
	{
		Format(szString, sizeof(szString), "%s%c", szString, chars[GetRandomInt(0, strlen(chars) - 1)]);
	}
	
	return szString;
}

//================================================================//
