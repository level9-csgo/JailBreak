#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <rtler>

#define PL_VERSION		"1.0.5"
#define UPDATE_URL		"http://dl.dropbox.com/u/16304603/rtler/updatefile.txt"

ConVar g_cvMinimum;

float minimum = 0.1;

public Plugin myinfo = 
{
	name = "The RTLer", 
	author = "alongub", 
	description = "In-game chat support for RTL languages.", 
	version = PL_VERSION, 
	url = "http://steamcommunity.com/id/alon"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("RTLify", Native_RTLify);
	
	RegPluginLibrary("rtler");
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("rtler_version", PL_VERSION, "RTLer Version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);
	
	g_cvMinimum = CreateConVar("rtler_minimum", "0.1", "Minimum percent of RTL letters for a word's direction to be considered right to left.", _, true, 0.001, true, 1.0);
	HookConVarChange(g_cvMinimum, OnMinimumChange);
	
	AutoExecConfig(true);
}

public void OnMinimumChange(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	minimum = StringToFloat(newValue);
}

int _RTLify(char[] dest, char[] original)
{
	int rtledWords = 0;
	
	char tokens[96][96]; // TODO: This shouldn't be a fixed size.	
	char words[sizeof(tokens)][sizeof(tokens[])];
	
	int n = ExplodeString(original, " ", tokens, sizeof(tokens), sizeof(tokens[]));
	
	for (int word = 0; word < n; word++)
	{
		if (WordAnalysis(tokens[word]) >= minimum)
		{
			ReverseString(tokens[word], sizeof(tokens[]), words[n - 1 - word]);
			rtledWords++;
		}
		else
		{
			int firstWord = word;
			int lastWord = word;
			
			while (WordAnalysis(tokens[lastWord]) < minimum)
			{
				lastWord++;
			}
			
			for (int t = lastWord - 1; t >= firstWord; t--)
			{
				strcopy(words[n - 1 - word], sizeof(tokens[]), tokens[t]);
				
				if (t > firstWord)
					word++;
			}
		}
	}
	
	ImplodeStrings(words, n, " ", dest, sizeof(words[]));
	return rtledWords;
}

void ReverseString(char[] str, int maxlength, char[] buffer)
{
	for (int character = strlen(str); character >= 0; character--)
	{
		if (str[character] >= 0xD6 && str[character] <= 0xDE)
			continue;
		
		if (character > 0 && str[character - 1] >= 0xD7 && str[character - 1] <= 0xD9)
			Format(buffer, maxlength, "%s%c%c", buffer, str[character - 1], str[character]);
		else
			Format(buffer, maxlength, "%s%c", buffer, str[character]);
	}
}

float WordAnalysis(char[] word)
{
	int count = 0, length = strlen(word);
	
	for (int n = 0; n < length - 1; n++)
	{
		if (IsRTLCharacter(word, n))
		{
			count++;
			n++;
		}
	}
	
	return float(count) * 2 / length;
}

bool IsRTLCharacter(char[] str, int n)
{
	return (str[n] >= 0xD6 && str[n] <= 0xDE && str[n + 1] >= 0x80 && str[n + 1] <= 0xBF);
}

public int Native_RTLify(Handle plugin, int params)
{
	int destLen = GetNativeCell(2);
	char[] dest = new char[destLen];
	
	int originalLen = destLen;
	GetNativeStringLength(3, originalLen);
	
	char[] original = new char[originalLen];
	GetNativeString(3, original, originalLen + 1);
	
	int amount = _RTLify(dest, original);
	SetNativeString(1, dest, destLen, true);
	
	return amount;
} 