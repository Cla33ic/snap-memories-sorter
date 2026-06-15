# Snap Memories Sorter

Turn your exported **Snapchat Memories** into two tidy, date-sorted photo/video folders on
your computer.

You get **two** copies of every memory:

- **`Originals/`** — the raw files exactly as Snapchat stored them, untouched.
- **`Merged/`** — the same memories **as you saw them in the app**, with the captions,
  stickers, drawings and other overlays put back on top of the photo or video.

Everything is sorted into `Year/Month` folders, and each file's date is set to the day the
memory was taken — so your Photos app / File Explorer shows them in the right order.

```
Your chosen output folder/
├── Originals/
│   └── 2023/
│       └── 05/
│           └── 2023-05-14_....jpg
└── Merged/
    └── 2023/
        └── 05/
            └── 2023-05-14_....jpg
```

> **Don't worry if you've never used a "terminal" before.** This guide walks you through
> every click. Just follow the steps for your computer (Mac or Windows) in order.

---

## Before you start: the big picture

You'll do four things, once:

1. **Ask Snapchat for your data** and download the ZIP files they send you.
2. **Install one free helper program** called *ffmpeg* (it does the picture/video work).
3. **Download these two script files** (the ones in this project).
4. **Run the script** for your computer. It will pop up windows asking you to pick your
   folders, then do everything automatically.

That's it. Steps 1–3 are one-time setup. After that you just run the script.

**How long does it take?** It depends on how many memories you have and, above all, how many
are videos: photos are processed almost instantly, but each video is re-encoded and takes
noticeably longer. A photo-heavy export finishes quickly; a video-heavy one can take a while.
When it starts, the script tells you how many photos and videos it found, and it prints each
file as it goes so you can watch it progress. You can leave it running, and it is safe to stop
and re-run later.

---

## Step 1 — Get your Snapchat data

1. Open this page in a browser and log in:
   **<https://accounts.snapchat.com/accounts/downloadmydata>**
   (or in the app: **Settings → My Data**).
2. Scroll down and make sure the box **"Include your Memories, ..."** is **ticked**.
3. Submit the request. Snapchat now prepares your data — this can take anywhere from a few
   minutes to a day. They'll **email you** when it's ready.
4. Open the email and **download every ZIP file** it links to. Big accounts are split into
   several files with names like `mydata~1234567890.zip`, `mydata~1234567891.zip`, etc.
   **Download all of them.**
5. Make a new folder somewhere easy (e.g. on your Desktop call it `Snapchat Zips`) and put
   **all** the downloaded `.zip` files inside it.

   **Do NOT unzip them yourself.** The script unzips them for you.

---

## Step 2 — Install ffmpeg (the free helper program)

*ffmpeg* is the tool that stitches the overlays back onto your photos and videos. You only
install it once.

### On a Mac

1. Open the **Terminal** app. (Press `Cmd`+`Space`, type `Terminal`, press `Enter`.)
2. First install **Homebrew** (a tool that installs other tools). Copy-paste this line into
   Terminal and press `Enter`, then follow its prompts:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
   *(If Homebrew is already installed, skip this.)*
3. Now install ffmpeg. Paste this and press `Enter`:
   ```bash
   brew install ffmpeg
   ```
4. Check it worked:
   ```bash
   ffmpeg -version
   ```
   If you see version text (not "command not found"), the install worked.

### On Windows

1. Click **Start**, type **PowerShell**, and open **Windows PowerShell**.
2. Paste this and press `Enter`:
   ```powershell
   winget install Gyan.FFmpeg
   ```
   Say **Yes** to any prompts.
3. **Close PowerShell and open it again** (this is important so it notices the new program).
4. Check it worked:
   ```powershell
   ffmpeg -version
   ```
   If you see version text (not an error), the install worked.

   <details>
   <summary>No <code>winget</code>? Install ffmpeg manually</summary>

   1. Download a build from <https://www.gyan.dev/ffmpeg/builds/> (the "release essentials" zip).
   2. Unzip it, and inside the `bin` folder you'll find `ffmpeg.exe`.
   3. Easiest option: copy `ffmpeg.exe` into the **same folder** as the script file from
      Step 3 below. The script will find it there automatically.
   </details>

---

## Step 3 — Download the script files

From this project page, download the two files (click each file, then the **Download raw**
button, or use the green **Code → Download ZIP** button and unzip it):

- **`snap-memories-sorter-macos.sh`** — for Mac
- **`snap-memories-sorter-windows.ps1`** — for Windows

Put the one for **your** computer somewhere easy to find, like your Desktop. You only need
the file that matches your computer.

---

## Step 4 — Run it

When you run the script it will pop up **two folder-picker windows**, one after the other:

1. **"Select the folder that contains your Snapchat export ZIP files"** → pick the
   `Snapchat Zips` folder you made in Step 1.
2. **"Select the destination folder"** → pick (or make) an empty folder where you want the
   sorted photos to end up, e.g. a new folder called `Snapchat Memories`. The `Originals/`
   and `Merged/` folders are created inside it.

Then it runs by itself. Depending on how many memories you have, this can take a while
(videos are the slow part). When it's done it prints a summary.

> The ZIP files are unzipped into a **temporary folder that is deleted automatically** when
> the script finishes — it doesn't leave a mess behind, and it never changes your original
> ZIP files.

### On a Mac

1. Open **Terminal** (`Cmd`+`Space`, type `Terminal`, `Enter`).
2. Go to the folder where you saved the script. If it's on your Desktop, paste this and press
   `Enter`:
   ```bash
   cd ~/Desktop
   ```
3. Allow the script to run, then start it:
   ```bash
   chmod +x snap-memories-sorter-macos.sh
   ./snap-memories-sorter-macos.sh
   ```
4. Pick your folders in the two pop-up windows and let it work.

### On Windows

The simplest way:

1. **Right-click** the file `snap-memories-sorter-windows.ps1`.
2. Choose **Run with PowerShell**.
3. Pick your folders in the two pop-up windows and let it work.

If Windows blocks it, open **Windows PowerShell**, go to the folder, and run it like this
(this allows the script just for this one run):

```powershell
cd $HOME\Desktop
powershell -ExecutionPolicy Bypass -File .\snap-memories-sorter-windows.ps1
```

---

## When it's finished

Open your destination folder. You'll find:

- **`Originals/`** — clean copies of every memory, sorted by year and month.
- **`Merged/`** — the same memories with captions/stickers/drawings baked back in.

Each line the script printed means:

| You saw            | It means                                                        |
|--------------------|-----------------------------------------------------------------|
| `[ok] 2023/05/...` | That memory was sorted successfully.                            |
| `(overlay merged)` | A caption/sticker was put back onto that photo or video.        |
| `[skip] ...`       | Already done in a previous run — left as-is.                    |
| `[warn] ...`       | The overlay couldn't be read (some are stored in odd formats), so the original is kept in Merged without it. |
| `[FAIL orig] ...`  | That file couldn't be copied into Originals (the rest still continue). |
| `[FAIL copy] ...`  | That file couldn't be copied into Merged either (the rest still continue). |

---

## Troubleshooting

- **"ffmpeg/ffprobe not found"** — You skipped or didn't finish Step 2, *or* you didn't
  reopen the terminal afterwards. Close it, open a new one, and run `ffmpeg -version` to
  confirm. (`ffprobe` is installed automatically together with `ffmpeg`.)
- **"No .zip files found"** — You pointed the first picker at the wrong folder. It must be
  the folder that directly contains the `.zip` files from Snapchat.
- **"No 'memories' folder found"** — Those ZIPs don't contain Memories. When requesting your
  data (Step 1) make sure the **Include your Memories** box was ticked.
- **It's taking forever** — That's normal for lots of videos; each one is re-encoded. Leave
  it running. You can safely stop and re-run later — finished files are skipped.
- **Mac: nothing happens / no window** — Make sure you ran it from Terminal as shown, and
  look for the pop-up folder window (it can appear behind other windows).

---

## Notes for the curious

- **Re-running is safe.** Files already in `Originals/` and `Merged/` are skipped.
- **Photos vs. videos.** Overlays go onto both. A photo with an overlay is saved as `.jpg`;
  videos keep their original format and audio.
- **Unknown dates.** If a file has no readable date, it's filed under `unknown/00/`.
- **Speed (Mac).** The Mac script processes a few files at once (`MAX_PARALLEL`, default 3,
  near the top of the file). Raise it if you have mostly photos.

---

## License

MIT — free to use, change, and share.
