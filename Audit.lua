-- Guild Union - registro de oficiales: quién ha hecho qué
local ADDON_NAME, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local seen = {}

local function Clean(s) return (tostring(s or ""):gsub("~", "-")) end

function HU:AuditId(e)
    return HU.Hash((e.tag or "") .. "|" .. self:Short(e.actor or ""):lower() .. "|" .. (e.text or "") .. "|" .. math.floor((e.t or 0) / 120))
end

-- Busca de qué hermandad es alguien
function HU:TagOf(name)
    if not name then return nil end
    local k = self:Key(name)
    if self.roster[k] then return self.myTag end
    if self:IsTest() and k == self:MeKey() then return self.myTag end
    for tag, W in pairs(self.whitelist) do
        if W.set[k] then return tag end
    end
    return nil
end

-- share: nil = solo local, "all" = mi hermandad y las demás, "cross" = solo las demás
function HU:AddAudit(e, share)
    e.t = e.t or time()
    e.id = e.id or self:AuditId(e)
    if seen[e.id] then return end
    seen[e.id] = true
    local list = self.db.audit
    list[#list + 1] = e
    while #list > 1500 do table.remove(list, 1) end
    if self.UI and self.UI.OnAudit then self.UI:OnAudit(e) end
    if share then self:ShareAudit(e, share) end
end

function HU:ShareAudit(e, share)
    if not self.myTag then return end
    local msg = HU.Utf8Cut(table.concat({ "AU", e.id, e.t, e.tag or "", Clean(e.actor), Clean(e.text) }, "~"), 250)
    if share == "all" then self:Send(msg, "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local p = self:BestPeer(tag)
        if p then self:Whisper(p.name, msg) end
    end
end

HU.comm.AU = function(self, sender, f, dist, raw)
    local id, t, tag, actor, text = f[1], HU.NetT(f[2]), f[3], f[4], f[5]
    if not id or not text or seen[id] then return end
    if tag ~= "" and (not self.cfg or not self.cfg.byTag[tag]) then return end
    -- (lo tiene que haber hecho un oficial, y traerlo él o quien reparte: antes cualquiera colaba
    -- "Fulano expulsó a X" en el registro de las 20 hermandades)
    if not actor or actor == "" or not self:MayCarry(actor, sender, dist, tag) or self:TrustedOfficer(actor, tag) ~= true then return end
    text = text:gsub("|", "||"):gsub("[%c]", " ")
    self:AddAudit({ id = id, t = t or time(), tag = tag ~= "" and tag or nil, actor = actor ~= "" and actor or nil, text = text })
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
end

---------------------------------------------------------------------------
-- Rachas (solo en el registro de oficiales): cuando un oficial echa o veta del chat [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local MULTI = { [2] = "DOOOUUUBLEEEE KILL", [3] = "TRIIIPLEEEE KILL", [4] = "QUAAADRAAA KILL", [5] = "PEEENTAAA KILLL" }
local MILESTONES = { [10] = "LEEEGEEENDAAARY", [25] = "GOOODLIIIKE", [50] = "UNSTOOOPPAAABLE", [100] = "BEYOOOND GOOODLIIIKE" }
local chain = { n = 0, t = -999 }

local function KilledToday()
    local today = date("%Y%m%d", time())
    for i = #HU.db.audit, 1, -1 do
        local e = HU.db.audit[i]
        if HU.SafeDate("%Y%m%d", e.t or 0) ~= today then break end
        if e.kill or (e.text or ""):sub(1, 2) == "!!" then return true end
    end
    return false
end

-- kind = "kick" (echar del canal) o "ban" (vetar del chat)
function HU:KillStreak(kind, victim)
    if not self.myTag then return end
    local me, who = self:Me(), self:Short(victim or "?")
    local now = GetTime()
    local first = not KilledToday()
    -- (la propia acción queda marcada para saber si ya hubo alguna hoy)
    local last = self.db.audit[#self.db.audit]
    if last and last.actor == me and (last.text or ""):find(who, 1, true) then last.kill = true end
    if first then
        self:AddAudit({ tag = self.myTag, actor = me, text = "!!FIIIRRRSSTTT BLOOOOOOOD  (" .. who .. ")", kill = true }, "all")
    end
    if now - chain.t <= 30 then chain.n = chain.n + 1 else chain.n = 1 end
    chain.t = now
    local m = MULTI[math.min(chain.n, 5)]
    if chain.n >= 2 and m then
        self:AddAudit({ tag = self.myTag, actor = me, text = "!!" .. m .. "  (" .. who .. ")", kill = true }, "all")
    end
    if kind == "ban" then
        self.db.myBans = (self.db.myBans or 0) + 1
        local ms = MILESTONES[self.db.myBans]
        if ms then
            self:AddAudit({ tag = self.myTag, actor = me, text = "!!" .. ms .. "  (" .. self.db.myBans .. L(" vetos") .. ")", kill = true }, "all")
        end
    end
end

---------------------------------------------------------------------------
-- Mensajes del sistema de la hermandad
---------------------------------------------------------------------------
local function MakePattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local order = {}
    local p = fmt:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
    if fmt:find("%%%d%$s") then
        p = p:gsub("%%(%d)%%%$s", function(d) order[#order + 1] = tonumber(d); return "(.+)" end)
    else
        p = p:gsub("%%s", function() order[#order + 1] = #order + 1; return "(.+)" end)
    end
    return "^" .. p .. "$", order
end

local function Match(text, fmt)
    local pat, order = MakePattern(fmt)
    if not pat then return nil end
    local caps = { text:match(pat) }
    if #caps == 0 then return nil end
    local args = {}
    for i, idx in ipairs(order) do args[idx] = caps[i] end
    return args
end

local SYSTEM = {
    { key = "ERR_GUILD_PROMOTE_SSS", f = function(a) return a[1], L("subió a ") .. a[2] .. L(" a ") .. a[3] end },
    { key = "ERR_GUILD_DEMOTE_SSS",  f = function(a) return a[1], L("bajó a ") .. a[2] .. L(" a ") .. a[3] end },
    { key = "ERR_GUILD_REMOVE_SS",   f = function(a) return a[2], L("expulsó a ") .. a[1] .. L(" de la hermandad") end },
    { key = "ERR_GUILD_LEADER_CHANGED_SS", f = function(a) return a[1], L("nombró maestro de la hermandad a ") .. a[2] end },
    { key = "ERR_GUILD_JOIN_S",      f = function(a) return nil, a[1] .. L(" entró en la hermandad") end },
    { key = "ERR_GUILD_LEAVE_S",     f = function(a) return nil, a[1] .. L(" dejó la hermandad") end },
}

HU:On("CHAT_MSG_SYSTEM", function(text)
    if not HU.myTag or HU:IsTest() or type(text) ~= "string" then return end
    for _, s in ipairs(SYSTEM) do
        local args = Match(text, _G[s.key])
        if args then
            local actor, what = s.f(args)
            HU:AddAudit({ tag = HU.myTag, actor = actor and HU:FullName(actor), text = what },
                HU:IsRelay() and "cross" or nil)
            return
        end
    end
end)

---------------------------------------------------------------------------
-- Avisos del canal (los ven todos los que están en el canal)
---------------------------------------------------------------------------
local NOTICES = HU.LT({
    PLAYER_KICKED   = "echó a %s del canal",
    PLAYER_BANNED   = "vetó a %s del canal",
    PLAYER_UNBANNED = "quitó el veto a %s",
    SET_MODERATOR   = "nombró moderador del canal a %s",
    UNSET_MODERATOR = "quitó de moderador del canal a %s",
    OWNER_CHANGED   = "%s es ahora propietario del canal",
})

HU:On("CHAT_MSG_CHANNEL_NOTICE_USER", function(notice, target, _, fullName, actor, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) ~= "main" then return end
    local fmt = NOTICES[notice]
    if not fmt or not target or target == "" then return end
    local who = (actor and actor ~= "") and HU:FullName(actor) or nil
    if notice == "OWNER_CHANGED" then who = nil end
    HU:AddAudit({ tag = who and HU:TagOf(who), actor = who, text = fmt:format(HU:Short(target)) })
end)

HU:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    HU.db.audit = HU.db.audit or {}
    for _, e in ipairs(HU.db.audit) do if e.id then seen[e.id] = true end end
end)

-- Autores que aparecen en el registro (para filtrar)