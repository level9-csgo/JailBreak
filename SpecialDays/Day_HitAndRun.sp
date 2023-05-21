#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_GangsUpgrades>
#include <JB_SpecialDays>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "HitAndRun Day"
#define DAY_GRAVITY 0.20
#define DAY_HEALTH 32767

#define COUNTDOWN_DEATH 15.0
#define PLAYERS_PER_INFECTED 7
#define SERVER_INFECTOR_INDEX -1

#define INFECTED_HIGHLIGHT "\n \n<font color='#CF0903'>You are infected!</font>"
#define FREEZE_SOUND "physics/glass/glass_impact_bullet4.wav"

#define FFADE_IN 0x0001 // Just here so we don't pass 0 into the function
#define FFADE_PURGE 0x0010 // Purges all other fades, replacing them with this one

//====================//

ArrayList g_arInfecteds;

Handle g_hCountdownTimer = INVALID_HANDLE;

UserMsg g_FadeUserMsgId;

char g_szDayLoadout[][] = 
{
	"weapon_ssg08", 
	"weapon_knife", 
	"weapon_flashbang", 
	"weapon_flashbang", 
	"weapon_hegrenade", 
	"weapon_smokegrenade"
};

bool g_bIsDayActivated;

float g_fTimer;

int g_iInfectorIndex[MAXPLAYERS + 1] =  { SERVER_INFECTOR_INDEX, ... };
int g_iDayId = -1;

int g_iHaloSprite = -1;
int g_iBeamSprite = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginEnd()
{
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, false, false, false);
	}
}

public void OnMapStart()
{
	g_iHaloSprite = PrecacheModel("materials/sprites/glow.vmt");
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_bIsDayActivated)
	{
		if (StrEqual(classname, "smokegrenade_projectile"))
		{
			SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch);
			SDKHook(entity, SDKHook_SpawnPost, Hook_OnSpawnPost);
		}
		else if (StrEqual(classname, "flashbang_projectile")) {
			SDKHook(entity, SDKHook_SpawnPost, Hook_OnSpawnPost);
		}
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		DisarmPlayer(client);
		
		for (int iCurrentItem = 0; iCurrentItem < sizeof(g_szDayLoadout); iCurrentItem++)
		{
			GivePlayerItem(client, g_szDayLoadout[iCurrentItem]);
		}
		
		SetEntityRenderColor(client, 255, 255, 255, 255);
		
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		delete g_arInfecteds;
		g_arInfecteds = new ArrayList();
		
		InitInfecteds();
		
		g_fTimer = COUNTDOWN_DEATH;
		g_hCountdownTimer = CreateTimer(0.1, Timer_InfectedsCountdown, _, TIMER_REPEAT);
		
		int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
		if (iUpgradeIndex != -1) {
			JB_ToggleGangUpgrade(iUpgradeIndex, false);
		}
		
		HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
		HookEvent("weapon_reload", Event_WeaponReload, EventHookMode_Post);
		
		g_FadeUserMsgId = GetUserMessageId("Fade");
		
		ToggleBunnyhop(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		if (!countdown)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient))
				{
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				}
			}
			
			if (g_hCountdownTimer != INVALID_HANDLE) {
				KillTimer(g_hCountdownTimer);
			}
			g_hCountdownTimer = INVALID_HANDLE;
			
			int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
			if (iUpgradeIndex != -1) {
				JB_ToggleGangUpgrade(iUpgradeIndex, true);
			}
			
			UnhookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
			UnhookEvent("weapon_reload", Event_WeaponReload, EventHookMode_Post);
			
			g_FadeUserMsgId = INVALID_MESSAGE_ID;
			
			delete g_arInfecteds;
			
			ToggleBunnyhop(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	float fFlashDuration = GetEntPropFloat(client, Prop_Send, "m_flFlashDuration");
	
	int iColor[4];
	iColor[0] = GetRandomInt(1, 255);
	iColor[1] = GetRandomInt(1, 255);
	iColor[2] = GetRandomInt(1, 255);
	iColor[3] = 255;
	
	if (fFlashDuration <= 3.0)
	{
		iColor[3] = RoundToNearest((255.0 / 3.0) * fFlashDuration);
	}
	
	fFlashDuration -= 3.0;
	fFlashDuration *= 1000.0;
	fFlashDuration /= 2.0;
	fFlashDuration = fFlashDuration < 0.0 ? 0.0:fFlashDuration;
	
	SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 0.0);
	
	SetClientScreenColor(client, 1500, RoundToNearest(fFlashDuration), FFADE_IN | FFADE_PURGE, iColor);
	
	return Plugin_Handled;
}

void Event_WeaponReload(Event event, const char[] name, bool dontBroadcast)
{
	int primary = GetPlayerWeaponSlot(GetClientOfUserId(event.GetInt("userid")), CS_SLOT_PRIMARY);
	if (primary != -1)
	{
		SetEntProp(primary, Prop_Send, "m_iClip1", 10);
	}
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (!(1 <= attacker <= MaxClients))
	{
		return Plugin_Handled;
	}
	
	int iInfectedIndex = g_arInfecteds.FindValue(GetClientSerial(attacker));
	if (iInfectedIndex != -1 && !IsClientInfected(victim))
	{
		// Set varribles data
		g_arInfecteds.Set(iInfectedIndex, GetClientSerial(victim));
		g_iInfectorIndex[victim] = attacker;
		
		// Set infected effects
		SetEntityRenderMode(victim, RENDER_TRANSALPHA);
		SetEntityRenderColor(victim, GetRandomInt(1, 255), GetRandomInt(1, 255), GetRandomInt(1, 255), 255);
		
		// Remove infected effects
		SetEntityRenderMode(attacker, RENDER_NORMAL);
		SetEntityRenderColor(attacker, 255, 255, 255, 255);
		
		// Notify players
		PrintToChatAll("%s \x04%N\x01 has infected \x02%N\x01! \x0B[%.1f]\x01", PREFIX, attacker, victim, g_fTimer);
	}
	
	return Plugin_Handled;
}

public void Hook_OnSpawnPost(int entity)
{
	if (g_iBeamSprite > -1)
	{
		TE_SetupBeamFollow(entity, g_iBeamSprite, 0, 0.7, 1.0, 1.0, 1, { 0, 100, 200, 255 } );
		TE_SendToAll();
	}
}

public void Hook_OnStartTouch(int entity, int other)
{
	float fPosition[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fPosition);
	AcceptEntityInput(entity, "Kill");
	
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		TE_SetupBeamRingPoint(fPosition, 10.0, 150.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 1.5, 30.0, 0.0, { 0, 100, 200, 255 }, 10, 0);
		TE_SendToAll();
		
		TE_SetupBeamRingPoint(fPosition, 10.0, 300.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 1.25, 30.0, 0.0, { 0, 100, 200, 255 }, 10, 0);
		TE_SendToAll();
		
		TE_SetupBeamRingPoint(fPosition, 10.0, 450.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 1.0, 30.0, 0.0, { 0, 100, 200, 255 }, 10, 0);
		TE_SendToAll();
	}
	
	EmitAmbientSound(FREEZE_SOUND, fPosition, other, SNDLEVEL_RAIDSIREN);
	
	float fClientPos[3];
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient))
		{
			GetClientAbsOrigin(iCurrentClient, fClientPos);
			
			if (GetVectorDistance(fPosition, fClientPos) <= 200.0)
			{
				SetClientScreenColor(iCurrentClient, 1000, 750, FFADE_IN, { 0, 100, 200, 150 } );
				
				SetEntPropFloat(iCurrentClient, Prop_Data, "m_flLaggedMovementValue", 0.0);
				EmitAmbientSound(FREEZE_SOUND, fPosition, iCurrentClient, SNDLEVEL_RAIDSIREN);
				SetEntityRenderColor(iCurrentClient, 58, 70, 240, 255);
				
				CreateTimer(2.0, Timer_UnFreeze, GetClientSerial(iCurrentClient));
				
			}
		}
	}
}

//================================[ Timers ]================================//

public Action Timer_InfectedsCountdown(Handle hTimer)
{
	if (g_fTimer <= 0.1)
	{
		if (GetOnlineTeamCount(CS_TEAM_T) == 1)
		{
			g_hCountdownTimer = INVALID_HANDLE;
			return Plugin_Stop;
		}
		
		for (int iCurrentIndex = 0, iCurrentInfected; iCurrentIndex < g_arInfecteds.Length; iCurrentIndex++)
		{
			iCurrentInfected = GetClientFromSerial(g_arInfecteds.Get(iCurrentIndex));
			
			if (iCurrentInfected && IsClientInGame(iCurrentInfected) && IsPlayerAlive(iCurrentInfected)) {
				SetEntityRenderMode(iCurrentInfected, RENDER_NORMAL);
				SetEntityRenderColor(iCurrentInfected, 255, 255, 255, 255);
				
				if (g_iInfectorIndex[iCurrentInfected] != -1 && IsClientInGame(g_iInfectorIndex[iCurrentInfected])) {
					// Kill the infected
					SDKHooks_TakeDamage(iCurrentInfected, g_iInfectorIndex[iCurrentInfected], g_iInfectorIndex[iCurrentInfected], float(GetClientHealth(iCurrentInfected)), DMG_POISON);
					
					// Notify players
					PrintToChatAll("%s \x02%N\x01 has died due to the infection, he was infected by \x04%N\x01.", PREFIX, iCurrentInfected, g_iInfectorIndex[iCurrentInfected]);
				}
				else {
					// Kill the infected
					ForcePlayerSuicide(iCurrentInfected);
					
					// Notify players
					PrintToChatAll("%s \x02%N\x01 has died due to the infection, and he was the \x07source\x01 of the infection.", PREFIX, iCurrentInfected);
				}
			}
		}
		
		g_arInfecteds.Clear();
		
		InitInfecteds();
		g_fTimer = COUNTDOWN_DEATH;
		return Plugin_Continue;
	}
	
	int iMessageSize = MAX_NAME_LENGTH * 5;
	char[] szMessage = new char[iMessageSize];
	
	Format(szMessage, iMessageSize, "HitAndRun Timer: %.1fs", g_fTimer);
	
	for (int iCurrentIndex = 0, iCurrentInfected; iCurrentIndex < g_arInfecteds.Length; iCurrentIndex++)
	{
		iCurrentInfected = GetClientFromSerial(g_arInfecteds.Get(iCurrentIndex));
		
		if (iCurrentInfected && IsClientInGame(iCurrentInfected) && IsPlayerAlive(iCurrentInfected)) {
			Format(szMessage, iMessageSize, "%s\nInfected: <font color='#26FE04'>%N</font>", szMessage, iCurrentInfected);
		} else {
			Format(szMessage, iMessageSize, "%s\nInfected: <font color='#CF0903'>Infected has left or died!</font>", szMessage);
		}
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			if (IsClientInfected(iCurrentClient)) {
				Format(szMessage, iMessageSize, "%s%s", szMessage, INFECTED_HIGHLIGHT);
			}
			
			PrintCenterText(iCurrentClient, szMessage);
			ReplaceString(szMessage, iMessageSize, INFECTED_HIGHLIGHT, "");
		}
	}
	
	g_fTimer -= 0.1;
	return Plugin_Continue;
}

public Action Timer_UnFreeze(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	if (!client || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
	
	float fPosition[3];
	GetClientAbsOrigin(client, fPosition);
	
	EmitAmbientSound(FREEZE_SOUND, fPosition, client, SNDLEVEL_RAIDSIREN);
	
	SetEntityRenderColor(client);
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void InitInfecteds()
{
	for (int iCurrentInfected = 0, iCurrentClient = -1; iCurrentInfected < GetInfectedsNumber(); iCurrentInfected++)
	{
		iCurrentClient = GetRandomAliveClient();
		
		if (iCurrentClient != -1 && !IsClientInfected(iCurrentClient))
		{
			g_arInfecteds.Push(GetClientSerial(iCurrentClient));
			SetEntityRenderMode(iCurrentClient, RENDER_TRANSALPHA);
			SetEntityRenderColor(iCurrentClient, GetRandomInt(1, 255), GetRandomInt(1, 255), GetRandomInt(1, 255), 255);
			
			g_iInfectorIndex[iCurrentClient] = SERVER_INFECTOR_INDEX;
		}
	}
}

void SetClientScreenColor(int client, int duration, int holdtime, int flags, int color[4])
{
	int clients[1];
	clients[0] = client;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, clients, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWriteShort(message, duration);
		BfWriteShort(message, holdtime);
		BfWriteShort(message, flags);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}
	
	EndMessage();
}

bool IsClientInfected(int client)
{
	return g_arInfecteds.FindValue(GetClientSerial(client)) != -1;
}

int GetRandomAliveClient()
{
	int iCounter = 0;
	int[] iClients = new int[MaxClients];
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; ++iCurrentClient)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient)) {
			iClients[iCounter++] = iCurrentClient;
		}
	}
	
	if (iCounter) {
		return iClients[GetRandomInt(0, iCounter - 1)];
	}
	
	return -1;
}

int GetInfectedsNumber()
{
	return (GetOnlineTeamCount(CS_TEAM_T) / PLAYERS_PER_INFECTED) + 1;
}

//================================================================//