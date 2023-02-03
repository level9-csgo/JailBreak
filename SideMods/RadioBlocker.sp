#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "[CS:GO] Radio Blocker", 
	author = "LuqS & KoNLiG & MINFAS & Sples1", 
	description = "Bye Radio Spammers", 
	version = "1.0", 
	url = "https://steamcommunity.com/id/LuqSGood"
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	
	// Radio Menu 1
	AddCommandListener(Command_SentRadioMessage, "go");
	AddCommandListener(Command_SentRadioMessage, "fallback");
	AddCommandListener(Command_SentRadioMessage, "sticktog");
	AddCommandListener(Command_SentRadioMessage, "holdpos");
	AddCommandListener(Command_SentRadioMessage, "followme");
	// Radio Menu 2
	AddCommandListener(Command_SentRadioMessage, "roger");
	AddCommandListener(Command_SentRadioMessage, "negative");
	AddCommandListener(Command_SentRadioMessage, "cheer");
	AddCommandListener(Command_SentRadioMessage, "compliment");
	AddCommandListener(Command_SentRadioMessage, "thanks");
	// Radio Menu 3
	AddCommandListener(Command_SentRadioMessage, "enemyspot");
	AddCommandListener(Command_SentRadioMessage, "needbackup");
	AddCommandListener(Command_SentRadioMessage, "takepoint");
	AddCommandListener(Command_SentRadioMessage, "sectorclear");
	AddCommandListener(Command_SentRadioMessage, "inposition");
	
	// Radio Commands That Can Be Used With Console
	AddCommandListener(Command_SentRadioMessage, "coverme");
	AddCommandListener(Command_SentRadioMessage, "regroup");
	AddCommandListener(Command_SentRadioMessage, "takingfire");
	AddCommandListener(Command_SentRadioMessage, "stormfront");
	AddCommandListener(Command_SentRadioMessage, "report");
	AddCommandListener(Command_SentRadioMessage, "getout");
	AddCommandListener(Command_SentRadioMessage, "enemydown");
	AddCommandListener(Command_SentRadioMessage, "getinpos");
	AddCommandListener(Command_SentRadioMessage, "reportingin");
	AddCommandListener(Command_SentRadioMessage, "go_a");
	AddCommandListener(Command_SentRadioMessage, "go_b");
	AddCommandListener(Command_SentRadioMessage, "playerradio");
	
	HookUserMessage(GetUserMessageId("RadioText"), BlockRadio, true);
	
	AddCommandListener(Command_SentRadioMessage, "chatwheel_ping");
	AddCommandListener(Command_SentRadioMessage, "player_ping"); // Thanks Sples1.
}

public Action Command_SentRadioMessage(int client, const char[] Command, int args)
{
	// Don't send the radio message.
	return Plugin_Stop;
}

public Action BlockRadio(UserMsg msg_id, Protobuf bf, const int[] players, int playersNum, bool reliable, bool init)
{
	char buffer[64];
	PbReadString(bf, "params", buffer, sizeof(buffer), 0);
	
	if (StrContains(buffer, "#Chatwheel_"))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
} 