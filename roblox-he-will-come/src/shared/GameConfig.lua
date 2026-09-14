--!nonstrict
-- HE WILL COME - все настройки в одном месте.

local GameConfig = {}

GameConfig.Rooms = {
	MaxPlayers = 4,          -- больше 4 в комнату нельзя
	MaxRooms = 4,            -- сколько комнат живёт на одном сервере
	ArenaSpacing = 3000,     -- комнаты стоят далеко друг от друга, чтобы не мешать
	ArenaBaseOffset = Vector3.new(3000, 0, 0),
	LobbyCenter = Vector3.new(0, 0, 0),
}

GameConfig.Movement = {
	WalkSpeed = 15,
	SprintSpeed = 24,
	CrouchSpeed = 7,
	MaxStamina = 100,
	SprintDrain = 15,
	StaminaRegen = 10,
	RegenDelay = 1.2,
	MinSprintStamina = 6,
}

-- Громкость действий. ОН слепой и охотится только на звук и свет.
GameConfig.Noise = {
	TickInterval = 0.5,
	Crouch = 0,              -- присел и крадёшься - ты для него не существуешь
	Walk = 14,
	Sprint = 34,
	Flashlight = 16,         -- включённый фонарь он тоже "чувствует"
	Fuse = 70,               -- вставил предохранитель - шум на весь дом
	Scream = 140,            -- паника при нуле рассудка
	Decay = 12,              -- сколько "тепла" спадает в секунду
	MaxHeat = 200,
	SenseRadius = 9,         -- вплотную чувствует даже молчащего
}

-- ОН
GameConfig.He = {
	BaseSpeed = 11,
	MaxSpeed = 27,
	Momentum = 0.45,         -- прибавка скорости в секунду, пока на него не смотрят
	MomentumLossOnGaze = 6,  -- сколько скорости теряет за секунду под взглядом
	GazeSpeedFactor = 0.18,  -- под взглядом почти стоит
	GazeRange = 70,
	GazeAngle = 22,          -- насколько точно надо смотреть, в градусах
	CatchDistance = 4.2,
	CatchCooldown = 6,
	RepathInterval = 0.5,
	WanderRadius = 45,
}

GameConfig.Sanity = {
	Max = 100,
	GazeDrain = 9,           -- смотреть на него страшно и дорого
	Regen = 4.5,
	RegenDelay = 2,
	PanicRefill = 30,
	PanicLockTime = 5,       -- после паники нельзя бежать
	NearDrain = 3,           -- он рядом - рассудок тоже капает
	NearDistance = 18,
}

GameConfig.Match = {
	PrepTime = 30,           -- тихая фаза до его прихода
	FusesRequired = 3,
	FuseHoldTime = 4,
	ReviveTime = 4,
	BleedOutTime = 45,
	EndScreenTime = 8,
	MaxMatchTime = 600,
}

GameConfig.Arena = {
	WallHeight = 16,
	WallThickness = 2,
	HalfX = 90,
	HalfZ = 70,
}

return GameConfig
