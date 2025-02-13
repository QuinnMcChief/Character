


	-------------------------------------------------------
	-- [ MEANT TO BE SHARED BY PLAYER CHARACTER & NPCs ] --
	-------------------------------------------------------


local rep = game:GetService("ReplicatedStorage")
local AnimationsFolder = rep.Assets.AnimationsFolder

local rs = game:GetService("RunService")

local SoundFX = game:GetService("SoundService").SoundFX

local ts = game:GetService("TweenService")
local fallSoundTweenInfo = TweenInfo.new(3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)

local states = Enum.HumanoidStateType

local Character = {
	--[[ Example: [CharacterObject] = {
		["Jumping"] = BoolValue | nil
		["Rolling"] = BoolValue | nil
		["BlahBlahBlah"] = BoolValue | nil
		etc. etc. I will OCCASIONALLY store other types of values in here, but mostly BoolValues
		
		Below functions will attempt to index these boolvalues. If they do not exist, for a character, they will be created.
	}]]
}

function Character.Is(valueName: string, character: Model): boolean --> Gets the value, or makes it if it doesn't exist.
	local characterValues = Character[character]
	if not characterValues then
		--> character template:
		Character[character] = {}
	end
	
	--> Make sure only the SERVER makes the folder!
	if rs:IsServer() then
		if not character:FindFirstChild("Statuses") then
			local StatusesFolder = game:GetService("ServerStorage").Assets.Templates.StarterCharacter.Statuses
			if StatusesFolder then
				StatusesFolder:Clone().Parent = character
			else
				warn("Could not find StatusesFolder in game.ServerStorage.Assets.Templates.StarterCharacter!")
			end
		end
	end
	
	if not characterValues[valueName] then
		local newValue = Instance.new("BoolValue")
		newValue.Name = valueName
		newValue:Remove()
		Character[character][valueName] = newValue
	end
	
	local value: BoolValue = characterValues[valueName]
	return value.Parent ~= nil
end

function Character.Add(valueName: string, character: Model): nil
	Character.Is(valueName, character) --> Creates value if it doesn't exist so this doesn't yield an error.
	Character[character][valueName].Parent = character.Statuses
	
	return Character[character][valueName]
end

function Character.Remove(valueName: string, character: Model): nil
	Character.Is(valueName, character) --> Creates value if it doesn't exist so this doesn't yield an error.
	Character[character][valueName]:Remove()
	local animationToStop: Animation? = AnimationsFolder:FindFirstChild(valueName)
	if animationToStop ~= nil then
		Character.StopAnimation(animationToStop, character)
	end
end


----------------------------------------------------------------------------------------------------

-- Plays a sound based each time keyframe "FootDown" is reached based on what the name of the part the player is walking on. All parts in my game are plastic (stylistic choice), but some are named dirt and colored brown, etc, so the sound played would be "Dirt"
local function onKeyframeReached(animTrack: AnimationTrack, character: Model)
	if Character["KeyframeReached"] ~= nil then
		Character["KeyframeReached"]:Disconnect()
		Character["KeyframeReached"] = nil
	end

	local root = character.HumanoidRootPart
	animTrack.KeyframeReached:Connect(function(kfName)
		if kfName == "FootDown" then
			local partUnderCharacter = workspace:Blockcast(
				CFrame.new(root.Position),
				root.Size,
				-(root.CFrame.UpVector) * (2.25 + 0.001),
				Character[character]["RaycastParams"]
			)
			if partUnderCharacter then
				local floorType = partUnderCharacter.Instance.Name
				local sound = SoundFX.FootstepSounds:FindFirstChild(floorType)
				if sound then
					if Character.Is("CrouchMoving", character) then
						SoundFX.FootstepSounds.Volume = 0.25
					else
						SoundFX.FootstepSounds.Volume = 1
					end
					sound:Play()
				end
			end
		end
	end)
end

function Character.PlayAnimation(data: table, character: Model): AnimationTrack
	local animation: Animation = data["Animation"]
	local looped: boolean = data["Looped"] or false
	
	if typeof(looped) ~= "boolean" then
		warn(`"looped" variable is not a boolean, it is {looped}! Will not play animation: {animation}.`)
		return
	end
	
	if not character then
		warn(`character is nil! Will not play animation: {animation}.`)
	end
	
	local animator: Animator = character.Humanoid.Animator
	local currentlyPlayingAnimationTracks = animator:GetPlayingAnimationTracks()
	for _, animTrack: AnimationTrack in ipairs(currentlyPlayingAnimationTracks) do
		if animTrack.Animation == animation then
			--return
		end
	end
	
	local newAnimTrack = animator:LoadAnimation(animation)
	newAnimTrack.Looped = looped
	onKeyframeReached(newAnimTrack, character)
	newAnimTrack:Play()
	
	return newAnimTrack
end

function Character.SetAnimationSpeedFromAnimation(animation: Animation, newPlaybackSpeed: number, character: Model)
	if not animation or not newPlaybackSpeed or not character then warn("Missing an argument for SetAnimationSpeed! Ending now...") return end
	if typeof(newPlaybackSpeed) ~= "number" then warn("newPlaybackSpeed is not a number! Ending now...") return end
	
	local animator: Animator = character.Humanoid.Animator
	local currentlyPlayingAnimationTracks = animator:GetPlayingAnimationTracks()
	for _, animTrack: AnimationTrack in ipairs(currentlyPlayingAnimationTracks) do
		if animTrack.Animation == animation then
			animTrack:AdjustSpeed()
		end
	end
end

function Character.StopAnimation(animation: Animation, character: Model)
	local animator: Animator = character.Humanoid.Animator
	local currentlyPlayingAnimationTracks = animator:GetPlayingAnimationTracks()
	for _, animTrack: AnimationTrack in ipairs(currentlyPlayingAnimationTracks) do
		if animTrack.Animation == animation then
			animTrack:Stop()
		end
	end
end


function Character.Idle(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyIdle = Character.Is("Idle", character)
	if isAlreadyIdle then --[[warn("Already idle, CharacterMovement.Idle will end now.")]] return end
	
	Character.Add("Idle", character)
	Character.Remove("Walking", character)
	Character.Remove("Sprinting", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("CrouchIdling", character)
	
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Idle,
		["Looped"] = true
	}, character)
end

function Character.Walk(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyWalking = Character.Is("Walking", character)
	if isAlreadyWalking then --[[warn("Already walking, CharacterMovement.Walk will end now.")]] return end
	
	Character.Add("Walking", character)
	Character.Remove("Idle", character)
	Character.Remove("Sprinting", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("CrouchIdling", character)
	
	hum.WalkSpeed = 14
	
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Walking,
		["Looped"] = true
	}, character)
end


function Character.Sprint(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadySprinting = Character.Is("Sprinting", character)
	if isAlreadySprinting then --[[warn("Already walking, CharacterMovement.Sprint will end now.")]] return end

	Character.Add("Sprinting", character)
	Character.Remove("Idle", character)
	Character.Remove("Walking", character)
	Character.Remove("CrouchIdling", character)
	Character.Remove("CrouchMoving", character)
	
	hum.WalkSpeed = 30
	
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Sprinting,
		["Looped"] = true
	}, character)
end

function Character.CrouchIdle(character: Model) --> "CrouchIdling" means crouching while not moving (standing still, in other words crouching while idle i.e. "CrouchIdling")
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyCrouchIdling = Character.Is("CrouchIdling", character)
	if isAlreadyCrouchIdling then --[[warn("Already CrouchIdling, CharacterMovement.CrouchIdling will end now.")]] return end

	Character.Add("CrouchIdling", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("Idle", character)

	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.CrouchIdling,
		["Looped"] = true
	}, character)
end

function Character.CrouchMove(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyCrouchMoving = Character.Is("CrouchMoving", character)
	if isAlreadyCrouchMoving then --[[warn("Already CrouchMoving, CharacterMovement.CrouchMoving will end now.")]] return end

	Character.Add("CrouchMoving", character)
	Character.Remove("CrouchIdling", character)
	Character.Remove("Walking", character)
	Character.Remove("Sprinting", character)
	
	hum.WalkSpeed = 5

	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.CrouchMoving,
		["Looped"] = true
	}, character)
end

function Character.Fall(character: Model, shouldJumpForward: boolean)
	local hum: Humanoid = character.Humanoid
	local root: BasePart = character.HumanoidRootPart
	local isAlreadyFalling = Character.Is("Falling", character)
	if isAlreadyFalling then --[[warn("Already falling, CharacterMovement.Fall will end now.")]] return end

	Character.Add("Falling", character)
	Character.Remove("Sprinting", character)
	Character.Remove("Walking", character)
	Character.Remove("RecoverRolling", character)
	Character.Remove("Idle", character) --> Sometimes character goes from Idle -> Falling in some weird contexts.
	if SoundFX.RecoverRoll.IsPlaying then SoundFX.RecoverRoll:Stop() end

	local fallY = root.Position.Y
	local currentVelocity = root.AssemblyLinearVelocity
	local rollVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local rotationConstant = root.CFrame - root.CFrame.Position--CFrame.new(Vector3.zero, hum.MoveDirection) DO NOT CHANGE rotationConstant TO AssemblyLinearVelocity, ITHERE IS A GAMEBREAKING BUG WHEN YOU SLOWLY WALK OFF LEDGES!!!
	hum.WalkSpeed = 0
	if rs:IsClient() then
		SoundFX.Jump:Play()
	elseif rs:IsServer() then
		
	end

	if shouldJumpForward then
		root.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, hum.JumpPower * 1.25, currentVelocity.Z)
	end

	local fallingSoundStartVolume = 0
	local fallingSoundMaxVolume = 3

	Character.PlayAnimation({["Animation"] = AnimationsFolder.Falling, ["Looped"] = true}, character)
	
	--> Raycast to check when player touches ground.
	--[[local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local fallConnection = rs.Heartbeat:Connect(function()
		local result = workspace:Blockcast(CFrame.new(root.CFrame - root.Position), root.Size, Vector3.new(0, 0.05, 0), params)
		if result then
			
		end
	end)]]
	while hum:GetState() ~= states.Landed --[[Character.Is("Falling", character)]] do
		root.CFrame = CFrame.new(root.Position) * rotationConstant --> Character should maintain its orientation until it lands!
		if root.Position.Y > fallY then
			fallY = root.Position.Y
		end

		local fallDistance = fallY - root.Position.Y
		if fallDistance > 0 and not Character[character]["CurrentFallSoundTween"] then --> Before I checked the second value in this if statement, the FallWind sound was playing every frame. Had to implement this, even if it's messy...
			SoundFX.FallWind:Play()
			Character[character]["CurrentFallSoundTween"] = ts:Create(SoundFX.FallWind, fallSoundTweenInfo, {Volume = fallingSoundMaxVolume})
			Character[character]["CurrentFallSoundTween"]:Play()
		end
		--> Deal with autojump
		root.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, root.AssemblyLinearVelocity.Y, currentVelocity.Z)
		if currentVelocity.X > 0 then
			currentVelocity -= Vector3.new(0.15, 0, 0)
		elseif currentVelocity.X < 0 then
			currentVelocity -= Vector3.new(-0.15, 0, 0)
		end
		if currentVelocity.Z > 0 then
			currentVelocity -= Vector3.new(0, 0, 0.15)
		elseif currentVelocity.Z < 0 then
			currentVelocity -= Vector3.new(0, 0, -0.15)
		end

		task.wait()
	end

	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) --> Stop the character in place when they land on the ground. Avoids weird floor collisions at high speeds
	Character.Remove("Falling", character)

	if Character[character]["CurrentFallSoundTween"] then Character[character]["CurrentFallSoundTween"]:Cancel() end
	SoundFX.FallWind:Stop()
	SoundFX.FallWind.Volume = fallingSoundStartVolume
	Character[character]["CurrentFallSoundTween"] = nil

	local currentY = root.Position.Y
	if not fallY then return end

	local fallDistance = (fallY - currentY)
	if fallDistance > 20 then
		local fallDistanceValueBase = Character.Add("FallDistance", character)
		fallDistanceValueBase:SetAttribute("Height", (fallY - currentY))
		if Character.Is("TryingToRecoverRoll", character) then
			Character.RecoverRoll(character, rollVelocity)--rollVelocity)
		else
			Character.Add("RecoveringFromBigFall", character)
			hum.WalkSpeed = 0
			hum:TakeDamage(math.floor(fallDistance * 1/5) )
			SoundFX.BigLanding:Play()
			local landingAnimTrack = Character.PlayAnimation({["Animation"] = AnimationsFolder.RecoveringFromBigFall}, character)
			landingAnimTrack.Ended:Wait()

			if not Character.Is("Falling", character) then
				Character.Remove("RecoveringFromBigFall", character)
				
			end
		end

	else
		SoundFX.SmallLanding:Play()
	end

	if Character[character]["CurrentMoveTo"] then
		Character.MoveTo(Character[character]["CurrentMoveTo"])
	end
	Character.Remove("FailedToRecoverRoll", character)
end

function Character.RecoverRoll(character: Model, direction: Vector3) --> Roll to mitigate fall damage (must be timed correctly)
	local hum: Humanoid = character.Humanoid
	local root: BasePart = character.HumanoidRootPart
	local rootAttachment: Attachment = root.RootAttachment
	local isAlreadyRecoverRolling = Character.Is("RecoverRolling", character)
	if isAlreadyRecoverRolling then --[[warn("Already falling, CharacterMovement.Fall will end now.")]] return end

	--> Should only be falling at this point...
	local rollingAnimTrack = Character.PlayAnimation({
		["Animation"] = AnimationsFolder.RecoverRolling,
		["Looped"] = false
	}, character)
	rollingAnimTrack:AdjustSpeed(1.5)
	Character.DisableControls(character)
	SoundFX.RecoverRoll:Play()
	
	Character.Add("RecoverRolling", character)
	Character.Remove("TryingToRecoverRoll", character)
	Character.Remove("Falling", character)
	
	hum.WalkSpeed = 30
	hum:Move(direction)
	
	rollingAnimTrack.Stopped:Wait()

	Character.Remove("RecoverRolling", character)
	Character.EnableControls(character)
	
end

function Character.StartRecoverRollAttempt(character: Model)
	--> Just as a note, character can only recover roll on big falls, not small falls.
	local failedToRecoverRoll = Character.Is("FailedToRecoverRoll", character)
	if failedToRecoverRoll then warn(`{character} can't try to recover, because they already missed their recovery roll window!`) return end
	local isTryingToRecoverRoll = Character.Is("TryingToRecoverRoll", character)
	if isTryingToRecoverRoll then return end
	local isRecoverRolling = Character.Is("RecoverRolling", character)
	if isRecoverRolling then return end
	
	Character.Add("TryingToRecoverRoll", character)
	local start = os.clock()
	local timeWindow = .1 --> in seconds
	local timeElapsed = os.clock() - start
	coroutine.resume(coroutine.create(function()
		while timeElapsed < timeWindow and Character.Is("Falling", character) do
			task.wait()
			timeElapsed = os.clock() - start
		end
		if timeElapsed >= .1 and Character.Is("Falling", character) then
			Character.Remove("TryingToRecoverRoll", character)
			Character.Add("FailedToRecoverRoll", character)
		end
	end))
end

function Character.Jump(character: Model)
	Character.Fall(character, true)
end

function Character.DisableControls(character: Model) --> I think this whole function is just reserved for the player
	Character.Add("DisabledControls", character)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if player then
		require(player.PlayerScripts.PlayerModule):GetControls():Disable()
	end
end

function Character.EnableControls(character: Model)
	Character.Remove("DisabledControls", character)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if player then
		require(player.PlayerScripts.PlayerModule):GetControls():Enable()
	end
end

function Character.DisableJumpDetection(character: Model)
	Character.Add("DisabledJumpDetection", character)
end

function Character.EnableJumpDetection(character: Model)
	Character.Remove("DisabledJumpDetection", character)
end

local function getNextMoveToInQueue(character: Model): {["Character"]: number, ["Destination"]: Vector3, ["StateFunction"]: string}
	if not Character[character] then warn(`Could not get next MoveTo in {character}'s queue, because they don't have a queue!`) return end
	return Character[character]["MoveToQueue"][1]

end

function Character.MoveTo(data: table)
	local character: Model = data["Character"]
	local destination: Vector3 = data["Destination"]
	local stateFunction: string = data["StateFunction"] --> e.g. "Walk", "Sprint", "CrouchMoving", etc. It's unrelated to the HumanoidStateType.
	
	local stop = Character.Is("Jumping", character) or Character.Is("Falling", character) or Character.Is("RecoveringFromBigFall", character)
	if stop then
		print(data)
		Character.AddMoveTo_ToQueue(data)
		return
	end
	
	local hum: Humanoid = character.Humanoid
	
	Character[character]["OnMoveToFinishedFunction"] = Character[character]["OnMoveToFinishedFunction"] or function(reachedDestination: boolean)
		Character.PrintQueue(character)

		if reachedDestination then
			Character[character]["CurrentMoveTo"] = nil
			local nextMoveToData = getNextMoveToInQueue(character)
			if nextMoveToData then
				table.Character.Remove(Character[character]["MoveToQueue"], 1)
				Character.MoveTo({["Character"] = character, ["Destination"] = nextMoveToData["Destination"], ["StateFunction"] = nextMoveToData["StateFunction"]})
			else
				Character.EnableControls(character)
			end
		else
			--Character.MoveTo(data)
		end
	end
	Character[character]["OnMoveToFinishedConnection"] = Character[character]["OnMoveToFinishedConnection"] or hum.MoveToFinished:Connect(Character[character]["OnMoveToFinishedFunction"])
	
	Character.DisableControls(character)
	if not stateFunction then warn("No StateFunction given for MoveTo!") end
	Character[stateFunction](character)
	Character[character]["CurrentMoveTo"] = data
	hum:MoveTo(destination)
end

function Character.AddMoveTo_ToQueue(data: table, index: number | nil)
	local character: Model = data["Character"]
	
	if not Character[character] then warn(`Could not add MoveTo to {character}'s queue, because they don't have one!`) return end
	local moveToQueueTable = Character[character]["MoveToQueue"]
	
	--if #Character[character]["MoveToQueue"] == 0 then
		--Character.MoveTo(data)
	--else
		local packedMoveToData = {
			["Character"] = character,
			["Destination"] = data["Destination"], 
			["StateFunction"] = data["StateFunction"]
		}
		if index ~= nil then
			table.insert(Character[character]["MoveToQueue"], index, packedMoveToData)
		else
			table.insert(Character[character]["MoveToQueue"], packedMoveToData)
		end
	--end
end

function Character.ClearMoveToQueue(character)
	if Character[character] then
		Character[character]["MoveToQueue"] = {}
	end
end

function Character.PrintQueue(character)
	if not Character[character] then warn(`Cannot print {character}'s MoveTo queue, because they do not have one!`) return end
	print(Character[character]["MoveToQueue"])
end



return Character
