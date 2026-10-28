# Main menu and race modes

Whiplash Shift now opens at the main menu. Choose a mode, configure it, then select/customize a vehicle in the garage and press IGNITE.

## Season Race

Season 1 shows the approved three cups of three races. The current playable preview contains Block Circuit only; the other eight courses are marked Coming Soon. Finishing this preview awards standings for that one available race, not completion of the planned nine-race season.

## Single Race

Select any built track, 1–99 laps and Forward or Reverse. Block Circuit and Split Shift are currently available. Track, laps and direction stay fixed when entering the garage; the garage still offers chassis, paint, parts, callsign and CPU difficulty.

Reverse changes the race route, checkpoints, CPU direction and corner cues. It uses the original forward road, relief and scenery geometry so buildings and boulders do not move. Start/grid clearance is checked before using a reversed course.

## Custom Season

Create a named list of 1–30 race entries. Each entry has its own track, lap count and direction. Tracks can repeat, allowing endurance rounds or forward/reverse pairs. Add, update, reorder and remove entries before starting.

Save and Load keep definitions in the local `user://seasons` library. Saving under the same name updates that saved definition. These files store the race list, not running car/physics state.

To share, choose Make Code and Copy, then send the code using your preferred messaging app. Another player pastes it into Share Code and chooses Import Code. Export File and Import File provide the equivalent portable JSON file. Import loads the editor without silently saving or overwriting a library entry; choose Save to retain it. Recipients need a game version containing every referenced track.

The versioned format accepts only known tracks and fields. Names, race counts, lap counts, direction and input/file sizes are checked before applying an import. Share-code checksums detect accidental edits; they are not author authentication. Imported files are data and never load game scripts or resources.

## Season scoring and results

Each race gives 10, 6 and 3 points to the three entrant slots in finishing/standing order. As in the existing game, the race ends when the player finishes; unfinished rivals are ordered by their progress then. CPU identities and their vehicles stay consistent for the run. Standings sort by points, then wins, then original grid slot for exact ties.

Results show provisional season standings. Next Race (or N) commits that round once and starts the next. Race Again (Enter) retries the current round without adding points. The final round offers Final Standings. A rapid repeated Continue cannot advance multiple rounds.

Returning to the main menu keeps an unfinished run in memory and offers Resume Season, which restarts its uncommitted current race. Starting another mode asks before replacing an unfinished season. Runs are not resumed after closing the application; saved custom-season definitions remain available.

## Settings and About

Settings exposes speed units and CPU difficulty. Display preferences and menu-selected CPU difficulty are stored in the existing settings file. The direct garage entry still supports legacy profile files; normal menu launches preserve the selected race settings instead of reloading legacy values over them.

About links to the supplied creator homepage, https://appsbydan.com, and support page, https://buymeacoffee.com/AppsbyDan. Links open the default browser only when their button is pressed.
