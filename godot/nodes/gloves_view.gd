class_name GlovesView
extends Node2D
## The fight patch's dropped gloves and stick (upgloves): the fixed-to-rink object at
## $FFBE5C, frame 846, at glovecords * 4 on the ice. setvideo puts it after every sort
## object and the pad stars, so it draws behind all of them. Attribute 0: the frame's own
## palette line (2, the home uniform). Hidden while glovecords is 0 (always, in retail).

var game: HockeyGame

func _ready() -> void:
	game = HockeyGame.find(self)
	if game == null:
		return
	material = game.palette_material(false)
	z_index = Rink2D.Z_LOGO + 1
	z_as_relative = false
	game.stepped.connect(_sync)

func _sync() -> void:
	var p: Variant = game.world.fight.gloves_pos()
	visible = p != null and SpriteAtlas.has_frame(FightLogic.SPF_GLOVES) and not game.world.intermission
	if not visible:
		return
	var g: Vector2i = p
	if game.world.sflags & HockeyWorld.SF_HOR:
		position = Vector2(-g.y, 0xC5 - g.x)
	else:
		position = Vector2(g.x, -g.y)
	queue_redraw()

func _draw() -> void:
	SpriteAtlas.draw_frame(self, FightLogic.SPF_GLOVES, Vector2.ZERO, 0)
