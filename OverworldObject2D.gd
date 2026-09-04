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
	
	var target_tex = TEX_RUN if is_running else TEX_WALK
	if sprite.texture != target_tex:
		sprite.texture = target_tex

	# 3. Handle visual positioning and step logic
	if moveTimer > 0 and quickTurnTimer <= 0:
		var anim_prefix = "Run" if is_running else "Walk"
		play_anim(str(anim_prefix, dirFacing))
		
		position.x = lerp(posTile.x, posTileLast.x, moveTimer) * world.cell_size.x
		position.z = lerp(posTile.z, posTileLast.z, moveTimer) * world.cell_size.z
	else:
		position.x = posTile.x * world.cell_size.x
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
					var celId = world.get_cell_item(Vector3i(posTile))
					slopeSpeedMultiplier = 1.0
					
					if celId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE:
						posTile.y += 1
						slopeSpeedMultiplier = 0.7
						
					var lastPosFloor = Vector3i(posTileLast.x, posTileLast.y - 1, posTileLast.z)
					celId = world.get_cell_item(lastPosFloor)
					
					if celId != GridMap.INVALID_CELL_ITEM:
						if GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] == world.get_cell_item_orientation(lastPosFloor) and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE:
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

# Helper function to prevent restarting the animation track every frame
func play_anim(anim_name: String):
	if animPlayer.current_animation != anim_name:
		animPlayer.play(anim_name)

func isFacingTileSolid() -> bool:
	if not tileDefs: 
		return true
	
	var standingCel = world.get_cell_item(Vector3i(posTile.x, posTile.y - 1, posTile.z))
	var checkTile = posTile + FACING_TO_OFFSET[dirFacing]
	var waistCelId = world.get_cell_item(Vector3i(checkTile))
	var floorCheckTile = Vector3i(checkTile.x, checkTile.y - 1, checkTile.z)
	
	if waistCelId != GridMap.INVALID_CELL_ITEM:
		match tileDefs.collisionType[waistCelId]:
			GridmapCollisionHelper.TYPES.SOLID:
				return true
			GridmapCollisionHelper.TYPES.SLOPE:
				if GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]] != world.get_cell_item_orientation(Vector3i(checkTile)):
					return true
	
	var celId = world.get_cell_item(floorCheckTile)
	var celOri = world.get_cell_item_orientation(floorCheckTile)
	var testOri = world.get_cell_item_orientation(Vector3i(posTile.x, posTile.y - 1, posTile.z))
	
	if standingCel != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[standingCel] == GridmapCollisionHelper.TYPES.SLOPE:
		if celId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE and testOri == celOri:
			return false
		if GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] != testOri and GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]] != testOri:
			return true
			
	if celId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE and GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] != celOri:
		if GridmapCollisionHelper.INDEX_IS_SLOPE[celOri]:
			return true
		return false
		
	var celIdForSlope = world.get_cell_item(Vector3i(checkTile.x, checkTile.y - 2, checkTile.z))
	if celId == GridMap.INVALID_CELL_ITEM:
		if standingCel != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[standingCel] == GridmapCollisionHelper.TYPES.SLOPE and GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] == testOri and celIdForSlope != GridMap.INVALID_CELL_ITEM:
			return false
		else:
			return true
			
	return false

func hasPlayerInvokedMove() -> bool:
	return Input.is_action_pressed("overworld_up") or Input.is_action_pressed("overworld_down") or Input.is_action_pressed("overworld_left") or Input.is_action_pressed("overworld_right")
	
func hasPlayerJustInvokedMove() -> bool:
	return (Input.is_action_just_pressed("overworld_up") or Input.is_action_just_pressed("overworld_down") or Input.is_action_just_pressed("overworld_left") or Input.is_action_just_pressed("overworld_right")) and quickTurnTimer <= 0 and moveTimer <= 0
