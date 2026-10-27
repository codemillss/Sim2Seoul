CREATE TABLE `multiplayer_players` (
	`id` text PRIMARY KEY NOT NULL,
	`room_id` text NOT NULL,
	`user_key` text NOT NULL,
	`token_hash` text NOT NULL,
	`avatar_json` text NOT NULL,
	`sequence` integer DEFAULT 0 NOT NULL,
	`x` real NOT NULL,
	`y` real NOT NULL,
	`z` real NOT NULL,
	`yaw` real DEFAULT 0 NOT NULL,
	`motion` text DEFAULT 'idle' NOT NULL,
	`last_action_ms` integer NOT NULL,
	`last_position_ms` integer NOT NULL,
	`last_seen_ms` integer NOT NULL,
	FOREIGN KEY (`room_id`) REFERENCES `multiplayer_rooms`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `multiplayer_players_room_presence` ON `multiplayer_players` (`room_id`,`last_seen_ms`);--> statement-breakpoint
CREATE UNIQUE INDEX `multiplayer_players_room_id_user_key_unique` ON `multiplayer_players` (`room_id`,`user_key`);--> statement-breakpoint
CREATE TABLE `multiplayer_rate_limits` (
	`key` text PRIMARY KEY NOT NULL,
	`last_ms` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `multiplayer_rooms` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_key` text NOT NULL,
	`invite_hash` text NOT NULL,
	`build_id` text NOT NULL,
	`spawn_x` real NOT NULL,
	`spawn_y` real NOT NULL,
	`spawn_z` real NOT NULL,
	`created_ms` integer NOT NULL,
	`expires_ms` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `multiplayer_rooms_owner_expiry` ON `multiplayer_rooms` (`owner_key`,`expires_ms`);--> statement-breakpoint
CREATE INDEX `multiplayer_rooms_expiry` ON `multiplayer_rooms` (`expires_ms`);