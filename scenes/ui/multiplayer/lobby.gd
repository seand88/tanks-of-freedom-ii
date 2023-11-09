extends "res://scenes/ui/menu/base_menu_panel.gd"

@onready var multiplayer_srv = $"/root/Multiplayer"
@onready var online = $"/root/Online"
@onready var map_list_service = $"/root/MapManager"
@onready var switcher = $"/root/SceneSwitcher"
@onready var match_setup = $"/root/MatchSetup"
@onready var start_button = $"widgets/start_button"
@onready var minimap = $"widgets/minimap"

@onready var widgets = $"widgets"
@onready var downloading_label = $"downloading"

@onready var player_panels = [
	$"widgets/lobby_player_0",
	$"widgets/lobby_player_1",
	$"widgets/lobby_player_2",
	$"widgets/lobby_player_3",
]
@onready var player_labels = [
	[$"widgets/player_0", $"widgets/player_0/label"],
	[$"widgets/player_1", $"widgets/player_1/label"],
	[$"widgets/player_2", $"widgets/player_2/label"],
	[$"widgets/player_3", $"widgets/player_3/label"],
]
var hq_templates = [
	"modern_hq",
	"steampunk_hq",
	"futuristic_hq",
	"feudal_hq",
]
var server_state = null

func _ready():
	super._ready()
	self.multiplayer_srv.player_connected.connect(_on_player_connected)
	self.multiplayer_srv.player_disconnected.connect(_on_player_disconnected)
	self.multiplayer_srv.server_disconnected.connect(_on_server_disconnected)

	for panel in self.player_panels:
		panel.player_joined.connect(_on_player_joined_side)
		panel.player_left.connect(_on_player_left_side)

func show_panel():
	super.show_panel()

	if self.map_list_service._is_bundled(self.multiplayer_srv.selected_map) or self.map_list_service._is_online(self.multiplayer_srv.selected_map):
		self._fill_map_data(self.multiplayer_srv.selected_map)
		self._apply_server_state()
		await self.get_tree().create_timer(0.1).timeout
		self.start_button.grab_focus()
	else:
		self._download_map_data(self.multiplayer_srv.selected_map)

func _download_map_data(map_name):
	self.widgets.hide()
	self.downloading_label.show()

	var result = await self.online.download_map(map_name)

	self.downloading_label.hide()
	self.widgets.show()

	if result:
		self._fill_map_data(map_name)
		self._apply_server_state()
		await self.get_tree().create_timer(0.1).timeout
		self.start_button.grab_focus()
	else:
		_on_back_button_pressed()


func _fill_map_data(fill_name):
	self.minimap.fill_minimap(fill_name)
	$"widgets/minimap/map_name/label".set_text(fill_name)
	self._fill_player_panels(fill_name)

func _fill_player_labels():
	for label in self.player_labels:
		label[0].hide()

	var player_info = self.multiplayer_srv.players.values()
	for index in range(player_info.size()):
		self.player_labels[index][0].show()
		self.player_labels[index][1].set_text(player_info[index]["name"])


func _hide_player_panels():
	for panel in self.player_panels:
		panel.hide()
		panel._reset_labels()

func _fill_player_panels(fill_name):
	self._hide_player_panels()

	var sides = self._gather_player_sides(self.map_list_service.get_map_data(fill_name))

	var index = 0

	for side in sides:
		if index >= self.player_panels.size():
			continue
		self.player_panels[index].fill_panel(side)
		self.player_panels[index].show()
		index += 1

func _gather_player_sides(map_data):
	var sides = {}
	var side
	var key

	for y in range(self.map_list_service.MAX_MAP_SIZE):
		for x in range(self.map_list_service.MAX_MAP_SIZE):
			key = str(x) + "_" + str(y)
			if map_data["tiles"].has(key):
				side = self._lookup_side(map_data["tiles"][key])
				
				if side != null:
					sides[side] = side

	return sides

func _lookup_side(data):
	if data["building"]["tile"] != null:
		if data["building"]["tile"] in self.hq_templates:
			return data["building"]["side"]

	return null

	
func _on_back_button_pressed():
	if self.downloading_label.is_visible():
		return

	super._on_back_button_pressed()
	
	self.multiplayer_srv.close_game()
	self.main_menu.close_multiplayer_lobby()

func _on_player_connected(peer_id, _player_info):
	_fill_player_labels()
	if multiplayer.is_server() and peer_id != multiplayer.get_unique_id():
		var state = {}
		for panel in self.player_panels:
			state[panel.index] = panel.player_peer_id
		_set_lobby_state.rpc_id(peer_id, state)
	for panel in self.player_panels:
		panel._update_join_label()

func _on_player_disconnected(peer_id):
	_fill_player_labels()
	for panel in self.player_panels:
		if panel.player_peer_id == peer_id:
			panel._set_peer_id(null)

func _on_server_disconnected():
	_on_back_button_pressed()


func _on_start_button_pressed():
	self.audio.play("menu_click")

func _on_player_joined_side(index):
	for panel in self.player_panels:
		if panel.index != index:
			panel.lock_side()
	for peer_id in self.multiplayer_srv.players:
		if peer_id != multiplayer.get_unique_id():
			_player_joined_a_side.rpc_id(peer_id, multiplayer.get_unique_id(), index)

func _on_player_left_side(index):
	for panel in self.player_panels:
		if panel.index != index:
			panel.unlock_side()
	for peer_id in self.multiplayer_srv.players:
		if peer_id != multiplayer.get_unique_id():
			_player_left_a_side.rpc_id(peer_id, index)

@rpc("any_peer", "reliable")
func _player_joined_a_side(peer_id, index):
	self.player_panels[index]._set_peer_id(peer_id)

@rpc("any_peer", "reliable")
func _player_left_a_side(index):
	self.player_panels[index]._set_peer_id(null)

@rpc("any_peer", "reliable")
func _set_lobby_state(state):
	self.server_state = state

func _apply_server_state():
	if self.server_state != null:
		for index in self.server_state:
			self.player_panels[index]._set_peer_id(self.server_state[index])
	self.server_state = null

