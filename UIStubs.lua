-- Guild Union Reduce - sin el panel grande: quitados UIMembers, UIChat, UIOfficers y UIInfo. [+ARCHITECTURE.md]
local _, HU = ...
local UI = HU.UI
-- (el banco carga el addon sin UI.lua: entonces no hay panel que rellenar)
if not UI then return end

local function Nothing() end
for _, name in ipairs({
    "FillChat", "OnChat", "RefreshChatTabs", "UpdateOfficers", "OnAudit",
    "SetChatFont", "SetChatFontSize", "UpdateUndockButtons", "BuildChat", "BuildMembers", "BuildOfficers",
    "ApplySides", "UpdateMembers", "RebuildMembers", "InvalidateGather", "UpdateRoster", "SetOfficerMode",
    "UpdateIntruders", "UpdateGuildsWindow",
}) do
    if UI[name] == nil then UI[name] = Nothing end
end
