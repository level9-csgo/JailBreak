#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <JailBreak>
#include <JB_GangsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define MIN_TEAMS_AMOUNT 2
#define MAX_TEAMS_AMOUNT 10

//====================//

enum struct Client
{
	int glow_color_index;
	int teams_amount;
	
	void Reset() {
		this.glow_color_index = 0;
		this.teams_amount = MIN_TEAMS_AMOUNT;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Glow", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	// Guard & Admin Commands
	RegConsoleCmd("sm_glow", Command_Glow, "Access the glow management menu.");
	
	// Event Hooks
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	GlowPlayer(GetClientOfUserId(event.GetInt("userid")), 0);
}

//================================[ Commands ]================================//

public Action Command_Glow(int client, int args)
{
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for root administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char arg_name[MAX_NAME_LENGTH];
		GetCmdArgString(arg_name, sizeof(arg_name));
		int target_index = FindTarget(client, arg_name, true, false);
		
		if (target_index == -1) {
			// Automated message
			return Plugin_Handled;
		}
		
		if (!IsClientAllowed(target_index)) {
			PrintToChat(client, "%s Glow management menu allowed for alive guards or admins.", PREFIX_ERROR);
		} else {
			ShowGlowManagementMenu(target_index);
		}
	}
	else {
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Glow management menu allowed for alive guards or admins.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		ShowGlowManagementMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowGlowManagementMenu(int client)
{
	char item_display[MAX_NAME_LENGTH * 2], item_info[16];
	Menu menu = new Menu(Handler_GlowManagement);
	menu.SetTitle("%s Glow Management - Main Menu\n ", PREFIX_MENU);
	
	Format(item_display, sizeof(item_display), "Glow Color: %s", g_szColors[g_ClientsData[client].glow_color_index][Color_Name]);
	menu.AddItem("", item_display);
	
	menu.AddItem("", "Glow From Player List");
	menu.AddItem("", "Glow By Aim");
	menu.AddItem("", "Glow By Gangs Color");
	menu.AddItem("", "Create Random Teams\n ");
	
	int current_color_index = -1;
	
	for (int current_client = 1, current_color[4]; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			GetEntityRenderColor(current_client, current_color[0], current_color[1], current_color[2], current_color[3]);
			
			if (current_color[0] == 255 && current_color[1] == 255 && current_color[2] == 255)
			{
				continue;
			}
			
			current_color_index = GetColorByRGB(current_color);
			
			FormatEx(item_display, sizeof(item_display), "%N (%s)", current_client, current_color_index == -1 ? "Unkown Color" : g_szColors[current_color_index][Color_Name]);
			
			IntToString(GetClientUserId(current_client), item_info, sizeof(item_info));
			menu.AddItem(item_info, item_display);
		}
	}
	
	if (menu.ItemCount > 5)
	{
		menu.InsertItem(5, "", "Remove All Glows!");
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_GlowManagement(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still in allow state
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Glow management menu allowed for alive guards or admins.", PREFIX_ERROR);
			return 0;
		}
		
		switch (item_position)
		{
			case 0 : 
			{
				g_ClientsData[client].glow_color_index = ++g_ClientsData[client].glow_color_index % sizeof(g_szColors);
				
				// Dispaly the menu again
				ShowGlowManagementMenu(client);
			}
			case 1:
			{
				ShowPlayerListMenu(client);
			}
			case 2:
			{
				int aimed_target = GetClientAimTarget(client);
				
				if (aimed_target <= 0)
				{
					PrintToChat(client, "%s You aren't aiming on any player!", PREFIX_ERROR);
				}
				else
				{
					GlowPlayer(aimed_target, client, g_ClientsData[client].glow_color_index);
				}
				
				ShowGlowManagementMenu(client);
			}
			case 3:
			{
				ExecuteGangsColoring(client);
			}
			case 4:
			{
				ShowRandomTeamsMenu(client);
			}
			case 5:
			{
				for (int current_client = 1; current_client <= MaxClients; current_client++)
				{
					if (IsClientInGame(current_client))
					{
						int client_color[4];
						GetEntityRenderColor(current_client, client_color[0], client_color[1], client_color[2], client_color[3]);
						
						if (!(client_color[0] == 255 && client_color[1] == 255 && client_color[2] == 255))
						{
							GlowPlayer(current_client, client);
						}
					}
				}
			}
			default:
			{
				char item_info[16];
				menu.GetItem(item_position, item_info, sizeof(item_info));
				
				// Initialize the target index by the item info, and make sure it's valid
				int target_index = GetClientOfUserId(StringToInt(item_info));
				
				if (!target_index)
				{
					PrintToChat(client, "%s The selected player is no longer in-game!", PREFIX_ERROR);
					return 0;
				}
				
				GlowPlayer(target_index, client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowPlayerListMenu(int client)
{
	char current_client_name[MAX_NAME_LENGTH], item_info[16];
	Menu menu = new Menu(Handler_PlayerList);
	menu.SetTitle("%s Glow Management - Player List\n ", PREFIX_MENU);
	
	for (int current_client = 1, current_color[4]; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			GetEntityRenderColor(current_client, current_color[0], current_color[1], current_color[2], current_color[3]);
			
			if (current_color[0] != 255 && current_color[1] != 255 && current_color[2] != 255)
			{
				continue;
			}
			
			GetClientName(current_client, current_client_name, sizeof(current_client_name));
			
			IntToString(GetClientUserId(current_client), item_info, sizeof(item_info));
			menu.AddItem(item_info, current_client_name);
		}
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_PlayerList(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still in allow state
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Glow management menu allowed for alive guards or admins.", PREFIX_ERROR);
			return 0;
		}
		
		char item_info[16];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		
		// Initialize the target index by the item info, and make sure it's valid
		int target_index = GetClientOfUserId(StringToInt(item_info));
		
		if (!target_index)
		{
			PrintToChat(client, "%s The selected player is no longer in-game!", PREFIX_ERROR);
			return 0;
		}
		
		GlowPlayer(target_index, client, g_ClientsData[client].glow_color_index);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowGlowManagementMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowRandomTeamsMenu(int client)
{
	char item_display[32];
	Menu menu = new Menu(Handler_RandomTeams);
	menu.SetTitle("%s Glow Management - Random Teams\n ", PREFIX_MENU);
	
	Format(item_display, sizeof(item_display), "Amount: %d Teams", g_ClientsData[client].teams_amount);
	menu.AddItem("", item_display);
	menu.AddItem("", "Create Teams!");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_RandomTeams(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Make sure the client is still in allow state
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Glow management menu allowed for alive guards or admins.", PREFIX_ERROR);
			return 0;
		}
		
		switch (item_position)
		{
			case 0:
			{
				if ((g_ClientsData[client].teams_amount = ++g_ClientsData[client].teams_amount % ((MAX_TEAMS_AMOUNT > GetOnlineTeamCount(CS_TEAM_T, false) ? GetOnlineTeamCount(CS_TEAM_T, false) : MAX_TEAMS_AMOUNT) + 1)) < MIN_TEAMS_AMOUNT)
				{
					g_ClientsData[client].teams_amount = MIN_TEAMS_AMOUNT;
				}
				
				ShowRandomTeamsMenu(client);
			}
			case 1:
			{
				// Prisoners = 9
				// Teams = 2
				// Result = {5, 4}
				
				ArrayList Teams = InitTeamSizes(GetOnlineTeamCount(CS_TEAM_T, true), g_ClientsData[client].teams_amount);
				
				int[] counter = new int[g_ClientsData[client].teams_amount];
				
				int client_team_index;
				
				for (int current_client = 1; current_client <= MaxClients; current_client++)
				{
					if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
					{
						do
						{
							client_team_index = GetRandomInt(0, Teams.Length - 1);
						} while (counter[client_team_index] == Teams.Get(client_team_index));
						
						counter[client_team_index]++;
						
						GlowPlayer(current_client, client, client_team_index, false, true);
					}
				}
				
				delete Teams;
				
				PrintToChatAll("%s %s \x04%N\x01 has divided all \x10prisoners\x01 to \x03%d\x01 teams!", PREFIX, GetClientTeam(client) == CS_TEAM_CT ? "Guard" : "Admin", client, g_ClientsData[client].teams_amount);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowGlowManagementMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Functions ]================================//

void GlowPlayer(int client, int executer, int color_index = -1, bool broadcast = true, bool hud_display = false)
{
	// Initialize the color
	int color[4];
	GetColorRGB(color_index == -1 ? "255,255,255,255" : g_szColors[color_index][Color_Rgb], color);
	
	// Change the entity color
	SetEntityRenderColor(client, color[0], color[1], color[2], color[3]);
	
	if (hud_display)
	{
		SetHudTextParams(-1.0, 0.2, 3.0, color[0], color[1], color[2], color[3]);
		ShowHudText(client, -1, "You're in team %s!", g_szColors[color_index][Color_Name]);
	}
	
	if (!executer || !broadcast)
	{
		return;
	}
	
	// Notify online players
	if (color_index == -1) {
		PrintToChatAll("%s \x04%N\x01 has removed prisoner \x10%N\x01 glow color.", PREFIX, executer, client);
	}
	else {
		PrintToChatAll("%s \x04%N\x01 has glowed prisoner \x06%N\x01 with the color \x07%s\x01.", PREFIX, executer, client, g_szColors[color_index][Color_Name]);
	}
}

void ExecuteGangsColoring(int executer)
{
	for (int current_client = 1, current_gang_index = -1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			if ((current_gang_index = Gangs_GetPlayerGang(current_client)) != -1) {
				GlowPlayer(current_client, executer, Gangs_GetGangColor(current_gang_index), false);
			}
			else {
				SetEntityRenderColor(current_client);
			}
		}
	}
	
	PrintToChatAll("%s \x04%N\x01 has glowed everyone by their gang color!", PREFIX, executer);
}

int GetColorByRGB(int color[4])
{
	for (int current_color_index = 0, current_color[4]; current_color_index < sizeof(g_szColors); current_color_index++)
	{
		GetColorRGB(g_szColors[current_color_index][Color_Rgb], current_color);
		
		if (current_color[0] == color[0] && current_color[1] == color[1] && current_color[2] == color[2] && current_color[3] == color[3])
		{
			return current_color_index;
		}
	}
	
	return -1;
}

ArrayList InitTeamSizes(int players, int teams)
{
	ArrayList array = new ArrayList();
	
	int index = 0;
	int player_count_in_team = players / teams;
	
	// player_count_in_team = (9 / 2 = 4)
	
	for (; index < teams; index++)
	{
		array.Push(player_count_in_team);
	}
	
	// array = {4, 4}
	
	int players_left = (players - player_count_in_team * teams); // = 1
	
	for (index = 0; 0 < players_left; players_left--, index++)
	{
		array.Set(index, array.Get(index) + 1);
	}
	
	return array;
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//