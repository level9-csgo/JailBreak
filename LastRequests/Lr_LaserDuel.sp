#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <JB_GangsSystem>
#include <customweapons>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define LR_NAME "Laser Duel"
#define LR_WEAPON "weapon_m4a1"

#define DEFAULT_HEALTH 1250
#define MIN_HEALTH 1000
#define MAX_HEALTH 1500

#define ABILITY_COOLDOWN 10.0
#define ABILITY_BULLETS_COST 4

#define LASER_GUN_VIEW_MODEL "models/weapons/eminem/ethereal/v_ethereal.mdl"
#define LASER_GUN_WORLD_MODEL "models/weapons/eminem/ethereal/w_ethereal.mdl"
#define LASER_GUN_SHOOT_SOUND "weapons/eminem/ethereal/ethereal_shoot1.wav"

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

enum struct Player
{
	float NextAbilityAttack;
	
	bool IsWrite;
	
	int OldButtons;
	
	void Reset() {
		this.NextAbilityAttack = 0.0;
		this.IsWrite = false;
		this.OldButtons = 0;
	}
}

Setup g_SetupData;
Player g_Players[MAXPLAYERS + 1];

ConVar g_cvInfiniteAmmo;

bool g_IsLrActivated;

int g_LrIndex = -1;

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
	
	g_SetupData.Reset();
	g_SetupData.iPrisoner = client;
	ShowLrSetupMenu(client);
}

public void JB_OnRandomLrSelected(int client, int lrId)
{
	// Make sure the given last request index, is the plugin's index
	if (g_LrIndex != lrId)
	{
		return;
	}
	
	g_SetupData.Reset();
	g_SetupData.iPrisoner = client;
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
			
			if (IsPlayerAlive(current_client))
			{
				int weapon = GetPlayerWeaponSlot(current_client, CS_SLOT_PRIMARY);
				if (weapon != -1)
				{
					CustomWeapon custom_weapon = CustomWeapon(weapon);
					if (custom_weapon)
					{
						custom_weapon.SetModel(CustomWeaponModel_View, "");
						custom_weapon.SetModel(CustomWeaponModel_World, "");
						
						custom_weapon.SetShotSound("");
					}
				}
			}
		}
	}
	
	
	UnhookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
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
		g_SetupData.iPrisoner, 
		GetClientHealth(g_SetupData.iPrisoner), 
		g_SetupData.iAgainst, 
		GetClientHealth(g_SetupData.iAgainst), 
		g_SetupData.iHealth, 
		g_SetupData.bHeadshot ? "Enabled":"Disabled", 
		g_SetupData.bAllowJump ? "Enabled":"Disabled", 
		g_SetupData.bAllowDuck ? "Enabled":"Disabled"
		);
	panel.DrawText(szMessage);
}

public void OnClientPostAdminCheck(int client)
{
	g_Players[client].Reset();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (!g_Players[client].IsWrite)
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL))
	{
		PrintToChat(client, "%s Operation has \x07aborted\x01.", PREFIX);
		ShowLrSetupMenu(client);
		g_Players[client].IsWrite = false;
		return Plugin_Handled;
	}
	
	int iHealthAmount = StringToInt(szArgs);
	if (MIN_HEALTH <= iHealthAmount <= MAX_HEALTH)
	{
		g_SetupData.iHealth = iHealthAmount;
	}
	else
	{
		PrintToChat(client, "%s You have specifed an invalid \x04health\x01 amount! [\x02%s\x01]", PREFIX, szArgs);
	}
	
	ShowLrSetupMenu(client);
	g_Players[client].IsWrite = false;
	return Plugin_Handled;
}

public void OnMapStart()
{
	PrecacheModel(LASER_GUN_VIEW_MODEL);
	PrecacheModel(LASER_GUN_WORLD_MODEL);
	
	g_iShotSprite = PrecacheModel("materials/supporter_tracers/phys_beam.vmt");
	g_iBombSprite = PrecacheModel("materials/supporter_tracers/squiggly_beam.vmt");
	
	g_iExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (!g_IsLrActivated || (client != g_SetupData.iPrisoner && client != g_SetupData.iAgainst))
	{
		return Plugin_Continue;
	}
	
	bool bPrees = false;
	if (!g_SetupData.bAllowJump && (buttons & IN_JUMP))
	{
		buttons &= ~IN_JUMP;
		bPrees = true;
	}
	if (!g_SetupData.bAllowDuck && (buttons & IN_DUCK))
	{
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
	if (!(g_Players[client].OldButtons & IN_ATTACK2) && (buttons & IN_ATTACK2) && g_Players[client].NextAbilityAttack <= GetGameTime())
	{
		// Apply the ability attack cooldown
		g_Players[client].NextAbilityAttack = GetGameTime() + ABILITY_COOLDOWN;
		
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
		
		// Take the bullets for the weapon due to the ability cost
		int ammo = GetEntProp(active_weapon, Prop_Send, "m_iClip1");
		SetEntProp(active_weapon, Prop_Send, "m_iClip1", ammo - KeepInRange(ABILITY_BULLETS_COST, 0, ammo));
		
		// Setup the tracer beam points, etc... And send to to everyone
		TE_SetupBeamPoints(client_eye_pos, trace_hit_pos, g_iBombSprite, 0, 0, 0, 0.4, 1.0, 1.0, 1, 0.0, { 0, 255, 0, 255 }, 0);
		TE_SendToAll();
	}
	
	g_Players[client].OldButtons = buttons;
	
	if (bPrees)
	{
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public bool Filter_DontHitPlayers(int entity, int mask, int data)
{
	return (entity != data);
}

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client != g_SetupData.iPrisoner && client != g_SetupData.iAgainst)
	{
		return;
	}
	
	// Initialize the client's eye position, and the bullet hit position
	float client_pos[3], bullet_pos[3];
	GetClientEyePosition(client, client_pos);
	client_pos[2] -= 5.0;
	
	bullet_pos[0] = event.GetFloat("x");
	bullet_pos[1] = event.GetFloat("y");
	bullet_pos[2] = event.GetFloat("z");
	
	// Setup the tracer line colors by the client's gang color
	int tracer_colors[4];
	
	int client_gang_id = Gangs_GetPlayerGang(client);
	if (client_gang_id != NO_GANG)
	{
		GetColorRGB(g_szColors[Gangs_GetGangColor(client_gang_id)][Color_Rgb], tracer_colors);
	}
	else
	{
		tracer_colors = { 255, 255, 255, 255 };
	}
	
	// Setup the tracer beam points, and send it to everyone
	TE_SetupBeamPoints(client_pos, bullet_pos, g_iShotSprite, 0, 0, 0, 2.0, 1.0, 5.0, 1, 0.0, tracer_colors, 0);
	TE_SendToAll();
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((client == g_SetupData.iPrisoner && attacker != g_SetupData.iAgainst) || (client != g_SetupData.iAgainst && attacker == g_SetupData.iPrisoner))
	{
		return Plugin_Handled;
	}
	
	if (g_SetupData.bHeadshot && !(damagetype & DMG_BLAST))
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
	
	if (g_SetupData.iAgainst)
	{
		GetClientName(g_SetupData.iAgainst, szItem, sizeof(szItem));
	}
	
	Format(szItem, sizeof(szItem), "Enemy: %s", !g_SetupData.iAgainst ? RANDOM_GUARD_STRING:szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Health: (%d/%d)", g_SetupData.iHealth, MAX_HEALTH);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Headshot: %s", g_SetupData.bHeadshot ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Jump: %s", g_SetupData.bAllowJump ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Duck: %s", g_SetupData.bAllowDuck ? "ON":"OFF");
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
			return 0;
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
				g_Players[client].IsWrite = true;
				PrintToChat(client, "%s Type your desired \x04health\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 3:
			{
				g_SetupData.bHeadshot = !g_SetupData.bHeadshot;
				ShowLrSetupMenu(client);
			}
			case 4:
			{
				g_SetupData.bAllowJump = !g_SetupData.bAllowJump;
				ShowLrSetupMenu(client);
			}
			case 5:
			{
				g_SetupData.bAllowDuck = !g_SetupData.bAllowDuck;
				ShowLrSetupMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		g_SetupData.Reset();
		JB_ShowLrMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Timers ]================================//

public Action Timer_ResetProgressBar(Handle timer, int serial)
{
	// Initialize the client index by the given serial, and validate it
	int client = GetClientFromSerial(serial);
	
	if (client)
	{
		// Reset the progress bar panel
		ResetProgressBar(client);
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void StartLr()
{
	if (!g_SetupData.iAgainst)
	{
		g_SetupData.iAgainst = GetRandomGuard();
	}
	
	SetupPlayer(g_SetupData.iPrisoner);
	SetupPlayer(g_SetupData.iAgainst);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && !IsFakeClient(current_client))
		{
			SDKHook(current_client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
	g_cvInfiniteAmmo.SetInt(2);
	
	g_IsLrActivated = true;
	JB_StartLr(g_SetupData.iPrisoner, g_SetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client))
	{
		return;
	}
	
	g_Players[client].Reset();
	
	DisarmPlayer(client);
	SetEntityHealth(client, g_SetupData.iHealth);
	
	int weapon = GivePlayerItem(client, LR_WEAPON);
	if (weapon == -1)
	{
		return;
	}
	
	CustomWeapon custom_weapon = CustomWeapon(weapon);
	if (!custom_weapon)
	{
		return;
	}
	
	custom_weapon.SetModel(CustomWeaponModel_View, LASER_GUN_VIEW_MODEL);
	custom_weapon.SetModel(CustomWeaponModel_World, LASER_GUN_WORLD_MODEL);
	
	custom_weapon.SetShotSound(LASER_GUN_SHOOT_SOUND);
}

void InitRandomSettings()
{
	g_SetupData.iAgainst = 0;
	g_SetupData.iHealth = RoundToDivider(GetRandomInt(MIN_HEALTH, MAX_HEALTH), 50);
	g_SetupData.bHeadshot = GetRandomInt(0, 1) == 1;
	g_SetupData.bAllowJump = GetRandomInt(0, 1) == 1;
	g_SetupData.bAllowDuck = GetRandomInt(0, 1) == 1;
}

void GetNextGuard()
{
	bool bFound;
	
	while (!bFound)
	{
		g_SetupData.iAgainst++;
		if (g_SetupData.iAgainst > MaxClients) {
			bFound = true;
			g_SetupData.iAgainst = 0;
		}
		else if (IsClientInGame(g_SetupData.iAgainst) && IsPlayerAlive(g_SetupData.iAgainst) && JB_GetClientGuardRank(g_SetupData.iAgainst) != Guard_NotGuard) {
			bFound = true;
		}
	}
}

void CS_CreateExplosion(int attacker, int weapon, float damage, float radius, float vec[3])
{
	TE_SetupExplosion(vec, g_iExplosionSprite, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	EmitSoundToAll("weapons/hegrenade/explode4.wav", SOUND_FROM_LOCAL_PLAYER, .volume = 1.0, .origin = vec);
	
	float fCurrentPos[3], fCurrentDis;
	for (int iCurrentVictim = 1; iCurrentVictim <= MaxClients; iCurrentVictim++)
	{
		if (IsClientInGame(iCurrentVictim) && IsPlayerAlive(iCurrentVictim) && (iCurrentVictim == g_SetupData.iPrisoner || iCurrentVictim == g_SetupData.iAgainst))
		{
			GetClientAbsOrigin(iCurrentVictim, fCurrentPos);
			
			if (!IsPathClear(vec, fCurrentPos, iCurrentVictim))
			{
				continue;
			}
			
			fCurrentDis = GetVectorDistance(vec, fCurrentPos);
			
			if (fCurrentDis <= radius)
			{
				float result = Sine(((radius - fCurrentDis) / radius) * (FLOAT_PI / 2)) * damage;
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

int KeepInRange(int value, int min, int max)
{
	return value < min ? min : value > max ? max : value;
}

//================================================================//