-- name: King Bob-omb v2

local osync = require("/lib/osync")

local sKingBobombParams = {
    [3] = { cooldown = 90, bombs = 1, fvel = 40, yvel = 20 },
    [2] = { cooldown = 75, bombs = 2, fvel = 50, yvel = 25 },
    [1] = { cooldown = 60, bombs = 3, fvel = 60, yvel = 30 },
}

define_custom_obj_fields({
    oKingBobombCooldown = "s32",
    oKingBobombBombs = "s32",
    oKingBobombReset = "u32",
})

local function bhv_bobomb_held_by_king(o)

    -- Don't explode as long as King bobomb holds the bomb
    local parent = o.parentObj
    if parent and obj_has_behavior_id(parent, id_bhvKingBobomb) == 1 then
        if parent.oAction ~= 9 then
            o.parentObj = o
            parent.prevObj = nil
            return
        end
        o.oAction = BOBOMB_ACT_CHASE_MARIO
        o.oBobombFuseLit = 1
        o.oBobombFuseTimer = 0
        parent.prevObj = o
    end

    -- Damage King bobomb
    local king = obj_get_nearest_object_with_behavior_id(o, id_bhvKingBobomb)
    if king and (king.oAction == 2 or king.oAction == 9) and o.oAction == BOBOMB_ACT_LAUNCHED and obj_check_hitbox_overlap(o, king) then
        o.oAction = BOBOMB_ACT_EXPLODE
        o.oPrevAction = BOBOMB_ACT_EXPLODE
        o.oTimer = 10
        king.oAction = 4
        king.oPosY = king.oFloorHeight + 10
        king.oVelY = -10
    end
end

hook_behavior(id_bhvBobomb, nil, false, nil, bhv_bobomb_held_by_king)

local function bhv_king_bobomb_act_9(o)
    local kingParams = sKingBobombParams[math.clamp(o.oHealth, 1, 3)]

    -- No longer grabbable
    o.oInteractionSubtype = o.oInteractionSubtype | INT_SUBTYPE_NOT_GRABBABLE

    -- Save anchor object
    if not o.oIntroLakituCloud and o.prevObj and obj_has_behavior_id(o.prevObj, id_bhvBobombAnchorMario) == 1 then
        o.oIntroLakituCloud = o.prevObj
    end
    if not o.prevObj then
        o.prevObj = o.oIntroLakituCloud
    end

    -- Init cooldown
    if (o.oAction ~= 2 and o.oAction ~= 9) or o.oKingBobombReset == 1 then
        o.oKingBobombCooldown = kingParams.cooldown
        o.oKingBobombBombs = 0
        o.oKingBobombReset = 0
    end

    -- Trigger bobomb throw action
    if o.oAction == 2 then
        o.oKingBobombCooldown = o.oKingBobombCooldown - 1
        if o.oKingBobombCooldown <= 0 then
            if o.oKingBobombBombs == 0 then
                o.oKingBobombBombs = kingParams.bombs
            end

            o.oAction = 9
            cur_obj_init_animation(9)

            osync.create_context("king_bobomb_throw_bobomb_" .. tostring(o._pointer), function ()
                osync.spawn_sync_object(id_bhvBobomb, E_MODEL_BLACK_BOBOMB, o.oPosX, o.oPosY, o.oPosZ, function (obj)
                    obj.parentObj = o
                    obj.oBobombFuseLit = 1
                    obj.oBobombFuseTimer = 0
                    obj.oAction = BOBOMB_ACT_CHASE_MARIO
                    obj_copy_angle(obj, o)
                end)
            end, nil, 30)
        end
    end

    -- Bobomb throw action
    if o.oAction == 9 then

        -- Check grab
        local m = nearest_mario_state_to_object(o)
        if m.action == ACT_GRABBED and m.interactObj == o then
            m.faceAngle.y = o.oMoveAngleYaw
            o.oKingBobombUnk88 = 1
            o.usingObj = m.marioObj
            o.prevObj = o.oIntroLakituCloud
            o.oAction = 3
            o.oKingBobombReset = 1
            return
        end

        -- Turn towards nearest Mario
        local targetAngle = obj_angle_to_object(o, m.marioObj)
        o.oFaceAngleYaw = approach_s16_symmetric(o.oFaceAngleYaw, targetAngle, 0x400)
        o.oMoveAngleYaw = o.oFaceAngleYaw
        o.oForwardVel = 0
        o.oVelX = 0
        o.oVelY = 0
        o.oVelZ = 0

        -- Throw bobomb
        if cur_obj_check_anim_frame(31) == 1 then
            local bobomb = obj_get_first_with_behavior_id_and_parent(id_bhvBobomb, o)
            if bobomb and obj_has_behavior_id(bobomb, id_bhvBobomb) == 1 then
                bobomb.oForwardVel = kingParams.fvel
                bobomb.oVelY = kingParams.yvel
                bobomb.parentObj = bobomb
                cur_obj_play_sound_and_rumble_if_visible(SOUND_OBJ_UNKNOWN4)
            end
            o.prevObj = o.oIntroLakituCloud
            o.oKingBobombBombs = o.oKingBobombBombs - 1
            if o.oKingBobombBombs == 0 then
                o.oKingBobombReset = 1
            end
        end

        -- Return to walk action
        if cur_obj_check_if_near_animation_end() == 1 then
            o.oAction = 2
        end
    end
end

hook_behavior(id_bhvKingBobomb, nil, false, nil, bhv_king_bobomb_act_9)
