#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>

#define PLUGIN_AUTHOR "KoNLiG & Ravid"

//==========[ Settings ]==========//

#define GAME_NAME "Combo Contest"

#define BUTTONS_AMOUNT 8

#define COLOR_DARKBLUE "<font color='#0000B3'>"
#define COLOR_MAGENTA "<font color='#FF00FF'>"
#define COLOR_END "</font>"

//====================//

Handle g_hGameTimer = INVALID_HANDLE;

char g_szButtons[][] = 
{
	"Attack", 
	"Attack 2", 
	"Jump", 
	"Duck", 
	"Forward", 
	"Back", 
	"Use", 
	"Move Left", 
	"Move Right", 
	"Reload", 
	"Scoreboard", 
	"Shift"
};

int g_iButtons[] = 
{
	IN_ATTACK, 
	IN_ATTACK2, 
	IN_JUMP, 
	IN_DUCK, 
	IN_FORWARD, 
	IN_BACK, 
	IN_USE, 
	IN_MOVELEFT, 
	IN_MOVERIGHT, 
	IN_RELOAD, 
	IN_SCORE, 
	IN_SPEED
};

bool g_IsGameRunning;

int g_iGameId = -1;
int g_iRandomButtons[BUTTONS_AMOUNT] =  { -1, ... };

int g_iClientButton[MAXPLAYERS + 1];
int g_iOldButtons[MAXPLAYERS + 1];

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

public void OnMapStart()
{
	DeleteTimer();
}

public void JB_OnGameStart(int gameId, int client)
{
	if (g_iGameId == gameId)
	{
		StartGame();
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId != gameId || !g_IsGameRunning) {
		return;
	}
	
	for (int current_button = 0; current_button < BUTTONS_AMOUNT; current_button++)
	{
		g_iRandomButtons[current_button] = -1;
	}
	
	DeleteTimer();
	PrintCenterTextAll("");
	g_IsGameRunning = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (!g_IsGameRunning || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T)
	{
		return Plugin_Continue;
	}
	
	int iClientButton = g_iRandomButtons[g_iClientButton[client]];
	if (buttons != 0 && buttons != g_iOldButtons[client])
	{
		if (!g_iOldButtons[client] && (buttons & g_iButtons[iClientButton]))
		{
			g_iClientButton[client]++;
			
			if (g_iClientButton[client] == BUTTONS_AMOUNT)
			{
				EndGame(client);
				return Plugin_Continue;
			}
			
			PrintClientButtons(client);
		}
		else
		{
			g_iClientButton[client] = 0;
			PrintClientButtons(client);
		}
	}
	
	g_iOldButtons[client] = buttons;
	
	return Plugin_Continue;
}

//================================[ Timers ]================================//

Action Timer_HintText(Handle timer)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			PrintClientButtons(current_client);
		}
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void PrintClientButtons(int client)
{
	char szMessage[512];
	Format(szMessage, sizeof(szMessage), "%sGame System - %s%s", COLOR_MAGENTA, GAME_NAME, COLOR_END);
	
	for (int iCurrectButton = 0; iCurrectButton < BUTTONS_AMOUNT; iCurrectButton++)
	{
		Format(szMessage, sizeof(szMessage), "%s\n%s%s%s", szMessage, g_iClientButton[client] == iCurrectButton ? COLOR_DARKBLUE..."-- ":"", g_szButtons[g_iRandomButtons[iCurrectButton]], g_iClientButton[client] == iCurrectButton ? " --"...COLOR_END:"");
	}
	
	PrintCenterText(client, szMessage);
}

void StartGame()
{
	GetRandomButtons();
	
	g_hGameTimer = CreateTimer(1.0, Timer_HintText, _, TIMER_REPEAT);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			g_iClientButton[current_client] = 0;
			PrintClientButtons(current_client);
		}
	}
	
	g_IsGameRunning = true;
}

void EndGame(int client)
{
	for (int current_button = 0; current_button < BUTTONS_AMOUNT; current_button++)
	{
		g_iRandomButtons[current_button] = -1;
	}
	
	g_IsGameRunning = false;
	JB_StopGame(g_iGameId, client);
	
	PrintCenterTextAll("");
	DeleteTimer();
}

void GetRandomButtons()
{
	ArrayList alCurrentArray = new ArrayList(sizeof(g_iButtons));
	
	for (int iCurrectButton = 0; iCurrectButton < sizeof(g_iButtons); iCurrectButton++) {
		alCurrentArray.Push(iCurrectButton);
	}
	
	int NumOfItems = sizeof(g_iButtons);
	int iCounter = 0;
	
	for (int iCurrectButton = 0; iCurrectButton < BUTTONS_AMOUNT; iCurrectButton++)
	{
		int iTemporary = GetRandomInt(0, NumOfItems - 1);
		g_iRandomButtons[iCounter] = alCurrentArray.Get(iTemporary);
		iCounter++;
	}
	delete alCurrentArray;
}

void DeleteTimer()
{
	if (g_hGameTimer != INVALID_HANDLE)
	{
		KillTimer(g_hGameTimer);
		g_hGameTimer = INVALID_HANDLE;
	}
}

//================================================================//