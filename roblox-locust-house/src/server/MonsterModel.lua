--!nonstrict
-- Собираем монстра ("Саранчу") из обычных партов: R6-скелет,
-- чтобы работал Humanoid:MoveTo и стандартный поиск пути.

local MonsterModel = {}

local SCALE = 1.45
local BODY_COLOR = Color3.fromRGB(46, 54, 32)
local LIMB_COLOR = Color3.fromRGB(32, 38, 24)

export type Rig = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Head: BasePart,
	Eyes: { BasePart },
	Light: PointLight,
}

local function makeLimb(parent: Model, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size * SCALE
	part.Color = color
	part.Material = Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = true
	part.Parent = parent
	return part
end

local function weld(a: BasePart, b: BasePart, offset: Vector3)
	b.CFrame = a.CFrame * CFrame.new(offset * SCALE)
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = CFrame.new(offset * SCALE)
	w.Parent = a
end

function MonsterModel.build(spawnPosition: Vector3, collisionGroup: string?): Rig
	local model = Instance.new("Model")
	model.Name = "Saranha"

	local root = makeLimb(model, "HumanoidRootPart", Vector3.new(2, 2, 1), BODY_COLOR)
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = CFrame.new(spawnPosition + Vector3.new(0, 3 * SCALE, 0))
	model.PrimaryPart = root

	local torso = makeLimb(model, "Torso", Vector3.new(2, 2, 1), BODY_COLOR)
	weld(root, torso, Vector3.new(0, 0, 0))

	local head = makeLimb(model, "Head", Vector3.new(1.6, 1.4, 1.6), Color3.fromRGB(70, 82, 46))
	weld(torso, head, Vector3.new(0, 1.7, 0))

	local eyes: { BasePart } = {}
	for i, side in { -0.45, 0.45 } do
		local eye = makeLimb(model, "Eye" .. i, Vector3.new(0.35, 0.35, 0.2), Color3.fromRGB(255, 60, 40))
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		weld(head, eye, Vector3.new(side, 0.15, -0.85))
		table.insert(eyes, eye)
	end

	-- Усы-антенны: чисто для вида, столкновений нет.
	for i, side in { -0.5, 0.5 } do
		local antenna = makeLimb(model, "Antenna" .. i, Vector3.new(0.18, 2.2, 0.18), LIMB_COLOR)
		antenna.CanCollide = false
		weld(head, antenna, Vector3.new(side, 1.3, -0.2))
	end

	weld(torso, makeLimb(model, "Right Arm", Vector3.new(1, 2.6, 1), LIMB_COLOR), Vector3.new(1.5, -0.2, 0))
	weld(torso, makeLimb(model, "Left Arm", Vector3.new(1, 2.6, 1), LIMB_COLOR), Vector3.new(-1.5, -0.2, 0))
	weld(torso, makeLimb(model, "Right Leg", Vector3.new(1, 2, 1), LIMB_COLOR), Vector3.new(0.5, -2, 0))
	weld(torso, makeLimb(model, "Left Leg", Vector3.new(1, 2, 1), LIMB_COLOR), Vector3.new(-0.5, -2, 0))

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 70, 50)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = torso

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = 100000 -- монстра нельзя убить, только убежать
	humanoid.Health = 100000
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = true
	humanoid.Parent = model

	-- Чтобы игроки не толкали монстра и не катались на нём.
	if collisionGroup then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = collisionGroup
			end
		end
	end

	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = head,
		Eyes = eyes,
		Light = light,
	}
end

return MonsterModel
