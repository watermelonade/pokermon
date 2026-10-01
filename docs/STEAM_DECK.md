# Shipping on Steam and the Steam Deck

What it takes to put A Friend in Need on Steam with the Deck as the main
target, and what this repo already does about it. Each point is marked:

- **[verified]**: checked in this repo, with how.
- **[docs]**: from Valve's or Godot's documentation, as remembered when this was
  written (2026-10). Steamworks pages move and get renamed: check the
  current page before relying on one of these.
- **[todo]**: not built yet.

Building is in README.md "Building". In short: `scripts/export.sh` writes
`build/linux/` and `build/windows/`, and CI (`.github/workflows/build.yml`)
does the same on pushes to main and on tags.

## 1. The builds

| | Linux x86_64 (primary) | Windows x86_64 (fallback) |
| --- | --- | --- |
| Files | `AFriendInNeed.x86_64` + `AFriendInNeed.pck` | `AFriendInNeed.exe` + `AFriendInNeed.pck` |
| Size (2026-10-01) | 71 MB + 61 KB | 105 MB + 61 KB |
| Runs on | the Deck natively, desktop Linux | Windows; the Deck through Proton |
| Checked | **[verified]** exported and ran under Xvfb (Mesa llvmpipe, OpenGL 3.3 driver): the table rendered, filled the 1280x800 screen at x2 and quit cleanly after the scripted screenshot | **[verified]** exports; a PE32+ x86-64 GUI executable with the game's name in its version info. **Not run**: no Windows or Wine here |

Almost all of the size is the engine: the game itself (the .pck) is 61 KB
today. The release template is Godot's official build, unmodified.

- **[verified]** The Linux binary needs glibc 2.28 or newer and nothing
  else outside libc (`ldd`: librt, libpthread, libdl, libm, libc; graphics
  and audio libraries are loaded at run time). SteamOS 3 is far newer.
- **[verified]** `tests/` and `tools/` are not in the .pck (its file table
  lists only `src/`, `scenes/`, the icon and Godot's own metadata).
- **[docs]** When an app has both a Linux and a Windows depot, the Deck
  installs and runs the Linux one. A player can force Proton per game
  (Properties > Compatibility), which then downloads the Windows depot. Test
  that path too, since Valve may: the Windows build under Proton must also
  work.
- **[docs]** Steam Linux Runtime: Steamworks lets an app run its Linux
  build inside a "Steam Linux Runtime" container. Godot 4 binaries work with
  the newer one (3.0, "sniper", glibc 2.31) and also on the host. If the
  partner site offers the choice, pick sniper; otherwise the default is fine
  for a Godot game, which links nothing Steam would have to provide.

## 2. Controller-only play and the back buttons

Deck Verified needs the whole game playable with the Deck's controls, with
no mouse, keyboard or touchscreen required. **[verified]** Today the table
plays entirely from input actions that each have a button on a plain
Xbox-style pad (D-pad/stick, A, B, X, Y, LB/RB, LT/RT, Start, Select;
`tests/test_controls.gd` checks every action has one, and
`tests/pad_check.tscn` signals at the real table with pretend pad events).
The back buttons are an extra, not needed. **[todo]** Every new
screen (overworld, menus, the Binder) must keep that up; text entry, if any
ever appears, must open Steam's on-screen keyboard
(`ISteamUtils::ShowGamepadTextInput` / `ShowFloatingGamepadTextInput`, via
GodotSteam).

### Why the back buttons need care

The four signals are on X, Y, LT and RT (the Deck labels its triggers L2
and R2), which any controller has and Steam's default Gamepad template
passes through, so a Deck can signal out of the box. They are also on
L4/R4/L5/R5, which the game reads as `JOY_BUTTON_PADDLE1-4` (button indices
16-19 in project.godot): a gesture under the table is what a signal is, so
the back buttons are the nicer home on a Deck. The rest of this section is
about making those work too.

**[docs]** On the Deck, Steam Input sits between the hardware and every
game. The game does not see the Deck's controller; it sees a virtual Xbox-
style gamepad that Steam drives from a *controller configuration*. That
virtual pad has no paddle buttons, and Steam's default "Gamepad" template
leaves the back buttons unbound. So out of the box **pressing L4 sends the
game nothing**: the back buttons only reach the game if the configuration the
game ships with maps the back buttons to something it reads.
(With Steam Input turned off for the game, Godot's SDL-based joypad code
could read the Deck's paddles directly, but players can't be expected to do
that and Valve tests with the default configuration.)

There are two ways to ship that configuration. Start with A; move to B when
GodotSteam goes in.

### Option A (simple, no code): back buttons send the keys 1-4

The game already binds `signal_1`..`signal_4` to the keyboard keys 1-4 as
well as to the paddles, and Steam Input can send keyboard keys from any
button. So a default configuration that is the Gamepad template plus four
back-button bindings works with the current code. **[docs]** Steps:

1. In Steamworks: App Admin > Application > **Steam Input**. Opt the game in
   to Steam Input for every controller type (Xbox, PlayStation, Switch,
   generic, Steam Deck) and set the default to the Gamepad template for now.
   Publish.
2. On a Deck (or desktop Steam with a controller, in Big Picture), with an
   account that has access to the app, launch the game, open the controller
   configuration (Steam button > Controller Settings) and edit the layout:
   - L4 -> Keyboard `1`, R4 -> Keyboard `2`, L5 -> Keyboard `3`,
     R5 -> Keyboard `4`. Give each a label ("Touch nose", "Scratch ear",
     "Stack chips", "Tip hat") so the Deck's overlay shows what they do.
   - Leave everything else as the Gamepad template.
3. Export the layout (from the configurator: Export Layout). As a developer
   of the app you are offered to save it as the **official configuration**
   for the game. Do that.
4. Back in Steamworks > Steam Input, choose that configuration as the
   default for the Steam Deck (and for other controllers with back
   buttons/paddles if you like), and publish.
5. Check on a Deck: a fresh install, never touched the layout, back buttons
   signal at the table.

Drawbacks: Steam sends real key presses, so the game can't tell the signal
came from a controller (it doesn't need to today). Controllers without back
buttons use X, Y, LT and RT (what the radial menu in early notes was for).

### Option B (proper): Steam Input action sets through GodotSteam

The game declares *actions* ("Signal 1", "Confirm", ...) in an In-Game
Actions file, the player's configuration maps buttons to them, and the game
reads them with `Steam.getDigitalActionData()` and shows the right button
glyphs (`Steam.getGlyphPNGForActionOrigin()`), including for players who
rebind. **[docs]** Steps:

1. `steam/input/game_actions_YOUR_APP_ID.vdf` is a starting manifest with
   one action set, "Table", and actions named like the Godot input actions.
   Rename it with the real app ID.
2. Development: copy it to `<Steam>/controller_config/` on the test
   machine; Steam then offers those actions in the configurator.
3. Build the default configuration in the configurator (back buttons ->
   `signal_1`..`signal_4`), export it as the official configuration, and in
   Steamworks > Steam Input select "Custom configuration" using the action
   manifest (upload the .vdf there) and the official configuration. Publish.
4. In the game: `Steam.inputInit()`, get the action set and action handles,
   `activateActionSet()` at the table, and poll each frame, feeding the
   results into the same code the Godot actions drive. **[todo]**: needs
   GodotSteam (README "Next steps").

### Checking a real controller by hand

Not checkable here (no controller in the cloud sandbox). With an Xbox pad
(or any pad Steam shows as one) on Linux or Windows, and on a Deck with the
default layout:

1. The title, the overworld and every menu work with the D-pad, the stick,
   A, B and Start alone.
2. At the table: X, Y, LT, RT each send one signal (one bubble, one step of
   Heat under a watchful dealer), however slowly or quickly the trigger is
   pulled, and resting a finger on a trigger doesn't send a second one.
3. Hold LB and press a signal button: a fake (the code panel shows it).
   Check LB + LT is comfortable enough for a fake; if not, say so.
4. LB/RB step the raise size, Select opens the help card, Start skips the
   tutorial.
5. Rosie's signal prompts in lesson 3 name X and answer to it.
6. Unplug the pad mid-pull and plug it back in: the next pull still signals.

## 3. Screen and text

- **[verified]** The game opens a 1280x800 window and draws its 640x400
  base resolution at exactly x2 (integer scaling, nearest filtering, pixel
  snapping in project.godot); the Xvfb capture of the exported build filled
  the 1280x800 screen edge to edge. Under the Deck's gamescope compositor
  the window is the screen either way.
- **[docs]** Valve's guideline for legible text on the Deck: the smallest
  text should be at least 9 px tall (lowercase x-height) at 1280x800; their
  criteria phrase it as "readable at handheld distance".
- **[verified]** The smallest text in the game today is font size 8 (the
  raise-size hint and the signal list). Measured from the exported build's
  screenshot, its lowercase letters are 5 px tall at 640x400, so **10 px on
  the Deck**: just over that line. Don't go below 8 at base resolution.
  The default font is a smooth vector font, slightly blurry at 8 px; a real
  pixel font (sized to the 640x400 grid) would be crisper.
  **Not checked**: how it reads on a real Deck screen at arm's length.
- **[docs]** Glyphs: when the game shows buttons, they must match the Deck
  (Steam Deck or Xbox-style A/B/X/Y, LB/RB). The hints use the Xbox names
  (`src/input/pad_controls.gd`: X Y LT RT, LB/RB); the Deck's own labels
  for the bumpers and triggers are L1/R1 and L2/R2. With Option B, use
  Steam's glyph API instead.

## 4. Suspend and resume

**[docs]** Pressing the power button suspends the whole Deck; the game's
process just stops and later continues. Valve checks that games survive it.
What can go wrong in a Godot game:

- The first frame after resume has a huge `delta` (minutes). Anything that
  advances by `delta` (animations, the bots' thinking delays, Heat cooling
  if it ever becomes time-based) should clamp it, e.g. `minf(delta, 0.1)`.
  Physics already caps steps per frame.
- Audio: Godot's PulseAudio/PipeWire output reconnects by itself.
- Saves: the design saves between hands, so a Deck that runs out of battery
  while suspended loses at most the current hand. **[todo]** no save system
  exists yet.
- **Not checked**: no suspend test has been run (needs a real Deck).

## 5. Saves and Steam Cloud

- **[verified]** Godot's `user://` folder for this project, on Linux and so
  on the Deck: `~/.local/share/godot/app_userdata/A Friend in Need/` (from
  `OS.get_user_data_dir()` with this project.godot). On Windows it would be
  `%APPDATA%\Godot\app_userdata\A Friend in Need\`.
- **Recommended project.godot change** (not made here: the overworld work
  owns that file): `application/config/use_custom_user_dir=true` with
  `application/config/custom_user_dir_name="AFriendInNeed"`. Saves then live
  in `~/.local/share/AFriendInNeed/` (Linux) and `%APPDATA%\AFriendInNeed\`
  (Windows), not under "godot", and the folder name has no spaces. Do it
  before any player has a save, because it moves the folder.
- **[docs]** Steam Auto-Cloud (no code needed): Steamworks > Application >
  Steam Cloud. Set a byte quota and file count (a few MB and a handful of
  files is plenty), then add root paths:
  - Windows: root `WinAppDataRoaming`, subdirectory `AFriendInNeed`,
    pattern `*.save` (or whatever the save files end up called),
    OS Windows.
  - Linux: root `LinuxXdgDataHome`, subdirectory `AFriendInNeed`, same
    pattern, OS Linux.
  - Add a root override so the Windows root maps onto the Linux one, which
    lets a save made on a Windows PC continue on the Deck.
  Keep settings (volume, key bindings) out of the pattern or in a separate
  file if they shouldn't follow the player between machines.
- Steam Cloud isn't a Deck Verified requirement, but a Deck owner who also
  plays on a PC expects it.

## 6. Launch options

**[docs]** Steamworks > App Admin > Installation > General Installation, one
launch option per depot:

| Executable | Arguments | Operating system | CPU |
| --- | --- | --- | --- |
| `AFriendInNeed.x86_64` | (none) | Linux + SteamOS | 64-bit |
| `AFriendInNeed.exe` | (none) | Windows | 64-bit |

The executable path is relative to the depot root, which is the contents of
`build/linux/` or `build/windows/`. The .pck must stay next to the
executable with the same base name.

Leave the arguments empty. `--rendering-driver opengl3` is the default for
this project already (GL Compatibility). The game's dev flags (`--autoplay`,
`--screenshot`, `--dealer=`) are harmless in release but shouldn't be in a
launch option.

## 7. Uploading builds (SteamPipe)

**[docs]** Templates are in `steam/`: `app_build.vdf` and one depot script
per platform. Every ID in them is a placeholder (`YOUR_APP_ID`,
`YOUR_LINUX_DEPOT_ID`, `YOUR_WINDOWS_DEPOT_ID`); fill them in from the
partner site once the app exists. **Not verified**: no app ID exists, so
these have never been run through SteamCMD.

1. Steamworks: create the app; under SteamPipe > Depots create two depots
   and set their OS (Linux + SteamOS; Windows). Publish.
2. Make a separate Steam account just for uploading builds, give it only
   the "Edit App Metadata" and "Publish App Changes to Steam" permissions
   for this app, and enable Steam Guard on it.
3. Install SteamCMD (Linux:
   `https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz`).
4. Build, then upload from the repo root:

   ```
   scripts/export.sh
   steamcmd +login <builder_account> +run_app_build "$PWD/steam/app_build.vdf" +quit
   ```

   SteamCMD prompts for the password and Steam Guard code the first time
   and caches a login token afterwards. Never put either in a file in the
   repo or in a command that ends up in shell history or CI logs.
5. Upload the Linux depot from Linux or macOS, never from Windows: a
   Windows SteamCMD can't record the executable bit, and the game then
   fails to launch on the Deck.
6. The build appears under SteamPipe > Builds. Set it live on a beta branch
   first (or `"SetLive" "beta"` in app_build.vdf), test it on a Deck, then
   set it live on default by hand.

From CI later: run step 4 in `build.yml` on tags, with the builder login in
GitHub Actions secrets. SteamCMD needs a cached login (a `config.vdf` made
by one interactive login, stored as a secret) because CI can't answer a
Steam Guard prompt. Not set up yet: the app doesn't exist.

## 8. Steam Direct and the store page

From the design doc's release plan, plus **[docs]** details:

1. **Steamworks account and the Steam Direct fee:** $100 per game,
   recouped after the game makes $1,000 in sales. Signing up needs
   identity, bank and tax information; there is a waiting period between
   paying the fee and being able to release. Check Steamworks for the
   current waiting periods.
2. **Store page early:** wishlists drive launch visibility, so put up a
   "Coming Soon" page with a GIF of the table months ahead. Needs capsule
   art in Valve's fixed sizes (the one thing worth paying an artist for),
   at least 5 screenshots, a description, and Valve's review of the page
   (a few business days) before it goes public.
3. **Content questionnaire:** declare simulated gambling. With no real
   money or paid currency, it's a routine disclosure.
4. **Demo for Steam Next Fest:** the vertical slice (one town, one
   tournament). A demo is its own app ID with its own depots: copy the
   `steam/` scripts with its IDs.
5. **Steam Deck:** ship the native Linux build, test the Windows build
   through Proton as a fallback, and request Deck Verified review
   (Steamworks > Steam Deck compatibility). Valve tests on a real Deck and
   rates the game Verified / Playable / Unsupported against the points
   above: controller-only, the default configuration, legible text,
   a supported resolution, no launcher, suspend/resume.
6. **Release:** the build must pass Valve's build review (a few days) before
   the release button unlocks.

## Checklist for the first Deck test

- [ ] `scripts/export.sh linux`, copy `build/linux/` to the Deck (or upload
      to a beta branch).
- [ ] It launches from Game Mode with no prompts and fills the screen.
- [ ] All of a hand is playable with the Deck's controls alone.
- [ ] The back buttons signal (needs the default configuration of §2).
- [ ] The smallest text is readable at arm's length.
- [ ] Suspend mid-hand for a minute, resume: the game carries on.
- [ ] Force Proton (Properties > Compatibility) and repeat with the
      Windows build.
