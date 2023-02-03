#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

#define DETECTION_CHAR '#'

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Root Chat", 
	author = PLUGIN_AUTHOR, 
	description = "Allows for root administrators to type on their own chat area. (Admin chat for root administrators)", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

//================================[ Events ]================================//

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// Make sure the client is allowed to type into the root administrators chat
	if (sArgs[0] != DETECTION_CHAR || !StrEqual(command, "say_team") || !(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		return Plugin_Continue;
	}
	
	// Print the client message to every root administrator
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && (GetUserFlagBits(current_client) & ADMFLAG_ROOT))
		{
			PrintToChat(current_client, " \x04(ROOT) %N:\x01 %s", client, sArgs[1]);
		}
	}
	
	// Block the message send in the global chat area
	return Plugin_Handled;
}

//================================================================//