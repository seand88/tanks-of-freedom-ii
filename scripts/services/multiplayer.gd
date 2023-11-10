extends Node

const PORT: int = 3939

signal connection_failed
signal connection_success
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal all_players_loaded

@onready var map_list_service: Node = $"/root/MapManager"
@onready var settings: Node = $"/root/Settings"

var players: Dictionary = {}
var players_loaded: int = 0

var selected_map: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func create_game(map_name: String) -> Error:
	self.players.clear()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(self.PORT, _get_player_count(map_name))
	if error:
		return error

	self.multiplayer.multiplayer_peer = peer
	players[1] = self._get_player_info()
	player_connected.emit(1, self._get_player_info())
	self.selected_map = map_name
	return OK

func connect_server(ip_address: String) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, self.PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func close_game() -> void:
	self.players.clear()
	self.players_loaded = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null



@rpc("call_local", "reliable")
func load_game() -> void:
	return

@rpc("any_peer", "call_local", "reliable")
func player_loaded() -> void:
	if multiplayer.is_server():
		players_loaded += 1
		if players_loaded == players.size():
			all_players_loaded.emit()
			#$/root/Game.start_game()
			players_loaded = 0


func _on_player_connected(id: int) -> void:
	_register_player.rpc_id(id, self._get_player_info())

@rpc("any_peer", "reliable")
func _register_player(new_player_info: Dictionary) -> void:
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

	if not multiplayer.is_server() and new_player_id == 1:
		self.selected_map = new_player_info["map"]

func _on_player_disconnected(id: int) -> void:
	self.players.erase(id)
	player_disconnected.emit(id)


func _on_connected_ok() -> void:
	var peer_id = multiplayer.get_unique_id()
	self.players[peer_id] = self._get_player_info()
	connection_success.emit()
	player_connected.emit(peer_id, self._get_player_info())

func _on_connected_fail() -> void:
	self.close_game()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	self.close_game()
	players.clear()
	server_disconnected.emit()









func _get_player_info() -> Dictionary:
	return {
		"name": self.settings.get_option("nickname"),
		"map": self.selected_map
	}

func _get_player_count(map_name: String) -> int:
	var map_data = self.map_list_service.get_map_data(map_name)

	var sides = {}
	var side
	var key

	for y in range(self.map_list_service.MAX_MAP_SIZE):
		for x in range(self.map_list_service.MAX_MAP_SIZE):
			key = str(x) + "_" + str(y)
			if map_data["tiles"].has(key):
				side = self._lookup_side(map_data["tiles"][key])
				
				if side != "":
					sides[side] = side
	return clampi(sides.size() - 1, 1, 3)

func _lookup_side(data: Dictionary) -> String:
	var hq_templates = [
		"modern_hq",
		"steampunk_hq",
		"futuristic_hq",
		"feudal_hq",
	]

	if data["building"]["tile"] != null:
		if data["building"]["tile"] in hq_templates:
			return data["building"]["side"]

	return ""
