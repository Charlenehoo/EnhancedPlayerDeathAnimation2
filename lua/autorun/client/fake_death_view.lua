local BONE_NAME_HEAD = "ValveBiped.Bip01_Head1"

local UP_OFFSET      = 8
local RIGHT_OFFSET   = 8
local FORWARD_OFFSET = -128

local ragdoll        = nil
net.Receive("EPDA_Ragdoll", function(len)
    ragdoll = net.ReadEntity()
end)

local function buildView(ent, origin, angles, fov, znear, zfar)
    local boneIDHead = ent:LookupBone(BONE_NAME_HEAD)
    if not boneIDHead then return end

    local posHead, _ = ent:GetBonePosition(boneIDHead)

    return {
        origin     = posHead + angles:Up() * UP_OFFSET + angles:Right() * RIGHT_OFFSET +
            angles:Forward() * FORWARD_OFFSET,
        angles     = angles,
        fov        = fov,
        znear      = znear,
        zfar       = zfar,
        drawviewer = true,
    }
end

hook.Add("CalcView", "CalcView_EPDA_FakeDeathView", function(ply, origin, angles, fov, znear, zfar)
    if IsValid(ragdoll) then
        return buildView(ragdoll, origin, angles, fov, znear, zfar)
        -- elseif IsValid(ply) then
        --     return buildView(ply, origin, angles, fov, znear, zfar)
    end
end)
