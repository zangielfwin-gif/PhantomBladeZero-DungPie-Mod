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
local actors = {}
local world = object({ SpawnActor = function(_, _, position)
    local component = object({ SetMobility = function() end, SetCollisionEnabled = function() end,
        SetStaticMesh = function() return true end })
    local actor = object({ StaticMeshComponent = component, SetLifeSpan = function() end, path = {position},
        SetActorScale3D = function() end, K2_AttachToComponent = function() return true end,
        K2_DetachFromActor = function() end, K2_GetActorLocation = function() return origin end,
        K2_DestroyActor = function(self) self.destroyed = true end,
        K2_SetActorLocation = function(self, position) self.path[#self.path + 1] = position end })
    actors[#actors + 1] = actor
    return actor
end })
local pawn_rotation = { Pitch = 0, Yaw = 0, Roll = 0 }
local pawn = object({ Mesh = mesh, CharacterMovement = move, bUseControllerRotationYaw = true,
    GetComponentByClass = function() return weapons end,
    GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
    K2_GetActorRotation = function() return pawn_rotation end,
    K2_SetActorRotation = function(_, rotation) pawn_rotation = rotation end,
    K2_GetActorLocation = function() return origin end,
    GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end,
    GetWorld = function() return world end,
    DisableInput = function() end, EnableInput = function() end })
local camera = object({ GetCameraLocation = function() return { X = 0, Y = 0, Z = 140 } end,
    GetCameraRotation = function() return { Yaw = 90 } end })
local left_stick = { X = 0, Y = 0 }
local controller = object({ PlayerCameraManager = camera, IsMoveInputIgnored = function() return false end,
    GetInputAnalogKeyState = function(_, key)
        return key.KeyName == "Gamepad_LeftX" and left_stick.X or left_stick.Y
    end,
    GetControlRotation = function() return rotate end,
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

Key = { O = 79, F6 = 6, F7 = 7, F8 = 8, F9 = 9, F10 = 10, BACKSPACE = 1, ZERO = 48, NUM_ZERO = 96,
    LEFT_ARROW = 37, UP_ARROW = 38, RIGHT_ARROW = 39, DOWN_ARROW = 40, RETURN = 13 }
FName = function(name) return name end
FText = function(text) return text end
RegisterKeyBind = function(key, fn) keys[key] = fn end
LoopInGameThreadAfterFrames = function(frames, fn) assert(frames == 1); tick = fn end
StaticFindObject = function(path)
    if path:find("WidgetBlueprintLibrary", 1, true) then
        return object({ Create = function(_, player, class, owner)
            assert(player == pawn and owner == controller and class.path:find("WBP_ActionMenu", 1, true))
            local tiles = {}
            for i = 1, 4 do
                local name = "Tile" .. i
                tiles[i] = object({
                    GetFName = function() return { ToString = function() return name end } end,
                    SetBrushColor = function(_, color) if color.A == 1 then menu_selection = name end end,
                })
            end
            menu_labels = {}
            for _, label in ipairs({ "Title", "Help", "Action1", "Action2", "Action3", "Action4" }) do
                tiles[#tiles + 1] = object({
                    GetFName = function() return { ToString = function() return label end } end,
                    Font = {}, SetFont = function() end,
                    SetText = function(_, text) menu_labels[label] = text end,
                })
            end
            return object({
                WidgetTree = { RootWidget = {
                    GetChildrenCount = function() return #tiles end,
                    GetChildAt = function(_, i) return tiles[i + 1] end,
                } },
                SetVisibility = function() end, SetAnchorsInViewport = function() end,
                SetAlignmentInViewport = function() end, SetDesiredSizeInViewport = function() end,
                SetPositionInViewport = function() end,
                AddToViewport = function() menu_visible = true end,
                RemoveFromParent = function() menu_visible = false end,
            })
        end })
    end
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

local function select_action(index)
    keys[79]()
    assert(menu_visible and menu_selection == "Tile1")
    if index % 2 == 0 then keys[39]() end
    if index >= 3 then keys[40]() end
    assert(menu_selection == "Tile" .. index)
    keys[13]()
    assert(not menu_visible)
end

select_action(2)
assert(count("F8 requires a drawn main weapon.") == 1)
armed = true
keys[8]()
assert(count("Playing WeaponEnchant") == 0)
select_action(2)
advance(.69)
assert(count("Weapon enchant started") == 0)
advance(.03)
assert(count("Weapon enchant started") == 1)
assert(effects[1].floats["User.UE_Length"] == 100 and effects[1].offset.Z == 50)
keys[8]()
assert(not effects[1].active and effects[2].colors["User.UE_Color"].R == .30)
keys[8]()
assert(not effects[2].active and effects[6].colors["User.UE_Color"].R == .060)
advance(30.1)
assert(effects[6].active)
weapon_index = 1
advance(.2)
assert(not effects[6].active)

blade.GetSkinnedAsset = function() error("bounds unavailable") end
keys[8]()
select_action(2)
advance(.72)
local fallback = effects[#effects]
assert(fallback.parent == blade and fallback.asset:find("NS_Common_WeaponBurn_001", 1, true))
assert(fallback.offset.X == 0 and fallback.offset.Y == 0 and fallback.offset.Z == 0)
keys[1]()
assert(not fallback.active)
advance(3)

keys[9]()
keys[10]()
assert(count("Released ") == 0)
select_action(3)
advance(.9)
keys[1]()
assert(count("Successful throws") == 0 and #sounds == 0)
for i, index in ipairs({3, 4, 3, 4, 4}) do
    select_action(index)
    advance(index == 3 and 1.08 or .57)
    assert(count("Released ") == i and #sounds == 2 * i - 1)
    advance(3.1)
    assert(count("Impact effect started") == i and #sounds == 2 * i)
    assert(poison_applications == (i == 5 and 1 or 0))
end
assert(count("Release smoke started for DungPie") == 2)
assert(count("Release smoke started for StalkDungPie") == 3)
assert(count("Poison visual started") == 1)
local poison
for _, effect in ipairs(effects) do
    if effect.asset:find("NS_Debuff_004_Poison", 1, true) then poison = effect end
end
assert(poison and poison.active)
poison_handles[99] = "dot"
keys[7]()
assert(not poison.active and poison_handles[99] == "dot" and poison_handles[1] == nil and poison_handles[2] == nil)
select_action(3)
advance(3.1)
assert(count("Successful throws") == 5 and poison_applications == 1)
keys[7]()

keys[79]()
keys[39]()
keys[40]()
assert(menu_selection == "Tile4")
keys[1]()
assert(not menu_visible)
keys[6]()
select_action(1)
advance(5.2)
assert(count("Playing PointDown") == 1 and count("Point-down spiral prop") == 0)
keys[6]()
select_action(1)
advance(.5)
assert(count("Point-down spiral prop") == 0)
keys[1]()
advance(2)
assert(count("Point-down spiral prop") == 0)
select_action(1)
held.D = true
advance(.10)
assert(pawn_rotation.Yaw > 0 and pawn_rotation.Yaw < 90 and move.MovementMode == 0)
advance(.25)
assert(math.abs(pawn_rotation.Yaw - 90) < .01)
held.D = false
left_stick.X = .10
advance(.10)
assert(math.abs(pawn_rotation.Yaw - 90) < .01)
left_stick.X, left_stick.Y = 0, 1
advance(.10)
assert(pawn_rotation.Yaw < 90 and pawn_rotation.Yaw > 0)
advance(.20)
assert(math.abs(pawn_rotation.Yaw) < .01)
left_stick.Y = 0
advance(7.05)
assert(pawn.bUseControllerRotationYaw and move.MovementMode == 1)
assert(count("Point-down spiral prop") == 8)
assert(count("Impact effect started for PointDownSpiral") == 8)
assert(count("Successful throws") == 5)
for i = #actors - 7, #actors do
    local path = actors[i].path
    assert(#path > 180 and path[2].Z < path[1].Z)
    assert(path[8].X ~= path[1].X and path[8].Y ~= path[1].Y)
end

keys[79]()
assert(menu_visible and menu_labels.Action1 == "下指" and menu_labels.Action4 == "小零食（后）")
keys[48]()
assert(menu_visible and menu_labels.Action1 == "Point Down")
keys[96]()
keys[79]()
assert(menu_visible and menu_labels.Action2 == "附魔" and menu_labels.Action3 == "小零食（前）")
keys[1]()
