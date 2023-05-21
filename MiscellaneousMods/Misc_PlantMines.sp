#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_LrSystem>
#include <JB_SpecialMods>

#define PLUGIN_AUTHOR "@f0rce & Tweaked By KoNLiG"

//==========[ Settings ]==========//

#define MINE_MODEL_PATH "models/weapons/w_c4_planted.mdl"
#define EXPLOSION_SOUND "weapons/hegrenade/explode3.wav"
#define INITIATE_SOUND "weapons/c4/c4_initiate.wav"
#define PLANT_SOUND "weapons/c4/c4_plant_quiet.wav"
#define TAP_SOUND "weapons/c4/key_press1.wav"
#define CLICK_SOUND "weapons/c4/c4_click.wav"

//====================//

GlobalForward g_fwdOnPlantMineDamage;

int g_iMine[MAXPLAYERS + 1]; // 2792
int g_LastButtons[MAXPLAYERS + 1]; // 3056
bool g_bIsPlanting[MAXPLAYERS + 1]; // 3320
Handle g_PlaceTimers[MAXPLAYERS + 1]; // 3584
int g_iTaps[MAXPLAYERS + 1]; // 3848
float g_fFirstTap[MAXPLAYERS + 1]; // 4112
float g_fLastExplode[MAXPLAYERS + 1]; // 4376

int g_iExplosionSprite;
int m_clrRender;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Mine Planter", 
	author = PLUGIN_AUTHOR, 
	description = "Place mines by pressing 'E'", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	m_clrRender = FindSendPropInfo("CBaseEntity", "m_clrRender");
	if (m_clrRender == -1)
	{
		SetFailState("Could not find \"m_clrRender\" offset");
	}
	
	// Event Hooks
	HookEvent("player_death", OnPlayerDeathPost, EventHookMode_Post);
	HookEvent("round_start", OnRoundStart, EventHookMode_Post);
}

public void OnMapStart()
{
	PrecacheSound(EXPLOSION_SOUND);
	PrecacheSound(INITIATE_SOUND);
	PrecacheSound(PLANT_SOUND);
	PrecacheSound(TAP_SOUND);
	PrecacheSound(CLICK_SOUND);
	g_iExplosionSprite = PrecacheModel("materials/sprites/zerogxplode.vmt");
	PrecacheModel(MINE_MODEL_PATH);
	PrecacheEffect("ParticleEffect");
	PrecacheParticleEffect("c4_timer_light");
}

public void OnClientPutInServer(int client)
{
	g_PlaceTimers[client] = INVALID_HANDLE;
	
	g_bIsPlanting[client] = false;
	g_fLastExplode[client] = GetGameTime();
	g_iTaps[client] = 0;
	g_iMine[client] = 0;
}

public void OnPlayerDeathPost(Event event, const char[] name, bool dontBroadcast)
{
	int victim_index = GetClientOfUserId(event.GetInt("userid"));
	
	if (g_iMine[victim_index] && IsValidEntity(g_iMine[victim_index]))
	{
		DetonateMine(g_iMine[victim_index]);
	}
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			if (g_PlaceTimers[current_client] != INVALID_HANDLE)
			{
				KillTimer(g_PlaceTimers[current_client]);
				g_PlaceTimers[current_client] = INVALID_HANDLE;
				
			}
			
			g_bIsPlanting[current_client] = false;
			g_fLastExplode[current_client] = GetGameTime();
			g_iTaps[current_client] = 0;
			g_iMine[current_client] = 0;
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_fwdOnPlantMineDamage = new GlobalForward("JB_OnPlantMineDamage", ET_Event, Param_Cell, Param_Cell, Param_FloatByRef);
	
	return APLRes_Success;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	static bool bMinesDeleted;
	
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning() || JB_IsLrRunning() || JB_IsLrPeriodRunning() || JB_GetCurrentSpecialMod() != -1)
	{
		if (!bMinesDeleted)
		{
			DeleteMines();
			bMinesDeleted = true;
		}
		
		return Plugin_Continue;
	}
	
	bMinesDeleted = false;
	
	if (GetClientTeam(client) != CS_TEAM_CT)
	{
		return Plugin_Continue;
	}
	
	float fGameTime = GetGameTime();
	
	if (g_fLastExplode[client] + 5.0 > fGameTime)
	{
		return Plugin_Continue;
	}
	
	if (g_iMine[client] != 0)
	{
		if (!IsValidEntity(g_iMine[client]))
		{
			g_iMine[client] = 0;
			g_LastButtons[client] = buttons;
			return Plugin_Continue;
		}
		
		if (g_iTaps[client] && g_fFirstTap[client] + 0.8 < fGameTime)
		{
			g_iTaps[client] = 0;
			PrintCenterText(client, "<font color='#57E964' size='21'><b>EXPLODING\n</font>Cancelled!");
		}
		
		if ((buttons & IN_USE) && !(g_LastButtons[client] & IN_USE))
		{
			if (!g_iTaps[client])
			{
				g_fFirstTap[client] = fGameTime;
			}
			
			g_iTaps[client]++;
			
			if (g_iTaps[client] == 3)
			{
				DetonateMine(g_iMine[client]);
				g_iTaps[client] = 0;
				g_iMine[client] = 0;
				PrintCenterText(client, "<font color='#57E964' size='25'><b>EXPLOSION\n<font color='#E54334'>DONE");
				return Plugin_Continue;
			}
			char var4[8];
			if (g_iTaps[client] >= 3)
			{
				var4 = "✔";
			}
			else
			{
				var4 = "✖";
			}
			char var5[8];
			if (g_iTaps[client] >= 2)
			{
				var5 = "✔";
			}
			else
			{
				var5 = "✖";
			}
			char var6[8];
			if (g_iTaps[client] >= 1)
			{
				var6 = "✔";
			}
			else
			{
				var6 = "✖";
			}
			
			PrintCenterText(client, "<font color='#57E964' size='22'><b>EXPLODING\n<font color='#168EF7' size='20'>%s %s %s <font color='#CCFFFF'>%i/3", var6, var5, var4, g_iTaps[client]);
			
			if (g_iTaps[client] != 1)
			{
				ClientCommand(client, "play %s", TAP_SOUND);
			}
		}
		
		g_LastButtons[client] = buttons;
		
		return Plugin_Continue;
	}
	
	if (buttons & IN_USE)
	{
		if (!IsPlayerAlive(client))
		{
			g_LastButtons[client] = buttons;
			return Plugin_Continue;
		}
		
		float fVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fVelocity);
		float fVelLength = GetVectorLength(fVelocity, false);
		if (!g_bIsPlanting[client])
		{
			
			if ((GetEntityFlags(client) & FL_ONGROUND) && fVelLength < 50.0)
			{
				StartPlacingProgress(client);
			}
		}
		else
		{
			if (!(GetEntityFlags(client) & FL_ONGROUND) || fVelLength > 50.0)
			{
				CancelPlant(client);
			}
		}
	}
	else
	{
		if (g_bIsPlanting[client])
		{
			CancelPlant(client);
		}
	}
	
	g_LastButtons[client] = buttons;
	return Plugin_Continue;
}

void StartPlacingProgress(int client)
{
	g_bIsPlanting[client] = true;
	DataPack dp;
	g_PlaceTimers[client] = CreateDataTimer(0.2, UpdatePlacingProgress, dp, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	dp.WriteCell(GetClientUserId(client));
	dp.WriteCell(1);
	UpdatePlacingProgress(g_PlaceTimers[client], dp);
}

public Action UpdatePlacingProgress(Handle timer, DataPack dp)
{
	dp.Reset();
	int client = GetClientOfUserId(dp.ReadCell());
	
	if (!client || !IsClientInGame(client) || !g_bIsPlanting[client])
	{
		g_PlaceTimers[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	DataPackPos position = dp.Position;
	int iProgress = dp.ReadCell();
	SetPackPosition(dp, position);
	WritePackCell(dp, iProgress + 1);
	
	if (iProgress == 1)
	{
		ClientCommand(client, "play %s", CLICK_SOUND);
	}
	
	if (iProgress == 21)
	{
		FinishPlacing(client);
		
		g_PlaceTimers[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	switch (iProgress)
	{
		case 1, 4, 5, 9, 15, 17, 19:
		{
			ClientCommand(client, "play %s", CLICK_SOUND);
		}
	}
	
	char szProgress[32];
	switch (iProgress)
	{
		case 1, 2:
		{
			Format(szProgress, sizeof(szProgress), "[ | - - - - - - - - - ]");
		}
		case 3, 4:
		{
			Format(szProgress, sizeof(szProgress), "[ | | - - - - - - - - ]");
		}
		case 5, 6:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | - - - - - - - ]");
		}
		case 7, 8:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | - - - - - - ]");
		}
		case 9, 10:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | - - - - - ]");
		}
		case 11, 12:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | | - - - - ]");
		}
		case 13, 14:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | | | - - - ]");
		}
		case 15, 16:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | | | | - - ]");
		}
		case 17, 18:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | | | | | - ]");
		}
		case 19, 20:
		{
			Format(szProgress, sizeof(szProgress), "[ | | | | | | | | | | ]");
		}
		default:
		{
			
		}
	}
	
	char var2[8];
	if (iProgress % 4 == 0)
	{
		StrCat(var2, sizeof(var2), ".");
	}
	else
	{
		if (iProgress % 4 == 1)
		{
			StrCat(var2, sizeof(var2), ".");
		}
		if (iProgress % 4 == 2)
		{
			StrCat(var2, sizeof(var2), ".");
		}
		StrCat(var2, sizeof(var2), ".");
	}
	
	PrintCenterText(client, "<font color='#57E964' size='22'><b>Placing a mine%s</b>\n<font color='#FFFFFF' size ='20'>Don't move!\n%s %d%%</font>", var2, szProgress, 100 * iProgress / 20);
	
	return Plugin_Continue;
}

void FinishPlacing(int client)
{
	g_bIsPlanting[client] = false;
	PrintCenterText(client, "<font color='#57E964' size='22'><b>Placed a mine!</b>\n<font color='#FFFFFF' size ='20'>Tap 'E' three times to explode!</font>");
	PlantMine(client);
}

void CancelPlant(int client)
{
	g_bIsPlanting[client] = false;
	PrintCenterText(client, "<font color='#57E964' size='21'><b>Placing cancelled\n</font>Cancelled!");
	
	if (g_PlaceTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_PlaceTimers[client]);
		g_PlaceTimers[client] = INVALID_HANDLE;
	}
}

void PlantMine(int client)
{
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	float fOrigin[3];
	GetClientAbsOrigin(client, fOrigin);
	int entity = CreateEntityByName("prop_physics_override");
	DispatchKeyValue(entity, "model", MINE_MODEL_PATH);
	DispatchKeyValue(entity, "targetname", "pmine");
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
	SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 2.5);
	TeleportEntity(entity, fOrigin, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	SetEntityMoveType(entity, MOVETYPE_NONE);
	CreateTimer(0.5, OnGrenadeThink, EntIndexToEntRef(entity));
	EmitAmbientSound(PLANT_SOUND, fOrigin, entity, 75, 0, 1.0, 100, 0.0);
	g_iMine[client] = entity;
	SDKHook(entity, SDKHook_StartTouch, OnMineTouch);
}

public Action OnGrenadeThink(Handle timer, any data)
{
	int entity = EntRefToEntIndex(data);
	if (entity == -1)
	{
		return Plugin_Stop;
	}
	
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", 0);
	if (owner == -1)
	{
		return Plugin_Stop;
	}
	
	float particleOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", particleOrigin, 0);
	particleOrigin[2] += 10.0;
	CreateParticle("c4_timer_light", particleOrigin, 0.1);
	CreateTimer(0.5, OnGrenadeThink, data, 0);
	return Plugin_Continue;
}

bool CreateParticle(char[] szParticle, float origin[3], float fKillAfter)
{
	int ent = CreateEntityByName("info_particle_system", -1);
	DispatchKeyValue(ent, "start_active", "0");
	DispatchKeyValue(ent, "effect_name", szParticle);
	DispatchSpawn(ent);
	TeleportEntity(ent, origin, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(ent);
	AcceptEntityInput(ent, "Start", -1, -1, 0);
	
	if (fKillAfter > 0.0)
	{
		CreateTimer(fKillAfter, KillParticle, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return true;
}

public Action KillParticle(Handle timer, any data)
{
	int ent = EntRefToEntIndex(data);
	if (IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill", -1, -1, 0);
	}
	
	return Plugin_Stop;
}

public Action OnMineTouch(int toucher, int touched)
{
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning() || JB_IsLrRunning() || JB_IsLrPeriodRunning() || JB_GetCurrentSpecialMod() != -1)
	{
		return Plugin_Continue;
	}
	
	if (1 <= toucher <= MaxClients)
	{
		if (!touched)
		{
			return Plugin_Continue;
		}
		
		DetonateMine(touched);
		return Plugin_Continue;
	}
	
	if (1 <= touched <= MaxClients)
	{
		if (IsClientInGame(touched) && IsPlayerAlive(touched) && GetClientTeam(touched) != 3)
		{
			DetonateMine(toucher);
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

void DetonateMine(int entity)
{
	SDKUnhook(entity, SDKHook_StartTouch, OnMineTouch);
	int attacker = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (1 <= attacker <= MaxClients)
	{
		g_fLastExplode[attacker] = GetGameTime();
		g_iMine[attacker] = 0;
	}
	
	float fOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fOrigin, 0);
	EmitAmbientSound(INITIATE_SOUND, fOrigin, entity, 75, 0, 0.5, 100, 0.0);
	CS_CreateExplosion(attacker, 144.0, 125.0, fOrigin);
	SetEntityRenderColor(entity, 0, 0, 0, 255);
	SetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity", -1, 0);
	CreateTimer(3.0, StartFadingOut, EntIndexToEntRef(entity), 0);
}

public Action StartFadingOut(Handle timer, any data)
{
	int ent = EntRefToEntIndex(data);
	
	if (ent == -1 || !IsValidEntity(ent))
	{
		return Plugin_Stop;
	}
	
	SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
	CreateTimer(0.01, EntityFadeOut, data, 1);
	return Plugin_Continue;
}

public Action EntityFadeOut(Handle timer, any data)
{
	int ent = EntRefToEntIndex(data);
	
	if (ent == -1 || !IsValidEntity(ent))
	{
		return Plugin_Stop;
	}
	int alpha = GetEntData(ent, m_clrRender + 3, 1);
	if (alpha - 10 <= 0)
	{
		RemoveEdict(ent);
		return Plugin_Stop;
	}
	SetEntData(ent, m_clrRender + 3, alpha - 10, 1, true);
	return Plugin_Continue;
}

void CS_CreateExplosion(int attacker, float damage, float radius, float pos[3])
{
	// Setup and send the explosion sprite effect
	TE_SetupExplosion(pos, g_iExplosionSprite, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	// Play the explosion sound effect to everyone from the explode position
	EmitSoundToAll("weapons/hegrenade/explode4.wav", SOUND_FROM_LOCAL_PLAYER, .volume = 1.0, .origin = pos);
	
	float current_position[3], current_distance;
	
	for (int current_victim = 1; current_victim <= MaxClients; current_victim++)
	{
		if (IsClientInGame(current_victim) && IsPlayerAlive(current_victim))
		{
			GetClientAbsOrigin(current_victim, current_position);
			
			if (IsPathClear(pos, current_position, current_victim))
			{
				current_distance = GetVectorDistance(pos, current_position);
				
				if (current_distance <= radius)
				{
					float modified_damage = Sine(((radius - current_distance) / radius) * (FLOAT_PI / 2)) * damage;
					
					Call_StartForward(g_fwdOnPlantMineDamage);
					Call_PushCell(attacker);
					Call_PushCell(current_victim);
					Call_PushFloatRef(modified_damage);
					
					Action fwd_return;
					
					int error = Call_Finish(fwd_return);
					
					// Check for forward failure
					if (error != SP_ERROR_NONE)
					{
						ThrowNativeError(error, "Global Forward Failed - Error: %d", error);
						return;
					}
					
					if (fwd_return >= Plugin_Handled)
					{
						return;
					}
					
					SDKHooks_TakeDamage(current_victim, attacker, attacker, modified_damage, DMG_BLAST, .bypassHooks = false);
				}
			}
		}
	}
}

bool IsPathClear(float start_pos[3], float end_pos[3], int victim)
{
	float client_angles[3];
	SubtractVectors(end_pos, start_pos, client_angles);
	GetVectorAngles(client_angles, client_angles);
	TR_TraceRayFilter(start_pos, client_angles, 33570827, RayType_Infinite, TraceRay_HitTargetOnly, victim);
	
	if (victim == TR_GetEntityIndex())
	{
		return true;
	}
	
	return false;
}

public bool TraceRay_HitTargetOnly(int entity, int contentsMask, any data)
{
	return data == entity;
}

int DeleteMines()
{
	int iMinesDeleted;
	int iMaxEnts = GetMaxEntities();
	char szTargetName[128];
	int owner;
	int entity = MaxClients + 1;
	while (entity < iMaxEnts)
	{
		if (IsValidEntity(entity))
		{
			GetEntPropString(entity, Prop_Data, "m_iName", szTargetName, 128, 0);
			if (StrEqual(szTargetName, "pmine", true))
			{
				owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", 0);
				if (1 <= owner <= MaxClients)
				{
					g_iMine[owner] = 0;
				}
				AcceptEntityInput(entity, "Kill", -1, -1, 0);
				iMinesDeleted++;
			}
		}
		entity++;
	}
	return iMinesDeleted;
}

void PrecacheParticleEffect(char[] sEffectName)
{
	static int table = -1;
	if (table == -1)
	{
		table = FindStringTable("ParticleEffectNames");
	}
	
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName, "", -1);
	LockStringTables(save);
}

void PrecacheEffect(char[] sEffectName)
{
	static int table = -1;
	if (table == -1)
	{
		table = FindStringTable("EffectDispatch");
	}
	
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

