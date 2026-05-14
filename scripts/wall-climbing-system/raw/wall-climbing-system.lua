-- made by @simplyIeaf1 on YouTube

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CLIMB_SPEED = 18
local R15_ANIM_SPEED = 1
local R6_ANIM_SPEED = 1
local RAYCAST_DISTANCE = 2.5
local CLIMB_DETECT_THRESHOLD = 0.3

local function setupClimbing(character)
	local humanoid = character:WaitForChild("Humanoid")
	local hrp = character:WaitForChild("HumanoidRootPart")
	
	local rigType = humanoid.RigType
	local animId = (rigType == Enum.HumanoidRigType.R15) and "rbxassetid://507765644" or "rbxassetid://180436334"
	
	local climbAnim = Instance.new("Animation")
	climbAnim.AnimationId = animId
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animTrack = animator:LoadAnimation(climbAnim)
	
	local isClimbing = false
	local currentWallNormal = nil
	local heartbeatConnection
	
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = 10000
	alignOrientation.Responsiveness = 200
	alignOrientation.Enabled = false
	alignOrientation.Parent = hrp
	
	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp
	alignOrientation.Attachment0 = attachment
	
	local function getRaycastPoints()
		local points = {}
		if rigType == Enum.HumanoidRigType.R15 then
			local leftLeg = character:FindFirstChild("LeftUpperLeg")
			local rightLeg = character:FindFirstChild("RightUpperLeg")
			local upperTorso = character:FindFirstChild("UpperTorso")
			
			if leftLeg then table.insert(points, leftLeg.Position) end
			if rightLeg then table.insert(points, rightLeg.Position) end
			if upperTorso then table.insert(points, upperTorso.Position) end
		else
			local leftLeg = character:FindFirstChild("Left Leg")
			local rightLeg = character:FindFirstChild("Right Leg")
			local torso = character:FindFirstChild("Torso")
			
			if leftLeg then table.insert(points, leftLeg.Position) end
			if rightLeg then table.insert(points, rightLeg.Position) end
			if torso then table.insert(points, torso.Position) end
		end
		
		return points
	end
	
	local function isMovingForward()
		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude > CLIMB_DETECT_THRESHOLD then
			local lookVector = hrp.CFrame.LookVector
			local dotProduct = moveDirection:Dot(lookVector)
			return dotProduct > 0.3
		end
		return false
	end
	
	local function detectWall()
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local points = getRaycastPoints()
		local hitCount = 0
		local averageNormal = Vector3.new(0, 0, 0)
		local averagePosition = Vector3.new(0, 0, 0)
		
		for _, point in ipairs(points) do
			local ray = workspace:Raycast(point, hrp.CFrame.LookVector * RAYCAST_DISTANCE, rayParams)
			if ray and ray.Instance:IsA("BasePart") and ray.Instance.CanTouch then
				hitCount = hitCount + 1
				averageNormal = averageNormal + ray.Normal
				averagePosition = averagePosition + ray.Position
			end
		end
		
		if hitCount > 0 then
			averageNormal = (averageNormal / hitCount).Unit
			averagePosition = averagePosition / hitCount
			return true, averageNormal, averagePosition
		end
		
		return false, nil, nil
	end
	
	local function startClimbing(wallNormal, wallPosition)
		if not isClimbing then
			isClimbing = true
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		end
		
		currentWallNormal = wallNormal
		
		local targetCFrame = CFrame.lookAt(hrp.Position, hrp.Position - wallNormal)
		alignOrientation.CFrame = targetCFrame
		alignOrientation.Enabled = true
		
		local currentAnimSpeed = (rigType == Enum.HumanoidRigType.R15) and R15_ANIM_SPEED or R6_ANIM_SPEED
		animTrack:AdjustSpeed(currentAnimSpeed)
		
		local verticalVelocity = Vector3.new(0, CLIMB_SPEED, 0)
		hrp.AssemblyLinearVelocity = verticalVelocity
		
		hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		
		if humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
			humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
		end
		
		if not animTrack.IsPlaying then
			animTrack:Play()
		end
	end
	
	local function stopClimbing()
		if isClimbing then
			isClimbing = false
			alignOrientation.Enabled = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		end
		
		currentWallNormal = nil
		
		if animTrack.IsPlaying then
			animTrack:Stop()
		end
		
		if humanoid:GetState() == Enum.HumanoidStateType.Climbing then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
	
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not character.Parent or humanoid.Health <= 0 then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
			end
			return
		end
		
		local hasWall, wallNormal, wallPosition = detectWall()
		local movingForward = isMovingForward()
		
		if hasWall and movingForward then
			startClimbing(wallNormal, wallPosition)
		else
			stopClimbing()
		end
	end)
	
	humanoid:GetPropertyChangedSignal("RigType"):Connect(function()
		rigType = humanoid.RigType
		animId = (rigType == Enum.HumanoidRigType.R15) and "rbxassetid://507765644" or "rbxassetid://180436334"
		climbAnim.AnimationId = animId
		animTrack = animator:LoadAnimation(climbAnim)
		local currentAnimSpeed = (rigType == Enum.HumanoidRigType.R15) and R15_ANIM_SPEED or R6_ANIM_SPEED
		animTrack:AdjustSpeed(currentAnimSpeed)
	end)
	
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
			end
			if alignOrientation then
				alignOrientation:Destroy()
			end
			if attachment then
				attachment:Destroy()
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupClimbing(character)
	end)
	
	if player.Character then
		setupClimbing(player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupClimbing(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		setupClimbing(character)
	end)
end
