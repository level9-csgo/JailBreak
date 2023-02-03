#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define LR_NAME "Dodgeball Duel"
#define LR_WEAPON "weapon_decoy"
#define DEFAULT_HEALTH 1

#define COLLISION_GROUP_DEBRIS_TRIGGER 2      // Default client collision group, non solid
#define COLLISION_GROUP_INTERACTIVE_DEBRIS 3  // Required client collision group, interactive solid

enum struct Setup
{
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

ConVar g_cvFallDamageScale;

bool g_bIsLrActivated;

// Stores the trail precached model index.
int g_TrailModelIndex;

int g_iLrId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...LR_NAME..." Lr", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_cvFallDamageScale = FindConVar("sv_falldamage_scale");
}

public void OnPluginEnd()
{
	if (g_bIsLrActivated) {
		JB_StopLr();
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_LrSystem"))
	{
		g_iLrId = JB_AddLr(LR_NAME, false, false, true, true);
	}
}

public void OnMapStart()
{
	// Precache the decoy projectile trail model index, and store the return index.
	g_TrailModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void JB_OnLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_esSetupData.Reset();
		g_esSetupData.iPrisoner = client;
		showLrSetupMenu(client);
	}
}

public void JB_OnRandomLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_esSetupData.Reset();
		g_esSetupData.iPrisoner = client;
		g_esSetupData.iAgainst = GetRandomGuard();
		StartLr();
	}
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (g_bIsLrActivated && g_iLrId == currentLr)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) 
			{
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				SetEntProp(iCurrentClient, Prop_Data, "m_iMaxHealth", 100);
	
				SetEntityCollisionGroup(iCurrentClient, COLLISION_GROUP_DEBRIS_TRIGGER);
				EntityCollisionRulesChanged(iCurrentClient);
			}
		}
		
		g_cvFallDamageScale.IntValue = 1;
		
		UnhookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
		
		ToggleBunnyhop(true);
		
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst)
			);
		panel.DrawText(szMessage);
	}
}

public Action Event_GrenadeThrow(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == g_esSetupData.iPrisoner || client == g_esSetupData.iAgainst)
	{
		DisarmPlayer(client);
		EquipPlayerWeapon(client, GivePlayerItem(client, LR_WEAPON));
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_bIsLrActivated && StrEqual(classname, "decoy_projectile"))
	{
		// This is too soon to retrive data from the entity by network properties, etc...
		// We must wait until the entity will fully spawn.
		SDKHook(entity, SDKHook_SpawnPost, Hook_OnSpawnPost);
	}
}

/*  */

/* SDK Hooks */

Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((victim == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (victim != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner)) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

void Hook_OnSpawnPost(int entity)
{
	// Once the projectile is touching anything, remove it.
	SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	// Display a colored following trail behind the projectile.
	if (g_TrailModelIndex)
	{
		int color[4];
		
		color[0] = GetRandomInt(1, 255);
		color[1] = GetRandomInt(1, 255);
		color[2] = GetRandomInt(1, 255);
		color[3] = 255;
		
		TE_SetupBeamFollow(entity, g_TrailModelIndex, 0, 1.5, 0.5, 2.0, 1, color);
		TE_SendToAll();
	}
}

Action Hook_OnStartTouch(int entity, int other)
{
	int thrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (thrower != -1 && (1 <= other <= MaxClients))
	{
		// Set the victim armor value to 0, else it won't kill him.
		SetEntProp(other, Prop_Send, "m_ArmorValue", 0);
		
		// Eliminate the victim.
		SDKHooks_TakeDamage(other, thrower, thrower, float(GetClientHealth(other)), entity);
	}
	
	// Remove the entity from the world.
	AcceptEntityInput(entity, "Kill");
}

/*  */

/* Menus */

void showLrSetupMenu(int client)
{
	char szItem[128], szItemInfo[8];
	Menu menu = new Menu(Handler_LrSetup);
	menu.SetTitle("%s Last Request - %s (Choose Your Enemy)\n ", PREFIX_MENU, LR_NAME);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_CT && !IsFakeClient(iCurrentClient))
		{
			IntToString(iCurrentClient, szItemInfo, sizeof(szItemInfo));
			GetClientName(iCurrentClient, szItem, sizeof(szItem));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_LrSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsLrAvailable(client, client))
		{
			return;
		}
		
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		g_esSetupData.iAgainst = StringToInt(szItem);
		
		if (!IsPlayerAlive(g_esSetupData.iAgainst) || GetClientTeam(g_esSetupData.iAgainst) != CS_TEAM_CT)
		{
			showLrSetupMenu(client);
		} else {
			StartLr();
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		g_esSetupData.Reset();
		JB_ShowLrMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

/*  */

/* Functions */

void StartLr()
{
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	g_cvFallDamageScale.IntValue = 0;
	
	HookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
	
	ToggleBunnyhop(false);
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (client == -1 || IsFakeClient(client))
	{
		return;
	}
	
	DisarmPlayer(client);
	GivePlayerItem(client, LR_WEAPON);
	SetEntityHealth(client, DEFAULT_HEALTH);
	
	SetEntProp(client, Prop_Data, "m_iMaxHealth", DEFAULT_HEALTH);

	SetEntityCollisionGroup(client, COLLISION_GROUP_INTERACTIVE_DEBRIS);
	EntityCollisionRulesChanged(client);
}

/*  */