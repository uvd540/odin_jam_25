package game

//
// TODO: Obstacles
// TODO: Birds are trapped at start
// TODO: Level complete
// TODO: Multiple levels
// TODO: Rendering improvements
// TODO: Give name to each bird
// 

import "core:c"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

game_width :: 1280
game_height :: 720

run: bool

Game_Mode :: enum {
	START,
	PLAY,
	GAMEOVER,
}

game_mode := Game_Mode.PLAY
play_caged := true

// :birds
Bird :: struct {
	position:       [2]f32,
	velocity:       [2]f32,
	delta_velocity: [2]f32,
}
birds: #soa[dynamic]Bird

//
// ;textures
// 
spritesheet_texture: rl.Texture

bird_src_rect :: rl.Rectangle{0, 0, 16, 16}
music_src_rect :: rl.Rectangle{16, 0, 16, 16}
tree_src_rect :: rl.Rectangle{32, 0, 16, 16}
cage_src_rect :: rl.Rectangle{48, 0, 16, 16}
smog_src_rect :: rl.Rectangle{64, 0, 16, 16}
airplane_src_rect :: rl.Rectangle{80, 0, 16, 16}

bird_dest_rect := rl.Rectangle{0, 0, 16, 16}
music_dest_rect := rl.Rectangle{0, 0, 32, 32}
cage_dest_rect := rl.Rectangle{0, 0, 48, 48}

// 
// ;config
// 
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
current_level: u8 = 0
influence_color: rl.Color

// 
// ;level
// 
source: rl.Rectangle
targets: [dynamic]Target
obstacles: [dynamic]Obstacle
influence_start: f32
influence_current: f32
smog_timer: Timer
level_num_birds: u8

Target :: struct {
	location:        rl.Rectangle,
	number_required: u8,
	number_current:  u8,
	pct_complete:    f32,
}

ObstacleType :: enum {
	Smog,
	Airplane,
}

Obstacle :: struct {
	type:             ObstacleType,
	position:         [2]f32,
	velocity:         [2]f32,
	src_rect:         rl.Rectangle,
	avoidance_factor: f32,
	scale:            f32,
}

obstacle_create :: proc(obstacle_type: ObstacleType) -> Obstacle {
	obstacle: Obstacle
	obstacle.type = obstacle_type
	switch obstacle_type {
	case .Smog:
		{
			obstacle.src_rect = smog_src_rect
			obstacle.avoidance_factor = 0.01
			obstacle.scale = 3
		}
	case .Airplane:
		{
			obstacle.src_rect = airplane_src_rect
			obstacle.avoidance_factor = 0.1
			obstacle.scale = 4
		}
	}
	return obstacle
}

obstacle_update :: proc(obstacle: ^Obstacle, dt: f32) {
	obstacle.position += obstacle.velocity * dt
	if obstacle.type == .Smog {
		wrap(&obstacle.position)
	}
}

obstacle_draw :: proc(obstacle: Obstacle) {
	dest_rect := rl.Rectangle {
		obstacle.position.x,
		obstacle.position.y,
		obstacle.scale * 16,
		obstacle.scale * 16,
	}
	rl.DrawTexturePro(spritesheet_texture, obstacle.src_rect, dest_rect, {0, 0}, 0, rl.WHITE)
}

bounce :: proc(position: [2]f32, velocity: ^[2]f32) {
	if position.x < 0 {
		velocity.x *= -1
	}
	if position.x > game_width {
		velocity.x *= -1
	}
	if position.y < 0 {
		velocity.y *= -1
	}
	if position.y > game_height {
		velocity.y *= -1
	}
}

wrap :: proc(position: ^[2]f32) {
	if position.x < 0 {
		position.x = game_width
	}
	if position.x > game_width {
		position.x = 0
	}
	if position.y < 0 {
		position.y = game_height
	}
	if position.y > game_height {
		position.y = 0
	}
}

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(game_width, game_height, "Bird Calls")

	spritesheet_texture = rl.LoadTexture("assets/spritesheet.png")
	birds = make(#soa[dynamic]Bird, 0, 100)
	obstacles = make([dynamic]Obstacle, 0, 25)
	targets = make([dynamic]Target, 0, 5)

	level_goto(0)
}

level_goto :: proc(level_num: u8) {
	clear(&birds)
	clear(&obstacles)
	clear(&targets)
	switch level_num {
	case 0:
		{
			append(
				&targets,
				Target{location = rl.Rectangle{500, 500, 48, 48}, number_required = 20},
				Target{location = rl.Rectangle{600, 100, 48, 48}, number_required = 20},
			)
			source = {50, 50, 48, 48}
			level_num_birds = 100
			influence_start = 100
			influence_current = influence_start
		}
	}
	birds_reset()
}

birds_reset :: proc() {
	for _ in 0 ..< level_num_birds {
		bird := Bird {
			velocity       = {0, 0},
			delta_velocity = {0, 0},
			position       = {
				(rand.float32() * (source.width - 16)) + source.x + 8,
				(rand.float32() * (source.height - 16)) + source.y + 8,
			},
		}
		append_soa(&birds, bird)
	}
}

update :: proc() {
	//
	// ;update
	// 
	mouse_position := rl.GetMousePosition()
	#partial switch game_mode {
	case .PLAY:
		{
			//
			// ;user-input
			// 
			if rl.IsKeyPressed(.R) {
				level_goto(current_level)
			}
			whistling = rl.IsMouseButtonDown(.LEFT)
			dt := rl.GetFrameTime()
			game_update(mouse_position, dt)
		}
	}
	//
	// ;draw
	// 
	rl.BeginDrawing()
	rl.DrawFPS(0, 0)
	rl.DrawTexturePro(spritesheet_texture, cage_src_rect, source, {0, 0}, 0, rl.WHITE)
	for target in targets {
		// log.info("drawing target: ", target)
		color_g := u8(target.pct_complete * 255)
		color_r := u8((1 - target.pct_complete) * 128)
		rl.DrawTexturePro(spritesheet_texture, tree_src_rect, target.location, {0, 0}, 0, rl.WHITE)
		rl.DrawText(
			fmt.ctprintf("%d", target.number_required - target.number_current),
			i32(target.location.x) + 4,
			i32(target.location.y) + 4,
			32,
			{color_r, color_g, 128, 128},
		)
	}
	#partial switch game_mode {
	case .PLAY:
		{
			rl.ClearBackground(rl.SKYBLUE)
			//
			// ;draw;ui
			//
			rl.DrawText(fmt.ctprintf("Wandering Birds: %d", len(birds)), 100, 20, 14, rl.WHITE)
			influence_rec := rl.Rectangle{200, 680, 880, 20}
			rl.DrawRectangleRoundedLinesEx(influence_rec, 10, 10, 4, rl.WHITE)
			influence_rec.width *= influence_current / influence_start
			rl.DrawRectangleRounded(influence_rec, 10, 10, rl.GREEN)
			// 
			// ;draw;birds
			// 
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
					music_dest_rect.x = mouse_position.x
					music_dest_rect.y = mouse_position.y
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
		}
	}
	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

game_update :: proc(mouse_position: [2]f32, dt: f32) {
	if whistling {
		influence_current -= whistling_factor * dt
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
		// check collisions with target
		remove := false
		for &target in targets {
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
		bounce(birds[i].position, &birds[i].velocity)
		i += 1
	}
	log.info("current targets: ", targets)
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
	delete(birds)
	delete(obstacles)
	delete(targets)
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

