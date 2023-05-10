#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name = "Block Spam Chat Text", 
	author = "KoNLiG", 
	description = "Blocks a specific character of ", 
	version = "1.0.0", 
	url = "Your website URL/AlliedModders profile URL"
};

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (StrContains(sArgs, "﷽") != -1)
	{
		ServerCommand("sm_gag #%d 1440 Chat Spam", GetClientUserId(client));
	}
} 