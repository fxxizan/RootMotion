--!strict

export type Configuration = {
    ["Whitelist"] : {Part | BasePart | Instance}?,
    ["AlignHRPCFrame"] : boolean?,
    ["MaintainVelocity"] : boolean?
}

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = PlayerService.LocalPlayer
local Character = Client.Character or Client.CharacterAdded:Wait()

local Camera = workspace.CurrentCamera

local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") :: Part
local Torso = Character:FindFirstChild("Torso") :: Part
local Head = Character:FindFirstChild("Head") :: Part
local Humanoid = Character:FindFirstChild("Humanoid") :: Humanoid

local HRPSize = HumanoidRootPart.Size

local CollisionParams = RaycastParams.new()
CollisionParams.IgnoreWater = true
CollisionParams.RespectCanCollide = true
CollisionParams.FilterType = Enum.RaycastFilterType.Exclude

local CollisionParams2 = OverlapParams.new()
CollisionParams2.RespectCanCollide = true
CollisionParams2.FilterType = Enum.RaycastFilterType.Exclude

local RootMotionModule = {}
local TemporaryParts = {
	["Connection"] = nil :: RBXScriptConnection?,
} --// This used to be more things but I removed them all since they were useless and I cba to remove this table so it stays

local function VerifyCollision(OldCFrame : CFrame, NewCFrame : CFrame) : boolean
	local BlockRay = workspace:Blockcast(OldCFrame, HRPSize, (NewCFrame.Position - OldCFrame.Position), CollisionParams)
	local TouchingParts = workspace:GetPartBoundsInBox(NewCFrame, HRPSize, CollisionParams2)

	if (BlockRay and BlockRay.Instance :: Instance? ~= nil) then
		return false        
	end

	if #TouchingParts >= 1 then
		return false
	end

	return true
end

function RootMotionModule:StartCorrection(Configuration : Configuration)
	local Motor = HumanoidRootPart:FindFirstChild("RootJoint") :: Motor6D?
	local CFrameToRead = HumanoidRootPart.CFrame

    if Configuration.AlignHRPCFrame then
        CFrameToRead = CFrame.lookAt(HumanoidRootPart.Position, HumanoidRootPart.Position + Camera.CFrame.LookVector * Vector3.new(1, 0, 1)) 
    end

	CollisionParams:AddToFilter(Character)
	CollisionParams2:AddToFilter(Character)

	if Configuration.Whitelist ~= nil then
		CollisionParams:AddToFilter(Configuration.Whitelist :: {Instance}) 
		CollisionParams2:AddToFilter(Configuration.Whitelist :: {Instance})
	end

	if Motor ~= nil then
		Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		Humanoid.AutoRotate = false
		Camera.CameraSubject = Head

		for Index, Limbs in Character:GetChildren() do
			if Limbs:IsA("BasePart") then
				(Limbs :: Part).CanCollide = false 
			end
		end

		Torso.Anchored = true --// This (should?) stop the torso from being affected by transforms

		HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
		HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero

		Torso.AssemblyLinearVelocity = Vector3.zero
		Torso.AssemblyAngularVelocity = Vector3.zero

		HumanoidRootPart.CFrame = CFrameToRead

		local OldPosition = CFrameToRead.Position
		local OldXRotation, OldYRotation, OldZRotation = CFrameToRead:ToOrientation()

		local C0 = Motor.C0
		local C1 = Motor.C1

		TemporaryParts.Connection = RunService.PreSimulation:Connect(function(DeltaTime) 
			debug.profilebegin("Root motion")

			local Transform = Motor.Transform
			local NewCFrame = CFrame.identity

			local NewTorsoCFrame = HumanoidRootPart.CFrame * C0 * Transform * C1:Inverse()
			local CurrentTorsoCFrame = HumanoidRootPart.CFrame

			local RootMotionDelta = CurrentTorsoCFrame:ToObjectSpace(NewTorsoCFrame) --// This does accumulate so it's not really a delta but I can't think of a better name
			NewCFrame = CFrameToRead * RootMotionDelta

			if not VerifyCollision(HumanoidRootPart.CFrame, NewCFrame) then 
				NewCFrame = CFrame.new(HumanoidRootPart.Position) * NewCFrame.Rotation
			end

			HumanoidRootPart.CFrame = NewCFrame
			Motor.Transform = CFrame.identity

            if Configuration.MaintainVelocity then
                local NewPosition = NewCFrame.Position
                local NewXRotation, NewYRotation, NewZRotation = NewCFrame:ToOrientation()
    
                local LinearVelocity = (NewPosition - OldPosition) / DeltaTime
                local AngularVelocity = Vector3.new(math.deg(NewXRotation - OldXRotation), math.deg(NewYRotation - OldYRotation), math.deg(NewZRotation - OldZRotation)) * 0.02
    
                HumanoidRootPart.AssemblyLinearVelocity = LinearVelocity
                HumanoidRootPart.AssemblyAngularVelocity = AngularVelocity
    
                Torso.AssemblyLinearVelocity = LinearVelocity
                Torso.AssemblyAngularVelocity = AngularVelocity
                --// This is for maintaining the original velocities and stuff when the rootmotion stops so ragdolls stay retain the motion instead of weirdly stopping
    
                OldPosition = NewPosition
                OldXRotation, OldYRotation, OldZRotation = NewXRotation, NewYRotation, NewZRotation 
            end

			debug.profileend()
		end) 
	end
end

function RootMotionModule:DestroyDependencies(ReverseAllEffects : boolean)    
	if TemporaryParts.Connection ~= nil then
		TemporaryParts.Connection:Disconnect()
		TemporaryParts.Connection = nil
	end

	CollisionParams.FilterDescendantsInstances = {}
	CollisionParams2.FilterDescendantsInstances = {}

	Torso.Anchored = false

    if ReverseAllEffects then
		Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		Humanoid.AutoRotate = true
		workspace.CurrentCamera.CameraSubject = Humanoid

		Torso.CanCollide = true
		Head.CanCollide = true
    end
end

return RootMotionModule