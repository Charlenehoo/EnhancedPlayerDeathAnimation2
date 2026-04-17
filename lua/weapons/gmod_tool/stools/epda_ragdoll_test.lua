TOOL.Category = "EPDA"
TOOL.Name = "Ragdoll Alignment Tester"
TOOL.Command = nil
TOOL.ConfigName = ""

if SERVER then
    -- 服务端全局管理
    local TestBots = {} -- 记录所有由本工具创建的 Bot

    -- 清理特定 Bot 及其布娃娃
    function EPDA_CleanupBot(ply)
        local data = TestBots[ply]
        if not data then return end
        if IsValid(data.bot) then
            data.bot:Kick()
        end
        if IsValid(data.ragdoll) then
            data.ragdoll:Remove()
        end
        TestBots[ply] = nil
    end

    -- 创建 Bot
    function EPDA_CreateBot(ply, pos)
        EPDA_CleanupBot(ply)

        local bot = player.CreateNextBot("EPDA_TestBot_" .. ply:SteamID())
        if not IsValid(bot) then
            print("EPDA: 创建 Bot 失败 (槽位已满)")
            return
        end

        bot:SetModel("models/player/kleiner.mdl")
        bot:Spawn()
        bot:SetPos(pos + Vector(0, 0, 32))
        bot:SetAngles(Angle(0, math.random(0, 360), 0))
        bot:SetHealth(bot:GetMaxHealth())
        bot:Freeze(false) -- 初始不冻结，待右键时冻结

        TestBots[ply] = {
            bot = bot,
            ragdoll = nil,
            active = true
        }

        print("EPDA: Bot 已创建")
    end

    -- 创建布娃娃并冻结 Bot
    function EPDA_CreateRagdoll(ply, pos)
        local data = TestBots[ply]
        if not data or not IsValid(data.bot) then
            print("EPDA: 请先创建 Bot")
            return
        end

        if IsValid(data.ragdoll) then
            data.ragdoll:Remove()
        end

        local rag = ents.Create("prop_ragdoll")
        rag:SetModel(data.bot:GetModel())
        rag:SetPos(pos)
        rag:SetAngles(data.bot:GetAngles())
        rag:Spawn()
        rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        -- 冻结布娃娃物理，使其保持静态姿态（作为参考）
        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:EnableMotion(false)
            end
        end

        data.ragdoll = rag

        -- 冻结 Bot，使其无法自主移动
        local bot = data.bot
        bot:Freeze(true)
        for i = 0, bot:GetPhysicsObjectCount() - 1 do
            local phys = bot:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:EnableMotion(false)
            end
        end

        print("EPDA: 布娃娃已创建，Bot 已冻结，开始每帧同步骨骼")
    end

    -- 每帧同步（服务端 Think 钩子）
    hook.Add("Think", "EPDA_RagdollSync", function()
        for ply, data in pairs(TestBots) do
            if not data.active then continue end
            local bot = data.bot
            local rag = data.ragdoll
            if not IsValid(bot) or not IsValid(rag) then continue end

            if bot:GetModel() ~= rag:GetModel() then
                rag:SetModel(bot:GetModel())
            end

            for boneId = 0, 255 do
                local boneName = rag:GetBoneName(boneId)
                if not boneName then break end

                local botBoneId = bot:LookupBone(boneName)
                if not botBoneId then continue end

                local ragMatrix = rag:GetBoneMatrix(boneId)
                if not ragMatrix then continue end

                bot:SetBoneMatrix(botBoneId, ragMatrix)
            end

            -- bot:InvalidateBoneCache()
        end
    end)

    -- 玩家断开时清理
    hook.Add("PlayerDisconnected", "EPDA_CleanupOnDisconnect", function(ply)
        EPDA_CleanupBot(ply)
    end)

    -- 接收工具枪网络消息
    util.AddNetworkString("EPDA_Tool_CreateBot")
    util.AddNetworkString("EPDA_Tool_CreateRagdoll")
    util.AddNetworkString("EPDA_Tool_Cleanup")

    net.Receive("EPDA_Tool_CreateBot", function(len, ply)
        local pos = net.ReadVector()
        EPDA_CreateBot(ply, pos)
    end)

    net.Receive("EPDA_Tool_CreateRagdoll", function(len, ply)
        local pos = net.ReadVector()
        EPDA_CreateRagdoll(ply, pos)
    end)

    net.Receive("EPDA_Tool_Cleanup", function(len, ply)
        EPDA_CleanupBot(ply)
    end)
end

if CLIENT then
    -- 客户端仅负责发送网络消息
    function TOOL:LeftClick(tr)
        if not IsFirstTimePredicted() then return true end
        net.Start("EPDA_Tool_CreateBot")
        net.WriteVector(tr.HitPos)
        net.SendToServer()
        return true
    end

    function TOOL:RightClick(tr)
        if not IsFirstTimePredicted() then return true end
        net.Start("EPDA_Tool_CreateRagdoll")
        net.WriteVector(tr.HitPos)
        net.SendToServer()
        return true
    end

    function TOOL:Holster()
        if IsFirstTimePredicted() then
            net.Start("EPDA_Tool_Cleanup")
            net.SendToServer()
        end
        return true
    end

    function TOOL:OnRemove()
        if IsFirstTimePredicted() then
            net.Start("EPDA_Tool_Cleanup")
            net.SendToServer()
        end
    end
end
