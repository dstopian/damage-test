local dummies = {} -- Changed from single 'ped' and 'blip' to a table to hold multiple dummy states
local displayDamage = 0        -- Stores the total damage to display (for bottom-right UI)
local displayDamageTime = 0    -- Stores the game time when damage was dealt for fading effect (for bottom-right UI)
local damage3DQueue = {}     -- NEW: Stores 3D damage pop-up data {ped, damage, startTime}
local spawnDistance = 2.0      -- Default spawn distance in meters

-- Configuration for the health and armor bars and damage display
local barConfig = {
    width = 0.08,
    height = 0.01,
    -- Screen position for the health and armor bars (top-center)
    xPosition = 0.5,
    yPositionHealth = 0.02,
    yPositionArmor = 0.035,
    yPositionDistance = 0.05, -- Slightly below armor for distance
    healthColor = {r = 70, g = 200, b = 70, a = 255},
    armorColor = {r = 50, g = 150, b = 255, a = 255},
    backgroundColor = {r = 0, g = 0, b = 0, a = 120},

    -- Screen position and settings for the 2D damage display (bottom-right)
    xPositionDamage = 0.9,
    yPositionDamage = 0.9,
    damageDisplayTime = 1500, -- How long the 2D damage text stays on screen in milliseconds
    damageFontSize = 0.36,    -- UPDATED: Font size for 2D damage text (0.6 * 0.6 = 0.36)
    damageColor = {r = 255, g = 255, b = 255, a = 255}, -- White color for 2D damage text

    -- Distance text specific settings
    distanceFontSize = 0.4, -- Font size for distance text
    distanceColor = {r = 255, g = 255, b = 255, a = 200}, -- White color, slightly transparent

    -- NEW: 3D Damage text specific settings
    damage3DOffsetZ = 0.5,     -- Z-offset above ped head (ADJUSTED: Lowered from 1.0 to 0.5)
    damage3DTime = 1000,       -- How long 3D damage text stays visible (ms)
    damage3DFontSize = 0.3,    -- Font size for 3D damage text (scaled down from default 0.6 for 2D)
    damage3DColor = {r = 255, g = 255, b = 255, a = 255}, -- White color for 3D damage text
}

-- Helper function for native notifications
local function showNotification(message)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(message)
    DrawNotification(false, false) -- Draw as an alert (true for flashing, false for solid)
end

-- Helper function to calculate a vector direction from rotation
function GetCamDirection(camRot)
    local degToRad = math.pi / 180.0
    local pitch = degToRad * camRot.x
    local yaw = degToRad * -camRot.y -- Negative yaw for correct direction

    local camDir = {
        x = -math.sin(yaw) * math.abs(math.cos(pitch)),
        y = math.cos(yaw) * math.abs(math.cos(pitch)),
        z = math.sin(pitch)
    }
    return camDir
end

-- Helper function to get readable bone name from bone index, with raycast inference
local function getBoneName(boneIndex, playerPed, targetPed)
    -- Ensure boneIndex is a number before attempting comparisons
    if type(boneIndex) ~= "number" then
        print(string.format("[WeaponTest] getBoneName received non-numeric boneIndex: %s (type: %s)", tostring(boneIndex), type(boneIndex)))
        return "Unknown Part"
    end

    -- Direct Bone Mappings (most specific first)
    if boneIndex == 31086 then return "Head" end -- SKEL_Head
    if boneIndex == 12844 then return "Neck" end -- SKEL_Neck1
    if boneIndex == 39317 then return "Right Brow" end -- SKEL_R_Brow
    if boneIndex == 20178 then return "Left Brow" end -- SKEL_L_Brow
    if boneIndex == 35502 then return "Jaw" end -- SKEL_Jaw

    -- Torso/Spine Bones (specific entries)
    if boneIndex == 24816 then return "Spine (Lower)" end -- SKEL_Spine3
    if boneIndex == 23553 then return "Spine (Mid)" end   -- SKEL_Spine1
    if boneIndex == 28203 then return "Pelvis" end    -- SKEL_Pelvis
    if boneIndex == 6535 or boneIndex == 6442 then return "Chest" end -- SKEL_Spine2, SKEL_Spine_Root
    if boneIndex == 11816 then return "Right Collar" end -- SKEL_R_Clavicle
    if boneIndex == 11197 then return "Left Collar" end -- SKEL_L_Clavicle
    if boneIndex == 57597 then return "Gut" end -- Usually torso related, very low spine
    
    -- Arm Bones
    if boneIndex == 40989 then return "Left Forearm" end  -- SKEL_L_Forearm
    if boneIndex == 26610 then return "Right Forearm" end -- SKEL_R_Forearm
    if boneIndex == 45509 then return "Left Upper Arm" end -- SKEL_L_UpperArm
    if boneIndex == 49774 then return "Right Upper Arm" end -- SKEL_R_UpperArm
    if boneIndex == 60309 then return "Left Hand" end   -- SKEL_L_Hand
    if boneIndex == 18905 then return "Right Hand" end  -- SKEL_R_Hand

    -- Leg Bones
    if boneIndex == 58271 then return "Left Thigh" end  -- SKEL_L_Thigh
    if boneIndex == 63931 then return "Right Thigh" end -- SKEL_R_Thigh
    if boneIndex == 36864 then return "Left Calf" end   -- SKEL_L_Calf
    if boneIndex == 5186 then return "Right Calf" end  -- SKEL_R_Calf
    if boneIndex == 57717 then return "Left Foot" end   -- SKEL_L_Foot
    if boneIndex == 52301 then return "Right Foot" end  -- SKEL_R_Foot

    -- Fallback for no specific bone hit (index 0 usually means general body hit)
    if boneIndex == 0 then return "Body" end 


    if boneIndex == 1 then -- Or add other bone indices that consistently show up as 'general torso'
        local camCoords = GetGameplayCamCoord()
        local camRot = GetGameplayCamRot(2) -- Get camera rotation (pitch, yaw, roll)
        local fwdVec = GetCamDirection(camRot)
        local rayFar = 200.0 -- Max distance for raycast, adjust as needed

        local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z,
                                            camCoords.x + fwdVec.x * rayFar, camCoords.y + fwdVec.y * rayFar, camCoords.z + fwdVec.z * rayFar,
                                            10, -- Hit flags: 10 includes peds, vehicles, objects, water, foliage.
                                            targetPed, -- Entity to ignore (but we want to detect it, so this might be tricky).
                                            0)
        
        local retval, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)

        if hit and DoesEntityExist(entityHit) and entityHit == targetPed then
            -- Raycast successfully hit the test dummy. Now check proximity to specific bones.
            local headCoords = GetPedBoneCoords(targetPed, 31086) -- SKEL_Head
            local rUpperArmCoords = GetPedBoneCoords(targetPed, 49774) -- SKEL_R_UpperArm
            local lUpperArmCoords = GetPedBoneCoords(targetPed, 45509) -- SKEL_L_UpperArm
            local rThighCoords = GetPedBoneCoords(targetPed, 63931) -- SKEL_R_Thigh
            local lThighCoords = GetPedBoneCoords(targetPed, 58271) -- SKEL_L_Thigh

            local distanceThreshold = 0.2 -- Meters: Adjust this value to fine-tune sensitivity

            -- Compare hit coordinates to bone positions
            if #(endCoords - headCoords) < distanceThreshold then
                return "Head (Inferred)"
            elseif #(endCoords - rUpperArmCoords) < distanceThreshold or #(endCoords - lUpperArmCoords) < distanceThreshold then
                return "Arm (Inferred)"
            elseif #(endCoords - rThighCoords) < distanceThreshold or #(endCoords - lThighCoords) < distanceThreshold then
                return "Leg (Inferred)"
            else
                -- If it hit the dummy, but not specifically a head/limb bone, it's a general torso hit.
                return "Torso (Inferred)"
            end
        else
            -- If raycast didn't confirm a more specific hit, assume general torso for boneIndex 1
            return "Torso"
        end
    end

    -- Generic fallback for any other unknown bone, or if inference failed/wasn't applicable
    print(string.format("[WeaponTest] Unknown Bone Index: %d", boneIndex)) -- Keep this debug print
    return "Unknown Part"
end


RegisterCommand('testdummy', function()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local forward = GetEntityForwardVector(playerPed)
    local spawnPos = coords + forward * spawnDistance -- Use spawnDistance here

    -- Request a model to spawn
    local model = `a_m_y_skater_01` -- You can change the model here
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    -- Create the ped
    local newPed = CreatePed(4, model, spawnPos.x, spawnPos.y, spawnPos.z - 1.0, 0.0, true, true)
    SetModelAsNoLongerNeeded(model)

    -- Set full health and armor
    local maxHealth = 200
    local maxArmor = 100 -- Set max armor to 100 to display it properly
    SetEntityMaxHealth(newPed, maxHealth)
    SetEntityHealth(newPed, maxHealth)
    AddArmourToPed(newPed, maxArmor)
    
    SetEntityAsMissionEntity(newPed, true, true)
    SetBlockingOfNonTemporaryEvents(newPed, true)
    SetPedDiesWhenInjured(newPed, false)
    TaskSetBlockingOfNonTemporaryEvents(newPed, true)
    TaskStandStill(newPed, -1)
    SetPedFleeAttributes(newPed, 0, 0)

    -- Enhanced combat attributes to make the dummy truly unresponsive
    SetPedCombatAttributes(newPed, 0, false)   -- BF_CanAttack
    SetPedCombatAttributes(newPed, 1, false)   -- BF_CanUseCover
    SetPedCombatAttributes(newPed, 2, false)   -- BF_CanFight
    SetPedCombatAttributes(newPed, 5, false)   -- BF_CanRetreat
    SetPedCombatAttributes(newPed, 17, false)  -- BF_CanBeInjured (ensure false)
    SetPedCombatAttributes(newPed, 29, true)   -- BF_AlwaysKeepPedStanding (prevents ragdoll)
    SetPedCombatAttributes(newPed, 46, true)   -- BF_CanBeKnockedDown (prevents ragdoll)
    SetPedCombatAttributes(newPed, 58, false)  -- BF_AlwaysFight
    SetPedCanRagdoll(newPed, false)            -- Explicitly prevent ragdoll state

--blip to easily find the ped
    local newBlip = AddBlipForEntity(newPed)
    SetBlipSprite(newBlip, 1)
    SetBlipColour(newBlip, 1)
    SetBlipScale(newBlip, 0.7)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Test Dummy")
    EndTextCommandSetBlipName(newBlip)

    -- Store dummy information in the 'dummies' table
    local dummyId = #dummies + 1 -- Simple incrementing ID
    dummies[dummyId] = {
        ped = newPed,
        blip = newBlip,
        lastHealth = maxHealth,
        lastArmor = maxArmor,
        id = dummyId -- Store the ID within the dummy's data
    }

    showNotification("Test dummy spawned. Total active: " .. #dummies)
    print(string.format("[WeaponTest] Dummy %d spawned. Total active: %d. Open F8 console to see damage logs.", dummyId, #dummies))
end, false)

--  key mapping for the testdummy command
RegisterKeyMapping(
    'testdummy',           -- The command to execute when the key is pressed
    'Spawn Test Dummy',    -- The name displayed in the Controls menu
    'keyboard',            -- The input control type (e.g., 'keyboard', 'mouse', 'gamepad')
    'F5'                   -- The default key (e.g., 'F5', 'E', 'MOUSE_LEFT')
)

-- Command to set spawn distance
RegisterCommand('distance', function(source, args)
    local newDistance = tonumber(args[1])
    if newDistance and newDistance > 0 then
        spawnDistance = newDistance
        showNotification("Test dummy spawn distance set to " .. spawnDistance .. " meters.")
        print("[WeaponTest] Spawn distance set to: " .. spawnDistance .. "m")
    else
        showNotification("Invalid distance. Please enter a positive number (e.g., /distance 5).")
        print("[WeaponTest] Invalid distance provided for /distance command.")
    end
end, false)


RegisterCommand('deletedummy', function()
    if #dummies > 0 then
        for i = #dummies, 1, -1 do -- Loop backwards to safely remove elements
            local dummy = dummies[i]
            if dummy.ped and DoesEntityExist(dummy.ped) then
                DeleteEntity(dummy.ped)
            end
            if dummy.blip and DoesBlipExist(dummy.blip) then
                RemoveBlip(dummy.blip)
            end
            table.remove(dummies, i)
        end
        showNotification("All test dummies despawned.")
        print("[WeaponTest] All dummies despawned.")
    else
        showNotification("There are no test dummies to despawn.")
    end
    -- Reset display after all dummies are gone
    displayDamage = 0
    displayDamageTime = 0
end, false)

-- Thread for drawing health/armor bars, distance text, and damage text for ALL dummies
CreateThread(function()
    while true do
        Wait(0) -- Set to 0 for maximum responsiveness

        local activeDummies = {}
        for i = 1, #dummies do
            local dummy = dummies[i]
            if dummy.ped and DoesEntityExist(dummy.ped) then
                table.insert(activeDummies, dummy)
            else
                -- Clean up dead/non-existent dummies from the list
                if dummy.blip and DoesBlipExist(dummy.blip) then
                    RemoveBlip(dummy.blip)
                end
            end
        end
        dummies = activeDummies -- Update the main dummies table with only active ones

        if #dummies > 0 then
            local yOffset = 0 -- Initial Y offset for drawing
            for i, dummy in ipairs(dummies) do
                local playerPed = PlayerPedId()
                local pedCoords = GetEntityCoords(dummy.ped)
                local playerCoords = GetEntityCoords(playerPed)

                local distanceToDummy = #(playerCoords - pedCoords) -- Calculate distance for current dummy

                
                DrawHealthArmorBars(dummy.ped, barConfig.xPosition, barConfig.yPositionHealth + yOffset, barConfig.yPositionArmor + yOffset)

                
                DrawDistanceText(distanceToDummy, barConfig.xPosition, barConfig.yPositionDistance + yOffset)

                
                yOffset = yOffset + (barConfig.height * 3) -- Roughly 3 times bar height for spacing
            end
        end

        
        local timeSinceDamage = GetGameTimer() - displayDamageTime
        if displayDamage > 0 and timeSinceDamage < barConfig.damageDisplayTime then
            local alpha = math.floor(255 * (1 - (timeSinceDamage / barConfig.damageDisplayTime)))
            DrawDamageText(displayDamage, barConfig.xPositionDamage, barConfig.yPositionDamage, alpha)
        else
            -- Reset display if time has passed
            displayDamage = 0
        end

        -- : Draw 3D damage pop-ups
        local activeDamage3D = {}
        for i = #damage3DQueue, 1, -1 do -- Loop backwards to safely remove
            local damageEntry = damage3DQueue[i]
            local timeElapsed = GetGameTimer() - damageEntry.startTime

            if timeElapsed < barConfig.damage3DTime then
                local alpha = math.floor(255 * (1 - (timeElapsed / barConfig.damage3DTime)))
                -- Use GetPedBoneCoords for a consistent position above the head
                local headCoords = GetPedBoneCoords(damageEntry.ped, 31086) -- SKEL_Head
                if headCoords then
                    Draw3DText(headCoords.x, headCoords.y, headCoords.z + barConfig.damage3DOffsetZ, damageEntry.damage, alpha)
                end
                table.insert(activeDamage3D, 1, damageEntry) -- Re-add to the front to maintain order
            end
        end
        damage3DQueue = activeDamage3D -- Update the queue
    end
end)


function DrawHealthArmorBars(entity, screenX, screenYHealth, screenYArmor)
    local health = GetEntityHealth(entity)
    local maxHealth = GetEntityMaxHealth(entity)
    local armor = GetPedArmour(entity)
    local maxArmor = 100 -- Assuming max armor is 100 as per `AddArmourToPed` usage

    
    if health <= 0 or (health == maxHealth and armor == maxArmor) then
        return
    end

    
    local healthPercentage = health / maxHealth
    local armorPercentage = armor / maxArmor

    
    DrawRect(screenX, screenYHealth, barConfig.width, barConfig.height, barConfig.backgroundColor.r, barConfig.backgroundColor.g, barConfig.backgroundColor.b, barConfig.backgroundColor.a)
    
    DrawRect(screenX - (barConfig.width / 2) * (1 - healthPercentage), screenYHealth, barConfig.width * healthPercentage, barConfig.height, barConfig.healthColor.r, barConfig.healthColor.g, barConfig.healthColor.b, barConfig.healthColor.a)

    
    DrawRect(screenX, screenYArmor, barConfig.width, barConfig.height, barConfig.backgroundColor.r, barConfig.backgroundColor.g, barConfig.backgroundColor.b, barConfig.backgroundColor.a)
    
    DrawRect(screenX - (barConfig.width / 2) * (1 - armorPercentage), screenYArmor, barConfig.width * armorPercentage, barConfig.height, barConfig.armorColor.r, barConfig.armorColor.g, barConfig.armorColor.b, barConfig.armorColor.a)
end


function DrawDamageText(damage, screenX, screenY, alpha)
    SetTextFont(0) -- Standard font for broader compatibility
    SetTextScale(0.0, barConfig.damageFontSize)
    SetTextColour(barConfig.damageColor.r, barConfig.damageColor.g, barConfig.damageColor.b, alpha)
    SetTextOutline()
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Damage: " .. math.floor(damage)) -- Display as whole number
    DrawText(screenX, screenY)
end


function DrawDistanceText(distance, screenX, screenY)
    SetTextFont(0) -- Standard font
    SetTextScale(0.0, barConfig.distanceFontSize)
    SetTextColour(barConfig.distanceColor.r, barConfig.distanceColor.g, barConfig.distanceColor.b, barConfig.distanceColor.a)
    SetTextCentre(true) -- Center the text horizontally
    SetTextEntry("STRING")
    AddTextComponentString("Distance: " .. string.format("%.1f", distance) .. "m") -- Format to 1 decimal place
    DrawText(screenX, screenY)
end


function Draw3DText(x, y, z, damage, alpha)
    local camCoords = GetGameplayCamCoord()
    local dist = #(camCoords - vector3(x, y, z))
    local scale = 1 / dist * 2 -- Scale text based on distance
    local fov = (1 / GetGameplayCamFov()) * 100
    local finalScale = barConfig.damage3DFontSize * scale * fov

    SetTextScale(0.0, finalScale)
    SetTextFont(0)
    SetTextColour(barConfig.damage3DColor.r, barConfig.damage3DColor.g, barConfig.damage3DColor.b, alpha)
    SetTextOutline()
    SetTextDropshadow(0, 0, 0, 0, alpha) -- Dropshadow fades with text
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(math.floor(damage)) -- Just the number for 3D
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end


CreateThread(function()
    while true do
        Wait(0) -- Set to 0 for maximum responsiveness

        
        for i = #dummies, 1, -1 do -- Loop backwards
            local dummy = dummies[i]
            if dummy.ped and DoesEntityExist(dummy.ped) then
                local currentHealth = GetEntityHealth(dummy.ped)
                local currentArmor = GetPedArmour(dummy.ped)

                if currentHealth < dummy.lastHealth or currentArmor < dummy.lastArmor then
                    local healthDamage = dummy.lastHealth - currentHealth
                    local armorDamage = dummy.lastArmor - currentArmor
                    local totalDamage = healthDamage + armorDamage

                    if totalDamage > 0 then
                        local lastHitBone = GetPedLastDamageBone(dummy.ped) -- Get the bone index that was last hit
                        -- Pass playerPed (PlayerPedId()) and the specific dummy.ped to getBoneName
                        local bodyPart = getBoneName(lastHitBone, PlayerPedId(), dummy.ped)

                        showNotification('Dealt ' .. totalDamage .. ' damage to dummy #' .. dummy.id .. ' (' .. bodyPart .. ')') -- Include dummy ID
                        
                        -- Update global variables for 2D on-screen damage display
                        displayDamage = totalDamage
                        displayDamageTime = GetGameTimer()

                        
                        table.insert(damage3DQueue, {ped = dummy.ped, damage = totalDamage, startTime = GetGameTimer()})

                        
                        print(string.format("[WeaponTest] Damage Dealt: Total=%d (Health: %d, Armor: %d) | Dummy #%d Hit: %s | Remaining: Health=%d, Armor=%d", totalDamage, healthDamage, armorDamage, dummy.id, bodyPart, currentHealth, currentArmor))
                    end

                    dummy.lastHealth = currentHealth
                    dummy.lastArmor = currentArmor
                end

                
                if IsEntityDead(dummy.ped) and not dummy.hasDied then -- Check a flag to notify only once
                    showNotification("Test dummy #" .. dummy.id .. " has been neutralized (incapacitated).")
                    print(string.format("[WeaponTest] Dummy #%d neutralized.", dummy.id))
                    dummy.hasDied = true -- Set flag to prevent repeated notifications
                
                end
            end
        end
    end
end)
