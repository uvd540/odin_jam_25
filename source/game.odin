package game

//
// TODO: Obstacles
// TODO: Level complete
// TODO: Multiple levels
// TODO: Rendering improvements
// TODO: Give name to each bird
// 

import "core:c"
import "core:fmt"
// import "core:log"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

game_width :: 800
game_height :: 800

run: bool

Game_Mode :: enum {
	START,
	EDIT,
	PLAY,
	GAMEOVER,
}

game_mode := Game_Mode.PLAY

// :birds
num_birds :: 100
Bird :: struct {
	position:       [2]f32,
	velocity:       [2]f32,
	delta_velocity: [2]f32,
}
birds: #soa[dynamic]Bird
bird_dest_rect := rl.Rectangle{0, 0, 16, 16}

//
// ;textures
// 
spritesheet_texture: rl.Texture
bird_src_rect :: rl.Rectangle{0, 0, 16, 16}
music_src_rect :: rl.Rectangle{16, 0, 16, 16}

// :config
config_max_speed :: 100
config_separation := true
config_alignment := true
config_cohesion := true
config_mouse_tracking := true
config_protected_distance: f32 = 20.0
config_visible_distance: f32 = 100.0
config_separation_factor: f32 = 0.04
config_alignment_factor: f32 = 0.002
config_cohesion_factor: f32 = 0.002
config_mouse_tracking_factor: f32 = 1
config_drag_factor: f32 = 0.1

//
// ;player
// 
whistling_factor :: 10
whistling := false
current_influence: f32
influence_color: rl.Color

// 
// :level
// 
Target :: struct {
	location:        rl.Rectangle,
	number_required: u8,
	number_current:  u8,
	pct_complete:    f32,
}

Level :: struct {
	start_location: rl.Rectangle,
	targets:        []Target,
	max_influence:  f32,
	polygon:        [][2]f32,
}

active_level: ^Level

level_1 := Level {
	start_location = rl.Rectangle{100, 100, 50, 50},
	targets        = []Target {
		{location = rl.Rectangle{500, 500, 50, 50}, number_required = 20},
		{location = rl.Rectangle{600, 100, 50, 50}, number_required = 20},
	},
	max_influence  = 100,
	polygon        = {
		{87, 86},
		{165, 84},
		{242, 78},
		{341, 103},
		{445, 101},
		{508, 83},
		{578, 101},
		{597, 95},
		{621, 95},
		{655, 90},
		{665, 116},
		{662, 139},
		{652, 169},
		{615, 181},
		{592, 242},
		{575, 296},
		{591, 552},
		{479, 574},
		{342, 363},
		{279, 287},
		{239, 235},
		{123, 215},
		{92, 166},
	},
}

editor_level_polygon: [dynamic][2]f32
selected_node_index: int = -1
node_radius :: 5

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Bird Calls")

	// log.info("loading textures...")

	// Anything in `assets` folder is available to load.
	spritesheet_texture = rl.LoadTexture("assets/spritesheet.png")
	// log.info("done loading textures")

	editor_level_polygon = make([dynamic][2]f32, 0, 50)

	// log.info("loading level...")
	active_level = &level_1
	// log.info("done loading level")

	birds_init()
	level_reset()
}

birds_init :: proc() {
	birds = make(#soa[dynamic]Bird, num_birds)
	for &bird in birds {
		bird.velocity = {0, 0}
		bird.delta_velocity = {0, 0}
		bird.position.x =
			(rand.float32() * (active_level.start_location.width - 16)) +
			active_level.start_location.x +
			8
		bird.position.y =
			(rand.float32() * (active_level.start_location.height - 16)) +
			active_level.start_location.y +
			8
	}
}

level_reset :: proc() {
	current_influence = active_level.max_influence
	for &target in active_level.targets {
		target.number_current = 0
		target.pct_complete = 0
	}
}

update :: proc() {
	//
	// ;update
	// 
	mouse_position := rl.GetMousePosition()
	if rl.IsKeyPressed(.F2) {
		#partial switch game_mode {
		case .PLAY:
			game_mode = .EDIT
		case .EDIT:
			game_mode = .PLAY
		}
	}
	#partial switch game_mode {
	case .PLAY:
		{
			//
			// ;user-input
			// 
			if rl.IsKeyPressed(.R) {
				birds_init()
				level_reset()
			}
			whistling = rl.IsMouseButtonDown(.LEFT)
			dt := rl.GetFrameTime()
			game_update(mouse_position, dt)
		}
	case .EDIT:
		{
			editor_update()
		}
	}
	//
	// ;draw
	// 
	rl.BeginDrawing()
	rl.DrawFPS(0, 0)
	rl.DrawRectangleRec(active_level.start_location, rl.DARKGRAY)
	for target in active_level.targets {
		color_g := u8(target.pct_complete * 255)
		color_r := u8((1 - target.pct_complete) * 128)
		rl.DrawRectangleRec(target.location, {color_r, color_g, color_r, 255})
		rl.DrawText(
			fmt.ctprintf("%d", target.number_required - target.number_current),
			i32(target.location.x) + 4,
			i32(target.location.y) + 4,
			32,
			rl.WHITE,
		)
	}
	#partial switch game_mode {
	case .PLAY:
		{
			rl.ClearBackground({0, 120, 153, 255})
			draw_polygon(active_level.polygon[:])
			for &bird in birds {
				bird_dest_rect.x = bird.position.x
				bird_dest_rect.y = bird.position.y
				rl.DrawTexturePro(
					spritesheet_texture,
					bird_src_rect,
					bird_dest_rect,
					{8, 8},
					0,
					rl.WHITE,
				)
				influence_color = whistling ? rl.GREEN : rl.GRAY
				rl.DrawCircleLinesV(
					rl.GetMousePosition(),
					config_visible_distance,
					influence_color,
				)
				if whistling {
					music_dest_rect := rl.Rectangle {
						mouse_position.x + 16,
						mouse_position.y - 16,
						32,
						32,
					}
					rl.DrawTexturePro(
						spritesheet_texture,
						music_src_rect,
						music_dest_rect,
						{8, 8},
						0,
						rl.WHITE,
					)
				}
			}
			//
			// :ui
			//
			rl.DrawText(fmt.ctprintf("Wandering Birds: %d", len(birds)), 100, 20, 14, rl.WHITE)
			// ;ui-influence
			influence_rec := rl.Rectangle{200, 680, 880, 20}
			rl.DrawRectangleRoundedLinesEx(influence_rec, 10, 10, 4, rl.WHITE)
			influence_rec.width *= current_influence / active_level.max_influence
			// log.info("current influence: ", current_influence)
			// log.info("max influence: ", active_level.max_influence)
			rl.DrawRectangleRounded(influence_rec, 10, 10, rl.GREEN)
		}
	case .EDIT:
		{
			rl.ClearBackground(rl.BROWN)
			rl.DrawCircleV(rl.GetMousePosition(), 2, rl.YELLOW)
			num_level_points := len(editor_level_polygon)
			for i in 0 ..< num_level_points {
				rl.DrawCircleV(editor_level_polygon[i], 5, rl.RED)
				if num_level_points > 1 {
					if i == 0 {
						rl.DrawLineV(
							editor_level_polygon[i],
							editor_level_polygon[num_level_points - 1],
							rl.WHITE,
						)
						continue
					}
					rl.DrawLineV(editor_level_polygon[i], editor_level_polygon[i - 1], rl.WHITE)
				}
			}
		}
	}
	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

game_update :: proc(mouse_position: [2]f32, dt: f32) {
	if whistling {
		current_influence -= whistling_factor * dt
	}
	num_birds := len(birds)
	for i in 0 ..< num_birds {
		separation_velocity: [2]f32
		num_neighbors_visible_range: f32
		alignment_velocity: [2]f32
		sum_velocity_visible_range: [2]f32
		cohesion_velocity: [2]f32
		sum_mass_times_position_visible_rangle: [2]f32
		mouse_tracking_velocity: [2]f32
		for j in 0 ..< num_birds {
			if i == j {continue} 	// same bird
			distance := linalg.distance(birds[i].position, birds[j].position)
			// separation
			if config_separation && distance <= config_protected_distance {
				separation_velocity +=
					(birds[i].position - birds[j].position) / distance * config_separation_factor
			}
			if distance <= config_visible_distance {
				num_neighbors_visible_range += 1
				// aligment
				if config_alignment {
					sum_velocity_visible_range += birds[j].velocity
				}
				// cohesion
				if config_cohesion {
					sum_mass_times_position_visible_rangle += birds[j].position
				}
			}
		}
		if num_neighbors_visible_range > 0 {
			// alignment
			if config_alignment {
				alignment_velocity =
					sum_velocity_visible_range /
					num_neighbors_visible_range *
					config_alignment_factor
			}
			// cohesion
			if config_cohesion {
				cohesion_velocity +=
					((sum_mass_times_position_visible_rangle / num_neighbors_visible_range) -
						birds[i].position) *
					config_cohesion_factor
			}
		}
		// mouse tracking
		if config_mouse_tracking && whistling {
			distance_to_mouse := linalg.distance(birds[i].position, mouse_position)
			if distance_to_mouse <= config_visible_distance {
				mouse_tracking_velocity =
					(mouse_position - birds[i].position) /
					distance_to_mouse *
					config_mouse_tracking_factor
			}
		}
		// add velocity components
		birds[i].delta_velocity =
			separation_velocity + alignment_velocity + cohesion_velocity + mouse_tracking_velocity
	}
	for i := 0; i < len(birds); {
		if birds[i].delta_velocity == {0, 0} {
			// drag
			birds[i].velocity = rl.Vector2MoveTowards(
				birds[i].velocity,
				{0, 0},
				config_drag_factor,
			)
		} else {
			birds[i].velocity += birds[i].delta_velocity
		}
		// clamp velocity
		birds_speed := linalg.length(birds[i].velocity)
		if birds_speed > config_max_speed {
			birds[i].velocity *= config_max_speed / birds_speed
		}
		birds[i].position += birds[i].velocity * dt
		// check if birds[i] at target
		remove := false
		for &target in active_level.targets {
			if target.pct_complete < 1 {
				if rl.CheckCollisionPointRec(birds[i].position, target.location) {
					target.number_current += 1
					remove = true
					target.pct_complete = f32(target.number_current) / f32(target.number_required)
				}
			}
		}
		if remove {
			unordered_remove_soa(&birds, i)
			continue
		}
		// wrap
		// TODO: remove for actual game
		if birds[i].position.x < 0 {
			birds[i].position.x = 1280
		}
		if birds[i].position.x > 1280 {
			birds[i].position.x = 0
		}
		if birds[i].position.y < 0 {
			birds[i].position.y = 720
		}
		if birds[i].position.y > 720 {
			birds[i].position.y = 0
		}
		i += 1
	}
}

editor_update :: proc() {
	mouse_position := rl.GetMousePosition()
	if selected_node_index >= 0 {
		editor_level_polygon[selected_node_index] = mouse_position
		if rl.IsMouseButtonPressed(.LEFT) {
			selected_node_index = -1
		}
	} else if rl.IsMouseButtonPressed(.LEFT) {
		for &point, i in editor_level_polygon {
			if rl.CheckCollisionCircles(mouse_position, 5, point, 5) {
				selected_node_index = i
				return
			}
		}
		append(&editor_level_polygon, mouse_position)
	}
}

draw_polygon :: proc(polygon: [][2]f32) {
	num_points := len(polygon)
	for i in 0 ..< num_points {
		rl.DrawCircleV(polygon[i], 5, rl.RED)
		if num_points > 1 {
			if i == 0 {
				rl.DrawLineV(polygon[i], polygon[num_points - 1], rl.WHITE)
				continue
			}
			rl.DrawLineV(polygon[i], polygon[i - 1], rl.WHITE)
		}
	}
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	// log.info(editor_level_polygon)
	delete(birds)
	delete(editor_level_polygon)
	// delete(level_1.targets)
	rl.UnloadTexture(spritesheet_texture)
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}

