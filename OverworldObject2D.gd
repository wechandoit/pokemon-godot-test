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

@onready var animPlayer = $Sprite3D/AnimationPlayer
@onready var floorCast = $floorCast
@onready var cam = $Camera3D

var moveTimer = 0.0
var quickTurnTimer = 0.0

func _ready():
	parent = get_parent_node_3d()
	world = parent.get_node("GridMap")
	# Cast the base MeshLibrary to your custom class so it recognizes collisionType
	tileDefs = world.mesh_library as GridmapCollisionHelper 
	animPlayer.play(str("Idle", dirFacing))

func _process(delta):
	if moveTimer > 0 and quickTurnTimer <= 0:
		if Input.is_action_pressed("overworld_run"):
			animPlayer.play(str("Run", dirFacing))
		else:
			animPlayer.play(str("Walk", dirFacing))
	else:
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
					animPlayer.play(str("Walk", dirFacing))
					moveBlocked = true
			
			if hasPlayerJustInvokedMove():
				if dirFacing != lastDirFacing:
					quickTurnTimer = quickTurnMargin
					animPlayer.play(str("Walk", dirFacing))
					
			if quickTurnTimer <= 0:
				if not isFacingTileSolid():
					posTileLast = posTile
					posTile += FACING_TO_OFFSET[dirFacing]
					var celId = world.get_cell_item(Vector3i(posTile))
					slopeSpeedMultiplier = 1.0
					
					# Using tileDefs and global class name instead of loaded helper
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
			
		else:
			moveBlocked = false
			if quickTurnTimer <= 0:
				moveTimer = 0.0
				moveVel = 0.0
		
		if moveTimer <= 0 and quickTurnTimer <= 0:
			moveTimer = 0.0
			moveVel = 0.0
			animPlayer.play(str("Idle", dirFacing))
		
	moveTimer -= delta * moveVel * slopeSpeedMultiplier
	quickTurnTimer -= delta
	lastDirFacing = dirFacing

func _physics_process(_delta):
	#floorCast.force_raycast_update()
	#if floorCast.is_colliding():
	#	global_position.y = floorCast.get_collision_point().y
	
	if moveTimer > 0 and quickTurnTimer <= 0:
		position.x = lerp(posTile.x, posTileLast.x, moveTimer) * world.cell_size.x
		position.z = lerp(posTile.z, posTileLast.z, moveTimer) * world.cell_size.z
		
		if Input.is_action_pressed("overworld_run"):
			moveVel = runSpeed
		else:
			moveVel = walkSpeed
	else:
		position.x = posTile.x * world.cell_size.x
		position.z = posTile.z * world.cell_size.z

func isFacingTileSolid() -> bool:
	if not tileDefs: 
		print("TILEDEF BLOCKING")
		return true # Fallback safeguard
	
	var standingCel = world.get_cell_item(Vector3i(posTile.x, posTile.y - 1, posTile.z))
	var checkTile = posTile + FACING_TO_OFFSET[dirFacing]
	var waistCelId = world.get_cell_item(Vector3i(checkTile))
	var floorCheckTile = Vector3i(checkTile.x, checkTile.y - 1, checkTile.z)
	
	print("Player Tile Y: ", posTile.y, " | Checking Floor Y: ", floorCheckTile.y)
	
	if waistCelId != GridMap.INVALID_CELL_ITEM:
		match tileDefs.collisionType[waistCelId]:
			GridmapCollisionHelper.TYPES.SOLID:
				print("SOLID BLOCKING")
				return true
			GridmapCollisionHelper.TYPES.SLOPE:
				if GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]] != world.get_cell_item_orientation(Vector3i(checkTile)):
					print("SLOPE BLOCKING 1")
					return true
	
	var celId = world.get_cell_item(floorCheckTile)
	var celOri = world.get_cell_item_orientation(floorCheckTile)
	var testOri = world.get_cell_item_orientation(Vector3i(posTile.x, posTile.y - 1, posTile.z))
	
	if standingCel != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[standingCel] == GridmapCollisionHelper.TYPES.SLOPE:
		if celId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE and testOri == celOri:
			print("SLOPE INVALID BLOCKING F")
			return false
		if GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] != testOri and GridmapCollisionHelper.ORTHO_TO_INDEX[FACING_INVERSE[dirFacing]] != testOri:
			print("SLOPE INVALID BLOCKING T")
			return true
			
	if celId != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[celId] == GridmapCollisionHelper.TYPES.SLOPE and GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] != celOri:
		if GridmapCollisionHelper.INDEX_IS_SLOPE[celOri]:
			print("SLOPE BLOCKING 2 T")
			return true
		print("SLOPE BLOCKING F")
		return false
		
	var celIdForSlope = world.get_cell_item(Vector3i(checkTile.x, checkTile.y - 2, checkTile.z))
	if celId == GridMap.INVALID_CELL_ITEM:
		if standingCel != GridMap.INVALID_CELL_ITEM and tileDefs.collisionType[standingCel] == GridmapCollisionHelper.TYPES.SLOPE and GridmapCollisionHelper.ORTHO_TO_INDEX[dirFacing] == testOri and celIdForSlope != GridMap.INVALID_CELL_ITEM:
			print("INVALID BLOCKING F")
			return false
		else:
			print("INVALID BLOCKING T")
			return true
			
	return false

func hasPlayerInvokedMove() -> bool:
	return Input.is_action_pressed("overworld_up") or Input.is_action_pressed("overworld_down") or Input.is_action_pressed("overworld_left") or Input.is_action_pressed("overworld_right")
	
func hasPlayerJustInvokedMove() -> bool:
	return (Input.is_action_just_pressed("overworld_up") or Input.is_action_just_pressed("overworld_down") or Input.is_action_just_pressed("overworld_left") or Input.is_action_just_pressed("overworld_right")) and quickTurnTimer <= 0 and moveTimer <= 0
