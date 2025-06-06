-- BossPullTracker.lua: Lógica central del addon (eventos, persistencia, activaciones de jefes)

-- Crear un frame oculto para gestionar eventos del juego
local eventFrame = CreateFrame("Frame")

-- Registrar eventos relevantes
eventFrame:RegisterEvent("PLAYER_LOGIN")                    -- Cuando el jugador inicia sesión (después de cargar la interfaz)
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")     -- Eventos de combate (para detectar pulls de jefes)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")           -- Carga de mundo (incluye entrar/salir de instancias)
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")           -- Cambio de zona (para detectar cambios de instancia sin cargar pantalla)
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")              -- Cambios en la composición de banda
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")           -- Cambios en la composición de grupo
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")           -- Gritos de NPCs (por si aportan información sobre pulls)

-- Tablas para seguimiento de activaciones de jefes (datos persistentes en SavedVariables)
local bossActivations = {}   -- Diccionario de jefes activados: { [nombreJefe] = nombreJugadorQueLoActivó }
local bossHistoryList = {}   -- Lista cronológica de activaciones (cada elemento = {boss = nombreJefe, player = nombreJugador})

-- Variable para almacenar la última instancia en la que estábamos (para detectar cambios)
local currentInstanceName = nil

-- Función local para determinar si un GUID corresponde a un jefe (NPC jefe) usando la API disponible en 3.3.5a
local function IsBossUnit(guid)
    if not guid then return false end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)  -- GUID tiene formato "tipo-otras-partes-npcID-instanciaID-..."; en WoTLK el tipo "Creature" indica NPC
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return false  -- Solo nos interesan unidades criatura o vehículo (jefes suelen ser criaturas/vehículos controlados por NPC)
    end
    -- Intentar identificar si es un jefe usando información disponible:
    -- Comprobar si nuestro objetivo actual o foco actual coincide con el GUID y verificar su clasificación
    for _, unit in ipairs({"target", "focus"}) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            local classification = UnitClassification(unit)      -- Clasificación de la unidad (ejemplo: "worldboss", "elite", etc.)
            local level = UnitLevel(unit)
            if classification == "worldboss" or level == -1 or level >= UnitLevel("player") + 3 then
                -- Consideramos que es un jefe si está clasificado como worldboss, o si es de nivel calavera (nivel -1) o nivel mucho mayor al del jugador
                return true
            end
        end
    end
    return false
end

-- Definir un diálogo de confirmación estático para borrar datos, que se usará al salir de instancia/grupo
StaticPopupDialogs["BOSSPULLTRACKER_CONFIRM_CLEAR"] = {
    text = "¿Deseas borrar la lista de activaciones de jefes guardada?",  -- Texto del cuadro de diálogo
    button1 = "Sí",
    button2 = "No",
    OnAccept = function(self)
        -- El jugador confirmó el borrado de datos
        ClearPulls()  -- Llama a la función global definida en BossPullTracker_Utils.lua para limpiar datos y UI
        -- Si proporcionamos un nombre de instancia nuevo (self.data) al mostrar el diálogo, significa que estamos entrando a una nueva instancia
        if self.data then
            BossPullTrackerDB.currentInstanceName = self.data
            currentInstanceName = self.data
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3  -- Evitar cierto taint de la UI usando un índice de preferencia no usado por Blizzard
}

-- Función global: Maneja los eventos de combate para detectar activaciones de jefes
function OnCombatLogEvent(timestamp, subEvent, srcGUID, srcName, srcFlags, srcRaidFlags,
                           destGUID, destName, destFlags, destRaidFlags, spellId, spellName)
    -- Filtrar tipos de sub-eventos de combate que no indican inicio de combate real (sanaciones, regeneración de poder, etc.)
    if subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL"
       or subEvent == "SPELL_ENERGIZE" or subEvent == "SPELL_PERIODIC_ENERGIZE" then
        return  -- Ignorar eventos de sanación o regeneración, ya que no inician peleas con jefes
    end
    if subEvent == "UNIT_DIED" then
        return  -- Ignorar muertes (no nos sirven para detectar quién inició el combate, especialmente si es muerte de un jefe u otras unidades)
    end

    -- Verificar si el evento involucra a un jefe atacando o siendo atacado por un jugador
    local bossName, playerName = nil, nil
    -- Caso 1: la FUENTE es un jefe y el DESTINO es un jugador (el jefe inicia atacando a un jugador)
    if IsBossUnit(srcGUID) and bit.band(destFlags or 0, 0x00000400) > 0 then  -- 0x00000400 = COMBATLOG_OBJECT_TYPE_PLAYER
        bossName = srcName      -- Nombre del jefe (fuente del evento)
        playerName = destName   -- Nombre del jugador al que atacó primero el jefe
    -- Caso 2: el DESTINO es un jefe y la FUENTE es un jugador (un jugador ataca al jefe primero)
    elseif IsBossUnit(destGUID) and bit.band(srcFlags or 0, 0x00000400) > 0 then
        bossName = destName     -- Nombre del jefe (destino del evento)
        playerName = srcName    -- Nombre del jugador que inició el ataque
    else
        return  -- Si ninguna combinación es jefe vs jugador, no nos interesa este evento para propósitos de activación
    end

    -- Si ya registramos este jefe en la lista de activaciones actuales, no duplicar la entrada
    if bossActivations[bossName] then
        return
    end

    -- Registrar la activación del jefe:
    bossActivations[bossName] = playerName
    table.insert(bossHistoryList, 1, { boss = bossName, player = playerName })  -- Insertar al inicio para mantener orden descendente (último pull primero)

    -- Actualizar la interfaz gráfica con el nuevo registro (función global definida en BossPullTracker_UI.lua)
    if subEvent == "SPELL_CAST_START" or subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SWING_DAMAGE" then
        if BossPullTrackerDB and BossPullTrackerDB.bossActivations then
            local bossName = bossName or destName or srcName or GetUnitName("target") or "Jefe desconocido"
            local playerName = playerName or srcName or UnitName("player") or "Jugador desconocido"
            local method = (subEvent == "SWING_DAMAGE") and "autoataque" or (spellName or "desconocido")
        
            -- Guardar activación
            table.insert(BossPullTrackerDB.bossActivations, {
                boss = bossName,
                player = playerName,
                method = method,
                time = date("%H:%M:%S")
            })

            -- Actualizar visual
            UpdateBossListUI(bossName, playerName, method)
        end
    end
end

-- Función global: Maneja los cambios de zona/instancia para control de persistencia de datos
function OnZoneChanged()
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        -- Estamos dentro de una instancia de mazmorra o banda
        local zoneName = GetRealZoneText() or "Instancia desconocida"
        if currentInstanceName and zoneName ~= currentInstanceName then
            -- Cambio a una instancia diferente mientras teníamos datos de otra instancia
            -- Preguntar al usuario si desea borrar los datos de la instancia previa, antes de empezar la nueva
            if bossHistoryList and #bossHistoryList > 0 then
                -- Mostrar confirmación; pasamos el nuevo nombre de instancia como data para establecerlo tras el borrado
                StaticPopup_Show("BOSSPULLTRACKER_CONFIRM_CLEAR", nil, nil, zoneName)
            else
                -- Si no hay datos previos (lista vacía), simplemente iniciar nueva instancia
                BossPullTrackerDB.currentInstanceName = zoneName
                currentInstanceName = zoneName
            end
        elseif not currentInstanceName then
            -- Entrando a una instancia por primera vez (no teníamos ninguna activa)
            BossPullTrackerDB.currentInstanceName = zoneName
            currentInstanceName = zoneName
        end
    else
        -- El jugador NO está en una instancia de mazmorra/raid (mundo abierto o ciudad)
        if currentInstanceName then
            -- Si teníamos una instancia en curso y ahora salimos, ofrecer limpiar datos de esa instancia
            if bossHistoryList and #bossHistoryList > 0 then
                StaticPopup_Show("BOSSPULLTRACKER_CONFIRM_CLEAR")  -- Salir a mundo abierto: pedir confirmación para borrar datos
            else
                -- Si la lista estaba vacía, simplemente resetear el nombre de instancia actual
                BossPullTrackerDB.currentInstanceName = nil
                currentInstanceName = nil
            end
        end
    end
end

-- Función global: Maneja los gritos de jefes (opcional, podría usarse para detectar inicios de combate mediante textos)
function OnBossYell(monsterName, message)
    -- Solo procesar si estamos en instancia de grupo/banda
    local inInstance, instType = IsInInstance()
    if not inInstance or not (instType == "party" or instType == "raid") then
        return
    end
    -- Ejemplo simple: si un jefe grita al iniciar combate antes de cualquier registro de combate,
    -- podríamos notificarlo en la interfaz (no sabemos quién lo activó, este método es informativo).
    if monsterName and not bossActivations[monsterName] then
        -- Podemos, por ejemplo, mostrar en la ventana que el jefe ha sido activado (jugador desconocido)
        bossActivations[monsterName] = "Desconocido"
        table.insert(bossHistoryList, 1, { boss = monsterName, player = "Desconocido" })
        UpdateBossListUI(monsterName, "|cffccccccDesconocido|r")  -- Color gris para indicar desconocido
        -- Nota: Este enfoque agrega la entrada con jugador "Desconocido" porque un grito no identifica quién provocó al jefe.
    end
end

-- Función global: Envía la lista de activaciones registrada al chat especificado (Decir/Grupo/Banda/Hermandad)
function OutputActivationsToChat(channel)
    if #bossHistoryList == 0 then
        print("BossPullTracker: No hay datos de activaciones para anunciar.")
        return
    end
    -- Recorrer la lista de activaciones desde la más antigua a la más reciente (invertir el orden actual)
    for i = #bossHistoryList, 1, -1 do
        local entry = bossHistoryList[i]
        local msg = string.format("%s fue activado primero por %s", entry.boss, entry.player)
        SendChatMessage(msg, channel)
    end
end

-- Asignar el manejador principal de eventos
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Evento al completar la carga de la interfaz del jugador
        -- Enlazar tablas de la base de datos global (por seguridad, aunque ya se asignaron al cargar SavedVariables)
        bossActivations = BossPullTrackerDB.bossActivations
        bossHistoryList = BossPullTrackerDB.bossHistoryList
        currentInstanceName = BossPullTrackerDB.currentInstanceName
        -- Mostrar u ocultar la ventana principal según la preferencia guardada
        if not BossPullTrackerDB.showUI then
            BossPullTrackerFrame:Hide()
        else
            BossPullTrackerFrame:Show()
        end
        -- Reconstruir la UI de la lista de jefes si hay datos persistentes (ej. tras un /reload o reconexión en mitad de la instancia)
        if bossHistoryList and #bossHistoryList > 0 then
            ClearBossListUI()  -- Limpiar cualquier contenido previo en la lista (por seguridad)
            -- Recorrer los registros guardados e insertarlos en la UI en orden descendente (última activación primero)
            for index = 1, #bossHistoryList do
                local entry = bossHistoryList[index]
                UpdateBossListUI(entry.boss, entry.player)
            end
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Obtener parámetros del evento de combate
        local timestamp, subEvent,
              srcGUID, srcName, srcFlags, srcRaidFlags,
              destGUID, destName, destFlags, destRaidFlags, 
              spellId, spellName , param9, param10, param11, param12= ... -- Capturamos algunos campos adicionales si hiciera falta (spellId, etc.)
        -- Verificar entorno: solo proceder si estamos dentro de una instancia de grupo o banda
        local inInstance, instType = IsInInstance()
        if not inInstance or not (instType == "party" or instType == "raid") then
            return  -- Fuera de mazmorra/raid, ignorar todos los eventos de combate
        end
        -- Delegar la lógica específica del evento de combate a la función OnCombatLogEvent
        OnCombatLogEvent(timestamp, subEvent, srcGUID, srcName, srcFlags, srcRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName)

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Eventos de cambio de zona/instancia. 
        -- Nota: PLAYER_ENTERING_WORLD se lanza tanto al iniciar sesión como al cruzar un portal de instancia (con pantalla de carga).
        local isLogin, isReload = ...
        if not isLogin and not isReload then
            -- Solo procesar cambios de zona reales, ignorando la llamada inicial de carga de personaje
            OnZoneChanged()
        end

    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        -- Eventos que indican cambio en el grupo/banda (p. ej., un jugador abandona el grupo o la banda se disuelve)
        local numRaid = GetNumRaidMembers() or 0
        local numParty = GetNumPartyMembers() or 0
        if numRaid == 0 and numParty == 0 then
            -- Ya no estamos en ningún grupo o banda
            if bossHistoryList and #bossHistoryList > 0 then
                -- Si hay datos de activaciones almacenados, preguntar al usuario si desea borrarlos (abandono del grupo/banda)
                StaticPopup_Show("BOSSPULLTRACKER_CONFIRM_CLEAR")
            end
            -- (Si la lista estaba vacía, no es necesario hacer nada especial)
        end

    elseif event == "CHAT_MSG_MONSTER_YELL" then
        -- Un NPC (posiblemente un jefe) gritó algo
        local msgText, monsterName = ...
        OnBossYell(monsterName, msgText)
    end
end)

-- Inicializar la base de datos persistente (SavedVariables) al cargar el addon
if not BossPullTrackerDB then 
    BossPullTrackerDB = {} 
end
if not BossPullTrackerDB.bossActivations then BossPullTrackerDB.bossActivations = {} end
if not BossPullTrackerDB.bossHistoryList then BossPullTrackerDB.bossHistoryList = {} end
if not BossPullTrackerDB.currentInstanceName then BossPullTrackerDB.currentInstanceName = nil end
if BossPullTrackerDB.showUI == nil then BossPullTrackerDB.showUI = true end  -- Mostrar la ventana por defecto, a menos que se haya guardado lo contrario

-- Vincular tablas locales con la persistencia (así manejamos siempre la misma tabla en memoria)
bossActivations = BossPullTrackerDB.bossActivations
bossHistoryList = BossPullTrackerDB.bossHistoryList
currentInstanceName = BossPullTrackerDB.currentInstanceName
