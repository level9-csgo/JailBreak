#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_SettingsSystem>
#include <JB_SpecialDays>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define CONFIG_PATH "addons/sourcemod/configs/SongsData.cfg"

#define SOUNDS_DIR "level9_jailbreak_songs"

#define ABORT_SYMBOL "-1"

//====================//

enum ParameterType
{
	Param_None = 0, 
	Param_Name, 
	Param_File
}

enum struct Song
{
	char szSongName[128];
	char szSongFile[64];
	char szSongCreator[MAX_NAME_LENGTH];
	bool bIsNew;
}

enum struct Client
{
	ParameterType iParamType;
	char szSongName[128];
	char szSongFile[64];
	
	void Reset()
	{
		this.iParamType = Param_None;
		this.szSongName[0] = '\0';
		this.szSongFile[0] = '\0';
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ArrayList g_SongsData;

char g_AuthorizedGroups[][] = 
{
	"Programmer"
};

int g_iSettingId = -1;
int g_iLastSong = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Music System", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_SongsData = new ArrayList(sizeof(Song));
	
	RegConsoleCmd("sm_music", Command_Music, "Access the music system main menu.");
	RegConsoleCmd("sm_stopmusic", Command_StopMusic, "Stops the running songs.");
	RegConsoleCmd("sm_sm", Command_StopMusic, "Stops the running songs. (An Alias)");
	
	char szDirPath[PLATFORM_MAX_PATH];
	strcopy(szDirPath, sizeof(szDirPath), CONFIG_PATH);
	BuildPath(Path_SM, szDirPath, sizeof(szDirPath), szDirPath[17]);
	delete OpenFile(szDirPath, "a+");
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Sound Settings", "This category is associated with sound in general, as well as music settings.");
		
		g_iSettingId = JB_CreateSetting("musicsys_volume", "Controls the music system volume. (Float setting)", "Music Volume", "Sound Settings", Setting_Float, 1.0, "0.1");
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_ClientsData[client].Reset();
}

public void OnMapStart()
{
	KV_LoadSongs();
	
	LoadAndPrecacheSongs();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (g_ClientsData[client].iParamType == Param_None)
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL))
	{
		PrintToChat(client, "%s Operation aborted.", PREFIX);
		
		g_ClientsData[client].iParamType = Param_None;
		
		ShowAddSongMenu(client);
		return Plugin_Handled;
	}
	
	if (g_ClientsData[client].iParamType == Param_Name) {
		strcopy(g_ClientsData[client].szSongName, sizeof(g_ClientsData[].szSongName), szArgs);
	} else {
		strcopy(g_ClientsData[client].szSongFile, sizeof(g_ClientsData[].szSongFile), szArgs);
	}
	
	g_ClientsData[client].iParamType = Param_None;
	ShowAddSongMenu(client);
	return Plugin_Handled;
}

//================================[ Events ]================================//

public Action Command_Music(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for root administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		ShowMusicMainMenu(iTargetIndex);
	}
	else
	{
		ShowMusicMainMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_StopMusic(int client, int args)
{
	StopMusicToClient(client);
	PrintToChat(client, "%s You've stopped the running music.", PREFIX);
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowMusicMainMenu(int client)
{
	char szItem[64];
	Menu menu = new Menu(Handler_Music);
	menu.SetTitle("%s Music System - Main Menu\n ", PREFIX_MENU);
	
	Format(szItem, sizeof(szItem), "Songs List [%d Songs]", g_SongsData.Length);
	menu.AddItem("", szItem, g_SongsData.Length ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	menu.AddItem("", "Stop Running Song\n ");
	
	menu.AddItem("", "Add Song [Root]", GetAdminFlag(GetUserAdmin(client), Admin_Root) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	menu.AddItem("", "Stop Songs To All [Root]", GetAdminFlag(GetUserAdmin(client), Admin_Root) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Music(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				ShowSongsListMenu(client);
			}
			case 1:
			{
				StopMusicToClient(client);
				PrintToChat(client, "%s You've stopped the running song.", PREFIX);
				ShowMusicMainMenu(client);
			}
			case 2:
			{
				ShowAddSongMenu(client);
			}
			case 3:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient))
					{
						StopMusicToClient(iCurrentClient);
					}
				}
				
				ShowMusicMainMenu(client);
				
				PrintToChatAll("%s Admin: \x0C%N\x01 stopped the running songs for everyone.", PREFIX, client);
				JB_WriteLogLine("Admin \"%L\" stopped the running songs for everyone.", client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void ShowSongsListMenu(int client, int start_item = 0)
{
	Menu menu = new Menu(Handler_SongsList);
	menu.SetTitle("%s Music System - Songs List [%d]\n ", PREFIX_MENU, g_SongsData.Length);
	
	ArrayList arSortedSongsData = new ArrayList(ByteCountToCells(64));
	
	for (int iCurrentSong = 0; iCurrentSong < g_SongsData.Length; iCurrentSong++)
	{
		arSortedSongsData.PushString(GetSongByIndex(iCurrentSong).szSongName);
	}
	
	arSortedSongsData.SortCustom(AlphabeticSortCaseInsensative);
	
	char szSongName[128];
	for (int iCurrentSong = 0; iCurrentSong < arSortedSongsData.Length; iCurrentSong++)
	{
		arSortedSongsData.GetString(iCurrentSong, szSongName, sizeof(szSongName));
		RTLify(szSongName, sizeof(szSongName), szSongName);
		menu.AddItem(szSongName, szSongName);
	}
	
	delete arSortedSongsData;
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No song was found.", ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.DisplayAt(client, start_item, MENU_TIME_FOREVER);
}

public int Handler_SongsList(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[128];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		RTLify(szItem, sizeof(szItem), szItem);
		
		ShowSongDetailsMenu(client, GetSongByName(szItem), menu.Selection);
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		ShowMusicMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

int AlphabeticSortCaseInsensative(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList ar = view_as<ArrayList>(array);
	
	/*if (GetClientGender(client) == (Girl || Gay || She/Her))
	{
		KickClient(client, "Your gender isn't allowed in the JailBreak server!!!!!1!!111!");
	}*/
	
	int str_size = ar.BlockSize * 4;
	
	char[] str1 = new char[str_size], str2 = new char[str_size];
	
	ar.GetString(index1, str1, str_size);
	ar.GetString(index2, str2, str_size);
	
	return strcmp(str1, str2, false);
}

void ShowAddSongMenu(int client)
{
	char szItem[256];
	Menu menu = new Menu(Handler_AddSong);
	menu.SetTitle("%s Music System - Add Song\n ", PREFIX_MENU);
	
	RTLify(szItem, sizeof(szItem), g_ClientsData[client].szSongName);
	Format(szItem, sizeof(szItem), "Song Name: %s", !g_ClientsData[client].szSongName[0] ? "None" : szItem);
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "Song File: %s%s\n ", !g_ClientsData[client].szSongFile[0] ? "None" : g_ClientsData[client].szSongFile, StrEqual(GetFileExt(g_ClientsData[client].szSongFile), "mp3") ? "" : ".mp3");
	menu.AddItem("", szItem);
	
	menu.AddItem("", "Add Song!");
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_AddSong(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 2:
			{
				if (!g_ClientsData[client].szSongName[0] || !g_ClientsData[client].szSongFile[0])
				{
					PrintToChat(client, "%s Invalid parameters specified.", PREFIX_ERROR);
					ShowAddSongMenu(client);
					return 0;
				}
				
				KV_AddSong(client);
				
				PrintToChat(client, "%s Successfully added the song \x04\"%s\"\x01!", PREFIX, g_ClientsData[client].szSongName);
				JB_WriteLogLine("Admin \"%L\" added the song \"%s\", file name: \"%s\".", client, g_ClientsData[client].szSongName, g_ClientsData[client].szSongFile);
				
				g_ClientsData[client].Reset();
			}
			default:
			{
				g_ClientsData[client].iParamType = view_as<ParameterType>(itemNum + 1);
				PrintToChat(client, "%s Type the \x04song %s\x01, or type \x02%s\x01 to abort.", PREFIX, g_ClientsData[client].iParamType == Param_Name ? "display name":g_ClientsData[client].iParamType == Param_File ? "file name":"", ABORT_SYMBOL);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		g_ClientsData[client].Reset();
		if (itemNum == MenuCancel_ExitBack) {
			ShowMusicMainMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void ShowSongDetailsMenu(int client, int songId, int menu_selection)
{
	char szItem[64], szItemInfo[8];
	Menu menu = new Menu(Handler_SongDetails);
	
	Song SongData; SongData = GetSongByIndex(songId);
	
	Format(szItem, sizeof(szItem), "%s%s", SongData.szSongFile, StrEqual(GetFileExt(SongData.szSongFile), "mp3") ? "" : ".mp3");
	
	RTLify(SongData.szSongName, sizeof(SongData.szSongName), SongData.szSongName);
	menu.SetTitle("%s Music System - Viewing Song\n \nSong Name: %s\nSong File: %s\nAdded By: %s\n ", PREFIX_MENU, 
		SongData.szSongName, 
		szItem, 
		SongData.szSongCreator
		);
	
	IntToString(songId, szItemInfo, sizeof(szItemInfo));
	menu.AddItem(szItemInfo, "Play To Yourself", SongData.bIsNew ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	bool client_allowed = IsClientAllowed(client);
	
	IntToString(menu_selection, szItemInfo, sizeof(szItemInfo));
	Format(szItem, sizeof(szItem), "Play To Everyone [Root]%s", client_allowed ? "\n " : "");
	menu.AddItem(szItemInfo, szItem, (!SongData.bIsNew && GetAdminFlag(GetUserAdmin(client), Admin_Root)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.AddItem("", "Delete Song", client_allowed ? ITEMDRAW_DEFAULT : ITEMDRAW_NOTEXT);
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SongDetails(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[128];
		menu.GetItem(0, szItem, sizeof(szItem));
		int iSongId = StringToInt(szItem);
		
		Song SongData; SongData = GetSongByIndex(iSongId);
		
		switch (itemNum)
		{
			case 0:
			{
				StopMusicToClient(client);
				
				DataPack dPack;
				CreateDataTimer(0.1, Timer_PlaySong, dPack);
				dPack.WriteCell(GetClientSerial(client));
				dPack.WriteCell(iSongId);
				dPack.WriteCell(false);
				dPack.Reset();
				
				PrintToChat(client, "%s Listening to song \x04\"%s\"\x01.", PREFIX, SongData.szSongName);
			}
			case 1:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient))
					{
						StopMusicToClient(iCurrentClient);
						
						DataPack dPack;
						CreateDataTimer(0.1, Timer_PlaySong, dPack);
						dPack.WriteCell(GetClientSerial(iCurrentClient));
						dPack.WriteCell(iSongId);
						dPack.WriteCell(false);
						dPack.Reset();
					}
				}
				
				PrintToChatAll("%s Admin: \x0C%N\x01 played the song \x04\"%s\"\x01.", PREFIX, client, SongData.szSongName);
				
				JB_WriteLogLine("Admin \"%L\" played the song \"%s\" to everyone.", client, SongData.szSongName);
			}
			default:
			{
				KV_DeleteSong(client, iSongId);
				
				menu.GetItem(1, szItem, sizeof(szItem));
				ShowSongsListMenu(client, StringToInt(szItem));
				PrintToChat(client, "%s Successfully deleted the song \x02\"%s\"\x01.", PREFIX, SongData.szSongName);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		char szItem[16];
		menu.GetItem(1, szItem, sizeof(szItem));
		ShowSongsListMenu(client, StringToInt(szItem));
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

//================================[ Natives ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_PlayRandomSong", Native_PlayRandomSong);
	CreateNative("JB_StopMusicToClient", Native_StopMusicToClient);
	
	RegPluginLibrary("JB_MusicSystem");
	return APLRes_Success;
}

public int Native_PlayRandomSong(Handle plugin, int numParams)
{
	if (!g_SongsData.Length)
	{
		return false;
	}
	
	int iRandomSongId = GetRandomInt(0, g_SongsData.Length - 1);
	int iCounter;
	
	Song SongData; SongData = GetSongByIndex(iRandomSongId);
	
	while (SongData.bIsNew || iRandomSongId == g_iLastSong)
	{
		iRandomSongId = GetRandomInt(0, g_SongsData.Length - 1);
		SongData = GetSongByIndex(iRandomSongId);
		if (iCounter == g_SongsData.Length) {
			return false;
		}
		
		iCounter++;
	}
	
	g_iLastSong = iRandomSongId;
	
	bool boolean = GetNativeCell(1);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			StopMusicToClient(iCurrentClient);
			
			DataPack dPack;
			CreateDataTimer(0.1, Timer_PlaySong, dPack);
			dPack.WriteCell(GetClientSerial(iCurrentClient));
			dPack.WriteCell(iRandomSongId);
			dPack.WriteCell(boolean);
			dPack.Reset();
		}
	}
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("Random song \"%s\" has been played by plugin \"%s\".", SongData.szSongName, szFileName);
	return true;
}

public int Native_StopMusicToClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	StopMusicToClient(client);
	return 0;
}

//================================[ Key Values ]================================//

void KV_LoadSongs()
{
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Failed to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Songs");
	kv.ImportFromFile(CONFIG_PATH);
	
	g_SongsData.Clear();
	
	Song CurrentSongData;
	
	if (kv.GotoFirstSubKey())
	{
		do {
			kv.GetString("Name", CurrentSongData.szSongName, sizeof(CurrentSongData.szSongName));
			kv.GetString("File", CurrentSongData.szSongFile, sizeof(CurrentSongData.szSongFile));
			kv.GetString("Creator", CurrentSongData.szSongCreator, sizeof(CurrentSongData.szSongCreator));
			CurrentSongData.bIsNew = false;
			
			g_SongsData.PushArray(CurrentSongData);
		}
		while (kv.GotoNextKey());
	}
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_AddSong(int client)
{
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Failed to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Songs");
	kv.ImportFromFile(CONFIG_PATH);
	
	char szKey[8];
	IntToString(g_SongsData.Length, szKey, sizeof(szKey));
	kv.JumpToKey(szKey, true);
	
	Song SongData;
	strcopy(SongData.szSongName, sizeof(SongData.szSongName), g_ClientsData[client].szSongName);
	strcopy(SongData.szSongFile, sizeof(SongData.szSongFile), g_ClientsData[client].szSongFile);
	GetClientName(client, SongData.szSongCreator, sizeof(SongData.szSongCreator));
	SongData.bIsNew = true;
	
	kv.SetString("Name", SongData.szSongName);
	kv.SetString("File", SongData.szSongFile);
	kv.SetString("Creator", SongData.szSongCreator);
	
	g_SongsData.PushArray(SongData);
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_DeleteSong(int client, int songId)
{
	if (!FileExists(CONFIG_PATH)) {
		SetFailState("Failed to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Songs");
	kv.ImportFromFile(CONFIG_PATH);
	
	char szKey[8];
	IntToString(songId, szKey, sizeof(szKey));
	
	if (kv.JumpToKey(szKey))
	{
		kv.DeleteThis();
		kv.Rewind();
	}
	
	JB_WriteLogLine("Admin \"%L\" deleted the song \"%s\".", client, GetSongByIndex(songId).szSongName);
	g_SongsData.Erase(songId);
	
	char szSectionName[8];
	int iStartPosition = songId;
	
	kv.GotoFirstSubKey();
	
	do {
		kv.GetSectionName(szSectionName, sizeof(szSectionName));
		
		if (StringToInt(szSectionName) < songId) {
			continue;
		}
		
		IntToString(iStartPosition, szKey, sizeof(szKey));
		kv.SetSectionName(szKey);
		iStartPosition++;
	} while (kv.GotoNextKey());
	
	kv.Rewind();
	kv.SetSectionName("Songs"); // In case it will be changed by the index fixer
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

//================================[ Timer ]================================//

Action Timer_PlaySong(Handle timer, DataPack dPack)
{
	int client = GetClientFromSerial(dPack.ReadCell());
	
	if (!client)
	{
		return Plugin_Continue;
	}
	
	Song SongData; SongData = GetSongByIndex(dPack.ReadCell());
	
	char szSettingValue[16];
	
	JB_GetClientSetting(client, g_iSettingId, szSettingValue, sizeof(szSettingValue));
	
	float volume = StringToFloat(szSettingValue);
	if (volume > 0.0)
	{
		char szSongPath[PLATFORM_MAX_PATH];
		Format(szSongPath, sizeof(szSongPath), "/%s/%s%s", SOUNDS_DIR, SongData.szSongFile, StrEqual(GetFileExt(SongData.szSongFile), "mp3") ? "" : ".mp3");
		
		//FakeClientCommand(client, "playvol %s %f", szSongPath, volume);
		EmitSoundToClient(client, szSongPath, SOUND_FROM_PLAYER, SNDCHAN_REPLACE, SNDLEVEL_NONE, SND_CHANGEVOL, volume, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true);
		//EmitSoundToClient(client, szSongPath, SOUND_FROM_PLAYER, .volume = (fSettingVolume == 1.0 ? 0.9 : fSettingVolume));
		
		if (dPack.ReadCell())
		{
			PrintToChat(client, " \x06♪\x01 \x0E%s \x06𝄞\x01", SongData.szSongName);
		}
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetSongByName(const char[] name)
{
	return g_SongsData.FindString(name);
}

any[] GetSongByIndex(int index)
{
	Song SongData;
	g_SongsData.GetArray(index, SongData, sizeof(SongData));
	return SongData;
}

void LoadAndPrecacheSongs()
{
	char szFilePath[PLATFORM_MAX_PATH];
	
	for (int iCurrentSong = 0; iCurrentSong < g_SongsData.Length; iCurrentSong++)
	{
		szFilePath = GetSongByIndex(iCurrentSong).szSongFile;
		
		Format(szFilePath, sizeof(szFilePath), "sound/%s/%s%s", SOUNDS_DIR, szFilePath, StrEqual(GetFileExt(szFilePath), "mp3") ? "" : ".mp3");
		AddFileToDownloadsTable(szFilePath);
		
		PrecacheSound(szFilePath[5]); // idx 5 to include the slash (/)
	}
}

void StopMusicToClient(int client)
{
	ClientCommand(client, "snd_playsounds Music.StopAllExceptMusic");
}

char[] GetFileExt(const char[] filePath)
{
	char ext[8];
	
	for (int current_char = strlen(filePath); current_char && filePath[current_char] != '.'; current_char--)
	{
		Format(ext, sizeof(ext), "%c%s", filePath[current_char], ext);
	}
	
	return ext;
}

/**
 * Return true if the client's steam account id matched one of specified authorized clients.
 * See g_AuthorizedGroups
 * 
 */
bool IsClientAllowed(int client)
{
	char client_group[32];
	GetAdminGroup(GetUserAdmin(client), 0, client_group, sizeof(client_group));
	
	for (int current_group = 0; current_group < sizeof(g_AuthorizedGroups); current_group++)
	{
		if (StrEqual(client_group, g_AuthorizedGroups[current_group], true))
		{
			return true;
		}
	}
	
	return false;
}

//================================================================//