#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <geoip>
#include <SteamWorks>

#define PREFIX " \x04[Level9]\x01"

#define STEAM_API_KEY "614ACF284426168C15F849A569A562FD" // You can get one from https://steamcommunity.com/dev/apikey

int g_iAdminChecking;
int g_iClientTimePlayed[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Player Info Extended", 
	author = "Natanel 'LuqS'", 
	description = "Get player info with a single command!", 
	version = "1.0", 
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_pinfo", Command_Playerinfo, ADMFLAG_ROOT, "Player info");
}

//================================[ Commands ]================================//

public Action Command_Playerinfo(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		PrintToChat(client, "%s Usage: \x04/pinfo\x01 <#userid|name>", PREFIX);
		return Plugin_Handled;
	}
	
	char arg_name[MAX_NAME_LENGTH];
	GetCmdArgString(arg_name, sizeof(arg_name));
	
	int target_index = FindTarget(client, arg_name, true);
	
	if (target_index == -1)
	{
		// Automated message
		return Plugin_Handled;
	}
	
	g_iAdminChecking = client;
	SteamWorks_SendHTTPRequest(CreateRequest_GetGamePlayTime(target_index));
	
	return Plugin_Handled;
}

//================================[ HTTP Callbacks ]================================//

public Handle CreateRequest_GetGamePlayTime(int client)
{
	char GetRequest[500];
	
	char sSteamID[64];
	GetClientAuthId(client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	
	Format(GetRequest, sizeof(GetRequest), "http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=%s&steamid=%s&appids_filter[0]=730", STEAM_API_KEY, sSteamID);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, GetRequest);
	
	SteamWorks_SetHTTPCallbacks(hRequest, TimePlayed_OnHTTPResponse);
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientSerial(client));
	
	return hRequest;
}

public int TimePlayed_OnHTTPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any client)
{
	if (!bFailure && bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK)
		SteamWorks_GetHTTPResponseBodyCallback(hRequest, HTTPResponseBodyTime, client);
	else
		PrintToServer("Could not get CSGO Playtime (HTTP status %d)", eStatusCode);
	
	delete hRequest;
	return 0;
}

public int HTTPResponseBodyTime(const char[] sData, any client)
{
	client = GetClientFromSerial(client);
	
	int iTimePlayedIndex = StrContains(sData, "playtime_forever");
	
	g_iClientTimePlayed[client] = iTimePlayedIndex != -1 ? (GetTimeFromData(sData[iTimePlayedIndex]) / 60) : -1;
	
	SteamWorks_SendHTTPRequest(CreateRequest_GetAccountExistingTime(client));
	
	return 0;
}

public Handle CreateRequest_GetAccountExistingTime(int client)
{
	char GetRequest[512];
	
	char sSteamID[64];
	GetClientAuthId(client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	
	Format(GetRequest, sizeof(GetRequest), "http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamIDS=%s", STEAM_API_KEY, sSteamID);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, GetRequest);
	
	SteamWorks_SetHTTPCallbacks(hRequest, AccountAge_OnHTTPResponse);
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientSerial(client));
	
	return hRequest;
}

public void AccountAge_OnHTTPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any client)
{
	if (!bFailure && bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK)
		SteamWorks_GetHTTPResponseBodyCallback(hRequest, HTTPResponseBodyAccAge, client);
	else
		PrintToServer("Could not get Account Age (HTTP status %d)", eStatusCode);
	
	delete hRequest;
}

public void HTTPResponseBodyAccAge(const char[] sData, any client)
{
	client = GetClientFromSerial(client);
	
	int iTimeCreatedIndex = StrContains(sData, "timecreated");
	
	PrintClientInfo(client, g_iAdminChecking);
	
	if (iTimeCreatedIndex != -1)
	{
		int iSteamAccountExistingTime = GetTime() - GetTimeFromData(sData[iTimeCreatedIndex]);
		
		char sMessage[128] = "Steam Account Age: \x04";
		char sStringToAdd[32];
		
		// YEARS
		int iYearsExisting = (iSteamAccountExistingTime) / 31556926;
		if (iYearsExisting >= 1)
		{
			iSteamAccountExistingTime -= iYearsExisting * 31556926;
			Format(sStringToAdd, sizeof(sStringToAdd), "%d Year(s)%s ", iYearsExisting, iSteamAccountExistingTime / 2629743 != 0 ? "," : "");
			StrCat(sMessage, sizeof(sMessage), sStringToAdd);
		}
		
		// MONTHS
		int iMonthsExisting = (iSteamAccountExistingTime) / 2629743;
		if (iMonthsExisting >= 1)
		{
			iSteamAccountExistingTime -= iMonthsExisting * 2629743;
			Format(sStringToAdd, sizeof(sStringToAdd), "%d Month(s)%s ", iMonthsExisting, iSteamAccountExistingTime / 604800 != 0 ? "," : "");
			StrCat(sMessage, sizeof(sMessage), sStringToAdd);
		}
		
		// WEEKS
		int iWeeksExisting = (iSteamAccountExistingTime) / 604800;
		if (iWeeksExisting >= 1)
		{
			iSteamAccountExistingTime -= iWeeksExisting * 604800;
			Format(sStringToAdd, sizeof(sStringToAdd), "%d Week(s)%s ", iWeeksExisting, iSteamAccountExistingTime / 86400 != 0 ? "," : "");
			StrCat(sMessage, sizeof(sMessage), sStringToAdd);
		}
		
		// DAYS
		int iDaysExisting = (iSteamAccountExistingTime) / 86400;
		if (iDaysExisting >= 1)
		{
			Format(sStringToAdd, sizeof(sStringToAdd), "%d Day(s)", iDaysExisting);
			StrCat(sMessage, sizeof(sMessage), sStringToAdd);
		}
		
		StrCat(sMessage, sizeof(sMessage), "\x01!");
		PrintToChat(g_iAdminChecking, sMessage);
	}
	else
	{
		PrintToChat(g_iAdminChecking, "Steam Account Age: \x02PRIVATE\x01");
	}
}

//================================[ Functions ]================================//

int GetTimeFromData(const char[] sData)
{
	char strBreak[4][32];
	ExplodeString(sData, ",", strBreak, sizeof(strBreak), sizeof(strBreak[]));
	String_Trim(strBreak[0], strBreak[0], sizeof(strBreak[]), "\"timecreated:playtime_forever");
	
	return StringToInt(strBreak[0]);
}

void PrintClientInfo(int iClientToCheck, int iClientToPrint)
{
	char sIP[32];
	GetClientIP(iClientToCheck, sIP, sizeof(sIP));
	
	char sLocation[46];
	GeoipCountry(sIP, sLocation, sizeof(sLocation));
	
	char sSteamID[64];
	GetClientAuthId(iClientToCheck, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	
	PrintToChat(iClientToPrint, "\x07━━━━━━━━━━━[ Player Info: ]━━━━━━━━━━━\x01");
	PrintToChat(iClientToPrint, "Name: \x04%N\x01", iClientToCheck);
	PrintToChat(iClientToPrint, "SID: \x04%s\x01", sSteamID);
	PrintToChat(iClientToPrint, "Prime: %s", (SteamWorks_HasLicenseForApp(iClientToCheck, 624820) == k_EUserHasLicenseResultDoesNotHaveLicense) ? "\x02✘":"\x04✓");
	PrintToChat(iClientToPrint, "IP: \x04%s", sIP);
	PrintToChat(iClientToPrint, "Location: \x04%s", sLocation);
	
	if (g_iClientTimePlayed[iClientToCheck] != -1)
		PrintToChat(iClientToPrint, "CSGO Playtime: \x04%d Hours", g_iClientTimePlayed[iClientToCheck]);
	else
		PrintToChat(iClientToPrint, "CSGO Playtime: \x02PRIVATE\x01");
}

void String_Trim(const char[] str, char[] output, int size, const char[] chrs = " \t\r\n")
{
	int x = 0;
	while (str[x] != '\0' && FindCharInString(chrs, str[x]) != -1) {
		x++;
	}
	
	x = strcopy(output, size, str[x]);
	x--;
	
	while (x >= 0 && FindCharInString(chrs, output[x]) != -1) {
		x--;
	}
	
	output[++x] = '\0';
}

//================================================================//