--!nonstrict
-- GameConfig: все числа игры в одном месте. Меняй тут, ничего больше трогать не надо.

local GameConfig = {}

GameConfig.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 25,
	MaxStamina = 100,
	SprintDrain = 16,      -- стамины в секунду при беге
	StaminaRegen = 11,     -- стамины в секунду при восстановлении
	RegenDelay = 1.0,      -- пауза перед восстановлением
	MinSprintStamina = 8,  -- ниже этого бежать нельзя
}

GameConfig.Slide = {
	Duration = 0.75,       -- сколько длится подкат
	Cooldown = 1.4,
	Speed = 58,            -- импульс подката
	HeightScale = 0.42,    -- во сколько раз ужимается персонаж (чтобы пролезть в лаз)
	StaminaCost = 18,
	Noise = 40,            -- радиус шума от подката
}

GameConfig.Noise = {
	SprintRadius = 26,
	SprintInterval = 0.45,
	DoorRadius = 35,
	BaitRadius = 70,
	BaitInterval = 0.6,
}

-- ГЛАВНАЯ ФИШКА: дерзость. Дразнишь монстра -> он злее и быстрее,
-- но твой множитель очков растёт. Поймал - теряешь всё.
GameConfig.Rage = {
	TauntRadius = 40,        -- с какой дистанции монстр слышит и видит подколку
	TauntCooldown = 2.5,
	TauntRageGain = 18,
	TauntNoise = 220,        -- дразнилку слышно почти через весь дом
	DecayDelay = 4.0,        -- через сколько секунд без подколок ярость падает
	DecayRate = 2.2,         -- ярости в секунду
	AngryThreshold = 40,
	FuryThreshold = 80,
	SpeedBonus = 0.45,       -- при 100 ярости монстр на 45% быстрее
	MultiplierStep = 0.35,   -- +0.35 к множителю за каждую подколку подряд
	MaxMultiplier = 5,
	StreakTimeout = 25,      -- не дразнишь 25 сек - серия сгорает
}

GameConfig.Bait = {
	MaxCharges = 3,
	RechargeTime = 18,
	ThrowSpeed = 90,
	LifeTime = 12,
	ConfuseTime = 4.5,       -- сколько монстр тупит возле приманки
	Cooldown = 1.0,
}

GameConfig.Monster = {
	PatrolSpeed = 9,
	InvestigateSpeed = 13,
	ChaseSpeed = 20,         -- меньше спринта игрока: убежать можно, но стамина кончится
	SightRange = 60,
	FurySightRange = 95,
	FieldOfView = 110,       -- градусов
	CatchDistance = 4.5,
	SearchTime = 7,          -- сколько ищет на последней известной точке
	LoseSightGrace = 2.5,    -- сколько секунд помнит игрока без прямой видимости
	RepathInterval = 0.45,
	StunOnBait = 4.5,
}

GameConfig.Round = {
	KeysToEscape = 4,
	RespawnDelay = 4,
	EscapeScore = 100,
	KeyScore = 25,
	TauntScore = 15,
	IntermissionTime = 8,
}

GameConfig.Map = {
	WallHeight = 14,
	WallThickness = 2,
	VentHeight = 3.5,        -- высота лаза: стоя не пройти, подкатом - да
	FloorY = 0,
	HalfX = 70,
	HalfZ = 55,
}

return GameConfig
