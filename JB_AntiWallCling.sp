#include <sourcemod>
#include <sdktools>
#include <JailBreak>
#include <JB_SpecialDays>
#include <Misc_Ghost>

#pragma semicolon 1
#pragma newdecls required

ConVar g_ClingDurationAction;

// Server tickrate. (64.0|128.0|...)
float g_ServerTickrate;

bool g_IsPlayerClingingWall[MAXPLAYERS + 1],  // Whether a player is currently clinging to a wall.
	 g_IsBackstabDayRunning; // Whether a backstab special day is running.

int g_BackstabDayIndex;

public Plugin myinfo = 
{
	name = "[JailBreak] Backstab Day - Anti Wall Cling", 
	author = "KoNLiG", 
	description = "Prevents players playing 'Backstab' duel from clinging into a wall.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{	
	// ConVars configuration.
	g_ClingDurationAction = CreateConVar("jb_anti_cling_duration_action", "3.0", "Wall cling duration for an action to be made. (Seconds)", .hasMin = true, .min = 1.5, .hasMax = true, .max = 10.0);
	
	// Get the server tickrate once.
	g_ServerTickrate = 1.0 / GetTickInterval();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		// Wait a frame for all special days to get registered.
		RequestFrame(Frame_FindBackstabIdx);
	}
}

void Frame_FindBackstabIdx()
{
	if ((g_BackstabDayIndex = JB_FindSpecialDay("Backstab Day")) == -1)
	{
		SetFailState("Unable to find 'Backstab' day.");
	}
}

//================================[ Events ]================================//

// General events.
public void JB_OnSpecialDayStart(int specialDayId)
{
	if (specialDayId == g_BackstabDayIndex)
	{
		g_IsBackstabDayRunning = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown)
{
	if (specialDayId != g_BackstabDayIndex)
	{
		return;
	}
	
	g_IsBackstabDayRunning = false;
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_IsPlayerClingingWall[current_client])
		{
			g_IsPlayerClingingWall[current_client] = false;
		}
	}
}

// Client events.
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (g_IsBackstabDayRunning && !(tickcount % RoundToFloor(g_ServerTickrate * g_ClingDurationAction.FloatValue)))
	{
		if (!IsPlayerAlive(client) || JB_IsClientGhost(client))
		{
			return;
		}
		
		if (IsPlayerClingWall(client))
		{
			// The client is clinging to a wall for too long.
			if (g_IsPlayerClingingWall[client])
			{
				// Slay the client.
				ForcePlayerSuicide(client);
				
				// Notify the client.
				PrintToChat(client, "%s You've automatically \x02slayed\x01 due to clinging to a wall for too long.", PREFIX);
				
				g_IsPlayerClingingWall[client] = false;
			}
			else
			{
				g_IsPlayerClingingWall[client] = true;
			}
		}
		else
		{
			g_IsPlayerClingingWall[client] = false;
		}
	}
}

public void OnClientDisconnect(int client)
{
	g_IsPlayerClingingWall[client] = false;
}

//================================[ Functions ]================================//

bool IsPlayerClingWall(int client)
{
	float back_pos[3];
	GetClientBackPosition(client, back_pos);
	
	float client_pos[3];
	GetClientAbsOrigin(client, client_pos);
	
	return GetVectorDistance(client_pos, back_pos) <= 67.0;
}

void GetClientBackPosition(int client, float result[3])
{
	float pos[3], ang[3];
	
	GetClientEyePosition(client, pos);
	GetClientAbsAngles(client, ang);
	
	// Flip the angle vector.
	ang[1] += 180.0;
	
	TR_TraceRayFilter(pos, ang, MASK_ALL, RayType_Infinite, Filter_ExcludePlayers);
	
	TR_GetEndPosition(result);
}

bool Filter_ExcludePlayers(int entity, int contentsMask)
{
	return entity > MaxClients;
}

//================================================================//