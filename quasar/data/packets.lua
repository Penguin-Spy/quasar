return{
["configuration"]={
["clientbound"]={
["clear_dialog"]=17,
["cookie_request"]=0,
["custom_payload"]=1,
["custom_report_details"]=15,
["disconnect"]=2,
["finish_configuration"]=3,
["keep_alive"]=4,
["ping"]=5,
["registry_data"]=7,
["reset_chat"]=6,
["resource_pack_pop"]=8,
["resource_pack_push"]=9,
["select_known_packs"]=14,
["server_links"]=16,
["show_dialog"]=18,
["store_cookie"]=10,
["transfer"]=11,
["update_enabled_features"]=12,
["update_tags"]=13,
},
["serverbound"]={
["client_information"]=0,
["cookie_response"]=1,
["custom_click_action"]=8,
["custom_payload"]=2,
["finish_configuration"]=3,
["keep_alive"]=4,
["pong"]=5,
["resource_pack"]=6,
["select_known_packs"]=7,
},
},
["handshake"]={
["serverbound"]={
["intention"]=0,
},
},
["login"]={
["clientbound"]={
["cookie_request"]=5,
["custom_query"]=4,
["hello"]=1,
["login_compression"]=3,
["login_disconnect"]=0,
["login_finished"]=2,
},
["serverbound"]={
["cookie_response"]=4,
["custom_query_answer"]=2,
["hello"]=0,
["key"]=1,
["login_acknowledged"]=3,
},
},
["play"]={
["clientbound"]={
["add_entity"]=1,
["animate"]=2,
["award_stats"]=3,
["block_changed_ack"]=4,
["block_destruction"]=5,
["block_entity_data"]=6,
["block_event"]=7,
["block_update"]=8,
["boss_event"]=9,
["bundle_delimiter"]=0,
["change_difficulty"]=10,
["chunk_batch_finished"]=11,
["chunk_batch_start"]=12,
["chunks_biomes"]=13,
["clear_dialog"]=132,
["clear_titles"]=14,
["command_suggestions"]=15,
["commands"]=16,
["container_close"]=17,
["container_set_content"]=18,
["container_set_data"]=19,
["container_set_slot"]=20,
["cookie_request"]=21,
["cooldown"]=22,
["custom_chat_completions"]=23,
["custom_payload"]=24,
["custom_report_details"]=129,
["damage_event"]=25,
["debug_sample"]=26,
["delete_chat"]=27,
["disconnect"]=28,
["disguised_chat"]=29,
["entity_event"]=30,
["entity_position_sync"]=31,
["explode"]=32,
["forget_level_chunk"]=33,
["game_event"]=34,
["horse_screen_open"]=35,
["hurt_animation"]=36,
["initialize_border"]=37,
["keep_alive"]=38,
["level_chunk_with_light"]=39,
["level_event"]=40,
["level_particles"]=41,
["light_update"]=42,
["login"]=43,
["map_item_data"]=44,
["merchant_offers"]=45,
["move_entity_pos"]=46,
["move_entity_pos_rot"]=47,
["move_entity_rot"]=49,
["move_minecart_along_track"]=48,
["move_vehicle"]=50,
["open_book"]=51,
["open_screen"]=52,
["open_sign_editor"]=53,
["ping"]=54,
["place_ghost_recipe"]=56,
["player_abilities"]=57,
["player_chat"]=58,
["player_combat_end"]=59,
["player_combat_enter"]=60,
["player_combat_kill"]=61,
["player_info_remove"]=62,
["player_info_update"]=63,
["player_look_at"]=64,
["player_position"]=65,
["player_rotation"]=66,
["pong_response"]=55,
["projectile_power"]=128,
["recipe_book_add"]=67,
["recipe_book_remove"]=68,
["recipe_book_settings"]=69,
["remove_entities"]=70,
["remove_mob_effect"]=71,
["reset_score"]=72,
["resource_pack_pop"]=73,
["resource_pack_push"]=74,
["respawn"]=75,
["rotate_head"]=76,
["section_blocks_update"]=77,
["select_advancements_tab"]=78,
["server_data"]=79,
["server_links"]=130,
["set_action_bar_text"]=80,
["set_border_center"]=81,
["set_border_lerp_size"]=82,
["set_border_size"]=83,
["set_border_warning_delay"]=84,
["set_border_warning_distance"]=85,
["set_camera"]=86,
["set_chunk_cache_center"]=87,
["set_chunk_cache_radius"]=88,
["set_cursor_item"]=89,
["set_default_spawn_position"]=90,
["set_display_objective"]=91,
["set_entity_data"]=92,
["set_entity_link"]=93,
["set_entity_motion"]=94,
["set_equipment"]=95,
["set_experience"]=96,
["set_health"]=97,
["set_held_slot"]=98,
["set_objective"]=99,
["set_passengers"]=100,
["set_player_inventory"]=101,
["set_player_team"]=102,
["set_score"]=103,
["set_simulation_distance"]=104,
["set_subtitle_text"]=105,
["set_time"]=106,
["set_title_text"]=107,
["set_titles_animation"]=108,
["show_dialog"]=133,
["sound"]=110,
["sound_entity"]=109,
["start_configuration"]=111,
["stop_sound"]=112,
["store_cookie"]=113,
["system_chat"]=114,
["tab_list"]=115,
["tag_query"]=116,
["take_item_entity"]=117,
["teleport_entity"]=118,
["test_instance_block_status"]=119,
["ticking_state"]=120,
["ticking_step"]=121,
["transfer"]=122,
["update_advancements"]=123,
["update_attributes"]=124,
["update_mob_effect"]=125,
["update_recipes"]=126,
["update_tags"]=127,
["waypoint"]=131,
},
["serverbound"]={
["accept_teleportation"]=0,
["block_entity_tag_query"]=1,
["bundle_item_selected"]=2,
["change_difficulty"]=3,
["change_game_mode"]=4,
["chat"]=8,
["chat_ack"]=5,
["chat_command"]=6,
["chat_command_signed"]=7,
["chat_session_update"]=9,
["chunk_batch_received"]=10,
["client_command"]=11,
["client_information"]=13,
["client_tick_end"]=12,
["command_suggestion"]=14,
["configuration_acknowledged"]=15,
["container_button_click"]=16,
["container_click"]=17,
["container_close"]=18,
["container_slot_state_changed"]=19,
["cookie_response"]=20,
["custom_click_action"]=65,
["custom_payload"]=21,
["debug_sample_subscription"]=22,
["edit_book"]=23,
["entity_tag_query"]=24,
["interact"]=25,
["jigsaw_generate"]=26,
["keep_alive"]=27,
["lock_difficulty"]=28,
["move_player_pos"]=29,
["move_player_pos_rot"]=30,
["move_player_rot"]=31,
["move_player_status_only"]=32,
["move_vehicle"]=33,
["paddle_boat"]=34,
["pick_item_from_block"]=35,
["pick_item_from_entity"]=36,
["ping_request"]=37,
["place_recipe"]=38,
["player_abilities"]=39,
["player_action"]=40,
["player_command"]=41,
["player_input"]=42,
["player_loaded"]=43,
["pong"]=44,
["recipe_book_change_settings"]=45,
["recipe_book_seen_recipe"]=46,
["rename_item"]=47,
["resource_pack"]=48,
["seen_advancements"]=49,
["select_trade"]=50,
["set_beacon"]=51,
["set_carried_item"]=52,
["set_command_block"]=53,
["set_command_minecart"]=54,
["set_creative_mode_slot"]=55,
["set_jigsaw_block"]=56,
["set_structure_block"]=57,
["set_test_block"]=58,
["sign_update"]=59,
["swing"]=60,
["teleport_to_entity"]=61,
["test_instance_block_action"]=62,
["use_item"]=64,
["use_item_on"]=63,
},
},
["status"]={
["clientbound"]={
["pong_response"]=1,
["status_response"]=0,
},
["serverbound"]={
["ping_request"]=1,
["status_request"]=0,
},
},
}