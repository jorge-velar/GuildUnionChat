-- luacheck para Guild Union. Se ejecuta desde esta carpeta con:  luacheck .
-- (lo pasa el CI en cada push: .github/workflows/ci.yml)
--
-- Sirve sobre todo para cazar:
--   * variables globales creadas sin querer (falta un «local») -> W111
--   * nombres mal escritos de la API del juego o del addon       -> W113
--   * variables que no se usan, código muerto, sombras...         -> W2xx, W4xx
std = "lua51"
max_line_length = false      -- hay líneas largas a propósito
unused_args = false          -- los manejadores de eventos reciben muchos argumentos que no usan
exclude_files = { "Libs/**", "Tools/**", ".git/**", ".claude/**" }

-- Lo que el addon escribe en las variables globales (a propósito)
globals = {
    "GuildUnionDB", "GuildUnionCharDB", "HermandadUnida",
    "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames", "ColorPickerFrame",
    "SLASH_HERMANDADUNIDA1", "SLASH_HERMANDADUNIDA2", "SLASH_HERMANDADUNIDA3", "SLASH_HERMANDADUNIDA4",
    "SLASH_WELOVEPVPLFG1", "SLASH_WELOVEPVPGUILD1",
    "BINDING_HEADER_GUILDUNION", "BINDING_NAME_GUILDUNION_TOGGLE", "GuildUnion_Toggle",
}

-- API de WoW que usa el addon hoy (sacada del propio código, versión 5.4.11). Si usas una función
-- nueva del juego y luacheck avisa con W113, compruébala y añádela aquí.
read_globals = {
    table = { fields = { "unpack" } }, -- (WoW la tiene: table.unpack)
    "Ambiguate", "BackdropTemplateMixin", "CHAT_GUILD_GET", "CHAT_OFFICER_GET", "CLASS_ICON_TCOORDS",
    "C_AddOns", "C_ChatInfo", "C_Club", "C_GuildInfo", "C_Item", "C_PartyInfo", "C_RestrictedActions",
    "C_Spell", "C_SpellBook", "C_Timer", "C_TradeSkillUI", "C_UI", "CanEditGuildInfo", "CanEditOfficerNote",
    "CanGuildDemote", "CanGuildInvite", "CanGuildPromote", "CanGuildRemove", "CanViewOfficerNote",
    "ChannelBan", "ChannelFrame", "ChannelKick", "ChannelModerator", "ChannelMute", "ChannelUnban",
    "ChannelUnmoderator", "ChannelUnmute", "ChatEdit_GetActiveWindow", "ChatEdit_InsertLink",
    "ChatFontNormal", "ChatFrameUtil", "ChatFrame_AddMessageEventFilter", "ChatFrame_AddMessageGroup",
    "ChatFrame_RemoveAllChannels", "ChatFrame_RemoveAllMessageGroups", "ChatFrame_RemoveChannel",
    "ChatFrame_SendTell", "ChatTypeInfo", "ClearOverrideBindings", "ColorPickerFrame", "ConvertToRaid",
    "CreateColor", "CreateFont", "CreateFrame", "DEFAULT_CHAT_FRAME", "ERR_ALREADY_INVITED_TO_GUILD_S",
    "ERR_ALREADY_IN_GUILD_S", "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_GUILD_INVITE_S",
    "ERR_GUILD_PLAYER_NOT_FOUND_S", "Enum", "FCF_OpenNewWindow", "FauxScrollFrame_GetOffset",
    "FauxScrollFrame_OnVerticalScroll", "FauxScrollFrame_Update", "FlashClientIcon",
    "GameFontHighlightSmall", "GameFontNormal", "GameFontNormalSmall", "GameTooltip", "GameTooltip_Hide",
    "GetActiveTalentGroup", "GetAddOnMemoryUsage", "GetAddOnMetadata", "GetBuildInfo",
    "GetChannelDisplayInfo", "GetChannelName", "GetChannelRosterInfo", "GetChatWindowInfo",
    "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftItemLink", "GetCurrentKeyBoardFocus",
    "GetCursorPosition", "GetFramerate", "GetGuildInfo", "GetGuildInfoText", "GetGuildRosterInfo",
    "GetGuildRosterLastOnline", "GetItemInfo", "GetNetStats", "GetNormalizedRealmName",
    "GetNumChannelMembers", "GetNumCrafts", "GetNumDisplayChannels", "GetNumGroupMembers",
    "GetNumGuildMembers", "GetNumSkillLines", "GetNumTalentGroups", "GetNumTalentTabs", "GetNumTradeSkills",
    "GetPlayerInfoByGUID", "GetProfessionInfo", "GetProfessions", "GetRealmName", "GetServerTime",
    "GetSkillLineInfo", "GetSpecialization", "GetSpecializationInfo", "GetSpellInfo", "GetTalentTabInfo",
    "GetTime", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillLine", "GetTradeSkillListLink",
    "GetZoneText", "GuildControlAddRank", "GuildControlDelRank", "GuildControlGetNumRanks",
    "GuildControlGetRankFlags", "GuildControlGetRankName", "GuildControlSaveRank", "GuildControlSetRank",
    "GuildControlSetRankFlag", "GuildDemote", "GuildInvite", "GuildPromote", "GuildRoster",
    "GuildRosterSetOfficerNote", "GuildUnionCharDB", "GuildUnionDB", "InCombatLockdown", "InviteUnit",
    "IsAddOnLoaded", "IsControlKeyDown", "IsGuildLeader", "IsInGroup", "IsInGuild", "IsInInstance",
    "IsInRaid", "IsMetaKeyDown", "IsMouseButtonDown", "IsResting", "IsShiftKeyDown", "JoinTemporaryChannel",
    "LOCALIZED_CLASS_NAMES_MALE", "LeaveChannelByName", "LibStub", "MAX_WOW_CHAT_CHANNELS", "Minimap",
    "NUM_CHAT_WINDOWS", "PlaySound", "RAID_CLASS_COLORS", "ReloadUI",
    "SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM", "SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP", "SOUNDKIT",
    "SendChatMessage", "SetChannelOwner", "SetChannelPassword", "SetGuildInfoText", "SetGuildMemberRank",
    "SetItemRef", "SetOverrideBinding", "SetSelectedDisplayChannel", "ShowUIPanel", "StaticPopup_Show",
    "SwapChatChannelByLocalID", "ToggleCommunitiesFrame", "ToggleGuildFrame", "UIParent", "UnitClass",
    "UnitIsAFK", "UnitLevel", "UnitName", "UnitRace", "UpdateAddOnMemoryUsage", "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_ID", "date", "debugprofilestop", "debugstack", "geterrorhandler", "hooksecurefunc",
    "issecretvalue", "issecurevariable", "strmatch", "time", "tinsert", "wipe",
}
