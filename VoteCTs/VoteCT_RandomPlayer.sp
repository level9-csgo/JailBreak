#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RANDOM_PLAYER_TIME 15 // Time in seconds for the random player game to display.

Handle g_hGameTimer = INVALID_HANDLE;

bool g_bIsEventEnabled;
bool g_bClientChoice[MAXPLAYERS + 1];

int g_iGameTimer;
int g_iVoteId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Random Player", 
	author = PLUGIN_AUTHOR, 
	description = "Random Player game for the guards sysetm.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_changevote", Command_ChangeVote, "Changes your descision for the random player choice.");
	RegConsoleCmd("sm_cv", Command_ChangeVote, "Changes your descision for the random player choice. (An Alias)");
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Random Player", "Random player game.");
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Random Player", "Random player game.");
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_bClientChoice[client] = false;
}

public void OnMapStart()
{
	if (g_hGameTimer != INVALID_HANDLE) {
		KillTimer(g_hGameTimer);
	}
	g_hGameTimer = INVALID_HANDLE;
}

public void JB_OnVoteCTEnd(int voteId)
{
	if (g_iVoteId == voteId)
	{
		g_bIsEventEnabled = true;
		g_iGameTimer = RANDOM_PLAYER_TIME;
		g_hGameTimer = CreateTimer(1.0, Timer_RandomPlayer, _, TIMER_REPEAT);
		
		PrintCenterTextAll("<font color='#1A1AFF'> Random Player</font>:\n  Time Left - <font color='#CC00CC'>%d</font> seconds.", g_iGameTimer);
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				g_bClientChoice[iCurrentClient] = false;
				showRandomPlayerMenu(iCurrentClient);
			}
		}
	}
}

public void JB_OnVoteCTStop()
{
	if (g_bIsEventEnabled)
	{
		if (g_hGameTimer != INVALID_HANDLE) {
			KillTimer(g_hGameTimer);
		}
		g_hGameTimer = INVALID_HANDLE;
		
		g_bIsEventEnabled = false;
	}
}

/*  */

/* Commands */

public Action Command_ChangeVote(int client, int args)
{
	if (!g_bIsEventEnabled)
	{
		PrintToChat(client, "%s There is no \x04random player\x01 game playing right now.", PREFIX);
		return Plugin_Handled;
	}
	
	showRandomPlayerMenu(client);
	return Plugin_Handled;
}

/*  */

/* Menus */

void showRandomPlayerMenu(int client)
{
	Menu menu = new Menu(Handler_RandomPlayer);
	menu.SetTitle("%s Vote CT - Random Player\n \nDo you wish to have a change of become a guard?", PREFIX_MENU);
	menu.AddItem("", "Accept");
	menu.AddItem("", "Decline");
	
	menu.Display(client, RANDOM_PLAYER_TIME);
}

public int Handler_RandomPlayer(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bIsEventEnabled)
		{
			return 0;
		}
		
		if (JB_IsClientBannedCT(client))
		{
			PrintToChat(client, "%s You cannot compete on this game due to your Ban CT.", PREFIX);
			return 0;
		}
		
		g_bClientChoice[client] = itemNum == 0;
		PrintToChat(client, "%s You have chosen to%s be a part of the \x04random player\x01, to change your descision type \x0B/cv\x01.", PREFIX, !g_bClientChoice[client] ? " \x07not\x01":"");
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

/*  */

/* Timers */

public Action Timer_RandomPlayer(Handle hTimer)
{
	if (g_iGameTimer <= 1)
	{
		JB_SetVoteCTWinner(g_iVoteId, GetRandomClient());
		
		g_bIsEventEnabled = false;
		g_hGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iGameTimer--;
	PrintCenterTextAll("<font color='#1A1AFF'> Random Player</font>:\n  Time Left - <font color='#CC00CC'>%d</font> seconds.", g_iGameTimer);
	return Plugin_Continue;
}

/*  */

/* Functions */

int GetRandomClient()
{
	int iCounter = 0;
	int[] iClients = new int[MaxClients];
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; ++iCurrentClient)
	{
		if (IsClientInGame(iCurrentClient) && g_bClientChoice[iCurrentClient] && !JB_IsClientBannedCT(iCurrentClient))
		{
			iClients[iCounter++] = iCurrentClient;
		}
	}
	
	return iCounter ? iClients[GetRandomInt(0, iCounter - 1)] : -1;
}

/*  */