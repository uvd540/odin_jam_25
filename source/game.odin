package game

import rl "vendor:raylib"
import "core:log"
// import "core:fmt"
import "core:c"
import "core:math/rand"
import "core:math/linalg"

run: bool

// TODO: Mouse position does not work well with camera
// camera: rl.Camera2D

// :birds
num_birds ::  100
Bird ::       struct {
	position: [2]f32,
	velocity: [2]f32,
	// temporary variables
	delta_velocity: [2]f32,
}
birds:        #soa[dynamic]Bird
bird_texture: rl.Texture
bird_src_rect :: rl.Rectangle{0, 0, 16, 16}
bird_dest_rect := rl.Rectangle{0, 0, 16, 16}

// :config
config_max_speed :: 100
config_separation := true
config_alignment  := true
config_cohesion   := true
config_mouse_tracking := true
config_protected_distance : f32 = 20.0
config_visible_distance   : f32 = 100.0
config_separation_factor  : f32 = 0.01
config_alignment_factor   : f32 = 0.005
config_cohesion_factor    : f32 = 0.005
config_mouse_tracking_factor :f32 = 1
config_drag_factor        : f32 = 0.1

debug_mode := true

// :level
start_location :: rl.Rectangle{100, 100, 50, 50}

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Bird Pathways")

	// camera.zoom = 2

	// Anything in `assets` folder is available to load.
	bird_texture = rl.LoadTexture("assets/bird.png")

	birds = make(#soa[dynamic]Bird, num_birds)
	birds_disperse()
}

birds_disperse :: proc() {
	for &bird in birds {
		bird.position.x = (rand.float32()*(start_location.width-16))  + start_location.x + 8
		bird.position.y = (rand.float32()*(start_location.height-16)) + start_location.y + 8
	}
}

update :: proc() {
	dt := rl.GetFrameTime()
	birds_update(dt)
	rl.BeginDrawing()
	rl.ClearBackground({0, 120, 153, 255})
	rl.DrawFPS(0, 0)
	// rl.BeginMode2D(camera)
	{
		rl.DrawRectangleRec(start_location, rl.DARKGRAY)
		// TODO performance: Consider using &bird
		for bird in birds {
			bird_dest_rect.x = bird.position.x
			bird_dest_rect.y = bird.position.y
			rl.DrawTexturePro(bird_texture, bird_src_rect, bird_dest_rect, {8, 8}, 0, rl.WHITE)
		}
		if debug_mode {
			rl.DrawCircleV(birds[0].position, config_protected_distance, {128, 128, 0, 128})
			rl.DrawCircleV(birds[0].position, config_visible_distance, {0, 128, 128, 128})
			log.info(birds[0].velocity)
		}
	}
	// rl.EndMode2D()
	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

birds_update :: proc(dt: f32) {
	num_birds := len(birds)
	for i in 0..<num_birds {
		separation_velocity: [2]f32
		cohesion_velocity: [2]f32
		mouse_tracking_velocity: [2]f32
		num_neighbors_visible_range:f32 = 0
		alignment_velocity: [2]f32
		sum_velocity_visible_range: [2]f32
		sum_mass_times_position_visible_rangle: [2]f32
		for j in 0..<num_birds {
			if i == j { continue } // same bird
			distance := linalg.distance(birds[i].position, birds[j].position)
			// separation
			if config_separation && distance <= config_protected_distance {
				separation_velocity += (birds[i].position - birds[j].position) / distance * config_separation_factor
			}
			if distance <= config_visible_distance {
				num_neighbors_visible_range += 1
				// alignment
				if config_alignment {
					sum_velocity_visible_range += birds[j].velocity
				}
				if config_cohesion {
					sum_mass_times_position_visible_rangle += birds[j].position
				}
			}
		}
		if num_neighbors_visible_range > 0 {
			if config_alignment {
				alignment_velocity = sum_velocity_visible_range / num_neighbors_visible_range * config_alignment_factor
			}
			if config_cohesion {
				cohesion_velocity += ((sum_mass_times_position_visible_rangle / num_neighbors_visible_range) - birds[i].position) * config_cohesion_factor
			}
		}
		// mouse tracking
		if config_mouse_tracking {
			mouse_position := rl.GetMousePosition()
			distance_to_mouse := linalg.distance(birds[i].position, mouse_position)
			if distance_to_mouse <= config_visible_distance {
				mouse_tracking_velocity = (mouse_position - birds[i].position) / distance_to_mouse * config_mouse_tracking_factor
			}
		}
		birds[i].delta_velocity = separation_velocity + alignment_velocity + cohesion_velocity + mouse_tracking_velocity
	}
	for &bird in birds {
		if bird.delta_velocity == {0, 0} {
			// drag
			bird.velocity = rl.Vector2MoveTowards(bird.velocity, {0, 0}, config_drag_factor)
		} else {
			bird.velocity += bird.delta_velocity
		}
		// clamp velocity
		bird_speed := linalg.length(bird.velocity)
	if bird_speed > config_max_speed {
			bird.velocity *= config_max_speed / bird_speed
		}
		bird.position += bird.velocity * dt
		// wrap
		// TODO: remove for actual game
		if bird.position.x < 0 {
			bird.position.x = 1280
		}
		if bird.position.x > 1280 {
			bird.position.x = 0
		}
		if bird.position.y < 0 {
			bird.position.y = 720
		}
		if bird.position.y > 720 {
			bird.position.y = 0
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
	rl.UnloadTexture(bird_texture)
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
