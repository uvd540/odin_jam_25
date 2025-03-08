package game

import rl "vendor:raylib"
import "core:log"
// import "core:fmt"
import "core:c"
import "core:math/rand"
import "core:math/linalg"

run: bool

camera: rl.Camera2D
// -- birds --
num_birds ::  25
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
// -- birds --

// -- config --
config_separation := true
config_alignment  := false
config_cohesion   := false
config_protected_distance : f32 = 10.0
config_visible_distance   : f32 = 25.0
config_separation_factor  : f32 = 0.1
config_alignment_factor   : f32 = 0.01
config_cohesion_factor    : f32 = 0.01
config_mouse_tracking_factor :f32 = 0.1
config_drag_factor        : f32 = 0.1
// -- config --

debug_mode := true

// -- level --
start_location :: rl.Rectangle{100, 100, 50, 50}
// -- level --

init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Bird Pathways")

	camera.zoom = 2

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
			log.info(birds[0].delta_velocity)
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
		alignment_velocity: [2]f32
		cohesion_velocity: [2]f32
		mouse_tracking_velocity: [2]f32
		for j in 0..<num_birds {
			if i == j { continue } // same bird
			distance := linalg.distance(birds[i].position, birds[j].position)
			// separation
			if config_separation && distance <= config_protected_distance {
				separation_velocity += (birds[i].position - birds[j].position) / distance * config_separation_factor
			}
		}
		// mouse tracking
		mouse_position := rl.GetMousePosition()
		distance_to_mouse := linalg.distance(birds[i].position, mouse_position)
		log.info(distance_to_mouse)
		if distance_to_mouse <= config_visible_distance {
			log.info("tracking mouse")
			mouse_tracking_velocity = (mouse_position - birds[i].position) / distance_to_mouse * config_mouse_tracking_factor
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
		bird.position += bird.velocity * dt
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
