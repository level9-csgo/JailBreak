#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <shop>

#define PREFIX " \x04[Custom-Icons]\x01"
#define PREFIX_MENU "[Custom-Icons]"

CategoryId g_ShopCategoryID;

int g_iClientIcons[MAXPLAYERS + 1];
int m_nPersonaDataPublicLevel = -1;

public Plugin myinfo = 
{
	name = "[Shop Integrated] Custom Scoreboard Icons", 
	author = "LuqS", 
	description = "Custom 'Levels' (Images / Icons) for client scoreboad with shop integration.", 
	version = "1.0.0", 
	url = "https://github.com/Natanel-Shitrit || https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public void OnPluginStart()
{
	// The offset of 'm_nPersonaDataPublicLevel', This will give us the ability to change the image.
	m_nPersonaDataPublicLevel = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void Shop_Started()
{
	g_ShopCategoryID = Shop_RegisterCategory("scoreboard_icons", "Scoreboard Icons", "Icons that get displayed next to player ping in the scoreboard");
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("CustomIcons");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/shop/custom_icons.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(sFilePath) || !kv.GotoFirstSubKey())
	{
		SetFailState("%s Couldn't load plugin config.", PREFIX_MENU);
	}
	
	int index;
	char name[64], description[64];
	
	// Parse Icons one by one.
	do
	{
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		if ((index = kv.GetNum("index", -1)) != -1 && Shop_StartItem(g_ShopCategoryID, name))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCustomInfo("index", index);
			Shop_SetCallbacks(.use_toggle = OnEquipItem, .preview = OnItemPreview);
			Shop_EndItem();
		}
		
	} while (kv.GotoNextKey());
	
	// Don't leak handles.
	kv.Close();
}

public ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	// If already equiped, just unequip.
	if (isOn)
	{
		g_iClientIcons[client] = -1;
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	// Toggle on the item.
	g_iClientIcons[client] = Shop_GetItemCustomInfo(item_id, "index", -1);
	
	// Player
	return Shop_UseOn;
}

public void OnItemPreview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	PreviewIcon(client, Shop_GetItemCustomInfo(item_id, "index", -1));
}

public void OnMapStart()
{
	// Hooking Resouce Entity
	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);
	
	// Add all icons to the download table
	AddDirectoryToDownloadTable("materials/panorama/images/icons/xp");
}

public void OnThinkPost(int m_iEntity)
{
	SetEntDataArray(m_iEntity, m_nPersonaDataPublicLevel, g_iClientIcons, MAXPLAYERS + 1);
}

public void OnClientDisconnect(int client)
{
	// Reset local variable
	g_iClientIcons[client] = -1;
}

void AddDirectoryToDownloadTable(char[] sDirectory)
{
	char sPath[PLATFORM_MAX_PATH], sFileAfter[PLATFORM_MAX_PATH];
	FileType fileType;
	
	Handle dir = OpenDirectory(sDirectory);
	
	if (dir != INVALID_HANDLE)
	{
		while (ReadDirEntry(dir, sPath, sizeof(sPath), fileType))
		{
			FormatEx(sFileAfter, sizeof(sFileAfter), "%s/%s", sDirectory, sPath);
			if (fileType == FileType_File)
			{
				AddFileToDownloadsTable(sFileAfter);
			}
		}
	}
	
	delete dir;
}

void PreviewIcon(int client, int icon_index, bool isFirstRun = true)
{
	static char sMessage[PLATFORM_MAX_PATH];
	
	Protobuf hMessage = view_as<Protobuf>(StartMessageOne("TextMsg", client));
	
	Format(sMessage, sizeof(sMessage), "</font><img src='file://{images}/icons/xp/level%d.png'/><script>", icon_index);
	
	hMessage.SetInt("msg_dst", 4);
	hMessage.AddString("params", "#SFUI_ContractKillStart");
	hMessage.AddString("params", sMessage);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	
	EndMessage();
	
	// show again so it won't be a small icon!
	if (isFirstRun)
	{
		DataPack dp = new DataPack();
		CreateDataTimer(0.1, Timer_PreviewIconRepeat, dp);
		dp.WriteCell(icon_index);
		dp.WriteCell(client);
		dp.Reset();
	}
}

public Action Timer_PreviewIconRepeat(Handle timer, DataPack dp)
{
	// First cell: client | Second cell: icon index
	PreviewIcon(dp.ReadCell(), dp.ReadCell(), false);
	
	return Plugin_Continue;
} 