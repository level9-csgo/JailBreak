#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Deagle Giver", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_deagle", Command_Deagle, "Access the deagle giver menu.");
}

//================================[ Commands ]================================//

public Action Command_Deagle(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for root administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1) {
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		if (!IsClientAllowed(iTargetIndex)) {
			PrintToChat(client, "%s Deagle giver menu allowed for alive guards or admins.", PREFIX_ERROR);
		} else {
			showDeagleGiverMenu(iTargetIndex);
		}
	}
	else {
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Deagle giver menu allowed for alive guards or admins.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		showDeagleGiverMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void showDeagleGiverMenu(int client)
{
	Menu menu = new Menu(Handler_DeagleGiver);
	menu.SetTitle("%s Deagle Give - Main Menu\n ", PREFIX_MENU);
	
	menu.AddItem("", "Give Prisoners Empty Deagles");
	menu.AddItem("", "Give Prisoners Full Deagles");
	menu.AddItem("", "Give Everyone Empty Deagles");
	menu.AddItem("", "Give Everyone Full Deagles");
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DeagleGiver(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsClientAllowed(client)) 
		{
			PrintToChat(client, "%s Deagle giver menu allowed for alive guards or admins.", PREFIX_ERROR);
			return 0;
		}
		
		switch (itemNum)
		{
			case 0, 1:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T) {
						GiveDeagle(iCurrentClient, !itemNum);
					}
				}
				
				PrintToChatAll("%s \x04%N\x01 has gave all the \x10prisoners\x01 a%s deagle!", PREFIX, client, !itemNum ? "n empty" : " full");
			}
			case 2, 3:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient)) {
						GiveDeagle(iCurrentClient, itemNum == 2);
					}
				}
				
				PrintToChatAll("%s \x04%N\x01 has gave everyone a%s deagle!", PREFIX, client, itemNum == 2 ? "n empty" : " full");
			}
		}
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

//================================[ Functions ]================================//

void GiveDeagle(int client, bool empty)
{
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	if (GetPlayerWeapon(client, CSWeapon_DEAGLE) != -1) {
		return;
	}
	
	int iSecondery = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	
	if (iSecondery != -1) {
		RemovePlayerItem(client, iSecondery);
	}
	
	GivePlayerItem(client, "weapon_deagle");
	
	iSecondery = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	
	if (iSecondery != -1 && IsValidEntity(iSecondery) && empty) {
		SetEntProp(iSecondery, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
		SetEntProp(iSecondery, Prop_Send, "m_iClip1", 0);
	}
}

int GetPlayerWeapon(int client, CSWeaponID weaponId)
{
	static int max;
	if (!max) {
		max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	}
	
	int i, def, weapon;
	for (; i < max; i++)
	{
		weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon != -1) {
			def = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			if (CS_ItemDefIndexToID(def) == weaponId) {
				return weapon;
			}
		}
	}
	
	return -1;
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//