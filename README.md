# Sudoku

A Sudoku game that works!

Lets you pencil out the candidates, which is necessary for advanced techniques.

Supports all box sizes as long as they hold between 2 and 16 numbers, and has a solver/generator/grader included.

Jigsaw (squiggly) puzzles are also supported, but manually entering them in CLI is tedious.

<img width="1390" height="1386" alt="image" src="https://github.com/user-attachments/assets/c0911d0f-f6b6-48f8-ac6f-fc7c0e8de0d3" />

## Running

This should get you going after cloning the repo:

```sh
zig build run -- 72..96..3...2.5....8...4.2........6.1.65.38.7.4........3.8...9....7.2...2..43..18
```

> **NOTE:** The sudoku string has to contain valid clue characters, anything else is considered as an empty cell.

If you're in for a challenge, let the program generate a puzzle for you!
A basic grader will run at startup letting you know how difficult the puzzle is.

```sh
zig build -Doptimize=ReleaseFast run
```

> **NOTE:** The puzzle generation is slow, so it's good to compile with optimizations
> enabled.

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

> **NOTE:** Getting a hint only works if you already placed candidates on the board
> and assumes they are correct. A preview will be shown to you with what the solver
> found and the game will wait for you to press the key again to apply it.

## Examples

### 4x3 Sudoku

```sh
zig build run -- -W 4 -H 3 8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C
```

<img width="1846" height="1842" alt="image" src="https://github.com/user-attachments/assets/ace7e5ef-55b0-476e-99d5-dcde7182e885" />

### Jigsaw Sudoku

```sh
zig build run -- --jigsaw 111111222113444422133455442334455222366657777366559997366659977386858997888888997 .38.4.1...6.9532......6....97......54..........5..2......6..8...57....6.34.8.....
```

> **NOTE:** Jigsaw puzzles need a special string that matches each cell with its
> associated region, so it's like the sudoku string but instead of clues you write
> the region index.

<img width="1390" height="1386" alt="image" src="https://github.com/user-attachments/assets/d5d48f65-561d-4db4-a8b7-30d3b1f8a836" />

## Troubleshooting

### Pixelated Rendering with Wayland

SDL3 may default to the X11 backend, which does not support HiDPI scaling. To ensure the application uses Wayland, set the following environment variable before launching:

```sh
SDL_VIDEO_DRIVER=wayland
```
