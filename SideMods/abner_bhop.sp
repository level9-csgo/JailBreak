#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required 
#define BHOPCHECK g_Bhop[client] || (!CSGO && GetConVarBool(hAutoBhop))
#define PLUGIN_ENABLED GetConVarBool(hBhop)
#define PLUGIN_VERSION "3.1fix"
#define RESTOREDEFAULT GetConVarBool(hRestoreDefault)


ConVar hBhop;
ConVar hAutoBhop;
ConVar hFlag;
ConVar hRestoreDefault;

//#define DEBUG

#define CVAR_ENABLED "1"
#define CVAR_AUTOBHOP "0"
#define CVAR_FLAG "\"\""
//#define CVAR_FLAG "z"
#define CVAR_RESTOREDEFAULT "1"

#define BHOPFLAG ADMFLAG_SLAY



bool CSGO = false;
int WATER_LIMIT;

bool g_Bhop[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CSS/CS:GO] AbNeR BHOP", 
	author = "AbNeR_CSS", 
	description = "Auto BHOP", 
	version = PLUGIN_VERSION, 
	url = "www.tecnohardclan.com"
}


public void OnPluginStart()
{
	CreateConVar("abnerbhop_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_REPLICATED);
	hBhop = CreateConVar("abner_bhop_enabled", CVAR_ENABLED, "Enable/disable plugin", FCVAR_NOTIFY | FCVAR_REPLICATED);
	hRestoreDefault = CreateConVar("abner_bhop_disable_restore_default", CVAR_RESTOREDEFAULT, "Restore default convar values when disable plugin", FCVAR_NOTIFY | FCVAR_REPLICATED);
	hAutoBhop = CreateConVar("abner_bhop_autobhop", CVAR_AUTOBHOP, "Enable/Disable auto bhop to everyone", FCVAR_NOTIFY | FCVAR_REPLICATED);
	hFlag = CreateConVar("abner_bhop_flag", CVAR_FLAG, "Admin flag that have autobhop enabled", FCVAR_NOTIFY | FCVAR_REPLICATED);
	
	AutoExecConfig(true, "abner_bhop");
	
	char theFolder[40];
	GetGameFolderName(theFolder, sizeof(theFolder));
	(CSGO = StrEqual(theFolder, "csgo")) ? (WATER_LIMIT = 2) : (WATER_LIMIT = 1);
	
	if (PLUGIN_ENABLED)
		BhopOn();
	
	HookConVarChange(hBhop, PluginChanged);
	HookConVarChange(hAutoBhop, AutoBhopChanged);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
			OnClientPostAdminCheck(i);
	}
	
}

public void OnPluginEnd() {
	if (RESTOREDEFAULT)BhopOff();
}


public void AutoBhopChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (!CSGO)
		return;
	
	SetCvar("sv_autobunnyhopping", newValue);
}

public void PluginChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (StringToInt(newValue) == 1)BhopOn();
	else if (RESTOREDEFAULT)BhopOff();
}

bool CheckFlag(int client)
{
	char flag[100];
	GetConVarString(hFlag, flag, sizeof(flag));
	if (StrEqual(flag, ""))
		return false;
	
	return (GetUserFlagBits(client) & ReadFlagString(flag)) != 0 ? true : false;
}


public void OnClientPostAdminCheck(int client)
{
	if (!PLUGIN_ENABLED)
		return;
	
	g_Bhop[client] = CheckFlag(client);
	#if defined DEBUG
	if (CheckFlag(client))
		PrintToServer("Flag BHOP: %N", client);
	#endif
	if (!CSGO)
		SDKHook(client, SDKHook_PreThink, PreThink);
}

public Action PreThink(int client)
{
	if (!PLUGIN_ENABLED)
		return Plugin_Continue;
	
	if (IsValidClient(client) && IsPlayerAlive(client) && BHOPCHECK)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}
	return Plugin_Continue;
}

void BhopOn()
{
	if (CSGO)
	{
		SetCvar("sv_enablebunnyhopping", "1");
		SetCvar("sv_staminamax", "0");
		SetCvar("sv_airaccelerate", "2000");
		SetCvar("sv_staminajumpcost", "0");
		SetCvar("sv_staminalandcost", "0");
	}
	else
	{
		SetCvar("sv_enablebunnyhopping", "1");
		SetCvar("sv_airaccelerate", "2000");
	}
}


void BhopOff()
{
	if (CSGO)
	{
		SetDefaultValue("sv_staminamax");
		SetDefaultValue("sv_staminajumpcost");
		SetDefaultValue("sv_staminalandcost");
	}
}

stock void SetCvarByCvar(ConVar cvar, const char[] sValue) {
	if (cvar == INVALID_HANDLE)
		return;
	
	char cvarName[100];
	cvar.GetName(cvarName, sizeof(cvarName));
	
	
	ServerCommand("%s %s", cvarName, sValue);
}

stock void SetDefaultValue(char[] scvar) {
	ConVar cvar = FindConVar(scvar);
	if (cvar == INVALID_HANDLE)
		return;
	
	char szDefault[100];
	cvar.GetDefault(szDefault, sizeof(szDefault));
	#if defined DEBUG
	PrintToServer("Restaurado valor padrao: %s %s", scvar, szDefault);
	PrintToChatAll("Restaurado valor padrao: %s %s", scvar, szDefault);
	#endif
	SetConVarString(cvar, szDefault, true);
}

stock void SetCvar(const char[] scvar, const char[] svalue)
{
	ConVar cvar = FindConVar(scvar);
	if (cvar == INVALID_HANDLE)
		return;
	
	#if defined DEBUG
	PrintToServer("Definido valor: %s %s", scvar, svalue);
	PrintToChatAll("Definido valor: %s %s", scvar, svalue);
	#endif
	SetConVarString(cvar, svalue, true);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!PLUGIN_ENABLED)
		return Plugin_Continue;
	
	if (BHOPCHECK)
		if (IsPlayerAlive(client) && buttons & IN_JUMP) //Check if player is alive and is in pressing space
		if (!(GetEntityMoveType(client) & MOVETYPE_LADDER) && !(GetEntityFlags(client) & FL_ONGROUND)) //Check if is not in ladder and is in air
		if (waterCheck(client) < WATER_LIMIT)
		buttons &= ~IN_JUMP;
	return Plugin_Continue;
}

int waterCheck(int client)
{
	int index = GetEntProp(client, Prop_Data, "m_nWaterLevel");
	return index;
}

stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	return IsClientInGame(client);
}





