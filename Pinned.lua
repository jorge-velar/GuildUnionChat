-- Guild Union - mensaje fijado por los oficiales (encima del chat)
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local function Clean(s) return (tostring(s or ""):gsub("[~\r\n]", " ")) end

-- Pueden fijar el maestro y los oficiales (y cualquiera en modo prueba)
-- Modo prueba "como miembro": para ver el addon como lo ve alguien que no es oficial
function HU:CanPin()
    if not self.myTag then return false end
    local idx = self:MyRankIndex()
    if idx and self:RankRole(self.myTag, idx) then return true end
    return self:CanManageRanks()
end

-- ¿Soy el maestro de mi hermandad?
function HU:IsMaster()
    if IsGuildLeader and IsGuildLeader() then return true end
    return self:MyRankIndex() == 0
end

-- Bytes que caben para el texto del fijado (el mensaje entero, cabecera incluida, va en 254)
local function PinMsg(p)
    return HU.Utf8Cut(table.concat({ "PN", p.t or 0, p.author or "", p.tag or "", Clean(p.text) }, "~"), 254)
end

function HU:SharePinned(target)
    local p = self.db.pinned
    if not p or not self.myTag then return end
    if target then return self:Whisper(target, PinMsg(p)) end
    local msg = PinMsg(p)
    self:Send(msg, "GUILD")
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(tag)
        if peer then self:Whisper(peer.name, msg) end
    end
end

-- Poner (o quitar, con texto vacío) el mensaje fijado: lo reciben todas las hermandades
-- (/gu fijar texto  ·  /gu fijar borrar)
local PIN_MAX = 200
function HU:SetPinned(text)
    if not self:CanPin() then return self:Print(L("Solo el maestro y los oficiales pueden fijar un mensaje.")) end
    text = Clean(HU.Trim(text or ""))
    if #text > PIN_MAX then
        text = HU.Utf8Cut(text, PIN_MAX)
        self:Print(L("El mensaje era demasiado largo: se ha cortado a ") .. PIN_MAX .. L(" letras."))
    end
    self.db.pinned = { text = text, author = self:Me(), tag = self.myTag, t = HU.StampNow() }
    self:SharePinned()
    self:Changed("pinned")
    if self.UI and self.UI.UpdatePinned then self.UI:UpdatePinned() end
    self:Print(text ~= "" and L("Mensaje fijado para toda la comunidad.") or L("Mensaje fijado quitado."))
end

HU.comm.PN = function(self, sender, f, dist, raw)
    local t, author, tag, text = HU.NetT(f[1]), f[2], f[3], f[4] or ""
    text = HU.SafeText(text, true)
    if not t or not author then return end
    local cur = self.db.pinned
    if cur and (cur.t or 0) >= t then return end
    -- el autor tiene que ser maestro u oficial conocido de una de las hermandades
    if not self:CheckOfficer(author, tag, function() HU.comm.PN(self, sender, f, dist, raw) end, sender, dist) then return end
    self.db.pinned = { text = text, author = author, tag = (tag ~= "" and tag) or nil, t = t }
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    self:Changed("pinned")
    if self.UI and self.UI.UpdatePinned then
        self.UI:UpdatePinned()
        if text ~= "" and self.UI.FlashPinned then self.UI:FlashPinned() end
    end
end

HU.comm.PQ = function(self, sender)
    if not self.db.pinned then return end
    if self:IsRelay() then return self:SharePinned(sender) end
    -- (el enlace puede no tenerlo, p. ej. si es un miembro que acaba de entrar: lo pasa también
    -- un oficial que lo tenga, un poco después)
    if self:CanPin() then
        HU.After(0.5 + math.random() * 2.5, function() HU:SharePinned(sender) end)
    end
end

HU:OnStart(function()
    HU.After(30, function() if HU.myTag then HU:Send("PQ", "GUILD") end end)
    -- el enlace lo hace llegar también a las otras hermandades de vez en cuando
    HU.NewTicker(300, function()
        if HU.db.pinned and HU.myTag and HU:IsRelay() then
            for _, tag in ipairs(HU:OtherTags()) do
                local peer = HU:BestPeer(tag)
                if peer then HU:SharePinned(peer.name) end
            end
        end
    end)
end)
