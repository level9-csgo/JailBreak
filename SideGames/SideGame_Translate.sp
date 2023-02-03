#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define GAME_NAME "Translate"

#define CONFIG_PATH "addons/sourcemod/configs/TranslateWords.cfg"

//====================//

enum
{
	Translate_Hebrew_To_English, 
	Translate_English_To_Hebrew, 
	Translate_Max
}

enum struct Question
{
	char english_word[32];
	char hebrew_word[32];
}

ArrayList g_QuestionsData;

char g_GameAnswer[32];

bool g_IsGameRunning[Translate_Max];

int g_iGameId[Translate_Max] =  { -1, ... };

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
	g_QuestionsData = new ArrayList(sizeof(Question));
}

public void OnPluginEnd()
{
	if (g_IsGameRunning[Translate_Hebrew_To_English])
	{
		JB_StopGame(g_iGameId[Translate_Hebrew_To_English], -1);
	}
	
	if (g_IsGameRunning[Translate_English_To_Hebrew])
	{
		JB_StopGame(g_iGameId[Translate_English_To_Hebrew], -1);
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GamesSystem"))
	{
		g_iGameId[Translate_English_To_Hebrew] = JB_CreateGame(GAME_NAME..." - English To Hebrew");
		g_iGameId[Translate_Hebrew_To_English] = JB_CreateGame(GAME_NAME..." - Hebrew To English");
	}
}

public void OnMapStart()
{
	KV_LoadTranslateQuestions();
}

public void JB_OnGameStart(int gameId, int client)
{
	Question QuestionData; QuestionData = GetQuestionByIndex(GetRandomInt(0, g_QuestionsData.Length - 1));
	
	if (g_iGameId[Translate_English_To_Hebrew] == gameId)
	{
		strcopy(g_GameAnswer, sizeof(g_GameAnswer), QuestionData.hebrew_word);
		
		ShowAlertPanel("%s Games System - %s\n \nThe first one to translate %s to hebrew will win!", PREFIX_MENU, GAME_NAME, QuestionData.english_word);
		
		g_IsGameRunning[Translate_English_To_Hebrew] = true;
	}
	
	if (g_iGameId[Translate_Hebrew_To_English] == gameId)
	{
		strcopy(g_GameAnswer, sizeof(g_GameAnswer), QuestionData.english_word);
		
		// Rtlify the formatted message
		char rtlify_word[32];
		RTLify(rtlify_word, sizeof(rtlify_word), QuestionData.hebrew_word);
		
		ShowAlertPanel("%s Games System - %s\n \nThe first one to translate %s to english will win!", PREFIX_MENU, GAME_NAME, rtlify_word);
		
		g_IsGameRunning[Translate_Hebrew_To_English] = true;
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId[Translate_English_To_Hebrew] == gameId && g_IsGameRunning[Translate_English_To_Hebrew])
	{
		g_IsGameRunning[Translate_English_To_Hebrew] = false;
	}
	
	if (g_iGameId[Translate_Hebrew_To_English] == gameId && g_IsGameRunning[Translate_Hebrew_To_English])
	{
		g_IsGameRunning[Translate_Hebrew_To_English] = false;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || !StrEqual(g_GameAnswer, sArgs))
	{
		return Plugin_Continue;
		
	}
	if (g_IsGameRunning[Translate_English_To_Hebrew])
	{
		JB_StopGame(g_iGameId[Translate_English_To_Hebrew], client);
		
		g_IsGameRunning[Translate_English_To_Hebrew] = false;
	}
	
	if (g_IsGameRunning[Translate_Hebrew_To_English])
	{
		JB_StopGame(g_iGameId[Translate_Hebrew_To_English], client);
		
		g_IsGameRunning[Translate_Hebrew_To_English] = false;
	}
	
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

public int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	// Do Nothing 
}

//================================[ Key Values ]================================//

void KV_LoadTranslateQuestions()
{
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Words");
	kv.ImportFromFile(CONFIG_PATH);
	
	kv.GotoFirstSubKey();
	
	g_QuestionsData.Clear();
	
	Question QuestionData;
	
	do {
		kv.GetString("english", QuestionData.english_word, sizeof(QuestionData.english_word));
		kv.GetString("hebrew", QuestionData.hebrew_word, sizeof(QuestionData.hebrew_word));
		
		g_QuestionsData.PushArray(QuestionData);
	} while (kv.GotoNextKey());
	
	delete kv;
}

//================================[ Functions ]================================//

any[] GetQuestionByIndex(int index)
{
	Question QuestionData;
	g_QuestionsData.GetArray(index, QuestionData);
	return QuestionData;
}

//================================================================//
