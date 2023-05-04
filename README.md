# Sudoku

A Sudoku game that doesn't come with puzzles in the box, bring your own!
Supports all box sizes as long as they hold between 2 and 16 numbers, and has a basic human-like solver included.
Lets you pencil out the candidates as well, which is necessary for advanced techniques.

## Building

This should get you going after cloning the repo:
```sh
$ zig build run -- 3 3 72..96..3...2.5....8...4.2........6.1.65.38.7.4........3.8...9....7.2...2..43..18
```

Another example with a 4x3 grid:
```sh
$ zig build run -- 4 3 8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C
```

## Controls

| Action         | Key                |
|----------------|--------------------|
| Quit game      | Escape             |
| Select cell    | Left mouse button  |
| Move selection | Arrow keys         |
| Place number   | <1-9,A-G>          |
| Clear number   | <0>, Del           |
| Toggle guess   | Shift + <1-9,A-G>  |
| Undo           | Ctrl + Z           |
| Redo           | Ctrl + Shift + Z   |
| Fill guesses   | H                  |
| Clear guesses  | Shift + H          |
| Solve          | Enter              |
