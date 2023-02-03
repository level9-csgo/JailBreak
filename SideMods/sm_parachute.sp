/*******************************************************************************

  SM Parachute

  Version: 2.5
  Author: SWAT_88

  1.0 	First version, should work on basically any mod
  1.1	Linear fallspeed added.
  1.2	Key assignment amended
  1.3	Added +use Button support. No keybinding required!
		Fixed some bugs in linear Flight mode:
		You dont stay hanging on the wall.
		You don't bounce when you touch the ground.
		You dont have Gravity 0.1 when you jump holding the E button.
  1.4	Fixed a	serious bug: 
		Maxplayers are now correctly counted.
  1.5	Added new features:
		Information, welcome and status messages in Chat, Panel or BottomCenterText!
		Buy Parachute and Sell Parachute added ! (CS ONLY)
		Translations added !
		Works on basically any mod !
  1.6	Model Added!
  1.7	Fixed another bug in linear Flight mode.
		Linear Flight mode should be bugfree now!
		Added Cvar for model display.
  1.7b	Fixed a small bug for checking the model.
		Added a better check for Parachute ending.
  1.7c	Fixed a stupid bug in HandleSay.
  1.8	Fixed a bug in OnPlayerDisconnect.
		Changed /bp /sp to !bp !sp
		Added new features:
			Realistic velocity-decrease.
			More detail on model textures.
			A new parachute.
  1.9	Added a new button: Space.
		Added automatic button change for TF2.
  2.0	Fixed some bugs:
			in RoundMsg
			in Chat Commands
  2.5   Fixed this error: "Can't create physics object for model/parachute/parachute_carbon.mdl".
   
  Description:
  
	If cost = 0 then Everybody have a parachute.
	To use your parachute press and hold your E(+use)/Space(+jump) button while falling.
	If you are running a TF2 server the button will automatic change to Space.
	I checked whether cstrike is running or not, so dont be afraid of crashing the plugin in another Mod, It's safe!!!
	Sidenote:
	To change the model you have to edit the global variables for the names. Afterwards recompile sm_parachute.sp. Here is a tutorial.
	To change the texture you have to recompile the smd and change its content. Here is the Model source.
	
  Commands:
  
	Press E(+use) to slow down your fall.
	No more binding Keys!
	Write !bp or !buy_parachute in Chat to buy a parachute (Only if cost > 0) !
	Write !sp or !sell_parachute in Chat to sell your parachute (Only if cost > 0) !

  Cvars:

	sm_parachute_enabled 	"1"		- 0: disables the plugin - 1: enables the plugin

	sm_parachute_fallspeed "100"	- speed of the fall when you use the parachute
	
	sm_parachute_linear 	"1"		- 0: disables linear fallspeed - 1: enables it
	
	sm_parachute_msgtype 	"1"		- 0: disables Information - 1: Chat - 2: Panel - 3: BottomCenter
	
	sm_parachute_cost 		"0"		- cost of the parachute (CS ONLY) (If cost = 0 then free for everyone)

	sm_parachute_payback 	"75"	- how many percent of the parachute cost you get when you sell your parachute (ie. 75% of 1000 = 750$)
	
	sm_parachute_welcome	"1"		- 0: disables Welcome Message - 1: enables it
	
	sm_parachute_roundmsg	"1"		- 0: disables Round Message - 1: enables it
	
	sm_parachute_model		"1"		- 0: dont use the model - 1: display the Model
	
	sm_parachute_decrease	"50"	- 0: dont use Realistic velocity-decrease - x: sets the velocity-decrease.
	
	sm_parachute_button		"1"		- 1: uses button +USE for parachute usage. - 2: uses button +JUMP.
	
  Supported Languages:
  
	en	English
	de	German
	
  If you write a Translation post it in this thread.

  Setup (SourceMod):

	Install the smx file to addons\sourcemod\plugins.
	Install the translation file to addons\sourcemod\translations.
	(Re)Load Plugin or change Map.
	
  TO DO:
  
	Smooth model movement.(I will need expert help for this)
	Animations.(I will not code it, it's too complicate, but any other expert can code it. It's Open Source)
	
  Copyright:
  
	Everybody can edit this plugin and copy this plugin.
	
  Thanks to:
  
	Greyscale
	Pinkfairie
	bl4nk
	theY4Kman
	Knagg0
	KRoT@L
	JTP10181
	
  HAVE FUN!!!

*******************************************************************************/

#include <sourcemod>
#include <sdktools>
#include <JB_MapFixer>
#include <Misc_Ghost>

#define PARACHUTE_VERSION 	"2.5"

new g_iVelocity = -1;

new Handle:g_fallspeed = INVALID_HANDLE;
new Handle:g_enabled = INVALID_HANDLE;
new Handle:g_linear = INVALID_HANDLE;
new Handle:g_decrease = INVALID_HANDLE;

new x;
new cl_flags;
new cl_buttons;
new Float:speed[3];
new bool:isfallspeed;

new bool:inUse[MAXPLAYERS + 1];
new bool:hasPara[MAXPLAYERS + 1];

int g_iMapFixerId = -1;

public Plugin myinfo = 
{
	name = "SM Parachute", 
	author = "SWAT_88", 
	description = "To use your parachute press and hold your E(+use) button while falling.", 
	version = PARACHUTE_VERSION, 
	url = "http://www.sourcemod.net/"
};

public OnPluginStart()
{
	g_enabled = CreateConVar("sm_parachute_enabled", "1");
	g_fallspeed = CreateConVar("sm_parachute_fallspeed", "60");
	g_linear = CreateConVar("sm_parachute_linear", "1");
	g_decrease = CreateConVar("sm_parachute_decrease", "0");
	g_iVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	
	HookEvent("player_death", PlayerDeath);
	HookEvent("round_start", RoundStart);
	
	HookConVarChange(g_enabled, CvarChange_Enabled);
	HookConVarChange(g_linear, CvarChange_Linear);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_MapFixer"))
	{
		g_iMapFixerId = JB_CreateMapFixer("enable_parachute", "Enable Parachute", Fixer_Bool, Admin_Root, 0, 1, 1);
	}
}

public void OnMapStart()
{
	if (GetConVarInt(g_enabled) != JB_GetMapFixer(g_iMapFixerId))
	{
		SetConVarInt(g_enabled, JB_GetMapFixer(g_iMapFixerId));
	}
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	OnMapStart();
}

public OnClientPutInServer(client)
{
	inUse[client] = false;
	hasPara[client] = false;
}

public Action:PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	new client;
	client = GetClientOfUserId(GetEventInt(event, "userid"));
	hasPara[client] = false;
	EndPara(client);
	return Plugin_Continue;
}

public StartPara(client)
{
	decl Float:velocity[3];
	decl Float:fallspeed;
	if (g_iVelocity == -1)return;
	if (GetConVarInt(g_enabled)) {
		fallspeed = GetConVarFloat(g_fallspeed) * (-1.0);
		GetEntDataVector(client, g_iVelocity, velocity);
		if (velocity[2] >= fallspeed) {
			isfallspeed = true;
		}
		if (velocity[2] < 0.0) {
			if (isfallspeed && GetConVarInt(g_linear) == 0) {
			}
			else if ((isfallspeed && GetConVarInt(g_linear) == 1) || GetConVarFloat(g_decrease) == 0.0) {
				velocity[2] = fallspeed;
			}
			else {
				velocity[2] = velocity[2] + GetConVarFloat(g_decrease);
			}
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
			SetEntDataVector(client, g_iVelocity, velocity);
			SetEntityGravity(client, 0.1);
		}
	}
}

public EndPara(client)
{
	if (GetConVarInt(g_enabled) == 1) {
		SetEntityGravity(client, 1.0);
		inUse[client] = false;
	}
}

public Check(client) {
	if (GetConVarInt(g_enabled) == 1) {
		GetEntDataVector(client, g_iVelocity, speed);
		cl_flags = GetEntityFlags(client);
		if (speed[2] >= 0 || (cl_flags & FL_ONGROUND))EndPara(client);
	}
}

public OnGameFrame()
{
	if (GetConVarInt(g_enabled) == 0)return;
	for (x = 1; x <= MaxClients; x++)
	{
		if (IsClientInGame(x) && (IsPlayerAlive(x) || JB_IsClientGhost(x)))
		{
			char global_name[16];
			GetEntPropString(x, Prop_Data, "m_iGlobalname", global_name, sizeof(global_name));
			
			cl_buttons = GetClientButtons(x);
			
			if ((cl_buttons & IN_USE) || (JB_IsClientGhost(x) && StrEqual(global_name, "parachute")))
			{
				if (!inUse[x])
				{
					inUse[x] = true;
					isfallspeed = false;
					StartPara(x);
				}
				
				StartPara(x);
			}
			else
			{
				if (inUse[x])
				{
					inUse[x] = false;
					EndPara(x);
				}
			}
			Check(x);
		}
	}
}

stock GetNextSpaceCount(String:text[], CurIndex) {
	new Count = 0;
	new len = strlen(text);
	for (new i = CurIndex; i < len; i++) {
		if (text[i] == ' ')return Count;
		else Count++;
	}
	return Count;
}

public CvarChange_Enabled(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (StringToInt(newvalue) == 0)
	{
		for (new client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && IsPlayerAlive(client))
			{
				if (hasPara[client]) {
					SetEntityGravity(client, 1.0);
					SetEntityMoveType(client, MOVETYPE_WALK);
				}
			}
		}
	}
}

public CvarChange_Linear(Handle:cvar, const String:oldvalue[], const String:newvalue[]) {
	if (StringToInt(newvalue) == 0) {
		for (new client = 1; client <= MaxClients; client++) {
			if (IsClientInGame(client) && IsPlayerAlive(client) && hasPara[client]) {
				SetEntityMoveType(client, MOVETYPE_WALK);
			}
		}
	}
} 