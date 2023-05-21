#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"
#define CONFIG_PATH "configs/FilesPaths.cfg"

char g_szValidFormats[][] = 
{
	"mdl", "phy", "vtx", "vvd",  // Model Files
	"vmt", "vtf", "png", "jpg",  // Texture And Material Files
	"mp3", "wav", "m4a" // Sound Files
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Files Manager", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	SetupConfigLoad();
}

/*  */

/* Events */

public void OnMapStart()
{
	SetupConfigLoad();
}

/*  */

/* Functions */

void SetupConfigLoad()
{
	char szDirPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, szDirPath, sizeof(szDirPath), CONFIG_PATH);
	File hFile = OpenFile(szDirPath, "a+");
	LoadFilesPaths(hFile);
	delete hFile;
}

void LoadFilesPaths(File hFile)
{
	char szFilePath[PLATFORM_MAX_PATH];
	while (!IsEndOfFile(hFile) && ReadFileLine(hFile, szFilePath, sizeof(szFilePath)))
	{
		TrimString(szFilePath);
		
		if (szFilePath[0] != '\0' && (szFilePath[0] != '/' && szFilePath[1] != '/'))
		{
			if (StrContains(szFilePath, "/*", true) != -1 && StrContains(szFilePath, "*/", true) != -1)
			{
				for (int iCurrentChar = 0; iCurrentChar < sizeof(szFilePath); iCurrentChar++) {
					ReplaceString(szFilePath, sizeof(szFilePath), szFilePath[iCurrentChar], "");
				}
			}
			
			AddFileToDownloadsTable(szFilePath);
			
			for (int iCurrentCode = 0; iCurrentCode < sizeof(g_szValidFormats); iCurrentCode++)
			{
				if (!StrEqual(GetFileExt(szFilePath), g_szValidFormats[iCurrentCode])) {
					continue;
				}
				
				char szFilePartentDir[16]; szFilePartentDir = GetFileParentDir(szFilePath);
				if (StrEqual(szFilePartentDir, "models") && StrEqual(GetFileExt(szFilePath), "mdl")) {
					ReplaceString(szFilePath, sizeof(szFilePath), "models/", "");
					PrecacheModel(szFilePath);
				}
				
				if (StrEqual(szFilePartentDir, "materials") && (StrEqual(GetFileExt(szFilePath), "vmt") && StrEqual(GetFileExt(szFilePath), "vtf"))) {
					ReplaceString(szFilePath, sizeof(szFilePath), "materials/", "");
					PrecacheGeneric(szFilePath);
				}
				
				if (StrEqual(szFilePartentDir, "particles") && StrEqual(GetFileExt(szFilePath), "pcf")) {
					ReplaceString(szFilePath, sizeof(szFilePath), "particles/", "");
					PrecacheGeneric(szFilePath);
				}
				
				if (StrEqual(szFilePartentDir, "sound") && (StrEqual(GetFileExt(szFilePath), "mp3") || StrEqual(GetFileExt(szFilePath), "wav") || StrEqual(GetFileExt(szFilePath), "m4a"))) {
					ReplaceString(szFilePath, sizeof(szFilePath), "sound/", "");
					PrecacheSound(szFilePath);
				}
			}
		}
	}
}

char[] GetFileExt(const char[] path)
{
	char buffer[8];
	
	int idx = FindCharInString(path, 'c', true);
	if (idx != -1)
	{
		strcopy(buffer, sizeof(buffer), path[idx]);
	}
	
	return buffer;
}

char[] GetFileParentDir(const char[] filePath)
{
	char szParentDir[16];
	for (int iCurrentChar = 0; iCurrentChar < strlen(filePath); iCurrentChar++)
	{
		if (filePath[iCurrentChar] == '/')
			break;
		Format(szParentDir, sizeof(szParentDir), "%s%c", szParentDir, filePath[iCurrentChar]);
	}
	return szParentDir;
}

/*  */