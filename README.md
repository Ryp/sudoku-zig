# Sudoku

A Sudoku game that works!

Lets you pencil out the candidates, which is necessary for advanced techniques.

Supports all box sizes as long as they hold between 2 and 16 numbers, and has a solver/generator/grader included.

Jigsaw (squiggly) puzzles are also supported, but manually entering them in CLI is tedious.

![image](https://github.com/Ryp/sudoku-zig/assets/1625198/aeef8711-5366-4aad-886a-1e3bf295cd86)

## Running

This should get you going after cloning the repo:
```sh
zig build run -- 3 3 72..96..3...2.5....8...4.2........6.1.65.38.7.4........3.8...9....7.2...2..43..18
```
> **NOTE:** The sudoku string has to contain valid clue characters, anything else is considered as an empty cell.

![image](https://github.com/Ryp/sudoku-zig/assets/1625198/1e333afa-67a0-49b1-876a-8b180dd0b525)

If you're in for a challenge, let the program generate a puzzle for you!
A basic grader will run at startup letting you know how difficult the puzzle is.
```sh
zig build run -- 3 3
```

## Controls

| Action                | Key                |
|-----------------------|--------------------|
| Quit game             | Escape             |
| Select cell           | Left mouse button  |
| Move selection        | Arrow keys         |
| Place number          | <1-9,A-G>          |
| Toggle candidate      | Shift + <1-9,A-G>  |
| Clear number          | <0>, Del           |
| Undo                  | Ctrl + Z           |
| Redo                  | Ctrl + Shift + Z   |
| Fill candidates       | H                  |
| Fill all candidates   | Ctrl + H           |
| Clear candidates      | Shift + H          |
| Solve                 | Enter              |
| Get/apply a hint      | Shift + Enter      |
| Change window size    | +/-                |

> **NOTE:** Getting a hint only works if you already placed candidates on the board and assumes they are correct.
> A preview will be shown to you with what the solver found and the game will wait for you to press the key again to apply it.

## Examples

### 4x3 Sudoku

```sh
zig build run -- 4 3 8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C
```

![image](https://github.com/Ryp/sudoku-zig/assets/1625198/4368f413-929f-46ea-a1fd-ce00478b7131)

### Jigsaw Sudoku
```sh
zig build run -- 3 3 .38.4.1...6.9532......6....97......54..........5..2......6..8...57....6.34.8..... 111111222113444422133455442334455222366657777366559997366659977386858997888888997
```
> **NOTE:** Jigsaw puzzles need a second string that matches each cell with its associated region, so it's like the sudoku string but instead of clues you write the region index.

![image](https://github.com/Ryp/sudoku-zig/assets/1625198/5982b7f8-c556-40ea-bc1b-68583388342f)

## Troubleshooting

### Pixelated Rendering with Wayland
SDL3 may default to the X11 backend, which does not support HiDPI scaling. To ensure the application uses Wayland, set the following environment variable before launching:
```sh
SDL_VIDEO_DRIVER=wayland
```
