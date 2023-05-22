#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <basecomm>

#define PREFIX " \x04[Level9]\x01"

#define MESSAGE_COOLDOWN 1.5

enum struct Client
{
	// Stores the blocked clients status
	bool is_client_blocked[MAXPLAYERS + 1];
	
	// The next client allowed time to send a private message
	float next_message_send;
	
	// Stores the userid of the client who sent the last message to the client
	int reply_client_userid;
	
	// Reset the structure data
	void Reset()
	{
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			this.is_client_blocked[current_client] = false;
		}
		
		this.next_message_send = 0.0;
		this.reply_client_userid = 0;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] Private Messages", 
	author = "KoNLiG", 
	description = "Private messages system, futures blockpm and message reply.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Client Commands
	RegConsoleCmd("sm_privatemessage", Command_PrivateMessage, "Sends a private message to a certain client.");
	RegConsoleCmd("sm_reply", Command_ReplyPrivateMessage, "Reply to a private message.");
	RegConsoleCmd("sm_blockpm", Command_BlockPrivateMessage, "Allows client to block other clients from sending them private messages.");
	
	// Client Commands (Shortcuts)
	RegConsoleCmd("sm_w", Command_PrivateMessage, "Sends a private message to a certain client. (An Alias)");
	RegConsoleCmd("sm_pm", Command_PrivateMessage, "Sends a private message to a certain client. (An Alias)");
	RegConsoleCmd("sm_re", Command_ReplyPrivateMessage, "Reply to a private message. (An Alias)");
	RegConsoleCmd("sm_bpm", Command_BlockPrivateMessage, "Allows client to block other clients from sending them private messages. (An Alias)");
}

//================================[ Events ]================================//

public void OnClientDisconnect(int client)
{
	// Reset the client data when disconnecting, FIX for overriding other player indexes with wrong data
	g_ClientsData[client].Reset();
}

//================================[ Commands ]================================//

public Action Command_PrivateMessage(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (BaseComm_IsClientGagged(client))
	{
		PrintToChat(client, "%s \x02You cannot pm while you're gagged. To see your gag status type /gagged\x01", PREFIX);
		return Plugin_Handled;
	}
	
	// If not enough command arguments were specified, display the command usage and don't continue
	if (args < 2)
	{
		PrintToChat(client, "%s Usage: \x04/pm\x01 <#userid|name> <message>", PREFIX);
		return Plugin_Handled;
	}
	
	float current_game_time = GetGameTime();
	
	// Check for the message send cooldown
	if (current_game_time < g_ClientsData[client].next_message_send)
	{
		PrintToChat(client, "%s Please wait \x02%.1f\x01 seconds before sending another private message.", PREFIX, g_ClientsData[client].next_message_send - current_game_time);
		return Plugin_Handled;
	}
	
	// Apply the next message send cooldown on the player
	g_ClientsData[client].next_message_send = current_game_time + MESSAGE_COOLDOWN;
	
	char target_name[MAX_NAME_LENGTH];
	GetCmdArg(1, target_name, sizeof(target_name));
	
	// Find the target index by the specified target name agrument
	int target_index = FindTarget(client, target_name, true, false);
	
	// Validate the target index
	if (target_index == -1)
	{
		// Automated message. See line '43'
		return Plugin_Handled;
	}
	
	// If the target is blocked by the client, don't continue
	if (g_ClientsData[client].is_client_blocked[target_index])
	{
		PrintToChat(client, "%s \x07Error:\x01 You cannot send private messages to a player you have blocked.", PREFIX);
		return Plugin_Handled;
	}
	
	// If the client is blocked by the target, don't continue (LOL)
	if (g_ClientsData[target_index].is_client_blocked[client])
	{
		PrintToChat(client, "%s \x07Error:\x01 Your message could not be delivered because you were blocked by the recipient.", PREFIX);
		return Plugin_Handled;
	}
	
	// Make sure the client isn't targeting himself
	if (target_index == client)
	{
		PrintToChat(client, "%s \x07Error:\x01 You cannot send private messages to yourself.", PREFIX);
		return Plugin_Handled;
	}
	
	g_ClientsData[target_index].reply_client_userid = GetClientUserId(client);
	
	// Get the message by joining all the arguments together
	char message[256];
	GetCmdArgString(message, sizeof(message));
	
	// Format the message and prepere it for display
	ReplaceString(message, sizeof(message), target_name, "");
	StripQuotes(message);
	TrimString(message);
	
	// Notify the sender & target
	PrintToChat(client, " \x0CTo %N:\x01 \x0E%s\x01", target_index, message);
	PrintToChat(target_index, " \x0CFrom %N:\x01 \x0E%s\x01", client, message);
	PrintToChat(target_index, " \x0DReply private messages with \x0B/re <message>");
	
	// Loop trough all the online admins, and display them the private message overview
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && GetUserAdmin(current_client) != INVALID_ADMIN_ID && current_client != client && current_client != target_index)
		{
			PrintToChat(current_client, "%s \x0BOverview | \x0C%N To %N : \x0E%s", PREFIX, client, target_index, message);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_ReplyPrivateMessage(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// If not enough command arguments were specified, display the command usage and don't continue
	if (!args)
	{
		PrintToChat(client, "%s Usage: \x04/reply\x01 <message>", PREFIX);
		return Plugin_Handled;
	}
	
	float current_game_time = GetGameTime();
	
	// Check for the message send cooldown
	if (current_game_time < g_ClientsData[client].next_message_send)
	{
		PrintToChat(client, "%s Please wait \x02%.1f\x01 seconds before replying a private message.", PREFIX, g_ClientsData[client].next_message_send - current_game_time);
		return Plugin_Handled;
	}
	
	// Apply the next message send cooldown on the player
	g_ClientsData[client].next_message_send = current_game_time + MESSAGE_COOLDOWN;
	
	int reply_target_index = GetClientOfUserId(g_ClientsData[client].reply_client_userid);
	if (!reply_target_index)
	{
		PrintToChat(client, "%s \x07Error:\x01 You have no private message to reply to.", PREFIX);
		return Plugin_Handled;
	}
	
	// If the target is blocked by the client, don't continue
	if (g_ClientsData[client].is_client_blocked[reply_target_index])
	{
		PrintToChat(client, "%s \x07Error:\x01 You cannot send private messages to a player you have blocked.", PREFIX);
		return Plugin_Handled;
	}
	
	// If the client is blocked by the target, don't continue (LOL)
	if (g_ClientsData[reply_target_index].is_client_blocked[client])
	{
		PrintToChat(client, "%s \x07Error:\x01 Your message could not be delivered because you were blocked by the recipient.", PREFIX);
		return Plugin_Handled;
	}
	
	g_ClientsData[reply_target_index].reply_client_userid = GetClientUserId(client);
	
	// Get the message by joining all the arguments together
	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	TrimString(message);
	
	// Notify the sender & target
	PrintToChat(client, " \x0CTo %N:\x01 \x0E%s\x01", reply_target_index, message);
	PrintToChat(reply_target_index, " \x0CFrom %N:\x01 \x0E%s\x01", client, message);
	
	// Loop trough all the online admins, and display them the private message overview
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && GetUserAdmin(current_client) != INVALID_ADMIN_ID && current_client != client && current_client != reply_target_index)
		{
			PrintToChat(current_client, "%s \x0BOverview | \x0C%N To %N : \x0E%s", PREFIX, client, reply_target_index, message);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_BlockPrivateMessage(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// If not enough command arguments were specified, display the command usage and don't continue
	if (args != 1)
	{
		PrintToChat(client, "%s Usage: \x06/blockpm\x01 <player name>", PREFIX);
		return Plugin_Handled;
	}
	
	char target_name[MAX_NAME_LENGTH];
	GetCmdArg(1, target_name, sizeof(target_name));
	
	// Find the target index by the specified target name agrument
	int target_index = FindTarget(client, target_name, true, false);
	
	// Validate the target index
	if (target_index == -1)
	{
		// Automated message. See line '43'
		return Plugin_Handled;
	}
	
	// Make sure the client isn't targeting himself
	if (client == target_index)
	{
		PrintToChat(client, "%s \x07Error:\x01 You cannot use blockpm command on yourself.", PREFIX);
		return Plugin_Handled;
	}
	
	// Set the block variable value to it's opposite
	g_ClientsData[client].is_client_blocked[target_index] = !g_ClientsData[client].is_client_blocked[target_index];
	
	// Notify the client	
	PrintToChat(client, "%s You have %s\x01 \x0B%N\x01 from sending you private messages.", PREFIX, g_ClientsData[client].is_client_blocked[target_index] ? "\x02blocked" : "\x04unblocked", target_index);
	
	return Plugin_Handled;
}

//================================================================//