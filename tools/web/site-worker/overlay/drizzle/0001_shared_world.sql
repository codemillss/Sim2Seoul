CREATE TABLE `multiplayer_world_actions` (
	`room_id` text NOT NULL,
	`player_id` text NOT NULL,
	`request_id` text NOT NULL,
	`request_hash` text NOT NULL,
	`result_json` text NOT NULL,
	`created_ms` integer NOT NULL,
	PRIMARY KEY(`room_id`, `player_id`, `request_id`),
	FOREIGN KEY (`room_id`) REFERENCES `multiplayer_worlds`(`room_id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `multiplayer_worlds` (
	`room_id` text PRIMARY KEY NOT NULL,
	`host_id` text NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`state_json` text NOT NULL,
	`updated_ms` integer NOT NULL,
	FOREIGN KEY (`room_id`) REFERENCES `multiplayer_rooms`(`id`) ON UPDATE no action ON DELETE cascade
);
