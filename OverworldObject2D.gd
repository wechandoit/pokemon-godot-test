extends CharacterBody3D
class_name OverworldObject2D

var parent: Node3D
var world: GridMap
var tileDefs: GridmapCollisionHelper # Safely typed reference to your custom library

const FACING_TO_OFFSET = [
	Vector3(1, 0, 0),   # DOWN
	Vector3(0, 0, 1),   # LEFT
	Vector3(-1, 0, 0),  # UP
	Vector3(0, 0, -1)   # RIGHT
]

enum FACING_VALUES {DOWN, LEFT, UP, RIGHT, INVALID}

const TEX_WALK = preload("res://player_m_walk.png")
const TEX_RUN = preload("res://player_m_run.png")

const walkSpeed = 4.0
const runSpeed = walkSpeed * 2.0
const quickTurnMargin = 0.25 / 3.0

const FACING_INVERSE = [FACING_VALUES.UP, FACING_VALUES.RIGHT, FACING_VALUES.DOWN, FACING_VALUES.LEFT, FACING_VALUES.INVALID]

var posTileLast = Vector3(0, 1, 0)
var posTile = Vector3(0, 1, 0)
var velTile = Vector3.ZERO

var dirFacing = FACING_VALUES.UP
var lastDirFacing = FACING_VALUES.UP
var moveVel = 0.0
var yLayer = 0

var slopeSpeedMultiplier = 1.0
var moveBlocked = false

@onready var sprite = $Sprite3D
@onready var animPlayer = $Sprite3D/AnimationPlayer
@onready var floorCast = $floorCast
@onready var cam = $Camera3D

var moveTimer = 0.0
var quickTurnTimer = 0.0

func _ready():
	parent = get_parent_node_3d()
	world = parent.get_node("GridMap")
	tileDefs = world.mesh_library as GridmapCollisionHelper 
	play_anim(str("Idle", dirFacing))

func _process(delta):
	# 1. Unified movement speed calculation
	var running_input = Input.is_action_pressed("overworld_run")
	moveVel = runSpeed if running_input else walkSpeed

	# 2. Prevent single-frame texture swapping between grid tiles
	var is_moving = moveTimer > 0 or hasPlayerInvokedMove()
	var is_running = running_input and is_moving
	
	print("Player Y -> Tile: %d | World: %.2f" % [posTile.y, position.y])
	
	var target_tex = TEX_RUN if is_running else TEX_WALK
	if sprite.texture != target_tex:
		sprite.texture = target_tex

	# 3. Handle visual positioning and step logic
	if moveTimer > 0 and quickTurnTimer <= 0:
		var anim_prefix = "Run" if is_running else "Walk"
		play_anim(str(anim_prefix, dirFacing))
		
		position.x = lerp(posTile.x, posTileLast.x, moveTimer) * world.cell_size.x
		position.y = lerp(posTile.y, posTileLast.y, moveTimer) * world.cell_size.y
		position.z = lerp(posTile.z, posTileLast.z, moveTimer) * world.cell_size.z
	else:
		position.x = posTile.x * world.cell_size.x
		position.y = posTile.y * world.cell_size.y
		position.z = posTile.z * world.cell_size.z
		
		if hasPlayerInvokedMove():
			if Input.is_action_pressed("overworld_up"):
				dirFacing = FACING_VALUES.UP
			elif Input.is_action_pressed("overworld_down"):
				dirFacing = FACING_VALUES.DOWN
			elif Input.is_action_pressed("overworld_left"):
				dirFacing = FACING_VALUES.LEFT
			elif Input.is_action_pressed("overworld_right"):
				dirFacing = FACING_VALUES.RIGHT
			
			if isFacingTileSolid():
				if not moveBlocked:
					quickTurnTimer = quickTurnMargin
					play_anim(str("Walk", dirFacing))
					moveBlocked = true
			
			if hasPlayerJustInvokedMove():
				if dirFacing != lastDirFacing:
					quickTurnTimer = quickTurnMargin
					play_anim(str("Walk", dirFacing))
					
			if quickTurnTimer <= 0:
				if not isFacingTileSolid():
					posTileLast = posTile
					posTile += FACING_TO_OFFSET[dirFacing]
					slopeSpeedMultiplier = 1.0
					
					var uphillOri = GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]]
					var downhillOri = GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing]

					# UPHILL STEP 1: Stepping off a slope onto an elevated flat floor
					var lastFloorTile = Vector3i(posTileLast.x, posTileLast.y - 1, posTileLast.z)
					var lastCelId = world.get_cell_item(lastFloorTile)
					var targetTopFloorTile = Vector3i(posTile.x, posTile.y, posTile.z)
					var targetTopCelId = world.get_cell_item(targetTopFloorTile)

					if lastCelId != GridMap.INVALID_CELL_ITEM \
					and tileDefs.collisionType[lastCelId] == GridmapCollisionHelper.TYPES.SLOPE \
					and world.get_cell_item_orientation(lastFloorTile) == uphillOri:
						if targetTopCelId != GridMap.INVALID_CELL_ITEM \
						and tileDefs.collisionType[targetTopCelId] != GridmapCollisionHelper.TYPES.SLOPE:
							posTile.y += 1
							slopeSpeedMultiplier = 0.7

					# UPHILL STEP 2: Stepping onto a slope tile from ground level
					var targetFloor = Vector3i(posTile.x, posTile.y - 1, posTile.z)
					var celId = world.get_cell_item(targetFloor)
					if celId != GridMap.INVALID_CELL_ITEM \
					and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE \
					and world.get_cell_item_orientation(targetFloor) == uphillOri:
						slopeSpeedMultiplier = 0.7

					# DOWNHILL STEP: Stepping down onto a slope tile
					if posTile.y > 1:
						var targetSlopeBelow = Vector3i(posTile.x, posTile.y - 2, posTile.z)
						var targetBelowCelId = world.get_cell_item(targetSlopeBelow)

						if targetBelowCelId != GridMap.INVALID_CELL_ITEM \
						and tileDefs.collisionType[targetBelowCelId] == GridmapCollisionHelper.TYPES.SLOPE \
						and world.get_cell_item_orientation(targetSlopeBelow) == downhillOri:
							posTile.y -= 1
							slopeSpeedMultiplier = 0.85

					moveTimer = 1.0
					var anim_prefix = "Run" if is_running else "Walk"
					play_anim(str(anim_prefix, dirFacing))
			
		else:
			moveBlocked = false
			if quickTurnTimer <= 0:
				moveTimer = 0.0
				moveVel = 0.0
		
		if moveTimer <= 0 and quickTurnTimer <= 0:
			moveTimer = 0.0
			moveVel = 0.0
			play_anim(str("Idle", dirFacing))
		
	moveTimer -= delta * moveVel * slopeSpeedMultiplier
	quickTurnTimer -= delta
	lastDirFacing = dirFacing

func play_anim(anim_name: String):
	if animPlayer.current_animation != anim_name:
		animPlayer.play(anim_name)

func isFacingTileSolid() -> bool:
	if not tileDefs: 
		return true
	
	var checkTile = posTile + FACING_TO_OFFSET[dirFacing]
	
	# Check if player is currently standing on a slope
	var standingFloor = Vector3i(posTile.x, posTile.y - 1, posTile.z)
	var standingCel = world.get_cell_item(standingFloor)
	var standingOnSlope = (standingCel != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[standingCel] == GridmapCollisionHelper.TYPES.SLOPE)
	var standingSlopeOri = world.get_cell_item_orientation(standingFloor) if standingOnSlope else -1

	var uphillOri = GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]]
	var downhillOri = GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing]

	# 1. Check elevated target tile at posTile.y (stepping uphill off slope onto flat floor)
	var targetAtY = Vector3i(checkTile.x, posTile.y, checkTile.z)
	var celAtY = world.get_cell_item(targetAtY)
	if standingOnSlope and standingSlopeOri == uphillOri and celAtY != GridMap.INVALID_CELL_ITEM:
		if tileDefs.collisionType[celAtY] != GridmapCollisionHelper.TYPES.SOLID:
			return false # Allowed to step up onto elevated flat floor

	# 2. Check head/waist height block at current elevated target
	var waistCelId = world.get_cell_item(Vector3i(checkTile.x, posTile.y, checkTile.z))
	if waistCelId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[waistCelId] == GridmapCollisionHelper.TYPES.SOLID:
		return true

	# 3. Check floor layer directly ahead at y - 1
	var floorCheckTile = Vector3i(checkTile.x, posTile.y - 1, checkTile.z)
	var celId = world.get_cell_item(floorCheckTile)

	if celId != GridMap.INVALID_CELL_ITEM:
		var celType = tileDefs.collisionType[celId]
		if celType == GridmapCollisionHelper.TYPES.SOLID:
			return true
		elif celType == GridmapCollisionHelper.TYPES.SLOPE:
			var celOri = world.get_cell_item_orientation(floorCheckTile)
			# Uphill step onto slope
			if celOri == uphillOri:
				return false
			# Parallel/sideways step on slope
			if standingOnSlope and celOri == standingSlopeOri:
				return false
			return true
		else:
			# Normal flat floor ahead at same layer
			return false

	# 4. Check layer below at y - 2 (stepping downhill onto slope or parallel slope)
	var slopeBelow = Vector3i(checkTile.x, posTile.y - 2, checkTile.z)
	var celIdBelow = world.get_cell_item(slopeBelow)
	if celIdBelow != GridMap.INVALID_CELL_ITEM:
		var celTypeBelow = tileDefs.collisionType[celIdBelow]
		if celTypeBelow == GridmapCollisionHelper.TYPES.SLOPE:
			var slopeOri = world.get_cell_item_orientation(slopeBelow)
			if slopeOri == downhillOri or (standingOnSlope and slopeOri == standingSlopeOri):
				return false

	# Block ledges/cliffs without slopes
	return true

func hasPlayerInvokedMove() -> bool:
	return Input.is_action_pressed("overworld_up") or Input.is_action_pressed("overworld_down") or Input.is_action_pressed("overworld_left") or Input.is_action_pressed("overworld_right")
	
func hasPlayerJustInvokedMove() -> bool:
	return (Input.is_action_just_pressed("overworld_up") or Input.is_action_just_pressed("overworld_down") or Input.is_action_just_pressed("overworld_left") or Input.is_action_just_pressed("overworld_right")) and quickTurnTimer <= 0 and moveTimer <= 0
