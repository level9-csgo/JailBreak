#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define MAX_MARKERS 5

#define MARKER_SPAWN_TIME 10.0

//====================//

enum
{
	First_Variable, 
	Second_Variable
}

enum struct Client
{
	int mark_scale_index;
	int mark_color_index;
	
	void Reset() {
		this.mark_scale_index = 0;
		this.mark_color_index = 0;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

char g_MarkerScales[][][] = 
{
	{ "Small", "100.0" }, 
	{ "Medium", "175.0" }, 
	{ "Big", "350.0" }
};

char g_MarkerColors[][][] = 
{
	{ "Red", "255,0,0,255" }, 
	{ "Green", "0,255,0,255" }, 
	{ "Blue", "0,0,255,255" }, 
	{ "Gold", "255,255,0,255" }, 
	{ "Purple", "255,0,255,255" }, 
	{ "Mint", "0,255,255,255" }, 
	{ "Orange", "255,128,0,255" }, 
	{ "Pink", "255,0,128,255" }, 
	{ "Olive", "128,255,0,255" }, 
	{ "Slate", "0,255,128,255" }, 
	{ "Menta", "0,128,255,255" }, 
	{ "Brown", "139,69,19,255" }, 
	{ "Maroon", "128,0,0,255" }, 
	{ "Vaiolet", "128,0,255,255" }, 
	{ "Magenta", "240,50,230,255" }
};

int g_iNumOfMarkers;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Mark", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Guard & Admin Commands
	RegConsoleCmd("sm_mark", Command_Mark, "Access the mark menu.");
}

//================================[ Events ]================================//

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
}

//================================[ Commands ]================================//

public Action Command_Mark(int client, int args)
{
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int target_index = FindTarget(client, szArg, true, false);
		
		if (target_index == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		if (!IsClientAllowed(target_index)) {
			PrintToChat(client, "%s Mark menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowMarkMenu(target_index);
		}
	}
	else
	{
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Mark menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowMarkMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowMarkMenu(int client)
{
	char szItem[32];
	Menu menu = new Menu(Handler_Mark);
	menu.SetTitle("%s Mark Menu:\n ", PREFIX_MENU);
	
	Format(szItem, sizeof(szItem), "Mark Scale: %s", g_MarkerScales[g_ClientsData[client].mark_scale_index][First_Variable]);
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "Mark Color: %s", g_MarkerColors[g_ClientsData[client].mark_color_index][First_Variable]);
	menu.AddItem("", szItem);
	
	menu.AddItem("", "Spawn At Aim Position");
	menu.AddItem("", "Spawn At Your Position");
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Mark(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client has permission for the mark menu
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Mark menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
			return;
		}
		
		if (!IsPlayerAlive(client))
		{
			PrintToChat(client, "%s Placing markers is allowed only for \x04alive admins and guards\x01!", PREFIX_ERROR);
			return;
		}
		
		switch (item_position)
		{
			case 0 : g_ClientsData[client].mark_scale_index = ++g_ClientsData[client].mark_scale_index % sizeof(g_MarkerScales);
			case 1 : g_ClientsData[client].mark_color_index = ++g_ClientsData[client].mark_color_index % sizeof(g_MarkerColors);
			case 2 : 
			{
				// Prevent overflow of spawned markers
				if (g_iNumOfMarkers >= MAX_MARKERS)
				{
					PrintToChat(client, "%s Maximum possible markers at once is \x04%d\x01!", PREFIX_ERROR, MAX_MARKERS);
					return;
				}
				
				// Initialize the client aim position
				float mark_spawn_position[3];
				GetClientAimPosition(client, mark_spawn_position);
				
				// Spawn the marker by the specified position
				CreateMarker(mark_spawn_position, client);
			}
			case 3 : 
			{
				// Prevent overflow of spawned markers
				if (g_iNumOfMarkers >= MAX_MARKERS)
				{
					PrintToChat(client, "%s Maximum possible markers at once is \x04%d\x01!", PREFIX_ERROR, MAX_MARKERS);
					return;
				}
				
				// Initialize the client position
				float mark_spawn_position[3];
				GetClientAbsOrigin(client, mark_spawn_position);
				
				// Spawn the marker by the specified position
				CreateMarker(mark_spawn_position, client);
			}
		}
		
		// Display the mark menu
		ShowMarkMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

//================================[ Timers ]================================//

public Action Timer_DecreaseMarker(Handle hTimer)
{
	if (g_iNumOfMarkers > 0)
	{
		g_iNumOfMarkers--;
	}
}

//================================[ Functions ]================================//

void CreateMarker(float pos[3], int client)
{
	// Prevent overflow of spawned markers
	if (g_iNumOfMarkers >= MAX_MARKERS)
	{
		return;
	}
	
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		int marker_color[4];
		
		GetColorRGB(g_MarkerColors[g_ClientsData[client].mark_color_index][Second_Variable], marker_color);
		
		pos[2] += 5.0;
		
		float marker_ring_scale = StringToFloat(g_MarkerScales[g_ClientsData[client].mark_scale_index][Second_Variable]);
		
		TE_SetupBeamRingPoint(pos, marker_ring_scale - 5.0, marker_ring_scale, g_iBeamSprite, g_iHaloSprite, 0, 10, MARKER_SPAWN_TIME, 10.0, 0.5, marker_color, 10, 0);
		TE_SendToAll();
		
		pos[2] -= 5.0;
		
		g_iNumOfMarkers++;
		
		CreateTimer(MARKER_SPAWN_TIME, Timer_DecreaseMarker);
	}
}

void GetColorRGB(char[] color, int buffer[4])
{
	char splits[4][10];
	ExplodeString(color, ",", splits, sizeof(splits), sizeof(splits[]));
	
	int formatted_color[4];
	
	for (int current_part = 0; current_part < 4; current_part++)
	{
		formatted_color[current_part] = StringToInt(splits[current_part]);
	}
	
	buffer = formatted_color;
}

void GetClientAimPosition(int client, float result[3])
{
	float fAngles[3], fPosition[3];
	
	// Initialize the client position and angles
	GetClientEyePosition(client, fPosition);
	GetClientEyeAngles(client, fAngles);
	
	TR_TraceRayFilter(fPosition, fAngles, MASK_ALL, RayType_Infinite, Filter_DontHitPlayers, client);
	
	if (TR_DidHit()) {
		TR_GetEndPosition(result);
	}
}

public bool Filter_DontHitPlayers(int entity, int mask, int data)
{
	return (entity != data);
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//
