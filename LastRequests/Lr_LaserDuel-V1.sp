#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <fpvm_interface>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define LR_NAME "Laser Duel"
#define LR_WEAPON "weapon_m4a1"

#define DEFAULT_HEALTH 1250
#define MIN_HEALTH 1000
#define MAX_HEALTH 1500

#define GUN_HEAT_BULLETS 18
#define GUN_HEAT_COOLDOWN 2.1
#define ABILITY_COOLDOWN 10.0

#define LASER_GUN_VIEW_MODEL "models/weapons/eminem/ethereal/v_ethereal.mdl"
#define LASER_GUN_WORLD_MODEL "models/weapons/eminem/ethereal/w_ethereal.mdl"
#define LASER_GUN_SHOOT_SOUND "weapons/eminem/ethereal/ethereal_shoot1.wav"

#define GUN_HEAT_SOUND "items/healthshot_success_01.wav"

//====================//

enum struct Setup
{
	bool bAllowJump;
	bool bAllowDuck;
	bool bHeadshot;
	int iHealth;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bAllowJump = true;
		this.bAllowDuck = true;
		this.bHeadshot = false;
		this.iHealth = DEFAULT_HEALTH;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

enum struct Client
{
	float NextAbilityAttack;
	int BulletsCounter;
	int OldButtons;
	
	bool IsWrite;
	
	Handle BulletsResetTimer;
	
	void Reset() {
		this.NextAbilityAttack = 0.0;
		this.BulletsCounter = 0;
		this.OldButtons = 0;
		this.IsWrite = false;
		
		this.DeleteTimer();
	}
	
	void DeleteTimer() {
		if (this.BulletsResetTimer != INVALID_HANDLE)
		{
			KillTimer(this.BulletsResetTimer);
			this.BulletsResetTimer = INVALID_HANDLE;
		}
	}
}

Setup g_esSetupData;
Client g_ClientsData[MAXPLAYERS + 1];

ConVar g_cvInfiniteAmmo;

bool g_IsLrActivated;

int g_LrIndex = -1;

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
	name = "[CS:GO] JailBreak - "...LR_NAME..." Lr", 
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
	// If the last request is running, and the plugin has come to his end, abort the last request game
	if (g_IsLrActivated)
	{
		JB_StopLr();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_LrSystem"))
	{
		g_LrIndex = JB_AddLr(LR_NAME, false, false, true, true);
	}
}

public void JB_OnLrSelected(int client, int lrId)
{
	// Make sure the given last request index, is the plugin's index
	if (g_LrIndex != lrId)
	{
		return;
	}
	
	g_esSetupData.Reset();
	g_esSetupData.iPrisoner = client;
	ShowLrSetupMenu(client);
}

public void JB_OnRandomLrSelected(int client, int lrId)
{
	// Make sure the given last request index, is the plugin's index
	if (g_LrIndex != lrId)
	{
		return;
	}
	
	g_esSetupData.Reset();
	g_esSetupData.iPrisoner = client;
	InitRandomSettings();
	StartLr();
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (!g_IsLrActivated || g_LrIndex != currentLr)
	{
		return;
	}
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			ResetProgressBar(current_client);
			
			SDKUnhook(current_client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			
			FPVMI_RemoveViewModelToClient(current_client, LR_WEAPON);
			FPVMI_RemoveWorldModelToClient(current_client, LR_WEAPON);
		}
	}
	
	int iPrimary = GetPlayerWeaponSlot(g_esSetupData.iPrisoner, CS_SLOT_PRIMARY);
	if (iPrimary != -1)
	{
		RemovePlayerItem(g_esSetupData.iPrisoner, iPrimary);
	}
	
	if ((iPrimary = GetPlayerWeaponSlot(g_esSetupData.iAgainst, CS_SLOT_PRIMARY)) != -1)
	{
		RemovePlayerItem(g_esSetupData.iAgainst, iPrimary);
	}
	
	UnhookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
	RemoveTempEntHook("Shotgun Shot", Hook_SilenceShot);
	
	g_cvInfiniteAmmo.SetInt(0);
	
	g_IsLrActivated = false;
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	// Make sure the given last request index, is the plugin's index
	if (g_LrIndex != currentLr)
	{
		return;
	}
	
	char szMessage[256];
	Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Health: %d HP\n• Headshot: %s\n• Jump: %s\n• Duck: %s", 
		LR_NAME, 
		g_esSetupData.iPrisoner, 
		GetClientHealth(g_esSetupData.iPrisoner), 
		g_esSetupData.iAgainst, 
		GetClientHealth(g_esSetupData.iAgainst), 
		g_esSetupData.iHealth, 
		g_esSetupData.bHeadshot ? "Enabled":"Disabled", 
		g_esSetupData.bAllowJump ? "Enabled":"Disabled", 
		g_esSetupData.bAllowDuck ? "Enabled":"Disabled"
		);
	panel.DrawText(szMessage);
}

public void OnClientPostAdminCheck(int client)
{
	g_ClientsData[client].Reset();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (!g_ClientsData[client].IsWrite)
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL))
	{
		PrintToChat(client, "%s Operation has \x07aborted\x01.", PREFIX);
		ShowLrSetupMenu(client);
		g_ClientsData[client].IsWrite = false;
		return Plugin_Handled;
	}
	
	int iHealthAmount = StringToInt(szArgs);
	if (MIN_HEALTH <= iHealthAmount <= MAX_HEALTH)
	{
		g_esSetupData.iHealth = iHealthAmount;
	}
	else
	{
		PrintToChat(client, "%s You have specifed an invalid \x04health\x01 amount! [\x02%s\x01]", PREFIX, szArgs);
	}
	
	ShowLrSetupMenu(client);
	g_ClientsData[client].IsWrite = false;
	return Plugin_Handled;
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

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client != g_esSetupData.iPrisoner && client != g_esSetupData.iAgainst)
	{
		return;
	}
	
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (!g_IsLrActivated || (client != g_esSetupData.iPrisoner && client != g_esSetupData.iAgainst))
	{
		return Plugin_Continue;
	}
	
	bool bPrees = false;
	if (!g_esSetupData.bAllowJump && (buttons & IN_JUMP)) {
		buttons &= ~IN_JUMP;
		bPrees = true;
	}
	if (!g_esSetupData.bAllowDuck && (buttons & IN_DUCK)) {
		buttons &= ~IN_DUCK;
		bPrees = true;
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
	if (!GetEntityClassname(active_weapon, weapon_name, sizeof(weapon_name)) || !StrEqual(weapon_name, LR_WEAPON))
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
		CS_CreateExplosion(client, active_weapon, 275.0, 250.0, trace_hit_pos);
		PerformScreenShake(client, 10000.0 / GetVectorDistance(client_eye_pos, trace_hit_pos));
		
		// Setup the tracer beam points, etc... And send to to everyone
		TE_SetupBeamPoints(client_eye_pos, trace_hit_pos, g_iBombSprite, 0, 0, 0, 0.4, 1.0, 1.0, 1, 0.0, { 0, 255, 0, 255 }, 0);
		TE_SendToAll();
	}
	
	g_ClientsData[client].OldButtons = buttons;
	
	if (bPrees) {
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
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
	
	if (active_weapon == -1 || !IsValidEntity(active_weapon) || !GetEntityClassname(active_weapon, weapon_name, sizeof(weapon_name)) || !StrEqual(weapon_name, LR_WEAPON))
	{
		return Plugin_Continue;
	}
	
	// Emit the weapon fire sound effect
	EmitSoundToAll(LASER_GUN_SHOOT_SOUND, client, .volume = 0.2);
	
	// Block the original sound
	return Plugin_Stop;
}

public bool Filter_DontHitPlayers(int entity, int mask, int data)
{
	return (entity != data);
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((client == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (client != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner))
	{
		return Plugin_Handled;
	}
	
	if (g_esSetupData.bHeadshot && !(damagetype & DMG_BLAST))
	{
		return damagetype & CS_DMG_HEADSHOT ? Plugin_Continue : Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//================================[ Menus ]================================//

void ShowLrSetupMenu(int client)
{
	char szItem[128];
	Menu menu = new Menu(Handler_LrSetup);
	menu.SetTitle("%s Last Request - %s Setup\n ", PREFIX_MENU, LR_NAME);
	
	menu.AddItem("", "Start Game");
	
	if (g_esSetupData.iAgainst)
	{
		GetClientName(g_esSetupData.iAgainst, szItem, sizeof(szItem));
	}
	
	Format(szItem, sizeof(szItem), "Enemy: %s", !g_esSetupData.iAgainst ? RANDOM_GUARD_STRING:szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Health: (%d/%d)", g_esSetupData.iHealth, MAX_HEALTH);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Headshot: %s", g_esSetupData.bHeadshot ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Jump: %s", g_esSetupData.bAllowJump ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Duck: %s", g_esSetupData.bAllowDuck ? "ON":"OFF");
	menu.AddItem("", szItem);
	
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
		
		switch (itemNum)
		{
			case 0:
			{
				StartLr();
			}
			case 1:
			{
				GetNextGuard();
				ShowLrSetupMenu(client);
			}
			case 2:
			{
				g_ClientsData[client].IsWrite = true;
				PrintToChat(client, "%s Type your desired \x04health\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 3:
			{
				g_esSetupData.bHeadshot = !g_esSetupData.bHeadshot;
				ShowLrSetupMenu(client);
			}
			case 4:
			{
				g_esSetupData.bAllowJump = !g_esSetupData.bAllowJump;
				ShowLrSetupMenu(client);
			}
			case 5:
			{
				g_esSetupData.bAllowDuck = !g_esSetupData.bAllowDuck;
				ShowLrSetupMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		g_esSetupData.Reset();
		JB_ShowLrMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
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

void StartLr()
{
	if (!g_esSetupData.iAgainst)
	{
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && !IsFakeClient(current_client))
		{
			SDKHook(current_client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
	AddTempEntHook("Shotgun Shot", Hook_SilenceShot);
	
	g_cvInfiniteAmmo.SetInt(2);
	
	g_IsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client))
	{
		return;
	}
	
	g_ClientsData[client].Reset();
	
	DisarmPlayer(client);
	SetEntityHealth(client, g_esSetupData.iHealth);
	EquipPlayerWeapon(client, GivePlayerItem(client, LR_WEAPON));
	
	FPVMI_AddViewModelToClient(client, LR_WEAPON, g_iLaserGunViewId);
	FPVMI_AddWorldModelToClient(client, LR_WEAPON, g_iLaserGunWorldId);
}

void InitRandomSettings()
{
	g_esSetupData.iAgainst = 0;
	g_esSetupData.iHealth = RoundToDivider(GetRandomInt(MIN_HEALTH, MAX_HEALTH), 50);
	g_esSetupData.bHeadshot = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowJump = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowDuck = GetRandomInt(0, 1) == 1;
}

void GetNextGuard()
{
	bool bFound;
	
	while (!bFound)
	{
		g_esSetupData.iAgainst++;
		if (g_esSetupData.iAgainst > MaxClients) {
			bFound = true;
			g_esSetupData.iAgainst = 0;
		}
		else if (IsClientInGame(g_esSetupData.iAgainst) && IsPlayerAlive(g_esSetupData.iAgainst) && JB_GetClientGuardRank(g_esSetupData.iAgainst) != Guard_NotGuard) {
			bFound = true;
		}
	}
}

void CS_CreateExplosion(int attacker, int weapon, float damage, float radius, float vec[3])
{
	TE_SetupExplosion(vec, g_iExplosionSprite, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	EmitSoundToAll("weapons/hegrenade/explode4.wav", _, _, _, _, 1.0, _, _, vec);
	
	float fCurrentPos[3], fCurrentDis;
	for (int iCurrentVictim = 1; iCurrentVictim <= MaxClients; iCurrentVictim++)
	{
		if (IsClientInGame(iCurrentVictim) && IsPlayerAlive(iCurrentVictim) && (iCurrentVictim == g_esSetupData.iPrisoner || iCurrentVictim == g_esSetupData.iAgainst))
		{
			GetClientAbsOrigin(iCurrentVictim, fCurrentPos);
			
			if (!IsPathClear(vec, fCurrentPos, iCurrentVictim))
			{
				continue;
			}
			
			fCurrentDis = GetVectorDistance(vec, fCurrentPos);
			
			if (fCurrentDis <= radius)
			{
				float result = Sine(((radius - fCurrentDis) / radius) * (3.14159 / 2)) * damage;
				SDKHooks_TakeDamage(iCurrentVictim, attacker, attacker, result, DMG_BLAST, weapon, NULL_VECTOR, vec);
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

int RoundToDivider(int value, int divider)
{
	if (value % divider != 0 && value <= 5)
	{
		if (value % divider >= divider / 2 || value - value % divider == 0) {
			value += divider - value % divider;
		}
		else {
			value -= value % divider;
		}
	}
	return value;
}

int KeepInRange(int value, int min = 0, int max = 255)
{
	return value < min ? min : value > max ? max : value;
}

//================================================================//