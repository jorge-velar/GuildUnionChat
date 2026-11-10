-- Guild Union - configuración de la comunidad en las notas de oficial
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local function NoteLine(note)
    if type(note) ~= "string" then return nil end
    local l = note:match("([Gg][Uu]:[GgTtRr]:.+)$")
    if l then l = HU.Trim(l) end
    return (l and l ~= "") and l or nil
end
HU.NoteConfigLine = NoteLine

-- Junta la configuración de la Información con la de las notas (sin repetir hermandades).
-- (las de las notas solo AÑADEN hermandades bien escritas, Nombre:ETIQ; el título de la Información manda)
function HU.MergeConfigText(info, extra)
    info = HU.SplitGlued(info)
    if not extra or extra == "" then return info end
    extra = HU.SplitGlued(extra)
    local tags, names, hasTitle = {}, {}, false
    for raw in info:gmatch("[^\r\n]+") do
        local l = HU.Trim(raw)
        local kind, rest = l:match("^[Gg][Uu]:(%a):(.*)$")
        if kind then
            kind = kind:lower()
            if kind == "g" then
                local n, t = rest:match("^(.*):([^:]*)$")
                if n then tags[HU.Trim(t):upper()] = true; names[HU.Trim(n):lower()] = true end
            elseif kind == "t" then hasTitle = true end
        end
    end
    local add = {}
    for raw in extra:gmatch("[^\r\n;]+") do
        local l = HU.Trim(raw)
        local kind, rest = l:match("^[Gg][Uu]:(%a):(.*)$")
        if kind then
            kind = kind:lower()
            if kind == "g" then
                local n, t = rest:match("^(.*):([^:]*)$")
                if n and HU.Trim(n) ~= "" and HU.Trim(t):match("^%w+$") and not tags[HU.Trim(t):upper()] and not names[HU.Trim(n):lower()] then
                    add[#add + 1] = l
                    tags[HU.Trim(t):upper()] = true
                    names[HU.Trim(n):lower()] = true
                end
            elseif kind == "t" and not hasTitle then
                add[#add + 1] = l; hasTitle = true
            elseif kind == "r" then
                add[#add + 1] = l
            end
        end
    end
    if #add == 0 then return info end
    return (info ~= "" and (info .. "\n") or "") .. table.concat(add, "\n")
end

-- La llama la lista de la hermandad (solo los oficiales ven las notas) [+ARCHITECTURE.md]
local function InfoHasCommunity()
    local t = HU:GuildInfoText()
    if not t then return nil end
    return t:find("[Gg][Uu]:[Gg]:") ~= nil, t
end
HU.InfoHasCommunity = InfoHasCommunity

function HU:CheckInfoWritten(lines)
    local text = table.concat(lines, "\n")
    local gname = GetGuildInfo and GetGuildInfo("player")
    local function check()
        local has = InfoHasCommunity()
        if has == nil then HU.After(10, check) return end -- (restricción: se mira al acabar)
        if has then HU.db.infoBackup = nil return end
        HU.db.infoBackup = { guild = gname, text = text, t = time() }
        local cur = HU.db.netCfg
        local merged = HU.MergeConfigText(text, HU.noteCfgText or "")
        HU.db.netCfg = { text = merged, t = math.max(HU.StampNow(), (cur and cur.t or 0) + 1), by = HU:Me(), guild = GetGuildInfo and GetGuildInfo("player") }
        HU:ShareNetCfg()
        HU:RefreshConfig(true)
        HU:Print(L("La unión ya funciona (el addon se la pasa a tu hermandad). Para que quede guardada, sustituye la Información de hermandad por el texto de la ventana."))
        if HU.UI and HU.UI.ShowCopy then
            -- (la Información entera, con lo que ya tenía y las líneas de la comunidad: se borra todo y se pega)
            HU.UI:ShowCopy(L("Información de hermandad (J): borra todo lo que hay y pega esto (Ctrl+V)"), HU.joinedText or text)
        end
    end
    HU.After(4, check)
end

function HU:OnNoteConfig(lines)
    -- (si la Información no tiene la comunidad, va también la copia guardada)
    local b = self.db.infoBackup
    if b and b.guild == (GetGuildInfo and GetGuildInfo("player")) then
        if InfoHasCommunity() then self.db.infoBackup = nil
        else -- (sin poder leerla también se usa la copia)
            local merged = HU.MergeConfigText(b.text, table.concat(lines, "\n"))
            lines = {}
            for l in merged:gmatch("[^\n]+") do lines[#lines + 1] = l end
        end
    end
    local text = table.concat(lines, "\n")
    self.noteCfgText = (text ~= "") and text or nil
    if text == "" then return end
    local cur = self.db.netCfg
    if cur and cur.text == text then return end
    self.db.netCfg = { text = text, t = math.max(HU.StampNow(), (cur and cur.t or 0) + 1), by = self:Me(), guild = GetGuildInfo and GetGuildInfo("player") }
    self:ShareNetCfg()
end

function HU:ShareNetCfg(target)
    local n = self.db.netCfg
    if not n or not IsInGuild() then return end
    local body = (n.text:gsub("[\r\n]+", ";"):gsub("~", "-"))
    local chunks = {}
    while #body > 0 do chunks[#chunks + 1] = body:sub(1, 200); body = body:sub(201) end
    for i, c in ipairs(chunks) do
        local msg = table.concat({ "NF", n.t, n.by or "", i, #chunks, c }, "~")
        if target then self:Whisper(target, msg) else self:Send(msg, "GUILD") end
    end
end

local parts = {}
HU.comm.NF = function(self, sender, f, dist)
    if dist ~= "GUILD" and dist ~= "WHISPER" then return end
    -- solo de mi propia hermandad (por susurro, de alguien de mi hermandad)
    local sk = self:Key(sender)
    if dist == "WHISPER" and not (sk and self.roster[sk]) then return end
    local t, by, i, n = HU.NetStamp(f[1]), f[2], tonumber(f[3]), tonumber(f[4])
    if not t or not i or not n or n > 10 or i < 1 or i > n then return end
    local cur = self.db.netCfg
    if cur and (cur.t or 0) >= t then return end
    local key = t .. ":" .. (by or "")
    local p = parts[key] or { got = 0, list = {} }
    parts[key] = p
    if not p.list[i] then p.list[i] = f[5] or ""; p.got = p.got + 1 end
    if p.got < n then return end
    parts[key] = nil
    local text = table.concat(p.list, "", 1, n):gsub(";", "\n")
    -- lo tiene que mandar un oficial de mi hermandad (o el maestro), y tiene que ser QUIEN LO MANDA:
    -- antes valía el nombre escrito en el mensaje, y un raso se hacía oficial con un GU:r falso
    local who = sender
    if by and by ~= "" and self:Key(by) ~= self:Key(sender) then return end
    local k = self:Key(who)
    local e = k and self.roster[k]
    if not e then return end
    if not self:RankRole(self.myTag, e.rankIndex) then return end
    self.db.netCfg = { text = text, t = t, by = who, guild = GetGuildInfo and GetGuildInfo("player") }
    self:RefreshConfig(true)
end

HU.comm.NK = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self:CanOfficer() or not self.db.netCfg then return end
    HU.After(math.random() * 4, function()
        if HU.nfAnswered and GetTime() - HU.nfAnswered < 10 then return end
        HU.nfAnswered = GetTime()
        HU:ShareNetCfg()
    end)
end

local origNF = HU.comm.NF
HU.comm.NF = function(self, sender, f, dist)
    self.nfAnswered = GetTime()
    return origNF(self, sender, f, dist)
end

HU:OnStart(function()
    HU.StampFix(HU.db.netCfg)
    HU.After(25, function()
        if HU:IsTest() or not IsInGuild() or HU:CanOfficer() then return end
        -- solo si la Información dice que hay líneas en notas de oficial y me faltan
        -- (sin nada en la Información: quizá el juego no dejó escribirla; se pide la copia)
        if not HU.cfg then
            if not HU.db.netCfg then HU:Send("NK", "GUILD") end
            return
        end
        local want = HU.cfg.noteLines
        if not want or want < 1 then return end
        local have = 0
        for _ in ((HU.db.netCfg and HU.db.netCfg.text) or ""):gmatch("[Gg][Uu]:%a:[^\n]+") do have = have + 1 end
        if have < want then HU:Send("NK", "GUILD") end
    end)
end)

---------------------------------------------------------------------------
-- Escribir la configuración: en Forever el addon no puede escribir notas de oficial, así que
-- todo va a la Información de hermandad, a mano
---------------------------------------------------------------------------
function HU:WriteCommunityConfig(lines)
    local leftover = {}
    for _, l in ipairs(lines) do leftover[#leftover + 1] = l end
    return {}, leftover
end

-- Que solo los oficiales vean las notas de oficial (lo hace el maestro, en los rangos de
-- miembro). Permiso 11 = "Ver notas de oficial".
function HU:MakeOfficerNotesPrivate()
    if not self:IsMaster() then return false, L("solo el maestro de la hermandad puede cambiar los permisos de los rangos") end
    -- (en Forever un addon no puede cambiar los permisos de los rangos: se explica cómo hacerlo)
    self:Print(L("Para que la contraseña no la vea cualquiera: en la ventana de la hermandad (Rangos), quita «Ver notas de oficial» a los rangos que no sean de oficiales."))
    return false, L("este cliente no deja cambiar los permisos desde un addon")
end
