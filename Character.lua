--[[
	This module implements a state machine for character movement in stickblox rpg.
	The character state machine uses dynamic BoolValue objects attached to a character’s Statuses folder to represent active states (e.g., Idle, Walking, Sprinting, CrouchMoving).
	Instead of toggling the true/false value of BoolValue objects, the script creates and removes BoolValues at runtime – making state changes visible in the Explorer,
	greatly aiding in debugging! This same mechanism is used to trigger animations, sound effects, and physics behavior (like falling dynamics or recovery rolls).
	
	Each function in this script both manipulates these state flags and coordinates associated actions (for example, starting an animation or adjusting speed).
	It is important to note, however, that it's possible for the character to exist in multiple states at once (e.g. Falling and TryingToRecoverRoll)

	(For those who are unaware: a "flag" in programming is value that indicates the state of an object. It is often a boolean (true or false) value, though in this case,
	it is defined simply as whether or not a BoolValue is parented to the character's Statuses folder.)
]]

local rep = game:GetService("ReplicatedStorage")
-- Get the folder containing animation assets from ReplicatedStorage
local AnimationsFolder = rep.Assets.AnimationsFolder

local rs = game:GetService("RunService")
-- SoundFX holds various sound effects used in the game
local SoundFX = game:GetService("SoundService").SoundFX

local ts = game:GetService("TweenService")
-- Configure tweening info for the fall sound’s volume adjustment
local fallSoundTweenInfo = TweenInfo.new(3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)

-- Shortcut for the HumanoidStateType enum, used for comparing the character’s current state
local states = Enum.HumanoidStateType

--[[
	The script utilizes Roblox’s Instance parenting system by dynamically adding or removing BoolValue objects
	to a character’s "Statuses" folder. When a BoolValue is parented, that state is active. When removed, it is inactive.
	This method both drives game logic (for instance, preventing autojump when crouched) and provides a visual snapshot of the character’s state.
	The Character table below will store these BoolValue objects keyed by the character instance for quick access.
]]
local Character = {
	--[[ 
		Structure:
		[CharacterObject] = {
			["StateName"] = BoolValue, -- Active if its Parent property is not nil.
			-- Additional state-related values can be stored here.
		}
		Each helper function in the script creates, adds, or removes these BoolValues to manage state transitions.
	]]
}

-- Checks if a given state (identified by valueName) is active on the character
-- This function ensures that a BoolValue representing the state exists and is stored in our table
-- It also creates the Statuses folder on the character if missing (server-side only)
function Character.Is(valueName: string, character: Model): boolean
	local characterValues = Character[character]
	if not characterValues then
		-- Initialize a template table for this character to hold its state BoolValues.
		Character[character] = {}
	end
	
	-- Ensure the Statuses folder exists on the character (only create it on the server).
	if rs:IsServer() then
		if not character:FindFirstChild("Statuses") then
			local StatusesFolder = game:GetService("ServerStorage").Assets.Templates.StarterCharacter.Statuses
			if StatusesFolder then
				-- Clone the template folder and parent it to the character.
				StatusesFolder:Clone().Parent = character
			else
				warn("Could not find StatusesFolder in game.ServerStorage.Assets.Templates.StarterCharacter!")
			end
		end
	end
	
	-- Create the BoolValue for this state if it doesn’t already exist.
	if not characterValues[valueName] then
		local newValue = Instance.new("BoolValue")
		newValue.Name = valueName
		-- Remove its Parent to indicate that the state is initially inactive.
		newValue:Remove()
		Character[character][valueName] = newValue
	end
	
	local value: BoolValue = characterValues[valueName]
	-- The state is considered active if its BoolValue is parented (i.e. placed in the Statuses folder).
	return value.Parent ~= nil
end

-- Activates a state by parenting its BoolValue to the character’s Statuses folder
-- This not only flags the state as active but also makes it visible in the Explorer for debugging
function Character.Add(valueName: string, character: Model): nil
	-- Ensure the BoolValue exists (Character.Is creates it if missing).
	Character.Is(valueName, character)
	-- Parent the BoolValue to activate the state.
	Character[character][valueName].Parent = character.Statuses
	
	return Character[character][valueName]
end

-- Deactivates a state by removing its BoolValue from the character’s Statuses folder.
-- It also stops any animation linked to this state, ensuring that the visual and logical states stay in sync.
function Character.Remove(valueName: string, character: Model): nil
	-- Ensure the state BoolValue exists.
	Character.Is(valueName, character)
	-- Remove the BoolValue from the hierarchy, marking the state as inactive.
	Character[character][valueName]:Remove()
	-- If there’s an animation with the same name, stop it.
	local animationToStop: Animation? = AnimationsFolder:FindFirstChild(valueName)
	if animationToStop ~= nil then
		Character.StopAnimation(animationToStop, character)
	end
end


----------------------------------------------------------------------------------------------------
-- Attaches a keyframe callback to an animation track to trigger contextual sound effects.
-- When the "FootDown" keyframe is reached, a blockcast is performed beneath the character to detect the floor material,
-- and the corresponding footstep sound is played. Volume adjustments are made if the character is crouching.
local function onKeyframeReached(animTrack: AnimationTrack, character: Model)
	-- If an earlier KeyframeReached connection exists, disconnect it to avoid duplicate calls.
	if Character["KeyframeReached"] ~= nil then
		Character["KeyframeReached"]:Disconnect()
		Character["KeyframeReached"] = nil
	end

	local root = character.HumanoidRootPart
	-- Connect to the KeyframeReached event.
	animTrack.KeyframeReached:Connect(function(kfName)
		if kfName == "FootDown" then
			-- Cast a block directly beneath the character to detect the type of surface.
			local partUnderCharacter = workspace:Blockcast(
				CFrame.new(root.Position),
				root.Size,
				-(root.CFrame.UpVector) * (2.25 + 0.001),
				Character[character]["RaycastParams"]
			)
			if partUnderCharacter then
				-- Use the name of the hit object to choose the correct sound.
				local floorType = partUnderCharacter.Instance.Name
				local sound = SoundFX.FootstepSounds:FindFirstChild(floorType)
				if sound then
					-- Adjust the sound volume based on whether the character is crouching.
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

-- Loads and plays an animation on the character using data provided in a table.
-- The data table must include an "Animation" object and may optionally specify a "Looped" boolean.
-- This function performs safety checks, loads the animation track from the character’s animator, attaches keyframe callbacks,
-- and starts playback—returning the AnimationTrack for further control if needed.
function Character.PlayAnimation(data: table, character: Model): AnimationTrack
	local animation: Animation = data["Animation"]
	local looped: boolean = data["Looped"] or false

	-- Ensure that 'looped' is a boolean.
	if typeof(looped) ~= "boolean" then
		warn("looped variable is not a boolean, it is {looped}! Will not play animation: {animation}.")
		return
	end
	
	if not character then
		warn("Character is nil! Will not play animation: {animation}.")
	end
	
	-- Load the animation track using the character’s animator (assumes 'animator' is defined in context).
	local newAnimTrack = animator:LoadAnimation(animation)
	newAnimTrack.Looped = looped
	-- Set up the keyframe event for sound effects.
	onKeyframeReached(newAnimTrack, character)
	-- Begin playback of the animation.
	newAnimTrack:Play()
	
	return newAnimTrack
end

-- Adjusts the playback speed of any animation tracks currently playing on the character that match the given animation
-- This allows for speed adjustments (e.g. to reflect momentum changes) after the animation has started
function Character.SetAnimationSpeedFromAnimation(animation: Animation, newPlaybackSpeed: number, character: Model)
	if not animation or not newPlaybackSpeed or not character then warn("Missing an argument for SetAnimationSpeed! Ending now...") return end
	if typeof(newPlaybackSpeed) ~= "number" then warn("newPlaybackSpeed is not a number! Ending now...") return end
	
	local animator: Animator = character.Humanoid.Animator
	local currentlyPlayingAnimationTracks = animator:GetPlayingAnimationTracks()
	for _, animTrack: AnimationTrack in ipairs(currentlyPlayingAnimationTracks) do
		if animTrack.Animation == animation then
			animTrack:AdjustSpeed() -- Potentially should pass newPlaybackSpeed here.
		end
	end
end

-- Stops any currently playing animation track on the character that matches the provided animation.
-- This function iterates through the character’s animator tracks and halts the matching animation, ensuring that visual and logical states stay aligned.
function Character.StopAnimation(animation: Animation, character: Model)
	local animator: Animator = character.Humanoid.Animator
	local currentlyPlayingAnimationTracks = animator:GetPlayingAnimationTracks()
	for _, animTrack: AnimationTrack in ipairs(currentlyPlayingAnimationTracks) do
		if animTrack.Animation == animation then
			animTrack:Stop()
		end
	end
end

-- Transitions the character to an Idle state.
-- If the character isn’t already idle, it adds the Idle state (by parenting its BoolValue) and removes any conflicting movement states.
-- Finally, it plays the Idle animation in a loop.
function Character.Idle(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyIdle = Character.Is("Idle", character)
	if isAlreadyIdle then 
		-- Already in Idle state – nothing further to do.
		return 
	end

	-- Activate Idle state.
	Character.Add("Idle", character)
	-- Remove any states that conflict with being idle.
	Character.Remove("Walking", character)
	Character.Remove("Sprinting", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("CrouchIdling", character) -- Differentiated from regular idle.
	
	-- Start the Idle animation.
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Idle,
		["Looped"] = true
	}, character)
end

-- Transitions the character to a Walking state.
-- Activates the Walking state, removes conflicting states, sets the humanoid’s WalkSpeed to a standard value, and plays the walking animation.
function Character.Walk(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyWalking = Character.Is("Walking", character)
	if isAlreadyWalking then 
		return 
	end
	
	-- Activate Walking state and remove other movement states.
	Character.Add("Walking", character)
	Character.Remove("Idle", character)
	Character.Remove("Sprinting", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("CrouchIdling", character)
	
	-- Set movement speed.
	hum.WalkSpeed = 14
	
	-- Play the walking animation.
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Walking,
		["Looped"] = true
	}, character)
end

-- Transitions the character to a Sprinting state.
-- Checks if the character is already sprinting. If they're not, it activates the Sprinting state, removes any conflicting states,
-- increases WalkSpeed, and plays the sprinting animation
function Character.Sprint(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadySprinting = Character.Is("Sprinting", character)
	if isAlreadySprinting then 
		warn("Already sprinting, CharacterMovement.Sprint will end now.")
		return 
	end

	-- Activate Sprinting state and clear conflicting states.
	Character.Add("Sprinting", character)
	Character.Remove("Idle", character)
	Character.Remove("Walking", character)
	Character.Remove("CrouchIdling", character)
	Character.Remove("CrouchMoving", character)
	
	-- Increase speed for sprinting.
	hum.WalkSpeed = 30
	
	-- Play the sprinting animation.
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.Sprinting,
		["Looped"] = true
	}, character)
end

-- Transitions the character to a Crouch Idling state (crouched but stationary).
-- Activates the CrouchIdling state, removes states that conflict with a crouched stance, and plays the corresponding animation.
function Character.CrouchIdle(character: Model) 
	-- "CrouchIdling" indicates the character is crouched without movement.
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyCrouchIdling = Character.Is("CrouchIdling", character)
	if isAlreadyCrouchIdling then 
		return 
	end

	-- Activate CrouchIdling state and clear conflicting states.
	Character.Add("CrouchIdling", character)
	Character.Remove("CrouchMoving", character)
	Character.Remove("Idle", character)

	-- Start the crouch-idle animation.
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.CrouchIdling,
		["Looped"] = true
	}, character)
end

-- Transitions the character to a Crouch Moving state (crouched while moving).
-- Ensures the state isn’t already active, activates it, removes other movement states,
-- reduces WalkSpeed, and plays the appropriate animation.
function Character.CrouchMove(character: Model)
	local hum = character.Humanoid
	local root = character.HumanoidRootPart
	local isAlreadyCrouchMoving = Character.Is("CrouchMoving", character)
	if isAlreadyCrouchMoving then 
		warn("Already CrouchMoving, CharacterMovement.CrouchMoving will end now.") 
		return 
	end

	-- Activate the CrouchMoving state and remove conflicting states.
	Character.Add("CrouchMoving", character)
	Character.Remove("CrouchIdling", character)
	Character.Remove("Walking", character)
	Character.Remove("Sprinting", character)
	
	-- Set a slower movement speed appropriate for crouching.
	hum.WalkSpeed = 5

	-- Play the crouch moving animation.
	Character.PlayAnimation({
		["Animation"] = AnimationsFolder.CrouchMoving,
		["Looped"] = true
	}, character)
end

-- Initiates the falling sequence for the character.
-- The function transitions the character into a Falling state, starts the falling animation,
-- and enters a loop that continuously updates the character’s orientation, velocity, and sound effects until landing.
-- It tracks the highest Y-position reached (to compute fall distance), applies gradual deceleration (simulating air resistance),
-- and, upon landing, determines whether to apply damage, play a landing animation, or allow a recovery roll.
function Character.Fall(character: Model, shouldJumpForward: boolean)
	local hum: Humanoid = character.Humanoid
	local root: BasePart = character.HumanoidRootPart
	local isAlreadyFalling = Character.Is("Falling", character)
	
	if isAlreadyFalling then 
		warn("Already falling, CharacterMovement.Fall will end now.")
		return 
	end

	-- Activate Falling state and remove other movement states.
	Character.Add("Falling", character)
	Character.Remove("Sprinting", character)
	Character.Remove("Walking", character)
	Character.Remove("RecoverRolling", character)
	Character.Remove("Idle", character) -- In case the character transitions from Idle.

	-- Stop any ongoing recovery roll sound effect to avoid overlap.
	if SoundFX.RecoverRoll.IsPlaying then SoundFX.RecoverRoll:Stop() end

	-- Record the highest Y-position during the fall (used later for damage calculation).
	local fallY = root.Position.Y 
	-- Capture the current horizontal velocity to preserve momentum.
	local currentVelocity = root.AssemblyLinearVelocity 
	local rollVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	-- Store the character's orientation so it remains consistent throughout the fall.
	local rotationConstant = root.CFrame - root.CFrame.Position
	-- Halt horizontal movement immediately.
	hum.WalkSpeed = 0
	if rs:IsClient() then
		SoundFX.Jump:Play()
	end

	-- Optionally add forward momentum to simulate a jump.
	if shouldJumpForward then
		root.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, hum.JumpPower * 1.25, currentVelocity.Z)
	end

	-- Set up parameters for the wind sound effect during a long fall.
	local fallingSoundStartVolume = 0
	local fallingSoundMaxVolume = 3

	-- Play the falling animation.
	Character.PlayAnimation({["Animation"] = AnimationsFolder.Falling, ["Looped"] = true}, character)
	
	-- Continuously update the fall until the character lands.
	while hum:GetState() ~= states.Landed  do
		-- Maintain the character’s orientation by reapplying the stored rotation.
		root.CFrame = CFrame.new(root.Position) * rotationConstant
		-- Update the highest Y-position reached.
		if root.Position.Y > fallY then
			fallY = root.Position.Y
		end

		local fallDistance = fallY - root.Position.Y
		-- If the fall is long and no tween is active, start the wind sound effect with a tween to increase volume.
		if fallDistance > 0 and not Character[character]["CurrentFallSoundTween"] then
			SoundFX.FallWind:Play()
			Character[character]["CurrentFallSoundTween"] = ts:Create(SoundFX.FallWind, fallSoundTweenInfo, {Volume = fallingSoundMaxVolume})
			Character[character]["CurrentFallSoundTween"]:Play()
		end
		
		-- Gradually reduce horizontal velocity to simulate air resistance.
		root.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, root.AssemblyLinearVelocity.Y, currentVelocity.Z)
		if currentVelocity.X > 0 then
			currentVelocity = currentVelocity - Vector3.new(0.15, 0, 0)
		elseif currentVelocity.X < 0 then
			currentVelocity = currentVelocity - Vector3.new(-0.15, 0, 0)
		end
		if currentVelocity.Z > 0 then
			currentVelocity = currentVelocity - Vector3.new(0, 0, 0.15)
		elseif currentVelocity.Z < 0 then
			currentVelocity = currentVelocity - Vector3.new(0, 0, -0.15)
		end

		task.wait()
	end

	-- Upon landing, stop all motion to avoid clipping issues.
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	Character.Remove("Falling", character)

	-- Clean up the wind sound tween if it exists.
	if Character[character]["CurrentFallSoundTween"] then Character[character]["CurrentFallSoundTween"]:Cancel() end
	SoundFX.FallWind:Stop()
	SoundFX.FallWind.Volume = fallingSoundStartVolume
	Character[character]["CurrentFallSoundTween"] = nil

	local currentY = root.Position.Y
	if not fallY then return end

	-- Calculate the total fall distance.
	local fallDistance = (fallY - currentY)
	-- If the fall is significant, handle damage and potential recovery roll.
	if fallDistance > 20 then
		-- Store the fall distance as an attribute for further processing.
		local fallDistanceValueBase = Character.Add("FallDistance", character)
		fallDistanceValueBase:SetAttribute("Height", fallDistance)
		if Character.Is("TryingToRecoverRoll", character) then
			-- Note: The following call retains an extra closing parenthesis from the original code.
			Character.RecoverRoll(character, rollVelocity))
		else
			Character.Add("RecoveringFromBigFall", character)
			hum.WalkSpeed = 0
			-- Apply damage proportional to the fall distance.
			hum:TakeDamage(math.floor(fallDistance * 1/5))
			SoundFX.BigLanding:Play()
			local landingAnimTrack = Character.PlayAnimation({["Animation"] = AnimationsFolder.RecoveringFromBigFall}, character)
			landingAnimTrack.Ended:Wait()

			if not Character.Is("Falling", character) then
				Character.Remove("RecoveringFromBigFall", character)
			end
		end

	else
		-- For short falls, play a minor landing sound.
		SoundFX.SmallLanding:Play()
	end

	Character.Remove("FailedToRecoverRoll", character)
end

--> RecoverRoll mitigates fall damage by causing the player to roll quickly forward.
--> It is only executed if the character times the roll correctly (as determined by StartRecoverRollAttempt).
function Character.RecoverRoll(character: Model, direction: Vector3)
	-- Perform a recovery roll maneuver to lessen the impact of a big fall.
	local hum: Humanoid = character.Humanoid
	local root: BasePart = character.HumanoidRootPart
	local rootAttachment: Attachment = root.RootAttachment
	local isAlreadyRecoverRolling = Character.Is("RecoverRolling", character)
	if isAlreadyRecoverRolling then 
		warn("Already recover rolling! No need to try again!")
		return
	end

	-- Play the recovery roll animation at a faster speed.
	local rollingAnimTrack = Character.PlayAnimation({
		["Animation"] = AnimationsFolder.RecoverRolling,
		["Looped"] = false
	}, character)
	rollingAnimTrack:AdjustSpeed(1.5)
	-- Disable player controls during the roll to avoid input interference.
	Character.DisableControls(character)
	SoundFX.RecoverRoll:Play()
	
	-- Activate the RecoverRolling state and clear other conflicting states.
	Character.Add("RecoverRolling", character)
	Character.Remove("TryingToRecoverRoll", character)
	Character.Remove("Falling", character)
	
	-- Increase movement speed and apply directional movement for the roll.
	hum.WalkSpeed = 30
	hum:Move(direction)
	
	-- Wait until the recovery roll animation completes.
	rollingAnimTrack.Stopped:Wait()

	-- Once finished, remove the rolling state and re-enable player controls.
	Character.Remove("RecoverRolling", character)
	Character.EnableControls(character)
end

-- Initiates a brief time window during which a recovery roll can be executed to mitigate fall damage
-- If the roll isn’t triggered within the time window, the attempt is marked as failed
function Character.StartRecoverRollAttempt(character: Model)
	-- Recovery roll attempts are only valid on significant falls.
	local failedToRecoverRoll = Character.Is("FailedToRecoverRoll", character)
	if failedToRecoverRoll then warn({character} .. " can't try to recover, because they already missed their recovery roll window!") return end
	local isTryingToRecoverRoll = Character.Is("TryingToRecoverRoll", character)
	if isTryingToRecoverRoll then return end
	local isRecoverRolling = Character.Is("RecoverRolling", character)
	if isRecoverRolling then return end
	
	-- Activate the state that indicates an attempt to recover roll
	Character.Add("TryingToRecoverRoll", character)
	local start = os.clock()
	local timeWindow = .1 --> time window in seconds for a valid recovery roll attempt
	local timeElapsed = os.clock() - start
	coroutine.resume(coroutine.create(function()
		while timeElapsed < timeWindow and Character.Is("Falling", character) do
			task.wait()
			timeElapsed = os.clock() - start
		end
		-- If the recovery roll is not triggered within the time window, mark the attempt as failed
		if timeElapsed >= .1 and Character.Is("Falling", character) then
			Character.Remove("TryingToRecoverRoll", character)
			Character.Add("FailedToRecoverRoll", character)
		end
	end))
end

-- A convenience function to initiate a jump, which is implemented by starting the fall sequence with forward momentum
function Character.Jump(character: Model)
	Character.Fall(character, true)
end

-- Disables player input controls by adding a state flag and interfacing with the player's control module.
-- This is particularly useful during scripted maneuvers (e.g. recovery roll) to ensure that manual input does not conflict.
function Character.DisableControls(character: Model)
	Character.Add("DisabledControls", character)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if player then
		require(player.PlayerScripts.PlayerModule):GetControls():Disable()
	end
end

-- Re-enables player input controls by removing the state flag and interfacing with the player's control module.
function Character.EnableControls(character: Model)
	Character.Remove("DisabledControls", character)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if player then
		require(player.PlayerScripts.PlayerModule):GetControls():Enable()
	end
end

-- Disables jump detection by adding a specific state flag.
-- This can be useful during certain animations or state transitions to prevent unintended jump behavior.
function Character.DisableJumpDetection(character: Model)
	Character.Add("DisabledJumpDetection", character)
end

-- Re-enables jump detection by removing the associated state flag.
function Character.EnableJumpDetection(character: Model)
	Character.Remove("DisabledJumpDetection", character)
end

return Character
