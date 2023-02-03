#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Helper", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	AddCommandListener(Listener_Help, "sm_help");
}

//================================[ Commands ]================================//

public Action Listener_Help(int iPlayerIndex, char[] command, int argc)
{
	if (argc == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(iPlayerIndex) == INVALID_ADMIN_ID) {
			PrintToChat(iPlayerIndex, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Stop;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(iPlayerIndex, szArg, true, false);
		
		if (iTargetIndex == -1)
		{
			// Automated message
			return Plugin_Stop;
		}
		
		showHelpMainMenu(iTargetIndex);
	}
	else {
		showHelpMainMenu(iPlayerIndex);
	}
	
	return Plugin_Stop;
}

//================================[ Menus ]================================//

void showHelpMainMenu(int iPlayerIndex)
{
	Menu menu = new Menu(Handler_RunesMain);
	menu.SetTitle("%s Helper - Main Menu\n ", PREFIX_MENU);
	
	
	
	// Display the menu to the client
	menu.Display(iPlayerIndex, MENU_TIME_FOREVER);
}

public int Handler_RunesMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int iPlayerIndex = param1, iItemNum = param2;
		
		
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

//================================================================//
