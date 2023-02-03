#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Commands Blocker", 
	author = PLUGIN_AUTHOR, 
	description = "Blockes client console commands like +left/+right, +strafe, etc...", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

//================================[ Events ]================================//

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if ((buttons & IN_LEFT) || (buttons & IN_RIGHT))
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
		
		// Unfreeze the client screen
		int client_flags = GetEntityFlags(client);
		SetEntityFlags(client, (client_flags |= FL_FROZEN));
		CreateTimer(0.2, Timer_UnFreezeScreen, GetClientUserId(client));
	}
	
	if (((vel[0] > 0.0 && !(buttons & IN_FORWARD)) || (vel[0] < 0.0 && !(buttons & IN_BACK)) || (vel[1] > 0.0 && !(buttons & IN_MOVERIGHT)) || (vel[1] < 0.0 && !(buttons & IN_MOVELEFT))))
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
	}
}

//================================[ Timers ]================================//

Action Timer_UnFreezeScreen(Handle timer, int userid)
{
	// Initialize the client index by the given serial, and make sure it's valid
	int client = GetClientOfUserId(userid);
	
	if (client)
	{
		// Unfreeze the client screen
		int client_flags = GetEntityFlags(client);
		SetEntityFlags(client, (client_flags &= ~FL_FROZEN));
	}
}

//================================================================//