#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define GAME_NAME "Jumble Words"

#define CONFIG_PATH "addons/sourcemod/configs/JumbleWords.cfg"

//====================//

ArrayList g_JumbleWordsData;

char g_GameAnswer[64];

bool g_IsGameRunning;

int g_iGameId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...GAME_NAME..." Game", 
	author = PLUGIN_AUTHOR, 
	description = GAME_NAME..." side game.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_JumbleWordsData = new ArrayList(ByteCountToCells(32));
}

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
	KV_LoadJumbleWords();
}

public void JB_OnGameStart(int gameId, int client)
{
	if (g_iGameId == gameId)
	{
		int word_index = GetRandomInt(0, g_JumbleWordsData.Length - 1);
		
		char word[32];
		g_JumbleWordsData.GetString(word_index, word, sizeof(word));
		
		strcopy(g_GameAnswer, sizeof(g_GameAnswer), word);
		
		if (!JumbleString(word))
		{
			PrintToChatAll("%s Jumble words game the turned off, because the chosen word was \x04corrupt\x01.", PREFIX);
			
			JB_StopGame(g_iGameId, -1);
			
			return;
		}
		
		ShowAlertPanel("%s Games System - %s\n \nThe first one to write the corrent order of %s will win!", PREFIX_MENU, GAME_NAME, word);
		
		g_IsGameRunning = true;
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId == gameId && g_IsGameRunning)
	{
		g_IsGameRunning = false;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsGameRunning || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || !StrEqual(g_GameAnswer, sArgs))
	{
		return Plugin_Continue;
	}
	
	JB_StopGame(g_iGameId, client);
	
	g_IsGameRunning = false;
	
	g_GameAnswer[0] = '\0';
	
	return Plugin_Continue;
}

//================================[ Menus ]================================//

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

//================================[ Key Values ]================================//

void KV_LoadJumbleWords()
{
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Words");
	
	kv.ImportFromFile(CONFIG_PATH);

	g_JumbleWordsData.Clear();
	
	char current_word[32];
	
	if (kv.GotoFirstSubKey(false))
	{
		do {
			kv.GetString(NULL_STRING, current_word, sizeof(current_word));
			
			g_JumbleWordsData.PushString(current_word);
		} while (kv.GotoNextKey(false));
		
		kv.Rewind();
		kv.ExportToFile(CONFIG_PATH);
	}
	
	kv.Close();
}

//================================[ Functions ]================================//

bool JumbleString(char[] str)
{
	if (strlen(str) <= 2 || IsStringCharsSame(str))
	{
		return false;
	}
	
	char str_current_char, str_origin[32];
	
	strcopy(str_origin, sizeof(str_origin), str);
	
	do
	{
		for (int current_char = 0; current_char < strlen(str); current_char++)
		{
			int index;
			
			do
			{
				index = GetRandomInt(0, strlen(str) - 1);
			} while (index == current_char);
			
			str_current_char = str[current_char];
			str[current_char] = str[index];
			str[index] = str_current_char;
		}
	} while (StrEqual(str_origin, str));
	
	return true;
}

bool IsStringCharsSame(const char[] str)
{
	char last_str = str[0];
	
	for (int current_char = 1; current_char < strlen(str); current_char++)
	{
		if (str[current_char] != last_str)
		{
			return false;
		}
		
		last_str = str[current_char];
	}
	
	return true;
}

//================================================================//
