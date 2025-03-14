-- PlayerKillAnnounce EventHandlers.lua
-- Tracks and announces player kills with streak tracking and statistics
local PlayerKillMessageDefault = "Enemyplayername killed!"
local KillStreakEndedMessageDefault = "My kill streak of STREAKCOUNT has ended!"
local NewStreakRecordMessageDefault = "NEW PERSONAL BEST: Kill streak of STREAKCOUNT!"
local NewMultiKillRecordMessageDefault = "NEW PERSONAL BEST: Multi-kill of MULTIKILLCOUNT!"
------------------------------------------------------------------------

local playerKillAnnounceFrame = CreateFrame("Frame", "PlayerKillAnnounceFrame", UIParent)
PKA_EnableKillAnnounce = true
PKA_KillAnnounceMessage = PlayerKillMessageDefault
PKA_KillCounts = {}
PKA_KillStreakEndedMessage = KillStreakEndedMessageDefault
PKA_NewStreakRecordMessage = NewStreakRecordMessageDefault
PKA_NewMultiKillRecordMessage = NewMultiKillRecordMessageDefault
PKA_CurrentKillStreak = 0
PKA_HighestKillStreak = 0
PKA_MultiKillCount = 0
PKA_HighestMultiKill = 0
PKA_LastCombatTime = 0
PKA_EnableRecordAnnounce = true
PKA_MultiKillThreshold = 3
PKA_MILESTONE_STREAKS = {25, 50, 75, 100, 150, 200, 250, 300}
PKA_AutoBattlegroundMode = true  -- Auto-detect BGs
PKA_BattlegroundMode = false     -- Manual override for BG mode
PKA_InBattleground = false       -- Current BG state

local PKA_CHAT_MESSAGE_R = 1.0
local PKA_CHAT_MESSAGE_G = 1.0
local PKA_CHAT_MESSAGE_B = 0.74

-- State tracking variables
local inCombat = false
local killStreakMilestoneFrame = nil
PKA_Debug = false  -- Debug mode for extra messages

-- Add these variables at the top
local PKA_RecentPetDamage = {}  -- Track recent pet damage
local PKA_DAMAGE_WINDOW = 0.01   -- 1.0 second window for pet damage (more reliable)

-- Add this variable near the other state tracking variables
local PKA_RecentlyCountedKills = {}  -- Track recently counted kills to prevent duplicates
local PKA_KILL_TRACKING_WINDOW = 1.0  -- 1 second window to prevent duplicate kill counting

-- Add this variable at the top with your other variables
local tooltipHookSetup = false

-- Functions to identify pets and pet owners
local function IsPetGUID(guid)
    if not guid then return false end

    -- Classic WoW GUID format: Pet-0-xxxx-xxxx-xxxx-xxxx
    return guid:match("^Pet%-") ~= nil
end

local function GetPetOwnerGUID(petGUID)
    if not petGUID or not IsPetGUID(petGUID) then return nil end

    -- Check if it's the player's pet
    if UnitExists("pet") and UnitGUID("pet") == petGUID then
        return UnitGUID("player")
    end

    -- For party/raid members' pets
    local numMembers = IsInRaid() and GetNumGroupMembers() or GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"

    for i = 1, numMembers do
        local unitID
        if prefix == "party" then
            unitID = (i == GetNumGroupMembers()) and "player" or (prefix..i)
        else
            unitID = prefix..i
        end

        local petID = unitID.."pet"

        if UnitExists(petID) and UnitGUID(petID) == petGUID then
            return UnitGUID(unitID)
        end
    end

    return nil
end

-- Add this helper function
local function GetNameFromGUID(guid)
    if not guid then return nil end

    -- Try to find the name from the GUID
    local name = select(6, GetPlayerInfoByGUID(guid))
    if name then return name end

    -- If that fails, check if it's the player
    if guid == UnitGUID("player") then
        return UnitName("player")
    end

    -- Check party/raid members
    local numMembers = IsInRaid() and GetNumGroupMembers() or GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"

    for i = 1, numMembers do
        local unitID
        if prefix == "party" then
            unitID = (i == GetNumGroupMembers()) and "player" or (prefix..i)
        else
            unitID = prefix..i
        end

        if UnitGUID(unitID) == guid then
            return UnitName(unitID)
        end
    end

    return nil
end

local function PrintSlashCommandUsage()
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka config - Open configuration UI", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka stats - Show kills list", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka status - Show current settings", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka debug - Show current streak values", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka registerkill [number] - Register test kill(s) for testing", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka death - Simulate player death (resets kill streak)", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka bgmode - Toggle battleground mode manually", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka toggledebug - Toggle debug messages", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka testguid - Test your GUID detection for debugging", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka debugevents - Enhanced combat log debugging for 30 seconds", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Usage: /pka debugpet - Track all pet damage and kills for 60 seconds", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
end

local function PrintStatus()
    local statusMessage = "Kill announce messages are " .. (PKA_EnableKillAnnounce and "ENABLED" or "DISABLED") .. "."
    DEFAULT_CHAT_FRAME:AddMessage(statusMessage, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Current kill announce message: " .. PKA_KillAnnounceMessage, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Streak ended message: " .. PKA_KillStreakEndedMessage, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("New streak record message: " .. PKA_NewStreakRecordMessage, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("New multi-kill record message: " .. PKA_NewMultiKillRecordMessage, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Multi-kill announcement threshold: " .. PKA_MultiKillThreshold, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Record announcements: " .. (PKA_EnableRecordAnnounce and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Battleground Mode: " .. (PKA_InBattleground and "ACTIVE" or "INACTIVE"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Auto BG Detection: " .. (PKA_AutoBattlegroundMode and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Manual BG Mode: " .. (PKA_BattlegroundMode and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
end

local function ShowDebugInfo()
    DEFAULT_CHAT_FRAME:AddMessage("Current Kill Streak: " .. PKA_CurrentKillStreak, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Highest Kill Streak: " .. PKA_HighestKillStreak, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Current Multi-kill Count: " .. PKA_MultiKillCount, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Highest Multi-kill: " .. PKA_HighestMultiKill, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Multi-kill Announcement Threshold: " .. PKA_MultiKillThreshold, PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Battleground Mode: " .. (PKA_InBattleground and "ACTIVE" or "INACTIVE"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Auto BG Detection: " .. (PKA_AutoBattlegroundMode and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    DEFAULT_CHAT_FRAME:AddMessage("Manual BG Mode: " .. (PKA_BattlegroundMode and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
end

local function InitializeCacheForPlayer(nameWithLevel, englishClass, race, gender, guild, playerLevel)
    if not PKA_KillCounts[nameWithLevel] then
        local currentZone = GetRealZoneText() or GetSubZoneText() or "Unknown"

        PKA_KillCounts[nameWithLevel] = {
            kills = 0,
            class = englishClass or "Unknown",
            race = race or "Unknown",
            gender = gender or 1,
            guild = guild or "Unknown",
            lastKill = "",
            playerLevel = playerLevel or -1,
            unknownLevel = false,
            zone = currentZone,
            killLocations = {} -- Initialize empty array for kill locations
        }
    end
end

local function UpdateKillCacheEntry(nameWithLevel, race, gender, guild, playerLevel, isUnknownLevel)
    PKA_KillCounts[nameWithLevel].kills = PKA_KillCounts[nameWithLevel].kills + 1
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    PKA_KillCounts[nameWithLevel].lastKill = timestamp
    PKA_KillCounts[nameWithLevel].playerLevel = playerLevel or -1

    -- Ensure zone is captured correctly
    local currentZone = GetRealZoneText() or GetSubZoneText() or "Unknown"
    PKA_KillCounts[nameWithLevel].zone = currentZone

    -- Get current map position
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = nil
    if mapID then
        position = C_Map.GetPlayerMapPosition(mapID, "player")
    end

    -- Create a location record with coordinates
    if mapID and position and position.x and position.y then
        local x = position.x * 100
        local y = position.y * 100

        -- Ensure the killLocations array exists
        PKA_KillCounts[nameWithLevel].killLocations = PKA_KillCounts[nameWithLevel].killLocations or {}

        -- Add new location record
        table.insert(PKA_KillCounts[nameWithLevel].killLocations, {
            timestamp = timestamp,
            zone = currentZone,
            mapID = mapID,
            x = x,
            y = y,
            killNumber = PKA_KillCounts[nameWithLevel].kills
        })

        -- Debug info
        if PKA_Debug then
            print(string.format("Kill recorded at %s (%.4f, %.4f) in %s (Map ID: %d)",
                timestamp, x, y, currentZone, mapID))
        end
    else
        -- Log error if we couldn't get position
        if PKA_Debug then
            print("Failed to get player position for kill location")
        end
    end

    -- Update other player information if available
    if race and race ~= "Unknown" then PKA_KillCounts[nameWithLevel].race = race end
    if gender and gender ~= "Unknown" then PKA_KillCounts[nameWithLevel].gender = gender end
    if guild and guild ~= "" then PKA_KillCounts[nameWithLevel].guild = guild end
    PKA_KillCounts[nameWithLevel].unknownLevel = isUnknownLevel or false
end

local function UpdateKillStreak()
    PKA_CurrentKillStreak = PKA_CurrentKillStreak + 1

    if PKA_CurrentKillStreak > PKA_HighestKillStreak then
        PKA_HighestKillStreak = PKA_CurrentKillStreak

        if PKA_HighestKillStreak > 1 then
            print("NEW KILL STREAK RECORD: " .. PKA_HighestKillStreak .. "!")

            if PKA_HighestKillStreak >= 10 and PKA_HighestKillStreak % 5 == 0 and PKA_EnableRecordAnnounce and IsInGroup() then
                local newRecordMsg = string.gsub(PKA_NewStreakRecordMessage or NewStreakRecordMessageDefault, "STREAKCOUNT", PKA_HighestKillStreak)
                SendChatMessage(newRecordMsg, "PARTY")
            end

            if PKA_UpdateConfigStats then
                PKA_UpdateConfigStats()
            end
        end
    end
end

local function UpdateMultiKill()
    if UnitAffectingCombat("player") then
        if not inCombat then
            inCombat = true
        end

        PKA_MultiKillCount = PKA_MultiKillCount + 1
    else
        PKA_MultiKillCount = 1
        inCombat = false
    end

    if PKA_MultiKillCount > PKA_HighestMultiKill then
        PKA_HighestMultiKill = PKA_MultiKillCount

        if PKA_HighestMultiKill > 1 then
            print("NEW MULTI-KILL RECORD: " .. PKA_HighestMultiKill .. "!")

            if PKA_HighestMultiKill >= 3 and PKA_EnableRecordAnnounce and IsInGroup() then
                local newMultiKillMsg = string.gsub(PKA_NewMultiKillRecordMessage or NewMultiKillRecordMessageDefault, "MULTIKILLCOUNT", PKA_HighestMultiKill)
                SendChatMessage(newMultiKillMsg, "PARTY")
            end

            if PKA_UpdateConfigStats then
                PKA_UpdateConfigStats()
            end
        end
    end
end

local function GetMultiKillText(count)
    if count < 2 then return "" end

    local killTexts = {
        "DOUBLE KILL!",
        "TRIPLE KILL!",
        "QUADRA KILL!",
        "PENTA KILL!",
        "HEXA KILL!",
        "HEPTA KILL!",
        "OCTA KILL!",
        "NONA KILL!"
    }

    -- Play sound based on kill count if enabled
    if PKA_EnableKillSounds then
        local soundFile
        if count == 2 then
            soundFile = "Interface\\AddOns\\PlayerKillAnnounce\\sounds\\double_kill.mp3"
        elseif count == 3 then
            soundFile = "Interface\\AddOns\\PlayerKillAnnounce\\sounds\\triple_kill.mp3"
        elseif count == 4 then
            soundFile = "Interface\\AddOns\\PlayerKillAnnounce\\sounds\\quadra_kill.mp3"
        elseif count == 5 then
            soundFile = "Interface\\AddOns\\PlayerKillAnnounce\\sounds\\penta_kill.mp3"
        end

        if soundFile then
            PlaySoundFile(soundFile, "Master")
        end
    end

    if count <= 9 then
        return killTexts[count - 1]
    else
        return "DECA KILL!"
    end
end

local function AnnounceKill(killedPlayer, level, nameWithLevel)
    -- Don't announce in battleground mode or if announcements are disabled
    if PKA_InBattleground or not PKA_EnableKillAnnounce or not IsInGroup() then return end

    local killMessage = PKA_KillAnnounceMessage and string.gsub(PKA_KillAnnounceMessage, "Enemyplayername", killedPlayer) or
                        string.gsub(PlayerKillMessageDefault, "Enemyplayername", killedPlayer)

    local playerLevel = UnitLevel("player")
    local levelDifference = level - playerLevel
    local levelDisplay = level == -1 and "??" or tostring(level)

    if level == -1 or (level > 0 and levelDifference >= 5) then
        killMessage = killMessage .. " (Level " .. levelDisplay .. ")"
    end

    killMessage = killMessage .. " x" .. PKA_KillCounts[nameWithLevel].kills

    if PKA_CurrentKillStreak >= 10 and PKA_CurrentKillStreak % 5 == 0 then
        killMessage = killMessage .. " - Kill Streak: " .. PKA_CurrentKillStreak
    end

    SendChatMessage(killMessage, "PARTY")

    if PKA_MultiKillCount >= PKA_MultiKillThreshold then
        SendChatMessage(GetMultiKillText(PKA_MultiKillCount), "PARTY")
    end
end

local function CreateKillDebugMessage(playerName, level, englishClass, race, nameWithLevel, killerGUID, killerName)
    local debugMsg = "Killed: " .. playerName

    local playerLevel = UnitLevel("player")
    local levelDifference = level > 0 and (level - playerLevel) or 0
    if level == -1 or (level > 0 and levelDifference >= 5) then
        debugMsg = debugMsg .. " (Level " .. (level == -1 and "??" or level)
    else
        debugMsg = debugMsg .. " ("
    end

    debugMsg = debugMsg .. englishClass .. ", " .. race .. ") - Total kills: " .. PKA_KillCounts[nameWithLevel].kills
    debugMsg = debugMsg .. " - Current streak: " .. PKA_CurrentKillStreak
    debugMsg = debugMsg .. " - Zone: " .. (PKA_KillCounts[nameWithLevel].zone or "Unknown")

    -- Add info on who got the kill
    if killerGUID and IsPetGUID(killerGUID) then
        debugMsg = debugMsg .. " - Kill by: Your Pet (" .. (killerName or "Unknown") .. ")"
    end

    if PKA_MultiKillCount >= 2 then
        debugMsg = debugMsg .. " - " .. GetMultiKillText(PKA_MultiKillCount)
    end

    return debugMsg
end

local function RegisterPlayerKill(playerName, level, englishClass, race, gender, guild, killerGUID, killerName)
    local playerLevel = UnitLevel("player")
    local nameWithLevel = playerName .. ":" .. level

    UpdateKillStreak()
    PKA_ShowKillStreakMilestone(PKA_CurrentKillStreak)

    UpdateMultiKill()

    InitializeCacheForPlayer(nameWithLevel, englishClass, race, gender, guild, playerLevel)
    UpdateKillCacheEntry(nameWithLevel, race, gender, guild, playerLevel, (level == -1))

    AnnounceKill(playerName, level, nameWithLevel)

    -- Print debug message using the new function
    local debugMsg = CreateKillDebugMessage(playerName, level, englishClass, race, nameWithLevel, killerGUID, killerName)
    print(debugMsg)

    PKA_SaveSettings()
end

local function SimulatePlayerDeath()
    DEFAULT_CHAT_FRAME:AddMessage("Simulating player death...", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)

    if PKA_CurrentKillStreak >= 10 and PKA_EnableRecordAnnounce and IsInGroup() then
        local streakEndedMsg = string.gsub(PKA_KillStreakEndedMessage, "STREAKCOUNT", PKA_CurrentKillStreak)
        SendChatMessage(streakEndedMsg, "PARTY")
    end

    PKA_CurrentKillStreak = 0
    PKA_MultiKillCount = 0
    inCombat = false
    PKA_SaveSettings()
    DEFAULT_CHAT_FRAME:AddMessage("Death simulated! Kill streak reset.", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
end

local function SimulatePlayerKills(killCount)
    DEFAULT_CHAT_FRAME:AddMessage("Registering " .. killCount .. " random test kill(s)...", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)

    local randomNames = {
        "Gankalicious", "Pwnyou", "Backstabber", "Shadowmelter", "Campmaster",
        "Roguenstein", "Sneakattack", "Huntard", "Faceroller", "Dotspammer",
        "Moonbender", "Healnoob", "Ragequitter", "Imbalanced", "Critmaster",
        "Zerglord", "Epicfail", "Oneshot", "Griefer", "Farmville",
        "Stunlock", "Procmaster", "Noobslayer", "Bodycamper", "Flagrunner"
    }

    local randomGuilds = {
        "Gank Squad", "PvP Masters", "Corpse Campers", "World Slayers", "Honor Farmers",
        "Rank Grinders", "Blood Knights", "Deadly Alliance", "Battleground Heroes", "Warsong Outlaws",
        "Death and Taxes", "Tactical Retreat", "Shadow Dancers", "First Strike", "Elite Few",
        "Kill on Sight", "No Mercy", "Rogues Do It", "Battlefield Legends", ""  -- Empty guild possible
    }

    local classes = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "SHAMAN", "MAGE", "WARLOCK", "DRUID"
    }

    local races = {
        "Human", "Dwarf", "NightElf", "Gnome",
    }

    local genders = {"Male", "Female"}

    -- Add random zones for testing
    local randomZones = {
        "Stormwind City", "Orgrimmar", "Ironforge", "Thunder Bluff", "Darnassus", "Undercity",
        "Elwynn Forest", "Durotar", "Mulgore", "Teldrassil", "Tirisfal Glades", "Westfall",
        "Redridge Mountains", "Duskwood", "Stranglethorn Vale", "The Barrens", "Ashenvale",
        "Alterac Mountains", "Arathi Highlands", "Badlands", "Blasted Lands", "Burning Steppes",
        "Desolace", "Dustwallow Marsh", "Eastern Plaguelands", "Felwood", "Feralas",
        "Hillsbrad Foothills", "Tanaris", "The Hinterlands", "Un'Goro Crater", "Western Plaguelands",
        "Winterspring", "Silithus", "Warsong Gulch", "Arathi Basin", "Alterac Valley"
    }

    for i = 1, killCount do
        local randomName = randomNames[math.random(#randomNames)]
        local randomGuild = randomGuilds[math.random(#randomGuilds)]
        local randomClass = classes[math.random(#classes)]
        local randomRace = races[math.random(#races)]
        local randomGender = genders[math.random(#genders)]
        local randomZone = randomZones[math.random(#randomZones)]

        local randomLevel = math.min(60, math.floor(math.random() * math.random() * 60) + 1)
        if math.random(100) <= 15 then  -- 15% chance for unknown level
            randomLevel = -1
        end

        -- Temporarily override GetRealZoneText to return our random zone
        local originalGetRealZoneText = GetRealZoneText
        GetRealZoneText = function() return randomZone end

        local randomX = 10.0 + (90.0 - 10.0) * math.random()
        local randomY = 10.0 + (90.0 - 10.0) * math.random()

        -- Override C_Map.GetPlayerMapPosition for this simulation
        local originalGetPlayerMapPosition = C_Map.GetPlayerMapPosition
        C_Map.GetPlayerMapPosition = function(mapID, unit)
            return {x = randomX, y = randomY}
        end

        -- Register the kill with random data
        RegisterPlayerKill(randomName, randomLevel, randomClass, randomRace, randomGender, randomGuild)

        -- Restore the original function
        C_Map.GetPlayerMapPosition = originalGetPlayerMapPosition

        -- Restore the original function
        GetRealZoneText = originalGetRealZoneText
    end

    DEFAULT_CHAT_FRAME:AddMessage("Successfully registered " .. killCount .. " random test kill(s).", PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
end

function PKA_SlashCommandHandler(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "" then
        PrintSlashCommandUsage()
    elseif command == "status" then
        PrintStatus()
    elseif command == "kills" or command == "stats" then
        PKA_CreateKillStatsFrame()
    elseif command == "debug" then
        ShowDebugInfo()
    elseif command == "toggledebug" then
        PKA_Debug = not PKA_Debug
        DEFAULT_CHAT_FRAME:AddMessage("Debug mode " .. (PKA_Debug and "enabled" or "disabled"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
    elseif command == "registerkill" then
        local testKillCount = 1

        if rest and rest ~= "" then
            local count = tonumber(rest)
            if count and count > 0 then
                testKillCount = count
            end
        end

        SimulatePlayerKills(testKillCount)
    elseif command == "death" then
        SimulatePlayerDeath()
    elseif command == "bgmode" then
        PKA_BattlegroundMode = not PKA_BattlegroundMode
        PKA_CheckBattlegroundStatus()
        DEFAULT_CHAT_FRAME:AddMessage("Manual Battleground Mode " .. (PKA_BattlegroundMode and "ENABLED" or "DISABLED"), PKA_CHAT_MESSAGE_R, PKA_CHAT_MESSAGE_G, PKA_CHAT_MESSAGE_B)
        PKA_SaveSettings()
    elseif command == "testguid" then
        PKA_DebugPlayerGUID()
    elseif command == "debugevents" then
        PKA_DebugEvents()
    elseif command == "debugpet" then
        PKA_DebugPetKills()
    else
        PrintSlashCommandUsage()
    end
end

local function OnPlayerTargetChanged()
    PKA_CollectPlayerInfo("target")
    PKA_CollectPlayerInfo("targettarget")
end

local function OnUpdateMouseoverUnit()
    PKA_CollectPlayerInfo("mouseover")
end

local function HandleCombatState(inCombatNow)
    if inCombat and not inCombatNow then
        PKA_MultiKillCount = 0
        inCombat = false
    elseif not inCombat and inCombatNow then
        PKA_MultiKillCount = 0
        inCombat = true
    end
end

local function HandlePlayerDeath()
    if PKA_CurrentKillStreak >= 10 and PKA_EnableRecordAnnounce and IsInGroup() then
        local streakEndedMsg = string.gsub(PKA_KillStreakEndedMessage, "STREAKCOUNT", PKA_CurrentKillStreak)
        SendChatMessage(streakEndedMsg, "PARTY")
    end

    PKA_CurrentKillStreak = 0
    PKA_MultiKillCount = 0
    inCombat = false
    PKA_SaveSettings()
    print("You died! Kill streak reset.")
end

local function ProcessEnemyPlayerDeath(destName, destGUID, sourceGUID, sourceName)
    local level, englishClass, race, gender, guild = PKA_GetPlayerInfo(destName, destGUID)

    if race == "Unknown" or gender == "Unknown" or englishClass == "Unknown" then
        print("Kill of " .. destName .. " not counted (incomplete data: " ..
              (race == "Unknown" and "race" or "") ..
              (gender == "Unknown" and (race == "Unknown" and ", gender" or "gender") or "") ..
              (englishClass == "Unknown" and ((race == "Unknown" or gender == "Unknown") and ", class" or "class") or "") ..
              " unknown)")
        return
    end

    -- At this point, we've already verified that this kill should count
    RegisterPlayerKill(destName, level, englishClass, race, gender, guild, sourceGUID, sourceName)
end


-- Add this function to clean up old damage records
local function CleanupRecentPetDamage()
    local now = GetTime()
    local cutoff = now - PKA_DAMAGE_WINDOW

    for guid, info in pairs(PKA_RecentPetDamage) do
        if info.timestamp < cutoff then
            PKA_RecentPetDamage[guid] = nil
        end
    end
end

-- Add this function to record pet damage
local function RecordPetDamage(petGUID, petName, targetGUID, targetName, amount)
    if not petGUID or not targetGUID then return end

    local ownerGUID = GetPetOwnerGUID(petGUID)
    if not ownerGUID then return end

    PKA_RecentPetDamage[targetGUID] = {
        timestamp = GetTime(),
        petGUID = petGUID,
        petName = petName,
        ownerGUID = ownerGUID,
        amount = amount or 0
    }

    if PKA_Debug then
        local playerGUID = UnitGUID("player")
        if ownerGUID == playerGUID then
            print("Recorded damage from your pet to: " .. targetName)
        end
    end
end

-- Replace the HandleCombatLogEvent function with this streamlined version
local function HandleCombatLogEvent()
    local timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags, param1, param2, param3, param4 = CombatLogGetCurrentEventInfo()

    -- Clean up old pet damage records
    CleanupRecentPetDamage()

    -- Clean up recently counted kills
    local now = GetTime()
    local cutoff = now - PKA_KILL_TRACKING_WINDOW
    for guid, timestamp in pairs(PKA_RecentlyCountedKills) do
        if timestamp < cutoff then
            PKA_RecentlyCountedKills[guid] = nil
        end
    end

    -- Debug all events for player/pet kills
    if PKA_Debug and
       (combatEvent == "UNIT_DIED" or combatEvent == "PARTY_KILL") and
       bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 and
       bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then

        print("DEBUG: " .. combatEvent .. " event detected")
        print("Source GUID: " .. (sourceGUID or "nil"))
        print("Source Name: " .. (sourceName or "nil"))
        print("Player GUID: " .. (UnitGUID("player") or "nil"))
        print("Player Name: " .. (UnitName("player") or "nil"))
        print("Target Killed: " .. (destName or "nil"))
    end

    -- Check for player death first
    if combatEvent == "UNIT_DIED" and destGUID == UnitGUID("player") then
        HandlePlayerDeath()
        return
    end

    -- Process player info for cache
    if sourceName and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
        PKA_UpdatePlayerInfoCache(sourceName, sourceGUID, nil, nil, nil, nil, nil)
    end

    if destName and bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
        PKA_UpdatePlayerInfoCache(destName, destGUID, nil, nil, nil, nil, nil)
    end

    if IsPetGUID(sourceGUID) and destGUID then
        local damageAmount = 0

        if combatEvent == "SWING_DAMAGE" then
            damageAmount = param1 or 0
        elseif combatEvent == "SPELL_DAMAGE" or combatEvent == "SPELL_PERIODIC_DAMAGE" then
            damageAmount = param4 or 0
        elseif combatEvent == "RANGE_DAMAGE" then
            damageAmount = param4 or 0
        end

        -- Only record if there was actual damage
        if damageAmount > 0 then
            RecordPetDamage(sourceGUID, sourceName, destGUID, destName, damageAmount)
        end
    end

    if combatEvent == "PARTY_KILL" and
       bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 and
       bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then

        local playerGUID = UnitGUID("player")
        local countKill = false

        if PKA_InBattleground then
            if sourceGUID == playerGUID then
                countKill = true
                if PKA_Debug then print("BG Mode: Player killing blow") end
            end
        else
            if sourceGUID == playerGUID then
                countKill = true
                if PKA_Debug then print("Normal Mode: Player killing blow") end
            elseif UnitInParty(sourceName) or UnitInRaid(sourceName) then
                countKill = true
                if PKA_Debug then print("Normal Mode: Party/Raid member killing blow") end
            end
        end

        if countKill then
            -- Mark this kill as already counted to prevent duplicates
            PKA_RecentlyCountedKills[destGUID] = GetTime()

            ProcessEnemyPlayerDeath(destName, destGUID, sourceGUID, sourceName)
        end
    end

    -- Handle pet kills via UNIT_DIED and recent pet damage
    if combatEvent == "UNIT_DIED" and
       bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 and
       bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then

        -- Skip if this kill was already counted recently (preventing double counts)
        if PKA_RecentlyCountedKills[destGUID] then
            if PKA_Debug then
                print("Skipping duplicate kill count for: " .. destName)
            end
            return
        end

        -- Check if this player was recently damaged by a pet
        local petDamage = PKA_RecentPetDamage[destGUID]

        if petDamage and (GetTime() - petDamage.timestamp) <= PKA_DAMAGE_WINDOW then
            local playerGUID = UnitGUID("player")
            local countKill = false

            -- In BG mode, only count the player's own pet kills
            if PKA_InBattleground then
                if petDamage.ownerGUID == playerGUID then
                    countKill = true
                    if PKA_Debug then
                        print("BG Mode: Pet killing blow detected (via recent damage)")
                        print("Pet: " .. (petDamage.petName or "Unknown"))
                        print("Time since damage: " .. string.format("%.6f", GetTime() - petDamage.timestamp) .. " seconds")
                    end
                end
            -- In normal mode, also accept party/raid member pets
            else
                if petDamage.ownerGUID == playerGUID then
                    countKill = true
                    if PKA_Debug then
                        print("Normal Mode: Your pet killing blow detected")
                        print("Time since damage: " .. string.format("%.6f", GetTime() - petDamage.timestamp) .. " seconds")
                    end
                else
                    -- Check if owner is in party/raid
                    local ownerName = GetNameFromGUID(petDamage.ownerGUID)

                    if ownerName and (UnitInParty(ownerName) or UnitInRaid(ownerName)) then
                        countKill = true
                        if PKA_Debug then
                            print("Normal Mode: Party/raid member's pet kill detected")
                            print("Time since damage: " .. string.format("%.6f", GetTime() - petDamage.timestamp) .. " seconds")
                        end
                    end
                end
            end

            if countKill then
                -- Mark this kill as counted
                PKA_RecentlyCountedKills[destGUID] = GetTime()

                ProcessEnemyPlayerDeath(destName, destGUID, petDamage.petGUID, petDamage.petName)
                PKA_RecentPetDamage[destGUID] = nil  -- Clear the record after processing
            end
        end
    end
end

local function IsKillStreakMilestone(count)
    for _, milestone in ipairs(PKA_MILESTONE_STREAKS) do
        if count == milestone then
            return true
        end
    end
    return false
end

local function CreateMilestoneFrameIfNeeded()
    if killStreakMilestoneFrame then return killStreakMilestoneFrame end

    local frame = CreateFrame("Frame", "PKA_MilestoneFrame", UIParent)
    frame:SetSize(400, 200)
    frame:SetPoint("TOP", 0, -60)
    frame:SetFrameStrata("HIGH")

    local icon = frame:CreateTexture("PKA_MilestoneIcon", "ARTWORK")
    icon:SetSize(200, 200)
    icon:SetPoint("TOP", 0, 0)
    icon:SetTexture("Interface\\AddOns\\PlayerKillAnnounce\\img\\RedridgePoliceLogo.blp")
    frame.icon = icon

    local text = frame:CreateFontString("PKA_MilestoneText", "OVERLAY", "SystemFont_Huge1")
    text:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    text:SetTextColor(1, 0, 0)
    text:SetTextHeight(30)
    frame.text = text

    frame:Hide()
    killStreakMilestoneFrame = frame
    return frame
end

local function SetupMilestoneAnimation(frame)
    if frame.animGroup then
        frame.animGroup:Stop()
        frame.animGroup:SetScript("OnPlay", nil)
        frame.animGroup:SetScript("OnFinished", nil)
        frame.animGroup:SetScript("OnStop", nil)
    end

    local animGroup = frame:CreateAnimationGroup()
    animGroup:SetLooping("NONE")

    local fadeIn = animGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(1)

    local hold = animGroup:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(9.0)
    hold:SetOrder(2)

    local fadeOut = animGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(3)

    animGroup:SetScript("OnFinished", function()
        frame:Hide()
    end)

    frame.animGroup = animGroup
    return animGroup
end

local function PlayMilestoneSound()
    PlaySound(8454) -- Warsong horde win sound
    PlaySound(8574) -- Cheer sound
end

function PKA_ShowKillStreakMilestone(killCount)
    if not IsKillStreakMilestone(killCount) then
        return
    end

    local frame = CreateMilestoneFrameIfNeeded()

    frame.text:SetText(killCount .. " KILL STREAK")

    frame:Show()
    frame:SetAlpha(0)

    local animGroup = SetupMilestoneAnimation(frame)

    PlayMilestoneSound()

    DoEmote("CHEER")

    animGroup:Play()
end

function RegisterEvents()
    playerKillAnnounceFrame:RegisterEvent("PLAYER_LOGIN")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    playerKillAnnounceFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    playerKillAnnounceFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_DEAD")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    playerKillAnnounceFrame:RegisterEvent("PLAYER_LOGOUT")
    playerKillAnnounceFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")  -- Add zone change event

    playerKillAnnounceFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            PKA_LoadSettings()
            PKA_SetupTooltip() -- Add this line to call the tooltip setup
            inCombat = UnitAffectingCombat("player")
            PKA_CheckBattlegroundStatus()  -- Check BG status on login/reload
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            HandleCombatLogEvent()
        elseif event == "PLAYER_TARGET_CHANGED" then
            OnPlayerTargetChanged()
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            OnUpdateMouseoverUnit()
        elseif event == "PLAYER_DEAD" then
            HandlePlayerDeath()
        elseif event == "PLAYER_REGEN_DISABLED" then
            HandleCombatState(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            HandleCombatState(false)
        elseif event == "PLAYER_LOGOUT" then
            PKA_CleanupDatabase()
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            PKA_CheckBattlegroundStatus()  -- Check BG status on zone change
        end
    end)
end

-- Add after the RegisterEvents function
function PKA_CheckBattlegroundStatus()
    if not PKA_AutoBattlegroundMode then
        PKA_InBattleground = PKA_BattlegroundMode
        return PKA_InBattleground
    end

    -- Get current zone
    local currentZone = GetRealZoneText() or ""

    -- List of battleground zones
    local battlegroundZones = {
        "Warsong Gulch",
        "Arathi Basin",
        "Alterac Valley",
        "Elwynn Forest",
        "Duskwood"
    }

    -- Check if current zone is a battleground
    for _, bgName in ipairs(battlegroundZones) do
        if currentZone == bgName then
            PKA_InBattleground = true
            if PKA_Debug and not PKA_LastBattlegroundState then
                print("PlayerKillAnnounce: Entered battleground. Only direct kills will be counted.")
            end
            PKA_LastBattlegroundState = true
            return true
        end
    end

    -- Not in a battleground
    if PKA_Debug and PKA_LastBattlegroundState then
        print("PlayerKillAnnounce: Left battleground. Normal kill tracking active.")
    end
    PKA_LastBattlegroundState = false
    PKA_InBattleground = PKA_BattlegroundMode
    return PKA_InBattleground
end

function PKA_SaveSettings()
    -- Save existing settings
    PlayerKillAnnounceDB = PlayerKillAnnounceDB or {}
    PlayerKillAnnounceDB.KillAnnounceMessage = PKA_KillAnnounceMessage
    PlayerKillAnnounceDB.KillCounts = PKA_KillCounts
    PlayerKillAnnounceDB.CurrentKillStreak = PKA_CurrentKillStreak
    PlayerKillAnnounceDB.HighestKillStreak = PKA_HighestKillStreak
    PlayerKillAnnounceDB.EnableKillAnnounce = PKA_EnableKillAnnounce
    PlayerKillAnnounceDB.KillStreakEndedMessage = PKA_KillStreakEndedMessage
    PlayerKillAnnounceDB.NewStreakRecordMessage = PKA_NewStreakRecordMessage
    PlayerKillAnnounceDB.NewMultiKillRecordMessage = PKA_NewMultiKillRecordMessage
    PlayerKillAnnounceDB.EnableRecordAnnounce = PKA_EnableRecordAnnounce
    PlayerKillAnnounceDB.MultiKillThreshold = PKA_MultiKillThreshold
    PlayerKillAnnounceDB.MultiKillCount = PKA_MultiKillCount
    PlayerKillAnnounceDB.HighestMultiKill = PKA_HighestMultiKill

    -- Save new battleground settings
    PlayerKillAnnounceDB.AutoBattlegroundMode = PKA_AutoBattlegroundMode
    PlayerKillAnnounceDB.BattlegroundMode = PKA_BattlegroundMode
    PlayerKillAnnounceDB.EnableKillSounds = PKA_EnableKillSounds
end

function PKA_LoadSettings()
    -- Load existing settings
    PlayerKillAnnounceDB = PlayerKillAnnounceDB or {}
    PKA_KillAnnounceMessage = PlayerKillAnnounceDB.KillAnnounceMessage or PlayerKillMessageDefault
    PKA_KillCounts = PlayerKillAnnounceDB.KillCounts or {}
    PKA_CurrentKillStreak = PlayerKillAnnounceDB.CurrentKillStreak or 0
    PKA_HighestKillStreak = PlayerKillAnnounceDB.HighestKillStreak or 0
    PKA_EnableKillAnnounce = PlayerKillAnnounceDB.EnableKillAnnounce ~= false
    PKA_KillStreakEndedMessage = PlayerKillAnnounceDB.KillStreakEndedMessage or KillStreakEndedMessageDefault
    PKA_NewStreakRecordMessage = PlayerKillAnnounceDB.NewStreakRecordMessage or NewStreakRecordMessageDefault
    PKA_NewMultiKillRecordMessage = PlayerKillAnnounceDB.NewMultiKillRecordMessage or NewMultiKillRecordMessageDefault
    PKA_EnableRecordAnnounce = PlayerKillAnnounceDB.EnableRecordAnnounce ~= false
    PKA_MultiKillThreshold = PlayerKillAnnounceDB.MultiKillThreshold or 3
    PKA_MultiKillCount = PlayerKillAnnounceDB.MultiKillCount or 0
    PKA_HighestMultiKill = PlayerKillAnnounceDB.HighestMultiKill or 0

    -- Load new battleground settings
    PKA_AutoBattlegroundMode = PlayerKillAnnounceDB.AutoBattlegroundMode ~= false
    PKA_BattlegroundMode = PlayerKillAnnounceDB.BattlegroundMode ~= false
    PKA_EnableKillSounds = PlayerKillAnnounceDB.EnableKillSounds
    if PKA_EnableKillSounds == nil then PKA_EnableKillSounds = true end  -- Default to enabled
end

function PKA_DebugPlayerGUID()
    local playerGUID = UnitGUID("player")
    print("Your player GUID is: " .. (playerGUID or "nil"))
    print("BG Mode is: " .. (PKA_InBattleground and "ACTIVE" or "INACTIVE"))
    print("Next time you kill someone in a BG, it should be registered")
end

-- Add this function near your other debug functions
function PKA_DebugEvents()
    print("Enabling enhanced combat log debugging for 30 seconds...")

    -- Store the original combat log handler
    local originalHandler = HandleCombatLogEvent

    -- Replace with our debug version temporarily
    HandleCombatLogEvent = function()
        local timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

        -- Print out kill-related events
        if (combatEvent == "UNIT_DIED" or combatEvent == "PARTY_KILL") and
           bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER or 0) > 0 then
            print("EVENT: " .. combatEvent)
            print("SOURCE: " .. (sourceName or "nil") .. " (" .. (sourceGUID or "nil") .. ")")
            print("TARGET: " .. (destName or "nil") .. " (" .. (destGUID or "nil") .. ")")
            print("FLAGS: source=" .. (sourceFlags or 0) .. ", dest=" .. (destFlags or 0))
            print("-----------------------------------")
        end

        -- Still call the original handler
        originalHandler()
    end

    -- Reset after 30 seconds
    C_Timer.After(30, function()
        print("Combat log debugging ended.")
        HandleCombatLogEvent = originalHandler
    end)
end

-- Add this function and command to detect all pet damage and kills
function PKA_DebugPetKills()
    print("Enabling pet kill debugging for 120 seconds...")

    -- Store the original combat log handler
    local originalHandler = HandleCombatLogEvent

    -- Replace with our debug version temporarily
    HandleCombatLogEvent = function()
        local timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags, param1, param2, param3, param4 = CombatLogGetCurrentEventInfo()

        -- Call the original handler first
        originalHandler()

        -- Track all pet damage events
        if IsPetGUID(sourceGUID) then
            local ownerGUID = GetPetOwnerGUID(sourceGUID)
            local playerGUID = UnitGUID("player")

            if ownerGUID == playerGUID then
                -- Log all pet damage events
                if combatEvent:find("_DAMAGE") or combatEvent == "SWING_DAMAGE" then
                    local amount = combatEvent == "SWING_DAMAGE" and param1 or (combatEvent == "SPELL_DAMAGE" and param4 or 0)

                    print("Pet damage to " .. destName .. ": " .. amount .. " damage")

                    -- Check current health if it's your target
                    if UnitExists("target") and UnitGUID("target") == destGUID then
                        print("Target health: " .. UnitHealth("target") .. "/" .. UnitHealthMax("target"))
                        if UnitHealth("target") <= 0 then
                            print("Target appears to be DEAD!")
                        end
                    end
                end
            end
        end

        -- Track UNIT_DIED events for any mob your pet damaged
        if combatEvent == "UNIT_DIED" then
            local petDamage = PKA_RecentPetDamage[destGUID]
            if petDamage then
                print("*** DEATH DETECTED - " .. destName .. " ***")
                print("This target was damaged by your pet " .. (petDamage.petName or "Unknown") ..
                      " " .. string.format("%.6f", GetTime() - petDamage.timestamp) .. " seconds ago")

                if bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 and
                   bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then
                    print("This was an enemy player kill!")
                else
                    print("This was NOT an enemy player")
                end
            end
        end
    end

    -- Reset after 120 seconds
    C_Timer.After(120, function()
        print("Pet kill debugging ended.")
        HandleCombatLogEvent = originalHandler
    end)
end

-- Add this function after PKA_LoadSettings but before RegisterEvents

function PKA_SetupTooltip()
    if tooltipHookSetup then return end

    -- Helper function to check if a kills line already exists in the tooltip
    local function HasKillsLineInTooltip(tooltip)
        for i = 1, tooltip:NumLines() do
            local line = _G[tooltip:GetName() .. "TextLeft" .. i]
            if line and line:GetText() and line:GetText():find("^Kills: ") then
                return true
            end
        end
        return false
    end

    -- Helper function to add kills to tooltip if not already present
    local function AddKillsToTooltip(tooltip, kills)
        if not HasKillsLineInTooltip(tooltip) then
            tooltip:AddLine("Kills: " .. kills, 1, 1, 1)
            tooltip:Show() -- Force refresh to show the new line
        end
    end

    -- Helper function to get kills for a player by name (checking all level entries)
    local function GetKillsByPlayerName(playerName)
        for nameWithLevel, data in pairs(PKA_KillCounts) do
            local storedName = nameWithLevel:match("^(.+):")
            if storedName == playerName then
                return data.kills
            end
        end
        return 0
    end

    -- Handle live player tooltips
    local function OnTooltipSetUnit(tooltip)
        -- Check if tooltip info is enabled
        if not PKA_ShowTooltipKillInfo then return end

        -- Get unit from tooltip
        local name, unit = tooltip:GetUnit()
        if not unit then return end

        -- Only continue for enemy players
        if not UnitIsPlayer(unit) or UnitIsFriend("player", unit) then return end

        -- Get the player's name and level for lookup
        local playerName = UnitName(unit)
        local playerLevel = UnitLevel(unit)
        local nameWithLevel = playerName .. ":" .. playerLevel

        -- Find kill count in our database
        local kills = 0
        if PKA_KillCounts[nameWithLevel] then
            kills = PKA_KillCounts[nameWithLevel].kills
        end

        AddKillsToTooltip(tooltip, kills)
    end

    -- Handle corpse tooltips
    local function OnTooltipShow(tooltip)
        if not tooltip:IsShown() then return end

        local line1 = _G[tooltip:GetName().."TextLeft1"]
        if not line1 then return end

        local text = line1:GetText()
        if not text or not text:find("^Corpse of ") then return end

        -- Extract player name
        local playerName = text:match("^Corpse of (.+)$")
        if not playerName then return end

        -- Look up player in our database (check at all levels)
        local kills = GetKillsByPlayerName(playerName)

        -- Always add the kill count, even if 0
        AddKillsToTooltip(tooltip, kills)
    end

    -- Hook into various tooltip events for better coverage
    GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
    GameTooltip:HookScript("OnShow", OnTooltipShow)

    -- The OnTooltipCleared event might fire too early, so we also use a small timer
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
        C_Timer.After(0.01, function()
            if tooltip:IsShown() then
                OnTooltipShow(tooltip)
            end
        end)
    end)

    tooltipHookSetup = true

    if PKA_Debug then
        print("PlayerKillAnnounce: Tooltip hooks initialized")
    end
end
