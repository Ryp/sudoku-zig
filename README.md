# Sudoku

A Sudoku game that doesn't come with puzzles in the box, bring your own!
Supports all box sizes as long as they hold between 2 and 16 numbers, and has a solver included.
Lets you pencil out the candidates as well, which is necessary for advanced techniques.
Jigsaw (squiggly) puzzles are also supported, but manually entering them in CLI is annoying.

## Running

This should get you going after cloning the repo:
```sh
zig build run -- 3 3 72..96..3...2.5....8...4.2........6.1.65.38.7.4........3.8...9....7.2...2..43..18
```
NOTE: The sudoku string has to contain valid clue characters, anything else is considered as an empty cell.

Example with a 4x3 sudoku:
```sh
zig build run -- 4 3 8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C
```

Example with a Jigsaw sudoku:
```sh
zig build run -- 3 3 .38.4.1...6.9532......6....97......54..........5..2......6..8...57....6.34.8..... 111111222113444422133455442334455222366657777366559997366659977386858997888888997
```
NOTE: Jigsaw puzzles need a second string that matches each cell with its associated region, so it's like the sudoku string but instead of clues you write the region index

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
