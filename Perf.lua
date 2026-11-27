-- Guild Union - medidor de tirones dentro del juego (/gu perf) [+ARCHITECTURE.md]
local ADDON_NAME, HU = ...
local L = HU.L

local Perf = {}
HU.Perf = Perf

Perf.FRAME_MS = 30     -- fotograma con tirón: el addon tardó esto o más en él
Perf.JUMP_KB = 1024    -- pico de memoria: la memoria de Lua creció esto o más de un fotograma al siguiente
Perf.KEEP = 10         -- peores fotogramas y picos que se guardan
Perf.MAX_LABELS = 400  -- causas distintas que se apuntan (el resto va a «(otros)»)
Perf.TOP = 15          -- causas que salen en el informe

local clock = debugprofilestop
local function Heap() return collectgarbage("count") end

local on = false
local origSafeCall, origAfter
local depth = 0
local stats, nLabels = {}, 0
local slow, spikes = {}, {}
local slowCount, spikeCount, frames = 0, 0, 0
local over4 = 0 -- fotogramas en los que el addon tardó más de 4 ms (para el vigilante del modo sencillo)
local startT, startClock, lastHeap, peakHeap
-- lo de este fotograma
local fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil

-- nombre de la función: archivo:línea (una vez por función; si el juego no tiene debug.getinfo, nada)
local names = setmetatable({}, { __mode = "k" })
local getinfo = type(debug) == "table" and type(debug.getinfo) == "function" and debug.getinfo or nil
local function FnName(fn)
    local n = names[fn]
    if n ~= nil then return n end
    n = false
    if getinfo then
        local ok, info = pcall(getinfo, fn, "S")
        if ok and type(info) == "table" and type(info.short_src) == "string" then
            n = (info.short_src:match("([^/\\]+)$") or info.short_src) .. ":" .. tostring(info.linedefined or "?")
        end
    end
    names[fn] = n
    return n
end

-- sin debug.getinfo: el origen del temporizador se toma al crearlo (solo con el medidor encendido)
local function Origin()
    if not debugstack then return nil end
    local s = debugstack(3, 1, 0) or ""
    local file, line = s:match("([^/\\]+%.lua)%]?:(%d+)")
    return file and (file .. ":" .. line) or nil
end

local function Label(where, fn, a, b)
    local label = tostring(where)
    if where == "CHAT_MSG_ADDON" then
        if type(a) == "string" and a:sub(1, 4) == "HU20" then
            -- (el tipo, con «~» detrás o solo, como HY, RQ, PA, CQ, PQ, NK; igual que lo lee Net/Security.lua)
            local kind = type(b) == "string" and (b:match("^(%u%u?)~") or b:match("^(%u%u?)$"))
            label = label .. " " .. a .. " " .. (kind or "?")
        else
            label = label .. " (otros addons)"
        end
    end
    local name = type(fn) == "function" and FnName(fn)
    if name then label = label .. " " .. name end
    return label
end

local function Keep(list, item, field)
    list[#list + 1] = item
    table.sort(list, function(x, y) return x[field] > y[field] end)
    while #list > Perf.KEEP do table.remove(list) end
end

local function Account(label, ms, kb)
    local s = stats[label]
    if not s then
        if nLabels >= Perf.MAX_LABELS then
            label = "(otros)"
            s = stats[label]
        end
        if not s then
            s = { n = 0, ms = 0, max = 0, kb = 0 }
            stats[label] = s
            nLabels = nLabels + 1
        end
    end
    s.n, s.ms, s.kb = s.n + 1, s.ms + ms, s.kb + kb
    if ms > s.max then s.max = ms end
    fMs, fKB = fMs + ms, fKB + kb
    if ms > fTopMs then fTop, fTopMs = label, ms end
    if kb > fTopKB then fTopKBLabel, fTopKB = label, kb end
end

-- HU:SafeCall medido: solo la llamada de fuera (las de dentro ya cuentan en ella)
local function TimedSafeCall(self, where, fn, ...)
    if depth > 0 then return origSafeCall(self, where, fn, ...) end
    depth = 1
    local k0, t0 = Heap(), clock()
    local ok = origSafeCall(self, where, fn, ...)
    local ms, kb = clock() - t0, Heap() - k0
    depth = 0
    if kb < 0 then kb = 0 end -- (el recolector de basura pasó por medio)
    local a, b = ...
    Account(Label(where, fn, a, b), ms, kb)
    return ok
end

local function WrapTimer(fn, origin)
    if not origin or getinfo then return fn end
    if names[fn] == nil then names[fn] = origin end
    return fn
end
local function TimedAfter(delay, fn) return origAfter(delay, WrapTimer(fn, Origin())) end

local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function()
    frames = frames + 1
    local now = time()
    if fMs > 4 then over4 = over4 + 1 end
    if fMs >= Perf.FRAME_MS then
        slowCount = slowCount + 1
        Keep(slow, { t = now, ms = fMs, label = fTop or "?", lms = fTopMs }, "ms")
    end
    local h = Heap()
    if lastHeap and h - lastHeap >= Perf.JUMP_KB then
        spikeCount = spikeCount + 1
        Keep(spikes, { t = now, kb = h - lastHeap, ours = fKB, label = fTopKBLabel or "-", lkb = fTopKB }, "kb")
    end
    lastHeap = h
    if not peakHeap or h > peakHeap then peakHeap = h end
    fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil
end)

function Perf.Reset()
    wipe(stats); wipe(slow); wipe(spikes)
    nLabels, slowCount, spikeCount, frames, over4 = 0, 0, 0, 0, 0
    startT, startClock, lastHeap, peakHeap = time(), clock(), nil, nil
    fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil
end

function Perf.Start()
    if on then return end
    on = true
    -- (lo que se repite ya va por HU:Every, que lleva su propia cuenta: ver HU:TaskLines)
    origSafeCall, origAfter = HU.SafeCall, HU.After
    HU.SafeCall, HU.After = TimedSafeCall, TimedAfter
    Perf.Reset()
    updater:Show()
    if HU.db then HU.db.perfOn = true end
end

function Perf.Stop()
    if not on then return end
    Perf.SaveSummary()
    on = false
    updater:Hide()
    -- (solo se devuelve lo nuestro si nadie lo ha cambiado después)
    if HU.SafeCall == TimedSafeCall then HU.SafeCall = origSafeCall end
    if HU.After == TimedAfter then HU.After = origAfter end
    if HU.db then HU.db.perfOn = nil end
end

function Perf.IsOn() return on end
-- (nil si el medidor está apagado)
function Perf.Over4() return on and over4 or nil end

local function Minutes() return startClock and (clock() - startClock) / 60000 or 0 end

-- lo único que se guarda: un resumen corto de la última sesión medida
function Perf.SaveSummary()
    if not on or not HU.db then return end
    local top, topMs
    for label, s in pairs(stats) do
        if not topMs or s.ms > topMs then top, topMs = label, s.ms end
    end
    HU.db.perfLast = {
        t = time(), v = HU.version, min = math.floor(Minutes() + 0.5), frames = frames,
        slow = slowCount, worst = slow[1] and math.floor(slow[1].ms + 0.5) or 0, worstWhat = slow[1] and slow[1].label or nil,
        spikes = spikeCount, spikeKB = spikes[1] and math.floor(spikes[1].kb) or 0,
        top = top, topMs = topMs and math.floor(topMs + 0.5) or 0,
    }
end

local function Clock(t) return date("%H:%M:%S", t) end
local function Ms(x) return string.format("%.1f", x) end

---------------------------------------------------------------------------
-- Siempre encendido: la CPU del addon según el juego y los FPS, una muestra cada 5 s, solo en RAM [+ARCHITECTURE.md]
---------------------------------------------------------------------------
Perf.SAMPLE_EVERY = 5   -- segundos entre muestras
Perf.CPU_HIGH = 3       -- % de CPU del addon que ya cuenta como alto
Perf.FPS_WINDOW = 600   -- los FPS más bajos de este rato (10 min)
local RING = Perf.FPS_WINDOW / Perf.SAMPLE_EVERY -- (120 muestras)
local RATE_N = 60 / Perf.SAMPLE_EVERY + 1        -- (13: la de hace un minuto y la de ahora)

local cpuNow, cpuMax, cpuMaxT, cpuHigh, cpuN = nil, nil, nil, 0, 0
local fpsNow, fpsMin, fpsMinT, fpsSum, fpsN = nil, nil, nil, 0, 0
local fpsV, fpsT, fpsI = {}, {}, 0                -- las del último rato, en rueda
local rateO, rateI, rateT, rateK = {}, {}, {}, 0  -- mensajes salidos y llegados hasta cada muestra, en rueda

-- (un número del juego que se puede usar: ni secreto, ni NaN, ni negativo)
local function Num(ok, v)
    if ok and type(v) == "number" and v == v and v >= 0 and not HU.Secret(v) then return v end
    return nil
end

-- El medidor de addons del juego y sus datos (Enum.AddOnProfilerMetric), o nil si no lo hay o está apagado
local function Profiler()
    local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if type(P) ~= "table" or type(M) ~= "table" or type(P.IsEnabled) ~= "function" then return nil end
    local ok, enabled = pcall(P.IsEnabled)
    if not (ok and HU.SafeBool(enabled, false)) then return nil end
    return P, M
end

-- % de CPU del addon en ese dato, como el menú del juego (AddonListMixin:GetAddonMetricPercent): lo del addon
-- frente a todo lo que no es de los otros addons. nil si no hay dato
local function CpuPct(P, metric)
    if metric == nil then return nil end
    local app = Num(pcall(P.GetApplicationMetric, metric))
    local all = Num(pcall(P.GetOverallMetric, metric))
    local mine = Num(pcall(P.GetAddOnMetric, ADDON_NAME, metric))
    if not (app and all and mine) then return nil end
    local total = app - all + mine
    if total <= 0 then return nil end
    return math.min(100, 100 * mine / total)
end
-- (un dato del addon tal cual, en ms o en veces, si el juego lo tiene)
local function AddonMetric(P, metric)
    if metric == nil then return nil end
    return Num(pcall(P.GetAddOnMetric, ADDON_NAME, metric))
end

-- (sin crear tablas ni textos: solo números en sitios que ya existen)
local function Sample()
    local now = time()
    local P, M = Profiler()
    cpuNow = P and CpuPct(P, M.RecentAverageTime) or nil
    if cpuNow then
        cpuN = cpuN + 1
        if cpuNow >= Perf.CPU_HIGH then cpuHigh = cpuHigh + 1 end
        if not cpuMax or cpuNow > cpuMax then cpuMax, cpuMaxT = cpuNow, now end
    end
    fpsNow = GetFramerate and Num(true, GetFramerate()) or nil
    if fpsNow then
        fpsSum, fpsN = fpsSum + fpsNow, fpsN + 1
        if not fpsMin or fpsNow < fpsMin then fpsMin, fpsMinT = fpsNow, now end
        fpsI = fpsI % RING + 1
        fpsV[fpsI], fpsT[fpsI] = fpsNow, now
    end
    local np = HU.netPerf
    rateK = rateK % RATE_N + 1
    rateO[rateK], rateI[rateK], rateT[rateK] = np.sentN, np.gotN, GetTime()
end

-- Los FPS más bajos del último rato (Perf.FPS_WINDOW) y su hora
function Perf.FpsLow()
    local now, low, lowT = time(), nil, nil
    for i = 1, #fpsV do
        if now - fpsT[i] <= Perf.FPS_WINDOW and (not low or fpsV[i] < low) then low, lowT = fpsV[i], fpsT[i] end
    end
    return low, lowT
end

-- Mensajes del addon por minuto que salen y que entran, en el último minuto (nil hasta tener dos muestras)
function Perf.MsgRates()
    if rateK == 0 then return nil end
    local old = rateK % RATE_N + 1
    if rateT[old] == nil then old = 1 end -- (aún no ha pasado un minuto: desde la primera)
    local dt = rateT[rateK] - rateT[old]
    if dt <= 0 then return nil end
    return (rateO[rateK] - rateO[old]) * 60 / dt, (rateI[rateK] - rateI[old]) * 60 / dt
end

-- Lo medido, para /gu carga (Report.lua): CPU ahora y la más alta (%), FPS ahora y los más bajos del último rato, y
-- mensajes por minuto que salen y entran. nil lo que no se sabe (sin medidor del juego, aún sin muestras)
function HU:PerfNow()
    local out, inn = Perf.MsgRates()
    return cpuNow, cpuMax, fpsNow, (Perf.FpsLow()), out, inn
end

local function Pct(x) return x and string.format("%.1f %%", x) or "-" end
local function Whole(x) return x and tostring(math.floor(x + 0.5)) or "-" end
local function At(t) return t and Clock(t) or "-" end

-- La parte de /gu perf que siempre se mide
function Perf.LoadLines()
    local out = { L("-- CPU y FPS (siempre: una muestra cada 5 s desde que entraste) --") }
    local P, M = Profiler()
    if not P then
        out[#out + 1] = L("CPU de GuildUnion: sin medidor del juego.")
    else
        out[#out + 1] = string.format(L("CPU de GuildUnion, como la lista de addons del juego: ahora %s · la más alta %s (%s) · muestras de %d %% o más: %d de %d"),
            Pct(cpuNow), Pct(cpuMax), At(cpuMaxT), Perf.CPU_HIGH, cpuHigh, cpuN)
        local peak, over5, over10 = AddonMetric(P, M.PeakTime), AddonMetric(P, M.CountTimeOver5Ms), AddonMetric(P, M.CountTimeOver10Ms)
        if peak or over5 or over10 then
            out[#out + 1] = string.format(L("Lo que cuenta el juego desde que arrancó: el fotograma más lento del addon %s ms · fotogramas de más de 5 ms: %s · de más de 10 ms: %s"),
                peak and Ms(peak) or "-", Whole(over5), Whole(over10))
        end
    end
    local low, lowT = Perf.FpsLow()
    out[#out + 1] = string.format(L("FPS: ahora %s · los más bajos en 10 min: %s (%s) · en la sesión: %s (%s) · media %s"),
        Whole(fpsNow), Whole(low), At(lowT), Whole(fpsMin), At(fpsMinT), Whole(fpsN > 0 and fpsSum / fpsN or nil))
    return out
end

-- La línea de /gu informe («== SESIÓN ==», Report.lua)
function HU:PerfSessionLine()
    local cpu = L("sin medidor del juego")
    if Profiler() then
        cpu = string.format(L("ahora %s · la más alta %s (%s) · %d de %d muestras de %d %% o más"),
            Pct(cpuNow), Pct(cpuMax), At(cpuMaxT), cpuHigh, cpuN, Perf.CPU_HIGH)
    end
    local low, lowT = Perf.FpsLow()
    return string.format(L("CPU del addon según el juego: %s · FPS: ahora %s · mín. 10 min %s (%s) · mín. sesión %s (%s) · media %s"),
        cpu, Whole(fpsNow), Whole(low), At(lowT), Whole(fpsMin), At(fpsMinT), Whole(fpsN > 0 and fpsSum / fpsN or nil))
end

function Perf.Report()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    Add(HU.ADDON_TITLE .. " " .. tostring(HU.version) .. " - " .. L("medidor de tirones") .. " - " .. date("%d/%m/%Y %H:%M"))
    if not on then
        Add(L("El medidor está apagado. Enciéndelo con /gu perf on y juega un rato."))
        -- (lo de siempre, aunque esté apagado)
        Add("")
        for _, l in ipairs(Perf.LoadLines()) do Add(l) end
        local p = HU.db and HU.db.perfLast
        if p then
            Add("")
            Add(L("Última sesión medida") .. " (" .. date("%d/%m %H:%M", p.t) .. ", " .. tostring(p.min) .. " min): "
                .. string.format(L("%d tirones (peor %d ms), %d picos de memoria (mayor %d KB)"), p.slow or 0, p.worst or 0, p.spikes or 0, p.spikeKB or 0))
            if p.worstWhat then Add(L("Peor tirón: ") .. p.worstWhat) end
            if p.top then Add(L("Lo que más tiempo se llevó: ") .. p.top .. " (" .. tostring(p.topMs) .. " ms)") end
        end
        return table.concat(lines, "\n")
    end
    Add(string.format(L("Encendido desde las %s (%d min). Fotogramas medidos: %d."), Clock(startT), math.floor(Minutes() + 0.5), frames))
    Add("")
    if slowCount == 0 and spikeCount == 0 then
        Add(L("VEREDICTO: el addon no ha dado ningún tirón."))
    else
        Add(string.format(L("VEREDICTO: %d tirones del addon (fotogramas de %d ms o más) y %d picos de memoria (%d KB o más)."),
            slowCount, Perf.FRAME_MS, spikeCount, Perf.JUMP_KB))
    end
    Add(string.format(L("Memoria de Lua más alta vista: %.1f MB (de todos los addons juntos)."), (peakHeap or Heap()) / 1024))
    Add("")
    for _, l in ipairs(Perf.LoadLines()) do Add(l) end
    if #slow > 0 then
        Add("")
        Add(L("-- Peores fotogramas (hora, ms del addon, qué se llevó más) --"))
        for _, e in ipairs(slow) do Add(Clock(e.t) .. "  " .. Ms(e.ms) .. " ms  " .. e.label .. " (" .. Ms(e.lms) .. " ms)") end
    end
    if #spikes > 0 then
        Add("")
        Add(L("-- Picos de memoria (hora, subida total, lo que hizo el addon) --"))
        for _, e in ipairs(spikes) do
            Add(Clock(e.t) .. "  +" .. math.floor(e.kb) .. " KB  " .. L("del addon: ") .. math.floor(e.ours) .. " KB  " .. e.label .. " (" .. math.floor(e.lkb) .. " KB)")
        end
        Add(L("(Si «del addon» es pequeño, la subida la causó otro addon o el juego.)"))
    end
    local list = {}
    for label, s in pairs(stats) do list[#list + 1] = { label = label, s = s } end
    table.sort(list, function(x, y) return x.s.ms > y.s.ms end)
    if #list > 0 then
        Add("")
        Add(L("-- Lo que más tiempo se lleva (veces, ms en total, ms la peor, KB) --"))
        for i = 1, math.min(Perf.TOP, #list) do
            local e = list[i]
            Add(e.s.n .. "x  " .. Ms(e.s.ms) .. "  " .. Ms(e.s.max) .. "  " .. math.floor(e.s.kb) .. "  " .. e.label)
        end
    end
    Add("")
    Add(L("-- Tareas que se repiten (HU:Every), desde que entraste --"))
    for _, l in ipairs(HU:TaskLines()) do Add(l) end
    Add("")
    Add(L("(Mide eventos, temporizadores e inicio del addon; no el dibujo de las ventanas.)"))
    return table.concat(lines, "\n")
end

local function Short()
    if slowCount == 0 and spikeCount == 0 then return L("sin tirones del addon") .. " (" .. math.floor(Minutes() + 0.5) .. " min)" end
    return string.format(L("%d tirones (peor %d ms), %d picos de memoria"), slowCount, slow[1] and math.floor(slow[1].ms + 0.5) or 0, spikeCount)
end

-- /gu perf [on | off | reset]
function HU:PerfCommand(arg)
    arg = arg or ""
    if arg == "on" or arg == "encender" then
        Perf.Start()
        self:Print(L("Medidor de tirones encendido. Juega normal y escribe /gu perf para ver el resultado (/gu perf off para apagarlo)."))
    elseif arg == "off" or arg == "apagar" then
        if on then self:Print(L("Medidor apagado: ") .. Short()) else self:Print(L("El medidor está apagado.")) end
        Perf.Stop()
    elseif arg == "reset" or arg == "borrar" then
        if on then Perf.Reset() end
        self:Print(L("Medidor puesto a cero."))
    else
        if on then
            Perf.SaveSummary()
            self:Print(L("Medidor: ") .. Short())
        end
        if HU.UI and HU.UI.ShowCopy then HU.UI:ShowCopy(L("Medidor de tirones (Ctrl+C y mándaselo a quien lleva el addon)"), Perf.Report())
        else for l in Perf.Report():gmatch("[^\n]+") do self:Print(l) end end
    end
end

-- si estaba encendido antes de /reload, sigue encendido; al salir se guarda el resumen
HU:OnStart(function() if HU.db and HU.db.perfOn then Perf.Start() end end)
HU:On("PLAYER_LOGOUT", function() Perf.SaveSummary() end)
-- (la CPU y los FPS, siempre; también en combate, que es cuando más importa)
HU:OnStart(function() HU:Every(Perf.SAMPLE_EVERY, "cpu-fps", Sample) end)

-- textos en inglés
local E = HU.EN
if E then
    E["medidor de tirones"] = "stutter meter"
    E["El medidor está apagado. Enciéndelo con /gu perf on y juega un rato."] = "The meter is off. Turn it on with /gu perf on and play for a while."
    E["Última sesión medida"] = "Last measured session"
    E["%d tirones (peor %d ms), %d picos de memoria (mayor %d KB)"] = "%d stutters (worst %d ms), %d memory spikes (largest %d KB)"
    E["Peor tirón: "] = "Worst stutter: "
    E["Lo que más tiempo se llevó: "] = "Most time spent in: "
    E["Encendido desde las %s (%d min). Fotogramas medidos: %d."] = "On since %s (%d min). Frames measured: %d."
    E["VEREDICTO: el addon no ha dado ningún tirón."] = "VERDICT: the addon caused no stutter."
    E["VEREDICTO: %d tirones del addon (fotogramas de %d ms o más) y %d picos de memoria (%d KB o más)."] = "VERDICT: %d addon stutters (frames of %d ms or more) and %d memory spikes (%d KB or more)."
    E["Memoria de Lua más alta vista: %.1f MB (de todos los addons juntos)."] = "Highest Lua memory seen: %.1f MB (all addons together)."
    E["-- Peores fotogramas (hora, ms del addon, qué se llevó más) --"] = "-- Worst frames (time, addon ms, biggest cause) --"
    E["-- Picos de memoria (hora, subida total, lo que hizo el addon) --"] = "-- Memory spikes (time, total rise, addon's part) --"
    E["del addon: "] = "addon: "
    E["(Si «del addon» es pequeño, la subida la causó otro addon o el juego.)"] = "(If the addon's part is small, another addon or the game caused it.)"
    E["-- Lo que más tiempo se lleva (veces, ms en total, ms la peor, KB) --"] = "-- Most time spent (calls, total ms, worst ms, KB) --"
    E["-- Tareas que se repiten (HU:Every), desde que entraste --"] = "-- Repeating tasks (HU:Every), since you logged in --"
    E["(Mide eventos, temporizadores e inicio del addon; no el dibujo de las ventanas.)"] = "(Measures the addon's events, timers and startup; not window drawing.)"
    E["sin tirones del addon"] = "no addon stutters"
    E["%d tirones (peor %d ms), %d picos de memoria"] = "%d stutters (worst %d ms), %d memory spikes"
    E["Medidor de tirones encendido. Juega normal y escribe /gu perf para ver el resultado (/gu perf off para apagarlo)."] = "Stutter meter on. Play normally and type /gu perf to see the result (/gu perf off to turn it off)."
    E["Medidor apagado: "] = "Meter off: "
    E["El medidor está apagado."] = "The meter is off."
    E["Medidor puesto a cero."] = "Meter reset."
    E["Medidor: "] = "Meter: "
    E["Medidor de tirones (Ctrl+C y mándaselo a quien lleva el addon)"] = "Stutter meter (Ctrl+C and send it to the addon's maintainer)"
    E["-- CPU y FPS (siempre: una muestra cada 5 s desde que entraste) --"] = "-- CPU and FPS (always: one sample every 5 s since you logged in) --"
    E["CPU de GuildUnion: sin medidor del juego."] = "GuildUnion CPU: no game profiler."
    E["CPU de GuildUnion, como la lista de addons del juego: ahora %s · la más alta %s (%s) · muestras de %d %% o más: %d de %d"] = "GuildUnion CPU, as in the game's addon list: now %s · highest %s (%s) · samples of %d %% or more: %d of %d"
    E["Lo que cuenta el juego desde que arrancó: el fotograma más lento del addon %s ms · fotogramas de más de 5 ms: %s · de más de 10 ms: %s"] = "What the game counts since it started: the addon's slowest frame %s ms · frames over 5 ms: %s · over 10 ms: %s"
    E["FPS: ahora %s · los más bajos en 10 min: %s (%s) · en la sesión: %s (%s) · media %s"] = "FPS: now %s · lowest in 10 min: %s (%s) · this session: %s (%s) · average %s"
    E["sin medidor del juego"] = "no game profiler"
    E["ahora %s · la más alta %s (%s) · %d de %d muestras de %d %% o más"] = "now %s · highest %s (%s) · %d of %d samples of %d %% or more"
    E["CPU del addon según el juego: %s · FPS: ahora %s · mín. 10 min %s (%s) · mín. sesión %s (%s) · media %s"] = "Addon CPU according to the game: %s · FPS: now %s · 10 min low %s (%s) · session low %s (%s) · average %s"
end

HU:Module("Perf", { "Core" })
