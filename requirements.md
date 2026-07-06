# Game Design Requirements: Open Mic Night!

## 1. Project Overview
* **Title:** Open Mic Night!
* **Engine:** Godot
* **Genre:** 2D Pixel-Art Side-Scrolling Beat-'em-Up
* **Target Platform:** Mobile (Landscape orientation)
* **Visual Style:** Old-school pixelated graphics

## 2. Core Gameplay Loop
The player selects a comedian character and walks down a scrolling street, dealing with random hecklers. Periodically, a venue appears. The player can enter the venue to fight rival comedians. The game is infinite, with difficulty ramping up in venues until the player eventually runs out of health and lives.

### 2.1 The Street Phase (Side-Scrolling)
* **Environment:** A continuously scrolling pixelated street.
* **NPCs (Hecklers/Pedestrians):**
  * Random people appear on the street.
  * Some will yell insults (e.g., "Hey, you suck!").
  * **Behavior:** They may or may not initiate a fight, but the player can always attack them first.
  * **Reward:** Defeating street NPCs awards score points.

### 2.2 The Venue Phase (Static Room)
* **Entry:** As the street scrolls, venues appear. Every venue exterior image will have a door located exactly at the **bottom center**. If the player walks up to the door and presses up/interact, they transition to the venue interior.
* **Interior:** A generic, silly pixel-art bar interior. No complex collision meshes are needed—just a fighting stage.
* **Combatants:** Upon entering, the player must fight other comedian characters pulled from the global character list (excluding the player's chosen character).
  * **Behavior:** Comedians in venues are *always* highly aggressive and will attack immediately.
* **Difficulty Scaling:**
  * Venue 1: 1 Comedian to fight.
  * Venue 2: 2 Comedians to fight.
  * Venue 3: 3 Comedians to fight, etc.

### 2.3 Boss Encounters (Every 5th Venue)
* Every 5th venue entered is a Boss Stage.
* **Mechanics:** The Boss cannot be fought or damaged.
* **Gameplay:** The Boss will throw projectiles (e.g., beer bottles) at the player. The player must use the "Duck" mechanic and movement to survive the barrage for a set amount of time or until the sequence ends to clear the venue.

## 3. Character System & Asset Architecture

To streamline development and make it easy to add new comedians without animating entirely new sprite sheets, the game uses a modular character system.

* **Bodies:** Two generic, fully animated pixel-art body types (Male and Female).
  * Animations needed: Idle, Walk, Punch, Kick, Duck, Hit Reaction, Defeated.
* **Heads:** Individual comedian heads that are pinned/socketed to the neck position of the generic bodies.
* **Configuration (JSON):**
  * Characters are generated at runtime by reading a `characters.json` file.
  * JSON structure should define: `CharacterName`, `HeadSpritePath`, `BodyType` (M/F).
* **Venue Configuration (JSON):**
  * Venues are also loaded dynamically via a `venues.json` file.
  * JSON structure should define: `VenueName`, `ExteriorSpritePath`, `InteriorSpritePath`.

## 4. Player Controls & UI

### 4.1 Mobile Controls
Since this is mobile landscape, implement virtual on-screen controls:
* **Left Side:** D-Pad or Virtual Joystick (Left, Right, Up for entering doors, Down for ducking).
* **Right Side:** Action Buttons (Punch, Kick, Jump - optional depending on combo needs).

### 4.2 HUD (Heads Up Display)
* **Health Bar:** Depletes when hit.
* **Lives:** Standard 3-life system (or configurable).
* **Score:** Accumulated by beating up hecklers and rival comedians.

## 5. Menus & Navigation

The game requires the following screens:
1. **Main Menu:**
   * **Play:** Proceeds to character selection, then starts the game.
   * **Settings:** Sliders/toggles for Music Volume and SFX Volume.
   * **Scoreboard:** Local high scores (persist data locally).
   * **About:** Credits and silly blurb about the game.
2. **Character Select Screen:**
   * Paged grid or carousel of available comedian heads (parsed from JSON).

## 6. Technical Notes for Development (Godot)

* **UI Scaling:** Ensure the 2D stretch mode is set to `viewport` or `canvas_items` in project settings to maintain crisp pixel art on various mobile screen resolutions.
* **Global State Management:** You will need a global manager to keep track of the current Score, Lives, selected Character ID, and current Venue Difficulty Level. Implement this using a Singleton. Note: Make sure to register this script in the Project Settings under the **Globals** tab (this is where Autoloads are managed now).
* **Hitboxes/Hurtboxes:** Keep the collision polygons simple (rectangles) to ensure responsive beat-'em-up combat feel.
