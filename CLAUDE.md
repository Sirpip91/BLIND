# BLIND (Godot-Sandbox)

A first-person Japanese ink (sumi-e) sword game, in Godot 4.7 Forward+,
GDScript only. It grew out of a sandbox for trying ideas, and the older
prototypes are still here. **The game is `Experiments/Arena/`**, and
`arena.tscn` is the main scene (F5). Keep building there: no new copies of it
unless asked.

## What the game is meant to be

Read this before changing anything about how it plays or looks.

- **Serious, lethal duels.** The player should feel they are using a sword and
  fighting for their life, not playing a game. One good cut kills.
- **Nothing gamified:** no OPEN text, combo counters, health bars, damage
  bonuses or cards. Show it in bodies, blades and ink. Upgrades change how you
  fight; they never add percentages.
- **The parry is untouchable.** Its timing and sides are exactly right
  (0.2 s window, perfect in about the first 0.11 s). Never change them.
- **Steering the sword is the favourite thing in it:** swipe and click cuts,
  or hold and draw the line of the cut. Cuts fall exactly where they were
  drawn. Time is never slowed while drawing. Plain clicks stay ("fine for
  noobs").
- **Difficulty comes from rules**, not stats: reading, bluffs, being flanked,
  second forms. Enemies that can be spammed or killed by luck are too easy.
  In groups no two blows land less than 0.5 s apart, so each can be met.
- **Look:** sumi-e, black on paper, one vivid colour at a time. Brush edges,
  mist, silhouettes. Nothing thick, blocky, cheap or generated-looking. No
  flicker or crawling texture. Black leads on the sword and its cuts; colour
  is an accent, never a rainbow.
- **The art is the owner's to make.** They paint in Substance and model in
  Blender. Every model here made by code is a stand-in and is labelled so:
  make them easy to replace, and don't invent final art.
- **No sound made in code.** All of it was removed on purpose. Wait for real
  recordings.
- Don't recreate a specific existing game.

### Working with the owner

Beginner to intermediate developer. Keep replies short and plain. When they
say "talk", change nothing. One quick check, then hand it over: they dislike
long test runs. Offer choices as things to try in the game. Don't delete or
overwrite something they like without asking. Never commit or push unless
asked.

## How a run goes

Main menu → (tutorial) → gatehouse → clearing → kill everyone → far gate opens
→ shut inside → next clearing. No fades except eyes closing on death, which
puts you back at the same fight.

Order, as listed in `encounters` on the Arena node: Practice (only by key),
The sword (tutorial), One ronin, Two ronin, the Watcher, Three ronin, the
Student, Five ronin, the Red Master, the Ghost, **mask room**, then night:
Three ronin, Watcher and two ronin, Five ronin, Watcher and Student, Red
Master, Ghost, mask room, and night again.

- **Gatehouses** (`grounds/gate.gd`, `passage.gd`): the one ahead and the one
  behind are the same inside, so the player is moved from one to the other
  while shut in. `grounds.grow()` rearranges the bamboo.
- **Mask room** (`grounds/shrine.gd`, `feel/choosing.gd`): E looks into a
  floating mask, hovering a colour lights its eyes, one is picked, and the
  mask is cut in half to take it. Colours stack.
- **Colours** (`player/aspect.gd`, `data/aspect_*.tres`): blue Sense (blows
  from off screen are felt at the edge), red Sunder (a full blade cuts through
  any guard), green Mend (perfect parries heal), purple Stillness (a perfect
  step leaves them standing).

## Controls

Mouse swipe then click: cut. Hold left: draw a cut. Right: guard (side =
swipe). Wheel up: thrust. Wheel down: flick the blood off. Space or Shift:
step. Q: lock on. Locked with several enemies, throw the mouse far to one side
for the next. Middle: next. E: look into the mask. Esc: pause.

Testing keys: `]` `[` next and previous level, K kill everyone and open the
gate, G next colour (Shift+G none), V sword paint styles, 1-9 and 0 and
Shift+1-6 jump to fights, R again, N day/night, C plain sword colour, H list.

## Where things are in `Experiments/Arena/`

| Path | What |
|------|------|
| `arena.gd` | Runs encounters, judges every blow, lock-on switching, where rules meet feel. |
| `encounter.gd`, `data/fight_*.tres` | A fight: who, how many at once, player health, `night`, `shrine`, `tutorial`. |
| `fighter/` | Shared by both sides: `arm` (sword phases), `poses`, `strike`, `exchange` (the rules of a blow landing), `vitals`, `pattern`. |
| `player/duelist.gd` | Movement, lock-on, dodge, the mouse's mark. |
| `player/swordsman.gd` | Clicks to cuts and guards, drawing, ink (stamina, shown on the blade). |
| `player/sword.gd` | The sword in hand: all one point on the view, in radians from its middle. `flick_clean()`. |
| `player/blade_colors.gd`, `aspect_blade.gdshader` | The colours painted on the blade, seven animated styles (Splashed is default). |
| `foe/foe.gd` | An enemy: armour, cuts, limbs lost, second forms. |
| `foe/kind.gd`, `data/*.tres` | Everything that makes one enemy not another. A new enemy is a new one of these. |
| `foe/brain.gd` | Where it walks, when it attacks. Patterns live in `foe.tscn` and `data/pattern_*.tres`. |
| `foe/director.gd` | Groups: waves, partners from the other side, bluffs, spacing of blows, places round the player. |
| `foe/reader.gd` | A trained eye: blocks what it sees coming, remembers tricks. |
| `foe/haunt.gd` | The Ghost's second life: teleporting runs, shadowless images, several cuts to finish. |
| `foe/body.gd`, `part.gd` | Procedural motion, and the hit volumes. |
| `foe/figure.gd` | Drives a rigged model's bones from `body.gd`. |
| `cutting/` | `edge` (line through bodies), `region` (planes), `slicer` (static meshes), `skinned` (cuts a rigged mesh while it's still moving), `piece`, `gash`. |
| `feel/` | `feel.gd` (what every moment looks like), `blood.gd`, `sense.gd`, `compass.gd`, splash and slash. |
| `lessons/`, `data/lesson_*.tres` | The tutorial. Clips are sprite sheets filmed from the game. Blood is black there (`kind.straw`). |
| `menu/` | Main menu, options, pause. `title` on MainMenu is a placeholder. |

Enemy second forms: `kind.changes` (WILD: the Red Master throws off his helmet)
and `kind.lives` (the Ghost: dies, then rises at night). Bosses need two
perfect parries (`parries_to_open`) and bluff with what you keep parrying
(`learns`).

## Enemy models

All enemies use `Assets/BaseMale` (Quaternius Universal Base Characters, CC0):
1.81 m, T-pose, Unreal bone names, no animations. Motion is all code, so the
sword stays exactly where the rules say.

To replace one: rig to **this same skeleton**, keep the bone names, and set
`figure` on its kind. Clothes go in `figure_extras` (skinned to the same
bones, cut along with the body). `armour` is a `.glb` whose objects are named
for the part they go on (`chest`, `chest_under`, `hips`, `helmet`, `upper_l`,
`fore_r`, `shin_l`...). `mask` is one unrigged mesh modelled where the face
is. **Material names pick the ink**: `Cloth`, `Collar`, `Plate`, `Iron`,
`Cord`, `Pale`, `Mask`, `MaskInk`, `Topknot`. Bodies must be closed meshes.
Painted textures on clothes and masks aren't hooked up yet.

## Core

`Core/` holds only what more than one experiment needs. No autoloads, no
addons.

| Path | What |
|------|------|
| `Core/Player/` | First-person walker: walk, sprint, crouch, head bob, `shake()`, `spike_fov()`, `face_point()`. Override `_steer()`. |
| `Core/FlyCam/`, `Core/Stage/`, `Core/sandbox.tscn` | Free camera, metre grid, and the scene they come in. Tab = walk/fly. `show_floor` and `use_stage_lighting` turn its own off. |
| `Core/Wash/` | The sumi-e look. `wash_pass.tscn` is the full-screen pass (render priority 100), `brush_blade.gd` lays strokes, `ink_blade.gdshader` goes on a blade. |
| `Core/Ink/` | The older comic-ink look. |
| `Core/Combat/` | `impact_frames.gd` (the flat page on big hits) and older sword code. |

How the wash treats things: anything more vivid than `keep_color` keeps its
colour and loses its shading; a material with `ROUGHNESS = 0` counts as held
by the player and isn't misted; transparent things are lost under the pass
unless their `render_priority` is above 100, which is how world text, strokes
and clips are drawn over it.

## Other experiments

Duel, Steel, SteelPaint, SteelGuard, SteelBoss, Rally led up to Arena. Steel's
sword feel is the reference. InkWash, InkHatch, BlindDuel, Dungeon and Showcase
are other looks and ideas. They are self-contained: an experiment never reaches
into another's folder. Leave them alone unless asked.

## Conventions

- 1 unit = 1 m. Player 1.8 m, eye 1.65 m. Model at real size in Blender.
- Physics layer 1 `world`, 2 `player`. Player is in group `"player"`.
- `Assets/<Name>/`: one folder per asset, `.glb` preferred. Importing `.blend`
  directly is off.
- Sparse comments that explain why, never what. Plain, slightly literary
  names. No AI-attribution comments in code.

## Traps

- **`arena.tscn` needs `[editable path="Sandbox"]`.** Without it, saving in
  the editor silently drops `duelist.gd` from the player. The older scenes
  (Steel, SteelPaint, SteelGuard, SteelBoss, Rally, Duel) don't have it.
- The editor keeps open scenes in memory: after editing `.tscn` files outside
  it, use Reload from disk, or a save puts the old one back.
- GDScript: `:=` on an untyped value is a parse error. Annotate the type.
- Physics interpolation is on. The player's sword turns it off and moves in
  `_process`.
- A tween with no tweeners errors; a polygon of size zero can't be drawn.
- Shader functions can't share a name with a local variable.
- The smoke test doesn't run scenes, so it won't catch a broken node path or a
  shader that won't compile. Start the game for that.

## Testing

```
godot --headless --path . -s res://Tests/smoke_test.gd
godot --headless --fixed-fps 60 --path . -s res://Tools/arena_bot.gd -- 2
```

The first loads every scene and compiles every script under `Core/` and
`Experiments/` (prints `PASS`). The second is a bot that plays one fight, by
its index in `encounters`. For looks, run a windowed `-s` script that saves
the viewport. Godot is the Steam install:
`C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.
Blender is the Steam install too (5.3) and runs headless.

`Tools/` also has `film_lessons.gd` (records the tutorial clips) and
`make_clothes.py` / `make_gate.py` (built the stand-in models; they overwrite
what's there).

## Where it's got to, and what's next

Done: duels, groups, gates and levels, bosses with second forms, night set,
mask room and stacking colours, animated sword paint, directional blood and
the flick, rigged enemies that are cut live, tutorial, main menu, group
lock-on.

Offered or agreed, not done:
- Ragdoll for cut halves (they fall stiff).
- The bind when blades lock.
- Painted textures on clothes and masks, and the owner's own models. The plan
  is about 18 body poses (8 directions wound up and through, plus a thrust)
  blended by the code.
- Walking and death animations from a pack on the same skeleton.
- Whether dying should lose the colours, and whether group fights start
  locked on.
- A title, real sound, bare feet, the flat look of strong colours on armour.
- Deleting the six older duel folders, only if asked.

## Credits

- Body, eyes and hair: Quaternius, Universal Base Characters, CC0
  (`Assets/BaseMale/License_Standard.txt`).
- Lettering: East Sea Dokdo, SIL Open Font License
  (`Assets/Fonts/EastSeaDokdo-OFL.txt`).
