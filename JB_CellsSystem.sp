#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_CellsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DIR_PATH "addons/sourcemod/configs/CellsData"

#define SHOW_GLOW_TIME 5.0

//====================//

#define GetEntityName(%1,%2,%3) GetEntPropString(%1, Prop_Data, "m_iName", %2, %3)
#define GetEntityHammerId(%1) GetEntProp(%1, Prop_Data, "m_iHammerID")

GlobalForward g_fwdOnCellMove;

ArrayList g_CellsData;

Handle g_hAutoCellsOpenTimer = INVALID_HANDLE;

ConVar g_cvAutoCellsOpenTime;
ConVar g_cvAbleCellsOpenTime;

char g_AuthorizedClassNames[][] = 
{
	"func_door", 
	"func_movelinear", 
	"func_door_rotating", 
	"prop_door_rotating", 
	"dz_door", 
	"func_breakable", 
	"func_wall_toggle", 
	"func_tracktrain", 
	"func_brush"
};

char g_CurrentMapName[128];

bool g_IsClientInMenu[MAXPLAYERS + 1];
bool g_IsCellsOpened;
bool g_UpdateMapData;

int g_RoundStartUnixstamp;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Cells System", 
	author = PLUGIN_AUTHOR, 
	description = "Provides fully jail cells control with chat commands and map menu configuration.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the cells data arraylist
	g_CellsData = new ArrayList();
	
	// ConVars Configurate
	g_cvAutoCellsOpenTime = CreateConVar("jb_cells_auto_open", "90", "Time in seconds for all the cells to automatically open.", _, true, 60.0, true, 180.0);
	g_cvAbleCellsOpenTime = CreateConVar("jb_cells_able_open", "3", "Time in seconds for guards to be able to open the cells. (With admin bypass)", _, true, 1.0, true, 30.0);
	
	AutoExecConfig(true, "CellSystem", "JailBreak");
	
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Admin Commands
	RegAdminCmd("sm_cells", Command_Cells, ADMFLAG_ROOT, "Access the map cells configuration menu.");
	
	// Client Commands
	RegConsoleCmd("sm_open", Command_Open, "Opens all the cells on the map.");
	RegConsoleCmd("sm_close", Command_Close, "Closes all the cells on the map.");
	
	// Event Hooks
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_Post);
}

public void OnPluginEnd()
{
	// Incase the server/plugin came to a crash state, make sure to save all the data
	OnMapEnd();
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	// Make sure to reset the client variables, to avoid client data override
	g_IsClientInMenu[client] = false;
}

public void OnMapStart()
{
	// Initialize the current map name
	GetCurrentMap(g_CurrentMapName, sizeof(g_CurrentMapName));
	
	// Set the cells open state variable as false, a new map just started
	g_IsCellsOpened = false;
	
	// Setup the map configuration file
	SetupMapConfig();
	
	// Perform entity hooks on the map entities
	for (int current_class_name = 0; current_class_name < sizeof(g_AuthorizedClassNames); current_class_name++)
	{
		HookEntityOutput(g_AuthorizedClassNames[current_class_name], "OnFullyOpen", Hook_OnCellsStatusChange);
		HookEntityOutput(g_AuthorizedClassNames[current_class_name], "OnFullyClosed", Hook_OnCellsStatusChange);
		HookEntityOutput(g_AuthorizedClassNames[current_class_name], "OnBreak", Hook_OnCellsStatusChange);
	}
}

public void OnMapEnd()
{
	// If the configuration file should be updated, update it!
	if (g_UpdateMapData)
	{
		KV_SetMapCellsData();
		g_UpdateMapData = false;
	}
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Create the automated cells open timer
	g_hAutoCellsOpenTimer = CreateTimer(g_cvAutoCellsOpenTime.FloatValue, Timer_AutoCellsOpen);
	
	// Update the round start unixstamp variable
	g_RoundStartUnixstamp = GetTime();
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	// Set the cells open state variable as false, a new round just started
	g_IsCellsOpened = false;
	
	// Reset the automatic cells open timer
	if (g_hAutoCellsOpenTimer != INVALID_HANDLE)
	{
		KillTimer(g_hAutoCellsOpenTimer);
		g_hAutoCellsOpenTimer = INVALID_HANDLE;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// If the client isn't inside the configuration menu, dont conitnue
	if (!g_IsClientInMenu[client])
	{
		return Plugin_Continue;
	}
	
	// Initialize the aimed entity and make sure it's valid
	int aimed_entity = GetEntityByAim(client);
	
	if (aimed_entity <= 0)
	{
		PrintCenterText(client, "<font color='#0000B3'> Doors Configuration</font>\n No entity has detected.");
		return Plugin_Continue;
	}
	
	// Gather information about the aimed entity
	char entity_class_name[64], entity_name[64];
	GetEntityClassname(aimed_entity, entity_class_name, sizeof(entity_class_name));
	GetEntityName(aimed_entity, entity_name, sizeof(entity_name));
	
	// Display the information
	PrintCenterText(client, "<font color='#0000B3'> Doors Configuration</font>\n  • Class Name: %s\n  • Name: %s\n  • Index: %d\n  • Hammer ID: %d", entity_class_name, entity_name[0] == '\0' ? "NULL" : entity_name, aimed_entity, GetEntityHammerId(aimed_entity));
	
	return Plugin_Continue;
}

//================================[ Entity Hooks ]================================//

public void Hook_OnCellsStatusChange(const char[] output, int caller, int activator, float delay)
{
	static float last_game_time;
	
	// Make sure the entity is configurated
	if (IsEntityConfigurated(caller) == -1)
	{
		return;
	}
	
	bool IsCellOpened = !StrEqual(output, "OnFullyClosed");
	
	//==== [ Execute the cell move forward ] =====//
	Call_StartForward(g_fwdOnCellMove);
	Call_PushCell(caller);
	Call_PushCell(IsCellOpened);
	Call_Finish();
	
	// Make sure the cell move within a time range of 0.5 from the last cell move
	if (GetGameTime() - last_game_time <= 0.5 || StrEqual(output, "OnBreak"))
	{
		// Notify server
		PrintCenterTextAll("The cell doors were %s!", IsCellOpened ? "opened" : "closed");
		
		g_IsCellsOpened = IsCellOpened;
	}
	
	last_game_time = GetGameTime();
}

//================================[ Commands ]================================//

public Action Command_Open(int client, int args)
{
	// Deney the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure the client has the command access
	if (!IsClientAllowed(client))
	{
		PrintToChat(client, "%s Cell opening is allowed for \x06alive guard and admins\x01 only.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Deney the command access if the client isn't admin, 
	// and not enough time has passed from the start of the round
	if ((GetTime() - g_RoundStartUnixstamp) < g_cvAbleCellsOpenTime.IntValue && GetUserAdmin(client) == INVALID_ADMIN_ID)
	{
		PrintToChat(client, "%s You cannot open the \x10cells\x01 that soon!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Notify the server
	PrintToChatAll("%s %s \x04%N\x01 has opened the \x10cells\x01!", PREFIX, GetClientTeam(client) == CS_TEAM_CT ? "Guard" : "Admin", client);
	
	// Open the cells
	ToggleCellsState(true);
	
	// Set the cells open state to true
	g_IsCellsOpened = true;
	
	return Plugin_Handled;
}

public Action Command_Close(int client, int args)
{
	// Deney the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Make sure the client has the command access
	if (!IsClientAllowed(client))
	{
		PrintToChat(client, "%s Cell closing is allowed for \x06alive guard and admins\x01 only.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Notify the server
	PrintToChatAll("%s %s \x04%N\x01 has closed the \x10cells\x01!", PREFIX, GetUserAdmin(client) != INVALID_ADMIN_ID ? "Admin":"Guard", client);
	
	// Close the cells
	ToggleCellsState(false);
	
	// Set the cells open state to false
	g_IsCellsOpened = false;
	
	return Plugin_Handled;
}

public Action Command_Cells(int client, int args)
{
	if (args == 1)
	{
		// Make sure the client has root admin flag
		if (!(GetUserFlagBits(client) & ADMFLAG_ROOT))
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
		
		if (!(GetUserFlagBits(target_index) & ADMFLAG_ROOT)) {
			PrintToChat(client, "%s Doors configuration menu allowed for root administrators only.", PREFIX_ERROR);
		} else {
			ShowDoorsConfigurationMenu(target_index);
		}
	}
	else {
		ShowDoorsConfigurationMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_OpenCells", Native_OpenCells);
	CreateNative("JB_CloseCells", Native_CloseCells);
	CreateNative("JB_IsCellsOpened", Native_IsCellsOpened);
	CreateNative("JB_IsMapCellsConfigurated", Native_IsMapCellsConfigurated);
	
	g_fwdOnCellMove = CreateGlobalForward("JB_OnCellMove", ET_Event, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_CellsSystem");
	return APLRes_Success;
}

public int Native_OpenCells(Handle plugin, int numParams)
{
	// If the server isn't processing, abort the action
	if (!IsServerProcessing())
	{
		return;
	}
	
	// Open the map cells
	ToggleCellsState(true);
	
	// Set the cells open state to true
	g_IsCellsOpened = true;
}

public int Native_CloseCells(Handle plugin, int numParams)
{
	// If the server isn't processing, abort the action
	if (!IsServerProcessing())
	{
		return;
	}
	
	// Open the map cells
	ToggleCellsState(false);
	
	// Set the cells open state to true
	g_IsCellsOpened = false;
}

public int Native_IsCellsOpened(Handle plugin, int numParams)
{
	return g_IsCellsOpened;
}

public int Native_IsMapCellsConfigurated(Handle plugin, int numParams)
{
	char map_name[128];
	GetNativeString(1, map_name, sizeof(map_name));
	return IsMapConfigurated(map_name);
}

//================================[ Menus ]================================//

void ShowDoorsConfigurationMenu(int client)
{
	char item_display[32], item_info[4];
	Menu menu = new Menu(Handler_DoorsConfiguration);
	menu.SetTitle("%s Cells System - Doors Configuration\n ", PREFIX_MENU);
	
	menu.AddItem("", "Save Viewed Door");
	menu.AddItem("", "Not Configurated Map(s)");
	menu.AddItem("", "Highlight Configurated Doors\n \n• Doors List:");
	
	// Loop trough all the map cells and add them into the menu
	for (int current_cell = 0; current_cell < g_CellsData.Length; current_cell++)
	{
		Format(item_display, sizeof(item_display), "Cell Door #%d", current_cell + 1);
		
		// Convert the current index into a string, and parse it through the menu item
		IntToString(current_cell, item_info, sizeof(item_info));
		menu.AddItem(item_info, item_display);
	}
	
	// If no cell doors are exists, add an extra notify menu item
	if (!g_CellsData.Length)
	{
		menu.AddItem("", "No cell door was found.", ITEMDRAW_DISABLED);
	}
	
	// If the client already inside a menu, close it for the entity info feature to be working
	if (GetClientMenu(client) != MenuSource_None)
	{
		CancelClientMenu(client);
	}
	
	g_IsClientInMenu[client] = true;
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_DoorsConfiguration(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Initialize the entity index by the clients's aim, and make sure it's valid
				int aimed_entity = GetEntityByAim(client);
				
				if (!aimed_entity)
				{
					PrintToChat(client, "%s \x07Failed to save, no entity was found. Please try again.\x01", PREFIX);
					ShowDoorsConfigurationMenu(client);
					return;
				}
				
				// Make sure the entity isn't configurated
				
				int cell_index = -1;
				if ((cell_index = IsEntityConfigurated(aimed_entity)) != -1)
				{
					PrintToChat(client, "%s Cell door \x04#%d\x01 is already map configurated.", PREFIX, cell_index + 1);
					ShowDoorsConfigurationMenu(client);
					return;
				}
				
				// Initialize the entity's class name, and make sure it's valid
				char entity_class_name[64];
				GetEntityClassname(aimed_entity, entity_class_name, sizeof(entity_class_name));
				
				if (!IsClassNameAuthorized(entity_class_name))
				{
					PrintToChat(client, "%s Class name \"\x02%s\x01\" is not supported.", PREFIX, entity_class_name);
					ShowDoorsConfigurationMenu(client);
					return;
				}
				
				// Notify the client
				PrintToChat(client, "%s Successfully saved cell door number \x04#%d\x01.", PREFIX, g_CellsData.Length + 1);
				
				// Push the entity's hammer id into the cells data arraylist
				g_CellsData.Push(GetEntityHammerId(aimed_entity));
				g_UpdateMapData = true;
				
				// Dispaly the unconfigurated maps menu
				ShowDoorsConfigurationMenu(client);
			}
			case 1:
			{
				// Dispaly the unconfigurated maps menu
				ShowNotConfiguratedMapsMenu(client);
				DisableEntityInfo(client);
			}
			case 2:
			{
				float glow_position[3];
				
				for (int current_cell = 0, current_entity; current_cell < g_CellsData.Length; current_cell++)
				{
					current_entity = GetEntityByHammerId(g_CellsData.Get(current_cell));
					if (!IsValidEntity(current_entity))
					{
						continue;
					}
					
					GetEntPropVector(current_entity, Prop_Send, "m_vecOrigin", glow_position);
					CreateGlowParticle(glow_position, SHOW_GLOW_TIME);
				}
				
				// Display the doors configuration menu
				ShowDoorsConfigurationMenu(client);
			}
			default:
			{
				// Initialize the cell door index by the item info
				char item_info[4];
				menu.GetItem(item_position, item_info, sizeof(item_info));
				int cell_index = StringToInt(item_info);
				
				// Display the cell detail menu, by the specified cell index
				ShowCellDetailMenu(client, cell_index);
				DisableEntityInfo(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		DisableEntityInfo(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void ShowNotConfiguratedMapsMenu(int client)
{
	Menu menu = new Menu(Handler_NotConfiguratedMaps);
	int not_configurated_maps = InitConfiguratedMaps(menu);
	menu.SetTitle("%s Cells System - Not Configurated Map(s) (%d Maps)\n ", PREFIX_MENU, not_configurated_maps);
	
	if (!not_configurated_maps)
	{
		menu.AddItem("", "Yay! All maps are configurated!", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Dispaly the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_NotConfiguratedMaps(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		ShowNotConfiguratedMapsMenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Display the last menu the client was at
		ShowDoorsConfigurationMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

void ShowCellDetailMenu(int client, int cellIndex)
{
	// Initialize the entity index & hammer id, and make sure they're valid
	int entity_hammer_id = g_CellsData.Get(cellIndex), entity_index = GetEntityByHammerId(entity_hammer_id);
	
	if (!IsValidEntity(entity_index))
	{
		// Notify the client
		PrintToChat(client, "%s Cell Door #%d is \x02corrupt\x01, sent back to main menu.", PREFIX, cellIndex + 1);
		
		// Display the cell doors configuration menu
		ShowDoorsConfigurationMenu(client);
		return;
	}
	
	// Gather information about the entity
	char entity_class_name[64], entity_name[64];
	GetEntityClassname(entity_index, entity_class_name, sizeof(entity_class_name));
	GetEntityName(entity_index, entity_name, sizeof(entity_name));
	
	// Display the information through the menu title
	Menu menu = new Menu(Handler_CellDoorDetail);
	menu.SetTitle("%s Cells System - Viewing Door \"#%d\"\n• Class Name: %s\n• Name: %s\n• Index: %d\n• Hammer ID: %d\n\n ", PREFIX_MENU, cellIndex + 1, entity_class_name, entity_name, entity_index, entity_hammer_id);
	
	// Convert the specified cell index into a string, and parse it though the first menu item
	char item_info[4];
	IntToString(cellIndex, item_info, sizeof(item_info));
	menu.AddItem(item_info, "Highlight Door");
	menu.AddItem("", "Delete Door");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Dispaly the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CellDoorDetail(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		// Initialize the cell index by the first menu item info
		char item_info[4];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		int cell_index = StringToInt(item_info);
		
		switch (item_position)
		{
			case 0:
			{
				int entity_index = GetEntityByHammerId(g_CellsData.Get(cell_index));
				
				if (!IsValidEntity(entity_index))
				{
					// Notify the client
					PrintToChat(client, "%s Cell Door #%d is \x02corrupt\x01, sent back to main menu.", PREFIX, cell_index + 1);
					
					// Display the cell doors configuration menu
					ShowDoorsConfigurationMenu(client);
					return;
				}
				
				// Initlaize the entity's origin, which will be the glow position
				float glow_position[3];
				GetEntPropVector(entity_index, Prop_Send, "m_vecOrigin", glow_position);
				CreateGlowParticle(glow_position, SHOW_GLOW_TIME);
				
				// Display the cell detail menu again
				ShowCellDetailMenu(client, cell_index);
			}
			case 1:
			{
				// Notify the client
				PrintToChat(client, "%s Successfully \x02deleted\x01 cell door number \x04#%d\x01.", PREFIX, cell_index + 1);
				
				// Erase the specified index from the arraylist
				g_CellsData.Erase(cell_index);
				g_UpdateMapData = true;
				
				// Display the doors configuration menu again
				ShowDoorsConfigurationMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Display the last menu the client was at
		ShowDoorsConfigurationMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
}

//================================[ Key Values ]================================//

void KV_LoadMapCells()
{
	// Initialize the current map config file path
	char file_path[PLATFORM_MAX_PATH]; file_path = GetMapConfigPath();
	
	// Make sure the map config file is exists
	if (!FileExists(file_path))
	{
		SetFailState("Unable to find file \"%s\"", file_path);
	}
	
	// Clear the cells data arraylist
	g_CellsData.Clear();
	
	KeyValues kv = new KeyValues("CellsData");
	kv.ImportFromFile(file_path);
	
	if (kv.GotoFirstSubKey(false))
	{
		do {
			g_CellsData.Push(kv.GetNum(NULL_STRING));
		} while (kv.GotoNextKey(false));
		
		kv.Rewind();
		kv.ExportToFile(file_path);
	}
	
	// Don't leak handles
	kv.Close();
}

void KV_SetMapCellsData()
{
	// Initialize the current map config file path
	char file_path[PLATFORM_MAX_PATH]; file_path = GetMapConfigPath();
	
	// Make sure the map config file is exists
	if (!FileExists(file_path))
	{
		SetFailState("Unable to find file \"%s\"", file_path);
	}
	
	// Completely clear the config file
	delete OpenFile(file_path, "w+");
	
	KeyValues kv = new KeyValues("CellsData");
	kv.ImportFromFile(file_path);
	
	char current_key[4];
	
	// Loop through all the map cells and insert them into the config file
	for (int current_cell = 0; current_cell < g_CellsData.Length; current_cell++)
	{
		IntToString(current_cell, current_key, sizeof(current_key));
		kv.SetNum(current_key, g_CellsData.Get(current_cell));
	}
	
	kv.Rewind();
	kv.ExportToFile(file_path);
	
	// Don't leak handles
	kv.Close();
	
	// Load the current map cells data again
	KV_LoadMapCells();
}

//================================[ Timers ]================================//

public Action Timer_AutoCellsOpen(Handle timer)
{
	// Open the map cells only if they are closed
	if (!g_IsCellsOpened)
	{
		ToggleCellsState(true);
		g_IsCellsOpened = true;
	}
	
	g_hAutoCellsOpenTimer = INVALID_HANDLE;
}

public Action Timer_FixFuncBrushExploit(Handle timer, DataPack dPack)
{
	// Initialize the entity index, and make sure it's valid
	int entity_index = dPack.ReadCell();
	
	if (!IsValidEntity(entity_index))
	{
		return Plugin_Continue;
	}
	
	// Fire the input
	AcceptEntityInput(entity_index, dPack.ReadCell() ? "Enable" : "Disable");
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ToggleCellsState(bool open)
{
	char entity_class_name[64];
	
	for (int current_cell = 0, current_entity; current_cell < g_CellsData.Length; current_cell++)
	{
		// Initialize the entity index, by the current array hammer id
		current_entity = GetEntityByHammerId(g_CellsData.Get(current_cell));
		
		// Make sure the entity is exists and valid
		if (!IsValidEntity(current_entity))
		{
			continue;
		}
		
		// Get the current entity class name
		GetEntityClassname(current_entity, entity_class_name, sizeof(entity_class_name));
		
		// If the current entity class name is 'func_brush', it needs a special input command,
		// Some 'func_brush' entities seems to spawn too late, the purpuse of the timer below is to fix it.
		if (StrEqual(entity_class_name, "func_brush"))
		{
			DataPack dPack;
			CreateDataTimer(0.5, Timer_FixFuncBrushExploit, dPack, TIMER_FLAG_NO_MAPCHANGE);
			dPack.WriteCell(current_entity);
			dPack.WriteCell(!open);
			dPack.Reset();
			
			continue;
		}
		
		// Fire the state change input command
		AcceptEntityInput(current_entity, !open ? "Close" : StrEqual(entity_class_name, "func_breakable") ? "Break" : "Open");
	}
}

void SetupMapConfig()
{
	// If the cells config directory isn't exists, create it!
	if (!DirExists(DIR_PATH))
	{
		CreateDirectory(DIR_PATH, 511);
	}
	
	// Build a platform path into the map config file, and open the file
	char directory_path[PLATFORM_MAX_PATH]; directory_path = GetMapConfigPath();
	BuildPath(Path_SM, directory_path, sizeof(directory_path), directory_path[17]);
	delete OpenFile(directory_path, "a+");
	
	// Load the current map cells data
	KV_LoadMapCells();
}

void CreateGlowParticle(float pos[3], float suicide = 5.0)
{
	int entity_index = CreateEntityByName("info_particle_system");
	
	if (entity_index == -1 || !IsValidEntity(entity_index))
	{
		return;
	}
	
	// Dispatch values into the entity's key values
	DispatchKeyValue(entity_index, "effect_name", "aircraft_navgreen");
	DispatchKeyValue(entity_index, "targetname", "particle");
	
	// Spawn the teleport the glow particle
	DispatchSpawn(entity_index);
	TeleportEntity(entity_index, pos, NULL_VECTOR, NULL_VECTOR);
	
	ActivateEntity(entity_index);
	AcceptEntityInput(entity_index, "Start");
	
	char szOutput[32];
	Format(szOutput, sizeof(szOutput), "OnUser1 !self:kill::%f:1", suicide);
	SetVariantString(szOutput);
	AcceptEntityInput(entity_index, "AddOutput");
	AcceptEntityInput(entity_index, "FireUser1");
}

void DisableEntityInfo(int client)
{
	if (IsClientInGame(client))
	{
		PrintCenterText(client, "");
		g_IsClientInMenu[client] = false;
	}
}

char GetFileExt(const char[] filePath)
{
	char ext[8];
	for (int iCurrentChar = strlen(filePath); iCurrentChar && filePath[iCurrentChar] != '.'; iCurrentChar--)
	{
		Format(ext, sizeof(ext), "%c%s", filePath[iCurrentChar], ext);
	}
	
	return ext;
}

char GetMapConfigPath()
{
	char file_path[PLATFORM_MAX_PATH];
	Format(file_path, sizeof(file_path), "%s/%s.cfg", DIR_PATH, g_CurrentMapName);
	return file_path;
}

int GetEntityByAim(int client)
{
	float fAngles[3];
	float fOrigin[3];
	
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, fAngles);
	
	TR_TraceRayFilter(fOrigin, fAngles, MASK_ALL, RayType_Infinite, Filter_DontHitPlayers);
	
	return (TR_DidHit() ? TR_GetEntityIndex() : -1);
}

bool Filter_DontHitPlayers(int entity, int mask)
{
	return (entity > MaxClients);
}

int GetEntityByHammerId(int hammerId)
{
	for (int current_entity = MAXPLAYERS; current_entity < GetMaxEntities(); current_entity++)
	{
		if (IsValidEntity(current_entity) && hammerId == GetEntProp(current_entity, Prop_Data, "m_iHammerID"))
		{
			return current_entity;
		}
	}
	
	return -1;
}

int InitConfiguratedMaps(Menu menu)
{
	DirectoryListing hDirectory = OpenDirectory("maps");
	
	if (hDirectory == null) {
		return 0;
	}
	
	char szPath[PLATFORM_MAX_PATH], szFilePath[PLATFORM_MAX_PATH];
	
	FileType fileType;
	KeyValues kv = new KeyValues("CellsData");
	
	int iCounter = 0;
	while (ReadDirEntry(hDirectory, szPath, sizeof(szPath), fileType))
	{
		if (fileType == FileType_File && StrEqual(GetFileExt(szPath), "bsp", false))
		{
			strcopy(szFilePath, sizeof(szFilePath), szPath);
			ReplaceString(szFilePath, sizeof(szFilePath), ".bsp", "");
			Format(szFilePath, sizeof(szFilePath), "%s/%s.cfg", DIR_PATH, szFilePath);
			
			if (FileExists(szFilePath))
			{
				kv.ImportFromFile(szFilePath);
				if (kv.GotoFirstSubKey(false)) {
					continue;
				}
			}
			
			iCounter++;
			menu.AddItem("", szPath);
		}
	}
	
	delete kv;
	delete hDirectory;
	
	return iCounter;
}

int IsEntityConfigurated(int entity)
{
	for (int iCurrentIndex = 0; iCurrentIndex < g_CellsData.Length; iCurrentIndex++)
	{
		if (entity == GetEntityByHammerId(g_CellsData.Get(iCurrentIndex)))
		{
			return iCurrentIndex;
		}
	}
	
	return -1;
}

bool IsClassNameAuthorized(const char[] class_name)
{
	for (int current_class_name = 0; current_class_name < sizeof(g_AuthorizedClassNames); current_class_name++)
	{
		if (StrEqual(g_AuthorizedClassNames[current_class_name], class_name))
		{
			return true;
		}
	}
	
	return false;
}

bool IsMapConfigurated(const char[] mapName)
{
	KeyValues kv = new KeyValues("CellsData");
	
	char szFilePath[PLATFORM_MAX_PATH];
	Format(szFilePath, sizeof(szFilePath), "%s/%s.cfg", DIR_PATH, mapName);
	
	bool bExist;
	if (FileExists(szFilePath))
	{
		kv.ImportFromFile(szFilePath);
		if (kv.GotoFirstSubKey(false)) {
			bExist = true;
		}
	}
	
	kv.Close();
	
	return bExist;
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//