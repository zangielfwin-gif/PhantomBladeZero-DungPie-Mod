-- Offline smoke test for the installed Lua entry points. The engine objects are stubs.
local function object(fields)
    fields = fields or {}
    function fields:IsValid() return not self.destroyed end
    function fields:GetAddress() return self end
    return fields
end

local function param(value, kind)
    return {
        type = function() return kind or "RemoteUnrealParam" end,
        get = function() return value end,
    }
end

local now, armed, weapon_index = 0, false, 0
local keys, held, events, effects, sounds = {}, {}, {}, {}, {}
local audio_error = false
local tick
local origin = { X = 0, Y = 0, Z = 80 }
local rotate = { Pitch = 0, Yaw = 0, Roll = 0 }
local function effect(asset, parent)
    local c = object({ asset = asset.path, parent = parent, colors = {}, floats = {}, sizes = {} })
    function c:SetVariableLinearColor(name, color) self.colors[name] = color end
    function c:SetVariableFloat(name, value) self.floats[name] = value end
    function c:SetVariableVec2(name, value) self.sizes[name] = value end
    function c:SetWorldScale3D(scale) self.scale = scale end
    function c:Activate() self.active = true; effects[#effects + 1] = self end
    function c:Deactivate() self.active = false end
    function c:SetVisibility(visible) self.visible = visible end
    return c
end
local library = object({
    SpawnSystemAttached = function(_, asset, parent, socket, offset, rotation, mode, destroy, active, pool, cull)
        assert(mode == 0 and destroy and not active and pool == 0 and not cull)
        local c = effect(asset, parent)
        c.offset = offset
        return c
    end,
    SpawnSystemAtLocation = function(_, pawn, asset, pos, rotation, scale, destroy, active, pool, cull)
        assert(destroy and not active and pool == 0 and not cull)
        local c = effect(asset)
        c.scale = scale
        return c
    end,
})
local skeleton = object()
local anim = object({
    IsAnyMontagePlaying = function() return false end,
    PlaySlotAnimationAsDynamicMontage = function() return object({ started = now }) end,
    Montage_GetPosition = function(_, montage) return now - montage.started end,
    Montage_Stop = function() end,
})
local mesh = object({
    GetSocketLocation = function() return origin end,
    GetSocketRotation = function() return rotate end,
    K2_GetComponentRotation = function() return rotate end,
    DoesSocketExist = function() return true end,
    GetAnimInstance = function() return anim end,
    GetAnimationMode = function() return 0 end,
    GetSkinnedAsset = function() return object({ Skeleton = skeleton }) end,
})
local blade = object({
    DoesSocketExist = function(_, socket) return socket == "MeshStart" or socket == "MeshEnd" end,
    IsVisible = function() return false end,
    GetFullName = function() return "SkeletalMeshComponentBudgeted Weapon Mesh" end,
    GetSocketLocation = function() return origin end,
    IsA = function(_, class) return class ~= "/Script/Engine.StaticMeshComponent" end,
    GetSkinnedAsset = function() return object({
        GetBounds = function() return {
            Origin = { X = 0, Y = 0, Z = 45 }, BoxExtent = { X = 3, Y = 2, Z = 55 },
        } end,
    }) end,
})
local weapon = object({ K2_GetComponentsByClass = function() return { param(blade) } end })
local weapons = object({
    IsInWeaponTransition = function() return false end,
    IsArmed = function(_, tag) assert(tag.TagName == "Weapon.Slot.Main"); return armed end,
    GetCurrentWeaponIndex = function() return weapon_index end,
    GetCurrentWeapon = function(_, tag, data, with_pending)
        assert(tag.TagName == "Weapon.Slot.Main" and not with_pending)
        data.WeaponActors = { param(weapon) }
        data.Scabbards = { object({ GetComponentByClass = function() error("Scabbard used as blade") end }) }
    end,
})
local move = object({ MovementMode = 1, CustomMovementMode = 0,
    IsMovingOnGround = function() return true end,
    DisableMovement = function(self) self.MovementMode = 0 end,
    SetMovementMode = function(self, mode) self.MovementMode = mode end })
local world = object({ SpawnActor = function()
    local component = object({ SetMobility = function() end, SetCollisionEnabled = function() end,
        SetStaticMesh = function() return true end })
    return object({ StaticMeshComponent = component, SetLifeSpan = function() end,
        SetActorScale3D = function() end, K2_AttachToComponent = function() return true end,
        K2_DetachFromActor = function() end, K2_GetActorLocation = function() return origin end,
        K2_DestroyActor = function(self) self.destroyed = true end,
        K2_SetActorLocation = function() end })
end })
local pawn = object({ Mesh = mesh, CharacterMovement = move,
    GetComponentByClass = function() return weapons end,
    GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
    K2_GetActorRotation = function() return rotate end,
    GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end,
    GetWorld = function() return world end,
    DisableInput = function() end, EnableInput = function() end })
local camera = object({ GetCameraLocation = function() return { X = 0, Y = 0, Z = 140 } end,
    GetCameraRotation = function() return { Yaw = 90 } end })
local controller = object({ PlayerCameraManager = camera, IsMoveInputIgnored = function() return false end,
    IsInputKeyDown = function(_, key) return held[key.KeyName] == true end,
    DisableInput = function() end, EnableInput = function() end })
local poison_handles, poison_applications, handle_id = {}, 0, 0
local asc = object({
    GetActiveEffects = function(_, query)
        local result = {}
        local kind = query.EffectDefinition.path:find("Dot_Phase1", 1, true) and "dot" or "phase"
        for id, active_kind in pairs(poison_handles) do
            if active_kind == kind then result[#result + 1] = param({ Handle = id }, "LocalUnrealParam") end
        end
        return result
    end,
    BP_ApplyGameplayEffectToSelf = function(_, class, level, context)
        assert(class.path:find("GE_Poison_Phase1", 1, true) and level == 1 and next(context) == nil)
        poison_applications = poison_applications + 1
        handle_id = handle_id + 2
        poison_handles[handle_id - 1], poison_handles[handle_id] = "phase", "dot"
        return { Handle = handle_id - 1 }
    end,
    RemoveActiveGameplayEffect = function(_, handle, stacks)
        assert(stacks == -1)
        poison_handles[handle.Handle] = nil
    end,
})
local kismet = {
    Conv_SoftObjPathToSoftObjRef = function(_, path) return path end,
    MakeSoftObjectPath = function(_, path) return path end,
    LoadAsset_Blocking = function(_, path)
        return object({ path = path, Skeleton = skeleton,
            IsA = function() return not path:find("/ThrowTest/", 1, true) end,
            IsClass = function() return path:sub(-2) == "_C" end })
    end,
    LineTraceSingle = function(_, _, _, next_pos, _, _, _, _, hit)
        if next_pos.Z > 0 then return false end
        hit.ImpactPoint, hit.ImpactNormal = next_pos, { X = 0, Y = 0, Z = 1 }
        return true
    end,
}
local gameplay = { IsGamePaused = function() return false end, GetTimeSeconds = function() return now end }
package.loadlib = function(path, symbol)
    assert(path:find("PBZThrowAudio.dll", 1, true))
    if symbol == "PBZ_Prewarm" then return function() end end
    local cue, pan, gain = symbol:match("^PBZ_(%a+)_([0-4])_([0-4])$")
    assert(cue and pan and gain)
    return function()
        if audio_error then error("injected audio failure") end
        sounds[#sounds + 1] = { asset = cue, pan = tonumber(pan), gain = tonumber(gain) }
    end
end

local player_error = false
package.loaded.UEHelpers = { GetPlayer = function()
        if player_error then player_error = false; error("injected player lookup failure") end
        return pawn
    end,
    GetPlayerController = function() return controller end, GetGameplayStatics = function() return gameplay end,
    GetKismetSystemLibrary = function() return kismet end }

Key = { F7 = 7, F8 = 8, F9 = 9, F10 = 10, BACKSPACE = 1, ZERO = 48, NUM_ZERO = 96 }
FName = function(name) return name end
RegisterKeyBind = function(key, fn) keys[key] = fn end
LoopInGameThreadAfterFrames = function(frames, fn) assert(frames == 1); tick = fn end
StaticFindObject = function(path)
    if path:find("NiagaraFunctionLibrary") then return library end
    if path:find("AbilitySystemBlueprintLibrary") then
        return object({ GetAbilitySystemComponent = function(_, actor) assert(actor == pawn); return asc end })
    end
    return object()
end
print = function(message) events[#events + 1] = message end

assert(load(MOD_SCRIPT))()
assert(tick)
for code, handler in pairs(keys) do
    keys[code] = function() handler(); tick() end
end

local function advance(seconds)
    local deadline = now + seconds
    while now < deadline do
        now = math.min(deadline, now + .01)
        tick()
    end
end

local function count(pattern, list)
    local n = 0
    for _, item in ipairs(list or events) do
        if (type(item) == "table" and item.asset or item):find(pattern, 1, true) then n = n + 1 end
    end
    return n
end

local function chord(key)
    keys[48]()
    keys[key]()
end

local audio_build = MOD_SCRIPT:find("PBZThrowAudio.dll", 1, true) ~= nil

keys[8]()
advance(.22)
assert(count("F8 requires a drawn main weapon.") == 1 and count("Playing WeaponEnchant") == 0)
armed = true
keys[8]()
advance(.88)
assert(count("Weapon enchant started") == 0)
advance(.05)
assert(count("Weapon enchant started") == 1 and #effects == 3)
assert(effects[1].parent == blade and effects[1].colors["User.UE_Color"].R == .060)
assert(effects[1].scale.X == .20 and effects[1].sizes["User.UE_SpriteSize"].Y == 28)
assert(effects[1].offset.Z == 10 and effects[2].offset.Z == 40 and effects[3].offset.Z == 70)
advance(30.1)
assert(effects[1].active and effects[2].active and effects[3].active)
chord(8)
assert(not effects[1].active and not effects[2].active and not effects[3].active)
assert(effects[4].parent == blade and effects[4].asset:find("NS_Common_WeaponBurn_001", 1, true))
assert(effects[4].floats["User.UE_Length"] == 100 and effects[4].offset.Z == 50)
chord(8)
assert(not effects[4].active and effects[5].colors["User.UE_Color"].R == .30)
assert(effects[5].scale.X == .22 and effects[5].sizes["User.UE_SpriteSize"].Y == 24)
assert(effects[8].asset:find("NS_Hit_GroundMud_004", 1, true))
chord(8)
for i = 5, 8 do assert(not effects[i].active) end
assert(effects[9].colors["User.UE_Color"].R == .060)
assert(count("Playing WeaponEnchant") == 1)
advance(2.4)
weapon_index = 1
advance(.2)
assert(not effects[9].active and not effects[10].active and not effects[11].active)
keys[8]()
advance(.4)
armed = false
advance(2.7)
assert(count("Weapon enchant started") == 1)

keys[9]()
advance(1.16)
keys[1]()
assert(count("Successful throws") == 0)
assert(#sounds == 0)
for i, key in ipairs({ 9, 10, 9, 10, 10 }) do
    keys[key]()
    local just_released = key == 9 and 1.28 or .78
    advance(just_released)
    assert(count("Released ") == i and count("Flight smoke started") == i - 1)
    local suffix = key == 9 and "Dung" or "Stalk"
    if audio_build then
        assert(#sounds == 2 * i - 1)
        assert(sounds[#sounds].asset == suffix .. "Release" and sounds[#sounds].pan == 2 and sounds[#sounds].gain == 4)
    end
    advance(3.1 - just_released)
    assert(count("Released ") == i and count("Flight smoke started") == i and count("Impact effect started") == i)
    if audio_build then
        assert(#sounds == 2 * i)
        local hit_sound = sounds[#sounds]
        assert(hit_sound.asset == suffix .. "Impact")
        assert((key == 9 and hit_sound.pan == 0 and hit_sound.gain < 4) or
               (key == 10 and hit_sound.pan > 2 and hit_sound.gain == 4))
    end
    assert(count("Poison visual started") == (i == 5 and 1 or 0))
    assert(poison_applications == (i == 5 and 1 or 0))
end
assert(count("DungPie (mud 0.60)") == 2 and count("StalkDungPie (mud 0.40)") == 3)
assert(count("Native phase 1 poison applied (DOT handles: 1)") == 1)
local poison
for _, c in ipairs(effects) do
    assert(not c.asset:find("NS_GroundHit_Dust_Small_002", 1, true))
    if c.asset:find("NS_Debuff_004_Poison", 1, true) then poison = c end
end
assert(poison and poison.parent == mesh and poison.active)
-- F7 held first, then 0 after the chord window.
held.F7 = true
keys[7]()
advance(.45)
poison_handles[99] = "dot"
keys[96]()
held.F7 = false
assert(count("F7+0 poison damage OFF") == 1 and poison.active)
assert(poison_handles[99] == "dot" and poison_handles[1] == nil and poison_handles[2] == nil)
advance(8.1)
assert(not poison.active)
for _, key in ipairs({ 9, 10, 9, 10, 9 }) do keys[key](); advance(3.1) end
assert(count("Poison visual started") == 2 and poison_applications == 1 and count("Released ") == 10)
-- Holding 0 first works even after the tap recognition window.
held.Zero = true
keys[48]()
advance(.35)
keys[7]()
held.Zero = false
assert(count("F7+0 poison damage ON") == 1)
for _, key in ipairs({ 10, 10, 10, 10, 10 }) do keys[key](); advance(3.1) end
assert(count("Poison visual started") == 3 and poison_applications == 1 and poison_handles[99] == "dot")
assert(count("Native poison already active") == 1)

chord(9)
assert(count("Released ") == 15 and count("Release smoke DungPie ON") == 1)
keys[10]()
advance(2.1)
assert(count("Release smoke started") == 0)
keys[9]()
advance(3.1)
assert(count("Release smoke started for DungPie") == 1)
chord(10)
chord(9)
assert(count("Released ") == 17)
keys[9]()
advance(3.1)
keys[10]()
advance(2.1)
assert(count("Release smoke started for DungPie") == 1 and count("Release smoke started for StalkDungPie") == 1)
chord(10)
keys[10]()
advance(2.1)
assert(count("Release smoke started") == 2)
assert(count("error") == 0)

-- A chord with no active enchant plays the selected style on the animation frame.
armed = true
chord(8)
assert(count("Playing WeaponEnchant") == 3)
local styled = count("Weapon enchant style")
advance(.68)
assert(count("Weapon enchant style") == styled)
advance(.05)
assert(count("Weapon enchant style fire_common") == 2)
advance(2.3)

-- Switching refreshes the full 60 seconds; Backspace also clears the enchant.
chord(8)
local first = #effects - 3
assert(effects[first].colors["User.UE_Color"].R == .30)
advance(59.99)
for i = first, first + 3 do assert(effects[i].active) end
advance(.02)
for i = first, first + 3 do assert(not effects[i].active) end
chord(8)
advance(3.1)
first = #effects - 2
assert(effects[first].colors["User.UE_Color"].R == .060)
keys[1]()
for i = first, first + 2 do assert(not effects[i].active) end

-- A held key cannot stall the input queue forever.
held.F10 = true
local starts = count("Playing StalkDungPie")
keys[10]()
advance(.76)
assert(count("Playing StalkDungPie") == starts + 1)
held.F10 = false
advance(2.1)

-- One failing frame does not prevent the next key or flight from being processed.
keys[9]()
player_error = true
tick()
assert(count("Frame update error") == 1)
local released = count("Released ")
advance(3.1)
assert(count("Released ") == released + 1)

if audio_build then
    local n, hits = #sounds, count("Impact effect started")
    audio_error = true
    keys[10]()
    advance(3.1)
    assert(#sounds == n and count("Impact effect started") == hits + 1)
    assert(count("Throw audio unavailable") == 2)
    audio_error = false
    keys[10]()
    advance(3.1)
    assert(#sounds == n + 2 and count("Impact effect started") == hits + 2)
end

-- A weapon without readable bounds should still receive the native fire effect.
blade.GetSkinnedAsset = function() error("bounds unavailable") end
chord(8)
advance(1.0)
local fallback = effects[#effects]
assert(fallback.parent == blade and fallback.asset:find("NS_Common_WeaponBurn_001", 1, true))
assert(fallback.offset.X == 0 and fallback.offset.Y == 0 and fallback.offset.Z == 0)
