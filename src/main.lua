local UE = require("UEHelpers")
local active
local flights = {}
local clips = {
    WeaponEnchant = { path = "/Game/ThrowTest/ForwardThrow.ForwardThrow", seconds = 85 / 30, use_time = 21 / 30 },
    DungPie = {
        path = "/Game/ThrowTest/DungPieThrow.DungPieThrow", seconds = 70 / 30, use_time = 31 / 30,
        projectile = {
            mesh = "/Game/PBZThrowPropsSafe/SM_DungPie.SM_DungPie",
            speed = 1500, lift = 260, gravity = 1500, scale = .34, lifetime = 2,
        },
    },
    StalkDungPie = {
        path = "/Game/ThrowTest/StalkDungPieThrow.StalkDungPieThrow", seconds = 50 / 30, use_time = 16 / 30,
        projectile = {
            mesh = "/Game/PBZThrowPropsSafe/SM_StalkDungPie.SM_StalkDungPie",
            speed = -200, lift = 0, gravity = 980, scale = .34, lifetime = 5,
        },
    },
}

local function log(message)
    print("[PBZThrowTest] " .. message .. "\n")
end

local function valid(object)
    if not object then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result
end

local function restore(label, callback)
    local ok, err = pcall(callback)
    if not ok then log(label .. ": " .. tostring(err)) end
end

local function sample_pose(s, label, elapsed)
    restore("pose sample", function()
        local function bone(name)
            return s.mesh:GetSocketLocation(FName(name))
        end
        local l, r = bone("upperarm_l"), bone("upperarm_r")
        local hl, hr = bone("thigh_l"), bone("thigh_r")
        local lf, rf = bone("foot_l"), bone("foot_r")
        local lt, rt = bone("ball_l"), bone("ball_r")
        local yaw = s.pawn:K2_GetActorRotation().Yaw
        local function heading(x,y)
            return (math.deg(math.atan(y,x)) - yaw + 180) % 360 - 180
        end
        local hand, hip = bone("hand_r"), bone("Pelvis")
        local yaw_rad = math.rad(yaw)
        local x, y = hand.X-hip.X, hand.Y-hip.Y
        local f, right = x * math.cos(yaw_rad) + y * math.sin(yaw_rad),
            -x * math.sin(yaw_rad) + y * math.cos(yaw_rad)
        log(string.format("%s %s %s %.3f actor %.1f mesh %.1f shoulder %.1f hips %.1f toes %.1f hand %.1f/%.1f/%.1f anim %.3f mode %d",
            s.name,"FullBody",label,elapsed,yaw,s.mesh:K2_GetComponentRotation().Yaw,
            heading(l.X-r.X,l.Y-r.Y),heading(hl.X-hr.X,hl.Y-hr.Y),
            heading(lt.X-lf.X+rt.X-rf.X,lt.Y-lf.Y+rt.Y-rf.Y),f,right,hand.Z-hip.Z,
            s.montage and s.anim:Montage_GetPosition(s.montage) or -1,s.mesh:GetAnimationMode()))
    end)
end
local function load_asset(path)
    local kismet = UE.GetKismetSystemLibrary()
    local reference = kismet:Conv_SoftObjPathToSoftObjRef(kismet:MakeSoftObjectPath(path))
    return kismet:LoadAsset_Blocking(reference)
end

local smoke = "/Game/PBZContent/VFX/SceneFX/SmokeAndFIre/NS_Smoke_002.NS_Smoke_002"
local dust = "/PBZVFXPack/VFX/BattleFX/Common/NS_GroundHit_Dust_Small_002.NS_GroundHit_Dust_Small_002"
local mud = "/PBZVFXPack/VFX/BattleFX/Common/HitEffect/NS_Hit_GroundMud_004.NS_Hit_GroundMud_004"
local poison = "/PBZVFXPack/VFX/BattleFX/Common/NS_Debuff_004_Poison.NS_Debuff_004_Poison"
local poison_phase = "/PBZCombatAsset/Prototypes/GameplayEffects/Inflictions/GE_Poison_Phase1.GE_Poison_Phase1_C"
local poison_dot = "/PBZCombatAsset/Prototypes/GameplayEffects/Inflictions/GE_Poison_Dot_Phase1.GE_Poison_Dot_Phase1_C"
local glow_root = "/PBZVFXPack/VFX/BattleFX/YanQianSui/"
local enchant_styles = {
    { name = "dung" },
    { name = "red", system = "NS_YanQianSui_WeaponBuff_301_Red" },
    { name = "blue", system = "NS_YanQianSui_WeaponBuff_302_Blue" },
    { name = "white", system = "NS_YanQianSui_WeaponBuff_303_White" },
}
local brown = { R = .18, G = .055, B = .019, A = .9 }
local dark_glow = { R = .036, G = .012, B = .003, A = 1 }
local blade_tint = {
    color = { R = .30, G = .084, B = .018, A = 1 },
    glow = { R = .32, G = .080, B = .012, A = 1 },
}
local release_puff = { floats = { ["User.UE_ParSizeScale"] = .35, ["User.UE_VelScale"] = .18 } }
local release_smoke = { DungPie = false, StalkDungPie = false }
local zero = { X = 0, Y = 0, Z = 0 }
local no_rotation = { Pitch = 0, Yaw = 0, Roll = 0 }

local throw_sounds = {
    DungPie = { release = "DungRelease", impact = "DungImpact" },
    StalkDungPie = { release = "StalkRelease", impact = "StalkImpact" },
}
local script_file = debug.getinfo(1, "S").source
local script_dir = script_file:match("^@(.*[/\\])")
local sound_dll = (script_dir or "ue4ss/Mods/PBZThrowTest/Scripts/") .. "PBZThrowAudio.dll"
local sound_functions, failed_sounds = {}, {}
local sound_warmed = false

local function prewarm_throw_audio()
    if sound_warmed then return end
    sound_warmed = true
    pcall(function()
        local start = package.loadlib(sound_dll, "PBZ_Prewarm")
        if start then start() end
    end)
end

local function spatial_sound(location)
    local controller = UE.GetPlayerController()
    if not valid(controller) or not valid(controller.PlayerCameraManager) then return 2, 4 end
    local camera = controller.PlayerCameraManager
    local listener = camera:GetCameraLocation()
    local yaw = math.rad(camera:GetCameraRotation().Yaw)
    local dx, dy, dz = location.X - listener.X, location.Y - listener.Y, location.Z - listener.Z
    local range = math.sqrt(dx * dx + dy * dy + dz * dz)
    if range >= 1850 then return end
    local balance = (-dx * math.sin(yaw) + dy * math.cos(yaw)) / math.max(range, 1)
    local pan = math.max(0, math.min(4, math.floor(2.5 + 2.3 * balance)))
    local gain = math.max(0, math.min(4, 4 - math.floor(math.max(0, range - 280) / 315)))
    return pan, gain
end

local function play_throw_sound(f, stage, location)
    local name = throw_sounds[f.name][stage]
    local ok, played = pcall(function()
        local spatial_ok, pan, gain = pcall(spatial_sound, location)
        if not spatial_ok then pan, gain = 2, 4 end
        if pan == nil then return false end
        local symbol = string.format("PBZ_%s_%d_%d", name, pan, gain)
        local queue = sound_functions[symbol]
        if not queue then
            local err
            queue, err = package.loadlib(sound_dll, symbol)
            assert(queue, err)
            sound_functions[symbol] = queue
        end
        queue()
        return true
    end)
    if ok and played then
        failed_sounds[name] = nil
        log("Throw audio " .. stage .. " " .. f.name)
    elseif not ok and not failed_sounds[name] then
        failed_sounds[name] = true
        log("Throw audio unavailable for " .. name .. ": " .. tostring(played))
    end
end

local fx_assets = {}
local throw_pawn, throw_count = nil, 0
local poison_fx, enchant_fx
local damage_enabled, poison_damage = true, nil
local enchant_style = 1

local function same_object(a, b)
    return valid(a) and valid(b) and a:GetAddress() == b:GetAddress()
end

local function array_value(entry)
    -- UE4SS returns parameter wrappers for elements of reflected array outputs.
    local ok, kind = pcall(function() return entry:type() end)
    if ok and (kind == "RemoteUnrealParam" or kind == "LocalUnrealParam") then
        return entry:get()
    end
    return entry
end

local function niagara(path)
    local library = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    assert(valid(library), "Niagara function library unavailable")
    local asset = fx_assets[path]
    if not valid(asset) then
        log("Loading native effect " .. path)
        asset = load_asset(path)
        assert(valid(asset) and asset:IsA("/Script/Niagara.NiagaraSystem"), "Could not load " .. path)
        fx_assets[path] = asset
    end
    return library, asset
end

local function stop_fx(component)
    if valid(component) then
        restore("Stop native effect", function()
            component:SetVisibility(false, false)
            component:Deactivate()
        end)
    end
end

local function activate_fx(component, color_param, smoke_glow, tuning)
    assert(valid(component), "Niagara spawn returned no component")
    local ok, err = pcall(function()
        if color_param then
            component:SetVariableLinearColor(FName(color_param), tuning and tuning.color or brown)
        end
        if smoke_glow then
            component:SetVariableLinearColor(FName("User.UE_GlowColor"), tuning and tuning.glow or dark_glow)
        end
        if tuning and tuning.floats then
            for name, value in pairs(tuning.floats) do component:SetVariableFloat(FName(name), value) end
        end
        component:Activate(true)
    end)
    if not ok then
        stop_fx(component)
        error(err)
    end
    return component
end

local function attach_fx(path, parent, socket, offset, scale, color_param, tuning)
    local library, asset = niagara(path)
    -- Keep relative location, auto destroy, configure before activating, no pooling.
    local component = library:SpawnSystemAttached(asset, parent, socket, offset, no_rotation, 0,
        true, false, 0, false)
    assert(valid(component), "Niagara attach returned no component")
    if scale ~= 1 then
        local ok, err = pcall(function()
            component:SetWorldScale3D({ X = scale, Y = scale, Z = scale })
        end)
        if not ok then
            stop_fx(component)
            error(err)
        end
    end
    return activate_fx(component, color_param, path == smoke, tuning)
end

local function burst_fx(pawn, path, location, scale, color_param, tuning)
    local library, asset = niagara(path)
    local component = library:SpawnSystemAtLocation(pawn, asset, location, no_rotation,
        { X = scale, Y = scale, Z = scale }, true, false, 0, false)
    return activate_fx(component, color_param, false, tuning)
end

local function stop_poison_damage()
    local owned = poison_damage
    poison_damage = nil
    if not owned or not valid(owned.asc) then return end
    for _, handle in ipairs(owned.handles) do
        restore("Remove mod poison", function() owned.asc:RemoveActiveGameplayEffect(handle, -1) end)
    end
end

local function toggle_poison_damage()
    damage_enabled = not damage_enabled
    if not damage_enabled then stop_poison_damage() end
    log("F7+0 poison damage " .. (damage_enabled and "ON" or "OFF (visual only)"))
end

local function apply_poison_damage(pawn)
    local library = StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    assert(valid(library), "Ability system library unavailable")
    local asc = library:GetAbilitySystemComponent(pawn)
    assert(valid(asc), "Player ability system unavailable")
    local phase, dot = load_asset(poison_phase), load_asset(poison_dot)
    assert(valid(phase) and valid(dot) and phase:IsClass() and dot:IsClass(), "Native poison classes unavailable")
    stop_poison_damage()
    local existing_phase = asc:GetActiveEffects({ EffectDefinition = phase })
    local existing_dot = asc:GetActiveEffects({ EffectDefinition = dot })
    assert(type(existing_phase) == "table" and type(existing_dot) == "table", "Cannot query active poison effects")
    if next(existing_phase) or next(existing_dot) then
        log("Native poison already active; preserving its source")
        return
    end

    -- Phase 1 applies its own nonlethal DOT. The engine creates its effect context when empty.
    local handle = asc:BP_ApplyGameplayEffectToSelf(phase, 1, {})
    assert(type(handle) == "table" and type(handle.Handle) == "number" and handle.Handle >= 0,
        "Native poison application rejected")
    local owned = { pawn = pawn, asc = asc, handles = { handle } }
    poison_damage = owned
    -- The child effect has its own handle. Record it so switching off can stop both effects.
    local dots = asc:GetActiveEffects({ EffectDefinition = dot })
    for _, entry in pairs(dots) do
        local child = array_value(entry)
        if child and type(child.Handle) == "number" and child.Handle >= 0 then
            table.insert(owned.handles, 1, { Handle = child.Handle })
        end
    end
    log(string.format("Native phase 1 poison applied (DOT handles: %d)", #owned.handles - 1))
end

local function record_throw(s, now)
    if not same_object(s.pawn, throw_pawn) then
        throw_pawn, throw_count = s.pawn, 0
    end
    throw_count = throw_count + 1
    log(string.format("Successful throws %d/5", throw_count))
    if throw_count ~= 5 then return end
    throw_count = 0
    if poison_fx then stop_fx(poison_fx.component); poison_fx = nil end
    restore("Poison effect", function()
        local component = attach_fx(poison, s.mesh, FName("None"), zero, 1)
        poison_fx = { pawn = s.pawn, component = component, expires = now + 8 }
        log("Poison visual started after the fifth throw (8s)")
    end)
    if damage_enabled then
        restore("Native poison damage", function() apply_poison_damage(s.pawn) end)
    end
end

local function toggle_release_smoke(name)
    release_smoke[name] = not release_smoke[name]
    log("Release smoke " .. name .. " " .. (release_smoke[name] and "ON" or "OFF"))
end

local function release_fx(f)
    if not release_smoke[f.name] then return end
    restore("Release smoke", function()
        burst_fx(f.pawn, dust, f.origin, .04, "User.UE_Color", release_puff)
        log("Release smoke started for " .. f.name)
    end)
end

local function start_flight_fx(f)
    local scale = f.name == "StalkDungPie" and .13 or .11
    restore("Flight smoke", function()
        f.trail = attach_fx(smoke, f.actor.StaticMeshComponent, FName("None"), zero, scale, "User.UE_Color")
        log("Flight smoke started for " .. f.name)
    end)
end

local function impact_fx(f, pawn, location)
    restore("Impact effect", function()
        local scale = f.name == "StalkDungPie" and .40 or .60
        burst_fx(pawn, mud, location, scale, "User.UE_MudColor")
        log(string.format("Impact effect started for %s (mud %.2f)", f.name, scale))
    end)
end

local function drawn_main_weapon(pawn)
    local class = StaticFindObject("/Script/SGameCombatSystem.CharacterWeaponsComponent")
    if not valid(class) then return end
    local weapons = pawn:GetComponentByClass(class)
    if not valid(weapons) or weapons:IsInWeaponTransition() then return end
    local tag = { TagName = FName("Weapon.Slot.Main") }
    if weapons:IsArmed(tag) ~= true then return end
    local index = weapons:GetCurrentWeaponIndex(tag, false)
    if type(index) ~= "number" or index < 0 then return end
    return weapons, tag, index
end

local function clear_weapon_effect(state)
    for _, component in ipairs(state.components) do stop_fx(component) end
    state.components = {}
end

local function stop_enchant(reason)
    if not enchant_fx then return end
    clear_weapon_effect(enchant_fx)
    enchant_fx = nil
    log("Weapon enchant ended: " .. reason)
end

local function blade_points(mesh)
    local sockets = {}
    local groups = {
        { "MeshStart", "BladeBloodStart" },
        { "MeshMiddle", "DeflectMiddle", "Deflect_Middle" },
        { "MeshEnd", "TrailEnd", "Edge Socket", "TrailStart", "DeflectTopMiddle" },
    }
    for _, group in ipairs(groups) do
        for _, name in ipairs(group) do
            local socket = FName(name)
            if mesh:DoesSocketExist(socket) then
                sockets[#sockets + 1] = socket
                break
            end
        end
    end
    return sockets
end

local function weapon_mesh(actor)
    local mesh_class = StaticFindObject("/Script/Engine.MeshComponent")
    assert(valid(mesh_class), "Mesh component class unavailable")
    local named = actor["Weapon Mesh"]
    if valid(named) and named:IsA(mesh_class) then return named end
    local best, score = nil, -1
    for _, entry in pairs(actor:K2_GetComponentsByClass(mesh_class)) do
        local mesh = array_value(entry)
        if valid(mesh) then
            local points = blade_points(mesh)
            local rank = #points * 2 + (mesh:IsVisible() and 1 or 0)
            if rank > score then best, score = mesh, rank end
        end
    end
    return best
end

local function replace_weapon_effect(state)
    clear_weapon_effect(state)
    local style = enchant_styles[enchant_style]
    local components = state.components
    for _, mesh in ipairs(state.blades) do
        if valid(mesh) then
            if style.system then
                local path = glow_root .. style.system .. "." .. style.system
                restore("Native weapon glow " .. style.name, function()
                    components[#components + 1] = attach_fx(path, mesh, FName("None"), zero, 1)
                end)
            else
                local points = blade_points(mesh)
                if #points == 0 then points[1] = FName("None") end
                for _, socket in ipairs(points) do
                    restore("Brown blade smoke", function()
                        components[#components + 1] =
                            attach_fx(smoke, mesh, socket, zero, .36, "User.UE_Color", blade_tint)
                    end)
                end
                restore("Brown blade splash", function()
                    local middle = points[math.ceil(#points / 2)]
                    components[#components + 1] =
                        burst_fx(state.pawn, mud, mesh:GetSocketLocation(middle), .27, "User.UE_MudColor", blade_tint)
                end)
            end
        end
    end
    log(string.format("Weapon enchant style %s (%d active effects)", style.name, #components))
end

local function cycle_weapon_effect(pawn, now)
    enchant_style = enchant_style % #enchant_styles + 1
    log("F8+0 selected weapon enchant: " .. enchant_styles[enchant_style].name)
    if not enchant_fx or not same_object(pawn, enchant_fx.pawn) or now >= enchant_fx.expires then return false end
    local weapons, _, index = drawn_main_weapon(pawn)
    if same_object(weapons, enchant_fx.weapons) and index == enchant_fx.index then
        replace_weapon_effect(enchant_fx)
        return true
    end
    return false
end

local function apply_enchant(s, now)
    local weapons, tag, index = drawn_main_weapon(s.pawn)
    if not same_object(weapons, s.weapons) or index ~= s.weapon_index then
        log("F8 enchant skipped: the original weapon is no longer drawn")
        return
    end
    local data, current_index = {}, {}
    -- The game's RuntimeWeaponSingleData exposes blades and scabbards as separate arrays.
    weapons:GetCurrentWeapon(tag, data, false, current_index)
    if type(data.WeaponActors) ~= "table" or #data.WeaponActors == 0 then
        log("F8 enchant skipped: current weapon has no blade actors")
        return
    end

    local blade_actors = {}
    for _, entry in ipairs(data.WeaponActors) do
        local actor = array_value(entry)
        if valid(actor) then
            blade_actors[#blade_actors + 1] = actor
        end
    end
    log(string.format("F8 current weapon: %d/%d live blade actors", #blade_actors, #data.WeaponActors))
    if #blade_actors == 0 then return end

    stop_enchant("refreshed")
    local state = { pawn = s.pawn, weapons = weapons, index = index, components = {}, blades = {},
        expires = now + 30, next_check = now }
    enchant_fx = state
    for _, actor in ipairs(blade_actors) do
        restore("Attach enchant to blade", function()
            local mesh = weapon_mesh(actor)
            if not valid(mesh) then log("F8 no mesh on " .. actor:GetFullName()); return end
            state.blades[#state.blades + 1] = mesh
            log("F8 blade mesh: " .. mesh:GetFullName())
        end)
    end
    if #state.blades == 0 then
        enchant_fx = nil
        log("F8 enchant could not resolve a blade mesh")
    else
        replace_weapon_effect(state)
        log("Weapon enchant started (30s)")
    end
end

local function update_enchant(s, now)
    if not s.weapons or s.enchant_applied then return end
    if s.anim:Montage_GetPosition(s.montage) < s.use_time then return end
    s.enchant_applied = true
    restore("F8 weapon enchant", function() apply_enchant(s, now) end)
end

local function update_status_fx(pawn, now)
    if not same_object(pawn, throw_pawn) then throw_pawn, throw_count = nil, 0 end
    if poison_fx and (not same_object(pawn, poison_fx.pawn) or now >= poison_fx.expires) then
        stop_fx(poison_fx.component)
        poison_fx = nil
    end
    if poison_damage and not same_object(pawn, poison_damage.pawn) then stop_poison_damage() end
    if not enchant_fx then return end
    if not same_object(pawn, enchant_fx.pawn) or now >= enchant_fx.expires then
        stop_enchant("expired or player changed")
    elseif now >= enchant_fx.next_check then
        enchant_fx.next_check = now + .15
        local ok, weapons, _, index = pcall(drawn_main_weapon, pawn)
        if not ok or not same_object(weapons, enchant_fx.weapons) or index ~= enchant_fx.index then
            stop_enchant("weapon sheathed or switched")
        end
    end
end

local function spawn_held_prop(s)
    local settings = s.projectile
    log("Loading mesh " .. settings.mesh)
    local asset = load_asset(settings.mesh)
    assert(valid(asset), "Could not load projectile mesh " .. settings.mesh)
    log("Mesh loaded for " .. s.name)
    local actor_class = StaticFindObject("/Script/Engine.StaticMeshActor")
    assert(valid(actor_class), "StaticMeshActor class unavailable")
    local world = s.pawn:GetWorld()
    assert(valid(world), "Game world unavailable")

    local socket = FName("middle_01_r")
    if not s.mesh:DoesSocketExist(socket) then socket = FName("hand_r") end
    local actor = world:SpawnActor(actor_class, s.mesh:GetSocketLocation(socket),
        s.mesh:GetSocketRotation(socket))
    assert(valid(actor), "Could not spawn projectile actor")
    s.held_prop = actor
    actor:SetLifeSpan(s.seconds + settings.lifetime + 1)

    local component = actor.StaticMeshComponent
    assert(valid(component), "Projectile mesh component unavailable")
    component:SetMobility(2) -- Movable
    component:SetCollisionEnabled(0) -- Flight uses a trace; the prop cannot block the pawn.
    log("Applying mesh for " .. s.name)
    assert(component:SetStaticMesh(asset), "Could not assign projectile mesh")
    local scale = settings.scale
    actor:SetActorScale3D({ X = scale, Y = scale, Z = scale })
    assert(actor:K2_AttachToComponent(s.mesh, socket, 2, 2, 1, false), "Could not attach prop to right hand")
    log("Held prop attached for " .. s.name)
end

local function release_prop(s, now, montage_time)
    local actor = s.held_prop
    local settings = s.projectile
    local origin = actor:K2_GetActorLocation()
    local forward = s.pawn:GetActorForwardVector()
    actor:K2_DetachFromActor(1, 1, 1) -- Keep the world-space hand transform.
    s.held_prop = nil
    s.released = true
    local f = {
        actor = actor, pawn = s.pawn, origin = origin, pos = origin, start = now,
        vx = forward.X * settings.speed, vy = forward.Y * settings.speed,
        lift = settings.lift, gravity = settings.gravity, lifetime = settings.lifetime,
        name = s.name,
    }
    flights[#flights + 1] = f
    log(string.format("Released %s at montage %.4fs (key %.4fs), velocity %.0f/%.0f/%.0f cm/s",
        s.name, montage_time, s.use_time, forward.X * settings.speed,
        forward.Y * settings.speed, settings.lift))
    play_throw_sound(f, "release", origin)
    record_throw(s, now)
    release_fx(f)
end

local function update_held_prop(s, now)
    if not s.projectile or s.released then return end
    local position = s.anim:Montage_GetPosition(s.montage)
    if position < s.use_time - .24 then return end
    if not valid(s.held_prop) then spawn_held_prop(s) end
    if position >= s.use_time then release_prop(s, now, position) end
end

local trace_color = { R = 0, G = 0, B = 0, A = 0 }
local function update_flight(f, pawn, now)
    if not valid(f.actor) then return true end
    if not valid(pawn) or not valid(f.pawn) or pawn:GetAddress() ~= f.pawn:GetAddress() then
        f.actor:K2_DestroyActor()
        return true
    end
    local t = now - f.start
    if t <= 0 then return false end
    if t >= f.lifetime then
        f.actor:K2_DestroyActor()
        log("Flight expired: " .. f.name)
        return true
    end
    local next_pos = {
        X = f.origin.X + f.vx * t,
        Y = f.origin.Y + f.vy * t,
        Z = f.origin.Z + f.lift * t - .5 * f.gravity * t * t,
    }
    local hit = {}
    -- Visibility channel, no debug draw, and ignore the throwing pawn.
    if UE.GetKismetSystemLibrary():LineTraceSingle(pawn, f.pos, next_pos, 0, false,
        {}, 0, hit, true, trace_color, trace_color, 0) then
        local point, normal = hit.ImpactPoint, hit.ImpactNormal
        f.actor:K2_SetActorLocation({
            X = point.X + 4 * normal.X, Y = point.Y + 4 * normal.Y, Z = point.Z + 4 * normal.Z,
        }, false, {}, true)
        f.actor:SetLifeSpan(.8)
        stop_fx(f.trail)
        f.trail = nil
        play_throw_sound(f, "impact", point)
        impact_fx(f, pawn, point)
        log(string.format("Landed %s after %.3fs, XY distance %.0f cm", f.name, t,
            math.sqrt((point.X - f.origin.X)^2 + (point.Y - f.origin.Y)^2)))
        return true
    end
    f.actor:K2_SetActorLocation(next_pos, false, {}, true)
    f.pos = next_pos
    -- Let the projectile move clear of the thrower's hand before emitting the trail.
    local trail_delay = f.name == "StalkDungPie" and .23 or .12
    if not f.trail_started and t >= trail_delay then
        f.trail_started = true
        start_flight_fx(f)
    end
    return false
end

local function update_flights(pawn, now)
    for i = #flights, 1, -1 do
        local f = flights[i]
        local ok, done = pcall(update_flight, f, pawn, now)
        if not ok then
            log("Flight error: " .. tostring(done))
            if valid(f.actor) then restore("destroy failed projectile", function() f.actor:K2_DestroyActor() end) end
        end
        if not ok or done then
            stop_fx(f.trail)
            table.remove(flights, i)
        end
    end
end


local function finish(reason)
    local s = active
    if not s then return end
    active = nil
    if valid(s.held_prop) then
        restore("destroy held prop", function() s.held_prop:K2_DestroyActor() end)
    end
    if valid(s.montage) and valid(s.anim) and reason ~= "completed" then
        restore("stop test montage", function() s.anim:Montage_Stop(.16, s.montage) end)
    end
    if s.movement and valid(s.move) then
        restore("restore movement", function()
            if s.move.MovementMode == 0 then
                s.move:SetMovementMode(s.mode, s.custom)
            end
        end)
    end
    if s.pawn_input and valid(s.pawn) and valid(s.controller) then
        restore("restore pawn input", function() s.pawn:EnableInput(s.controller) end)
    end
    if s.controller_input and valid(s.controller) then
        restore("restore controller input", function() s.controller:EnableInput(s.controller) end)
    end
    if valid(s.pawn) and valid(s.mesh) then
        sample_pose(s, "finished", UE.GetGameplayStatics():GetTimeSeconds(s.pawn) - s.start)
    end
    log("Stopped: " .. reason)
end

local function start(name)
    if active then log(name .. " ignored while " .. active.name .. " is playing"); return end
    local pawn, controller = UE.GetPlayer(), UE.GetPlayerController()
    if not valid(pawn) or not valid(controller) then return end
    if UE.GetGameplayStatics():IsGamePaused(pawn) or controller:IsMoveInputIgnored() then
        log(name .. " ignored while player controls are blocked")
        return
    end
    local mesh, move = pawn.Mesh, pawn.CharacterMovement
    if not valid(mesh) or not valid(move) or not move:IsMovingOnGround() then
        log(name .. " requires a grounded player")
        return
    end
    local velocity = pawn:GetVelocity()
    if velocity.X ^ 2 + velocity.Y ^ 2 + velocity.Z ^ 2 > 1 then
        log("Stand still before testing.")
        return
    end
    local anim = mesh:GetAnimInstance()
    if mesh:GetAnimationMode() ~= 0 or not valid(anim) or anim:IsAnyMontagePlaying() then
        log("Wait for the current animation to finish.")
        return
    end
    local weapons, weapon_index
    if name == "WeaponEnchant" then
        local ok, component, _, index = pcall(drawn_main_weapon, pawn)
        if not ok then log("F8 weapon state unavailable: " .. tostring(component)); return end
        if not valid(component) then log("F8 requires a drawn main weapon."); return end
        weapons, weapon_index = component, index
    end
    local item = clips[name]
    local clip = load_asset(item.path)
    if not valid(clip) then log("Could not load " .. item.path); return end
    local skinned = mesh:GetSkinnedAsset()
    local skeleton = valid(skinned) and skinned.Skeleton
    if not valid(skeleton) or not valid(clip.Skeleton)
        or skeleton:GetAddress() ~= clip.Skeleton:GetAddress() then
        log("Skeleton mismatch for " .. name)
        return
    end
    local s = { pawn = pawn, controller = controller, mesh = mesh, move = move,
        mode = move.MovementMode, custom = move.CustomMovementMode,
        name = name, anim = anim, seconds = item.seconds,
        projectile = item.projectile, use_time = item.use_time,
        weapons = weapons, weapon_index = weapon_index,
        start = UE.GetGameplayStatics():GetTimeSeconds(pawn), next_sample = 1 }
    s.times = { .035, .11, .22 }
    if item.use_time then
        s.times[#s.times + 1] = item.use_time - .065
        s.times[#s.times + 1] = item.use_time
        s.times[#s.times + 1] = item.use_time + .065
    end
    s.times[#s.times + 1] = item.seconds - .1
    sample_pose(s, "before", 0)
    active = s
    s.pawn_input = true
    pawn:DisableInput(controller)
    s.controller_input = true
    controller:DisableInput(controller)
    s.movement = true
    move:DisableMovement()
    -- Keep the original AnimBP active so the montage blends from and back to the live pose.
    local montage = anim:PlaySlotAnimationAsDynamicMontage(clip, FName("FullBody"), .16, .26, 1, 1, -1, 0)
    if not valid(montage) then finish("FullBody slot unavailable"); return end
    s.montage = montage
    if s.projectile then prewarm_throw_audio() end
    log("Playing " .. name .. ": " .. item.path)
end

local function guarded(label, callback)
    local ok, err = pcall(callback)
    if not ok then
        log(label .. ": " .. tostring(err))
        restore("Reset action after Lua error", function() finish("Lua error") end)
    end
end

local key_events = {}
local function key(keycode, callback)
    RegisterKeyBind(keycode, function()
        key_events[#key_events + 1] = callback
    end)
end
-- Reserve a short window to distinguish an action from its 0 chord.
local chord_window = .20
local max_hold_wait = .75
local pending_action, zero_pawn, zero_at

local function input_context()
    local pawn, controller = UE.GetPlayer(), UE.GetPlayerController()
    if not valid(pawn) or not valid(controller) then return end
    local gameplay = UE.GetGameplayStatics()
    if gameplay:IsGamePaused(pawn) then return end
    return pawn, controller, gameplay:GetTimeSeconds(pawn)
end

local function key_held(controller, name)
    local ok, down = pcall(function()
        return controller:IsInputKeyDown({ KeyName = FName(name) })
    end)
    return ok and down == true
end

local function run_chord(action, pawn, now)
    pending_action, zero_at = nil, nil
    if action == "WeaponEnchant" then
        if not cycle_weapon_effect(pawn, now) then start("WeaponEnchant") end
    elseif action == "PoisonDamage" then
        toggle_poison_damage()
    else
        toggle_release_smoke(action)
    end
end

local function queue_action(action, input_key)
    local pawn, controller, now = input_context()
    if not pawn then log(input_key .. " ignored outside active play"); return end
    local recent_zero = same_object(pawn, zero_pawn) and zero_at and now >= zero_at and now - zero_at <= chord_window
    if recent_zero or key_held(controller, "Zero") or key_held(controller, "NumPadZero") then
        run_chord(action, pawn, now)
    else
        pending_action = { action = action, key = input_key, pawn = pawn, ready = now + chord_window,
            latest = now + max_hold_wait }
        log(input_key .. " queued: " .. action)
    end
end

local function press_zero()
    local pawn, controller, now = input_context()
    if not pawn then return end
    local pending = pending_action
    if pending and same_object(pawn, pending.pawn) and (now <= pending.ready or key_held(controller, pending.key)) then
        run_chord(pending.action, pawn, now)
    else
        zero_pawn, zero_at = pawn, now
    end
end

local function update_pending_action(pawn, now)
    local pending = pending_action
    if not pending then return end
    local controller = UE.GetPlayerController()
    if not same_object(pawn, pending.pawn) or not valid(controller) or UE.GetGameplayStatics():IsGamePaused(pawn) then
        pending_action = nil
    elseif now >= pending.ready and (now >= pending.latest or not key_held(controller, pending.key)) then
        pending_action = nil
        if pending.action ~= "PoisonDamage" then start(pending.action) end
    end
end

key(Key.F7, function() queue_action("PoisonDamage", "F7") end)
key(Key.F8, function() queue_action("WeaponEnchant", "F8") end)
key(Key.F9, function() queue_action("DungPie", "F9") end)
key(Key.F10, function() queue_action("StalkDungPie", "F10") end)
key(Key.ZERO, press_zero)
key(Key.NUM_ZERO, press_zero)
key(Key.BACKSPACE, function()
    pending_action = nil
    finish("cancelled")
end)

-- Process inputs, animation and effects on the same game-thread frame.
local function update_frame()
    if #key_events > 0 then
        local events = key_events
        key_events = {}
        for _, callback in ipairs(events) do guarded("Input error", callback) end
    end
    if not pending_action and not active and #flights == 0 and not poison_fx and not enchant_fx then return end
    guarded("Frame update error", function()
        local pawn = UE.GetPlayer()
        local now = valid(pawn) and UE.GetGameplayStatics():GetTimeSeconds(pawn) or 0
        if #flights > 0 then update_flights(pawn, now) end
        update_status_fx(pawn, now)
        update_pending_action(pawn, now)
        local s = active
        if not s then return end
        if not same_object(pawn, s.pawn) or not valid(s.mesh) or not valid(s.move) or s.move.MovementMode ~= 0
            or UE.GetGameplayStatics():IsGamePaused(pawn) then
            finish("interrupted")
            return
        end
        update_held_prop(s, now)
        update_enchant(s, now)
        local elapsed = now - s.start
        local target = s.times[s.next_sample]
        if target and elapsed >= target then
            sample_pose(s, string.format("t%.3f", target), elapsed)
            s.next_sample = s.next_sample + 1
        end
        if elapsed >= s.seconds + .05 then finish("completed") end
    end)
end

LoopInGameThreadAfterFrames(1, update_frame)
log("Frame input fix enabled. Spatial throw audio enabled. F8+0 selects or casts enchant. F9+0 / F10+0 toggle release smoke. F7+0 toggles poison damage.")
