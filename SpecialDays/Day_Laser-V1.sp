#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <fpvm_interface>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define DAY_NAME "Laser Day"
#define DAY_WEAPON "weapon_m4a1"
#define DAY_HEALTH 1250

#define GUN_HEAT_BULLETS 18
#define GUN_HEAT_COOLDOWN 2.1
#define ABILITY_COOLDOWN 10.0

#define LASER_GUN_VIEW_MODEL "models/weapons/eminem/ethereal/v_ethereal.mdl"
#define LASER_GUN_WORLD_MODEL "models/weapons/eminem/ethereal/w_ethereal.mdl"
#define LASER_GUN_SHOOT_SOUND "weapons/eminem/ethereal/ethereal_shoot1.wav"

#define GUN_HEAT_SOUND "items/healthshot_success_01.wav"

//====================//

enum struct Client
{
	float NextAbilityAttack;
	int BulletsCounter;
	int OldButtons;
	
	Handle BulletsResetTimer;
	
	void Reset() {
		this.DeleteTimer();
		
		this.NextAbilityAttack = 0.0;
		this.BulletsCounter = 0;
		this.OldButtons = 0;
	}
	
	void DeleteTimer() {
		if (this.BulletsResetTimer != INVALID_HANDLE)
		{
			KillTimer(this.BulletsResetTimer);
			this.BulletsResetTimer = INVALID_HANDLE;
		}
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ConVar g_cvInfiniteAmmo;

bool g_IsDayActivated;

int g_DayIndex = -1;

int g_iLaserGunViewId = -1;
int g_iLaserGunWorldId = -1;

int g_iShotSprite = -1;
int g_iBombSprite = -1;
int g_iExplosionSprite = -1;

int g_flSimulationTime;
int g_flProgressBarStartTime;
int g_iProgressBarDuration;
int g_iBlockingUseActionInProgress;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Initialize the required progress bar network offsets
	g_flSimulationTime = FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	g_flProgressBarStartTime = FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	g_iBlockingUseActionInProgress = FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
	
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
}

public void OnPluginEnd()
{
	// If the special day is running, and the plugin has come to his end, stop the special day
	if (g_IsDayActivated)
	{
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_DayIndex = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	g_ClientsData[client].Reset();
	ResetProgressBar(client);
	
	DisarmPlayer(client);
	SetEntityHealth(client, DAY_HEALTH);
	GivePlayerItem(client, DAY_WEAPON);
	
	FPVMI_AddViewModelToClient(client, DAY_WEAPON, g_iLaserGunViewId);
	FPVMI_AddWorldModelToClient(client, DAY_WEAPON, g_iLaserGunWorldId);
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	// Add the special day event hooks
	HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
	AddTempEntHook("Shotgun Shot", Hook_SilenceShot);
	
	g_cvInfiniteAmmo.SetInt(2);
	
	ToggleBunnyhop(false);
	ToggleRunesState(false);
	
	g_IsDayActivated = true;
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	// Make sure the special day is running, and the given special day index is the plugin's index
	if (!g_IsDayActivated || g_DayIndex != specialDayId)
	{
		return;
	}
	
	if (!countdown)
	{
		// Loop through all the clients, and remove their custom weapon models
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				ResetProgressBar(current_client);
				
				FPVMI_RemoveViewModelToClient(current_client, DAY_WEAPON);
				FPVMI_RemoveWorldModelToClient(current_client, DAY_WEAPON);
			}
		}
		
		// Remove the special day event hooks
		UnhookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
		
		RemoveTempEntHook("Shotgun Shot", Hook_SilenceShot);
		
		ToggleBunnyhop(true);
		ToggleRunesState(true);
		
		g_cvInfiniteAmmo.SetInt(0);
	}
	
	g_IsDayActivated = false;
}

public void OnMapStart()
{
	PrecacheSound(GUN_HEAT_SOUND);
	
	g_iLaserGunViewId = PrecacheModel(LASER_GUN_VIEW_MODEL);
	g_iLaserGunWorldId = PrecacheModel(LASER_GUN_WORLD_MODEL);
	
	g_iShotSprite = PrecacheModel("materials/supporter_tracers/phys_beam.vmt");
	g_iBombSprite = PrecacheModel("materials/supporter_tracers/squiggly_beam.vmt");
	
	g_iExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// Make sure the special day is running, and the client is alive
	if (!g_IsDayActivated || !IsPlayerAlive(client) || !buttons)
	{
		return Plugin_Continue;
	}
	
	// Initialize the client's active weapon, and make sure it's valid
	int active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	// The client's active weapon index is invalid
	if (active_weapon == -1 || !IsValidEntity(active_weapon))
	{
		return Plugin_Continue;
	}
	
	char weapon_name[32];
	
	// The client's active weapon name is not available, or the weapon name isn't matching the special day weapon
	if (!GetEntityClassname(active_weapon, weapon_name, sizeof(weapon_name)) || !StrEqual(weapon_name, DAY_WEAPON))
	{
		return Plugin_Continue;
	}
	
	// The client isn't pressing the ability key, or the next ability attack isn't ready yet
	if (!(g_ClientsData[client].OldButtons & IN_ATTACK2) && (buttons & IN_ATTACK2) && g_ClientsData[client].NextAbilityAttack <= GetGameTime())
	{
		// Apply the ability attack cooldown
		g_ClientsData[client].NextAbilityAttack = GetGameTime() + ABILITY_COOLDOWN;
		
		// Dispaly the progress bar panel, and create the reset timer
		SetProgressBarFloat(client, ABILITY_COOLDOWN);
		CreateTimer(ABILITY_COOLDOWN, Timer_ResetProgressBar, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		
		// Initialize the client eye position and angles, for the trace ray filter to be function
		float client_eye_pos[3], client_eye_angles[3], trace_hit_pos[3];
		
		GetClientEyePosition(client, client_eye_pos);
		GetClientEyeAngles(client, client_eye_angles);
		
		TR_TraceRayFilter(client_eye_pos, client_eye_angles, MASK_ALL, RayType_Infinite, Filter_DontHitPlayers, client);
		
		if (TR_DidHit())
		{
			TR_GetEndPosition(trace_hit_pos);
		}
		
		// Perform the ability side effects
		CS_CreateExplosion(client, 275.0, 250.0, trace_hit_pos);
		PerformScreenShake(client, 10000.0 / GetVectorDistance(client_eye_pos, trace_hit_pos));
		
		// Setup the tracer beam points, etc... And send to to everyone
		TE_SetupBeamPoints(client_eye_pos, trace_hit_pos, g_iBombSprite, 0, 0, 0, 0.4, 1.0, 1.0, 1, 0.0, { 0, 255, 0, 255 }, 0);
		TE_SendToAll();
	}
	
	g_ClientsData[client].OldButtons = buttons;
	
	return Plugin_Continue;
}

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	// Increase the bullets counter, because the client just fired a bullet
	g_ClientsData[client].BulletsCounter++;
	
	// Check for the weapon bullets cooldown
	if (g_ClientsData[client].BulletsCounter >= GUN_HEAT_BULLETS)
	{
		// Apply the cooldown
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + GUN_HEAT_COOLDOWN);
		
		// Reset the client's cooldown variables
		g_ClientsData[client].BulletsCounter = 0;
		g_ClientsData[client].DeleteTimer();
		
		// Play the cooldown sound effetct with low pitch
		EmitSoundToClient(client, GUN_HEAT_SOUND, _, _, _, _, _, 80);
		return;
	}
	
	// Delete the old bullets reset timer if there is one at all, and recreate the reset bullets timer
	g_ClientsData[client].DeleteTimer();
	g_ClientsData[client].BulletsResetTimer = CreateTimer(0.3, Timer_ResetBulletsCounter, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	
	// Initialize the client's eye position, and the bullet hit position
	float client_pos[3], bullet_pos[3];
	GetClientEyePosition(client, client_pos);
	client_pos[2] -= 5.0;
	
	bullet_pos[0] = event.GetFloat("x");
	bullet_pos[1] = event.GetFloat("y");
	bullet_pos[2] = event.GetFloat("z");
	
	// Setup the trace line colors - 
	// The closer the client is to cooldown, the redder the color of the tracer line will be,
	// The farther the client is from the cooldown, the bluer the color of the tracer line will be.
	int tracer_colors[4];
	tracer_colors[0] = KeepInRange(RoundToFloor(g_ClientsData[client].BulletsCounter * 21.25)); // Red
	tracer_colors[1] = 0; // Green
	tracer_colors[2] = KeepInRange(255 - RoundToFloor(g_ClientsData[client].BulletsCounter * 21.25)); // Blue
	tracer_colors[3] = 255; // Alpha
	
	// Setup the tracer beam points, and send it to everyone
	TE_SetupBeamPoints(client_pos, bullet_pos, g_iShotSprite, 0, 0, 0, 2.0, 1.0, 5.0, 1, 0.0, tracer_colors, 0);
	TE_SendToAll();
}

public bool Filter_DontHitPlayers(int entity, int contentsMask, any data)
{
	return (entity != data);
}

public Action Hook_SilenceShot(const char[] teName, const int[] players, int numClients, float delay)
{
	int client = TE_ReadNum("m_iPlayer") + 1;
	
	// Make sure the client index is in-game and valid
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	char weapon_name[32];
	
	// Initialzie the client's weapon index and name, and validate it by the special day weapon define
	int active_weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	
	if (active_weapon == -1 || !IsValidEntity(active_weapon) || !GetEntityClassname(active_weapon, weapon_name, sizeof(weapon_name)) || !StrEqual(weapon_name, DAY_WEAPON))
	{
		return Plugin_Continue;
	}
	
	// Emit the weapon fire sound effect
	EmitSoundToAll(LASER_GUN_SHOOT_SOUND, client, .volume = 0.2);
	
	// Block the original sound
	return Plugin_Stop;
}

//================================[ Timers ]================================//

public Action Timer_ResetBulletsCounter(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client)
	{
		g_ClientsData[client].BulletsCounter = 0;
	}
	
	g_ClientsData[client].BulletsResetTimer = INVALID_HANDLE;
}

public Action Timer_ResetProgressBar(Handle timer, int serial)
{
	// Initialize the client index by the given serial, and validate it
	int client = GetClientFromSerial(serial);
	
	if (client)
	{
		// Reset the progress bar panel
		ResetProgressBar(client);
	}
}

//================================[ Functions ]================================//

void CS_CreateExplosion(int attacker, float damage, float radius, float pos[3])
{
	// Setup and send the explosion sprite effect
	TE_SetupExplosion(pos, g_iExplosionSprite, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	// Play the explosion sound effect to everyone from the explode position
	EmitSoundToAll("weapons/hegrenade/explode4.wav", .volume = 1.0, .origin = pos);
	
	float current_position[3], current_distance;
	
	for (int current_victim = 1; current_victim <= MaxClients; current_victim++)
	{
		if (IsClientInGame(current_victim) && IsPlayerAlive(current_victim))
		{
			GetClientAbsOrigin(current_victim, current_position);
			
			if (!IsPathClear(pos, current_position, current_victim))
			{
				continue;
			}
			
			current_distance = GetVectorDistance(pos, current_position);
			
			if (current_distance <= radius)
			{
				JB_DealDamage(current_victim, attacker, Sine(((radius - current_distance) / radius) * (3.14159 / 2)) * damage, DMG_BLAST);
			}
		}
	}
}

bool IsPathClear(float start_pos[3], float end_pos[3], int victimIndex)
{
	float client_angles[3];
	SubtractVectors(end_pos, start_pos, client_angles);
	GetVectorAngles(client_angles, client_angles);
	
	TR_TraceRayFilter(start_pos, client_angles, 33570827, RayType_Infinite, Filter_HitTargetOnly, victimIndex);
	
	return victimIndex == TR_GetEntityIndex();
}

public bool Filter_HitTargetOnly(int entity, int contentsMask, any data)
{
	return data == entity;
}

void SetProgressBarFloat(int client, float fProgressTime)
{
	int iProgressTime = RoundToCeil(fProgressTime);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + fProgressTime, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - fProgressTime), true);
	SetEntData(client, g_iBlockingUseActionInProgress, 0, 4, true);
}

void ResetProgressBar(int client)
{
	SetEntDataFloat(client, g_flProgressBarStartTime, 0.0, true);
	SetEntData(client, g_iProgressBarDuration, 0, 1, true);
}

void PerformScreenShake(int client, float amplitude = 1.0, float frequency = 255.0, float duration = 1.0)
{
	Handle message = StartMessageOne("Shake", client);
	
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("command", 0);
		pb.SetFloat("local_amplitude", amplitude);
		pb.SetFloat("frequency", frequency);
		pb.SetFloat("duration", duration);
	}
	else
	{
		PbSetInt(message, "command", 0);
		PbSetFloat(message, "local_amplitude", amplitude);
		PbSetFloat(message, "frequency", frequency);
		PbSetFloat(message, "duration", duration);
	}
	
	EndMessage();
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

int KeepInRange(int value, int min = 0, int max = 255)
{
	return value < min ? min : value > max ? max : value;
}

//================================================================//