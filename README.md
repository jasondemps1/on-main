# on-main

Live-code Common Lisp GUI and game programs on macOS from Sly or SLIME.

macOS only lets a process create windows on its **main thread**. Cocoa enforces
this, so GLFW, SDL, raylib and friends all inherit the rule. Sly and SLIME,
though, give SBCL's main thread to a REPL and evaluate your code in other
threads. `on-main` starts SBCL the other way round: the editor's server runs in
background threads, and the main thread waits for work you send it.

```lisp
(on-main:run 'my-game::game-loop)   ; window opens; your REPL stays responsive
```

Redefine functions with `C-c C-c` while the game runs and see the change on
the next frame.

## Symptoms this fixes

- A crash when opening a window from the REPL, often mentioning that
  `NSWindow` must be created on the main thread.
- A window that opens, after which Sly or SLIME stops responding: `C-c C-c`
  does nothing, completion stops working, and the minibuffer shows
  `; pipelined request...`. This is common after using `trivial-main-thread`
  from a running REPL. It runs your code by *interrupting* the main thread,
  which may be holding a lock at that moment that it then never releases.
- `slynk:create-server` or `swank:create-server` never returning in a
  hand-written launcher. Unless the communication style is `:spawn`, the server
  runs on the thread that started it.

## Requirements

- SBCL (other implementations aren't supported yet)
- Emacs 28.1+ with Sly or SLIME

It works on Linux and Windows too, where it's harmless rather than required.

## Installation

From source with Emacs 29+:

```elisp
(package-vc-install "https://github.com/<you>/on-main")
```

Or clone the repo and add it to your `load-path`. Then load the adapter for
your editor:

```elisp
(with-eval-after-load 'sly   (require 'on-main-sly))
(with-eval-after-load 'slime (require 'on-main-slime))
```

## Usage

From any buffer in your project, run **`M-x on-main-sly`** (or
**`M-x on-main-slime`**). This:

1. starts your Lisp in the project root (the nearest directory with an `.asd`),
2. adds that directory to ASDF's search path,
3. boots Slynk/Swank in background threads and connects,
4. hands the main thread to the `on-main` queue.

With a prefix argument (`C-u M-x on-main-sly`) you choose from
`sly-lisp-implementations` / `slime-lisp-implementations`. Otherwise the
default entry, or `inferior-lisp-program`, is used, with all your existing
flags.

Then send work to the main thread from the REPL:

```lisp
(asdf:load-system :my-game)
(on-main:run 'my-game::game-loop)
```

Pass a **symbol** rather than `#'game-loop` so redefinitions take effect.

### A `main` that works in both modes

A built executable already runs `main` on the main thread. During development,
`main` can hand itself over instead. This version doesn't depend on `on-main`
at build time:

```lisp
(defun main ()
  (if (eq sb-thread:*current-thread* (sb-thread:main-thread))
      (game-loop)
      (uiop:symbol-call :on-main :run 'game-loop)))
```

## Lisp API

All in the `on-main` package.

| Function | Description |
| --- | --- |
| `(run fn)` | Queue `fn` for the main thread and return immediately. Errors open the debugger on the main thread; its ABORT restart returns to the queue. |
| `(call fn &key timeout)` | Run `fn` on the main thread and return its values. Errors are re-signalled in the caller. If the main thread is busy (e.g. a game loop is running), it waits, or signals an error after `timeout` seconds. |
| `(main-thread-p)` | True on the main thread. |
| `(queue-length)` | Number of functions waiting. |

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `on-main-project-root` | `asd` | Where Lisp starts: `asd` (nearest `.asd`), `project` (project.el root), `default-directory`, or a function. |
| `on-main-load-system` | `nil` | Load the project's ASDF system after connecting. |
| `on-main-lisp-file` | bundled `on-main.lisp` | The Lisp-side boot file. |

## Live-coding tips for macOS

- **Call per-frame code by name** from your loop (`(draw-frame)`), so
  `C-c C-c` on `draw-frame` takes effect on the next frame.
- **Wrap each frame in a restart**, so an error doesn't kill the window:
  ```lisp
  (with-simple-restart (continue "Skip this frame") (draw-frame))
  ```
- **Mask float traps.** macOS graphics code does floating-point operations
  that SBCL treats as errors by default. Mask them inside the loop, since traps
  are per-thread:
  ```lisp
  (sb-int:with-float-traps-masked (:invalid :divide-by-zero :overflow :inexact)
    ...)
  ```

## Example: claw-raylib

```lisp
(defun draw-frame ()
  (raylib:clear-background raylib:+raywhite+)
  (raylib:draw-text "hello from lisp" 190 200 20 raylib:+lightgray+))

(defun game-loop ()
  (sb-int:with-float-traps-masked (:invalid :divide-by-zero :overflow :inexact)
    (raylib:with-window ("demo" (800 450))
      (raylib:set-target-fps 60)
      (loop :until (raylib:window-should-close)
            :do (raylib:with-drawing
                  (with-simple-restart (continue "Skip this frame")
                    (draw-frame)))))))
```

```lisp
(on-main:run 'game-loop)
```

On macOS, current claw-raylib needs a one-line fix in `library.lisp`: change
`:test #'string=` to `:test #'equal`. CFFI's default
`*foreign-library-directories*` on Darwin contains forms, not strings.

## Without Emacs launching Lisp

From your project root:

```sh
sbcl --load /path/to/on-main/on-main.lisp
```

Then connect with `M-x sly-connect` or `M-x slime-connect` to `localhost:4005`.
Environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `ON_MAIN_BACKEND` | `slynk` | `slynk` or `swank` |
| `ON_MAIN_LOADER` | asked from Emacs | Path to `slynk-loader.lisp` / `swank-loader.lisp` |
| `ON_MAIN_PORT` | `4005` | Server port |
| `ON_MAIN_PROJECT_ROOT` | current directory | Added to ASDF's search path |

Without `ON_MAIN_LOADER`, the path is requested from a running Emacs through
`emacsclient`, so your Emacs needs `server-start`. Use the Slynk/Swank that
ships with your editor, since mismatched versions misbehave.

## Limitations

- SBCL only, for now.
- The `*on-main ...*` inferior buffer shows main-thread output (library log
  lines and so on), but you can't type into it: its REPL never runs, by design.
- `sly-restart-inferior-lisp` may not keep the project directory. Quit and run
  `on-main-sly` again instead.

## Development

```sh
make deps   # clone Sly and SLIME into .deps/
make test   # byte-compile, ERT unit tests, Lisp smoke tests, Sly and SLIME end-to-end
```

CI runs the same on macOS and Linux.

## License

MIT
