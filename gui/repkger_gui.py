#!/usr/bin/env python3
"""Repkger GUI — a real windowed front-end for the repkger rootless .pkg installer.

Launched three ways:
  * double-click Repkger.app            -> windowed chooser
  * drag .pkg/.mpkg/.dmg/.zip/.bundle onto the app icon  -> those files pre-loaded
  * "Open With" from Finder on a package -> same as a drop

The repkger CLI is embedded at Contents/Resources/repkger (so the app is fully
self-contained); when run from the repo it falls back to ../bin/repkger.

Headless/automation helper:  repkger-gui --smoketest <file> ...
  prints the repkger command that *would* run for the first selected file and
  exits 0 (no Tk window, no execution) — used to validate the wiring.
"""

import os
import sys
import subprocess
import threading

# ---------------------------------------------------------------------------
# locate the embedded CLI
# ---------------------------------------------------------------------------
def repkger_path():
    here = os.path.dirname(os.path.abspath(__file__))
    # bundled: this script lives at Contents/MacOS, CLI at Contents/Resources
    c1 = os.path.normpath(os.path.join(here, "..", "Resources", "repkger"))
    if os.path.isfile(c1):
        return c1
    # repo dev: gui/repkger_gui.py, CLI at bin/repkger
    c2 = os.path.normpath(os.path.join(here, "..", "bin", "repkger"))
    if os.path.isfile(c2):
        return c2
    return "repkger"  # hope it is on PATH


def build_command(mode, files, target, run_scripts, home_rooted, only_prefix):
    """Return the repkger argv list for the current UI state (no execution)."""
    rk = repkger_path()
    if mode == "brew":
        cask = (files[0] if files else "").strip()
        if not cask:
            return None
        return [rk, "brew", "install", "--cask", cask]
    if mode == "uninstall":
        name = (files[0] if files else "").strip()
        if not name:
            return None
        return [rk, "uninstall", name, "--yes"]
    if not files:
        return None
    pkg = files[0]
    if mode == "inspect":
        return [rk, "inspect", pkg, "--files", "20"]
    if mode == "bom-redo":
        return [rk, "bom-redo", pkg, "--home", target, "--preview"]
    # install (default)
    cmd = [rk, "install", pkg, "--home", target, "--yes"]
    if run_scripts:
        cmd.append("--run-scripts")
    if home_rooted:
        cmd.append("--home-rooted")
    if only_prefix:
        cmd += ["--only", only_prefix]
    return cmd


# ---------------------------------------------------------------------------
# headless smoke test (no GUI)
# ---------------------------------------------------------------------------
def smoketest(files):
    rk = repkger_path()
    print("repkger CLI :", rk, "(exists)" if os.path.isfile(rk) else "(on PATH)")
    for mode in ("install", "inspect", "bom-redo", "brew", "uninstall"):
        cmd = build_command(mode, files, os.path.expanduser("~/Applications"),
                            False, False, "")
        print("  %-9s -> %s" % (mode, cmd))
    return 0


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--smoketest" in sys.argv:
        return smoketest(files)

    import tkinter as tk
    from tkinter import filedialog, messagebox, scrolledtext, ttk

    rk = repkger_path()
    home = os.path.expanduser("~")

    root = tk.Tk()
    root.title("Repkger — rootless .pkg installer")
    try:
        root.tk_setPalette(background="#f5f5f7", foreground="#1d1d1f")
    except Exception:
        pass
    root.resizable(True, True)

    mode = tk.StringVar(value="install")
    target = tk.StringVar(value=os.path.join(home, "Applications"))
    run_scripts = tk.BooleanVar(value=False)
    home_rooted = tk.BooleanVar(value=False)
    only_prefix = tk.StringVar(value="")
    cask_var = tk.StringVar(value="")
    selected = []

    # ---- helpers (defined before the widgets that reference them) ------------
    def add_files():
        paths = filedialog.askopenfilenames(
            title="Choose installer package(s)",
            filetypes=[("Installer packages", "*.pkg *.mpkg *.dmg *.zip *.bundle"),
                       ("All files", "*.*")])
        for p in paths:
            if p not in selected:
                selected.append(p)
                listbox.insert(tk.END, p)
        refresh()

    def remove_sel():
        for i in reversed(listbox.curselection()):
            selected.pop(i)
            listbox.delete(i)
        refresh()

    def log(line):
        out.configure(state="normal")
        out.insert(tk.END, line + "\n")
        out.configure(state="disabled")
        out.see(tk.END)

    def run():
        if mode.get() in ("brew", "uninstall"):
            files_arg = [cask_var.get()]
        else:
            files_arg = list(selected)
        cmd = build_command(mode.get(), files_arg, target.get(),
                            run_scripts.get(), home_rooted.get(), only_prefix.get())
        if not cmd:
            messagebox.showerror("Repkger", "Nothing to do — pick a package / enter a cask name.")
            return
        log("$ " + " ".join(cmd))
        threading.Thread(target=_run, args=(cmd,), daemon=True).start()

    def _run(cmd):
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, bufsize=1)
            for line in proc.stdout:
                root.after(0, log, line.rstrip("\n"))
            proc.wait()
            root.after(0, log, "--- exit %d ---" % proc.returncode)
            if proc.returncode == 0:
                root.after(0, lambda: messagebox.showinfo("Repkger", "Done."))
        except Exception as e:
            root.after(0, log, "ERROR: %s" % e)
            root.after(0, lambda: messagebox.showerror("Repkger", str(e)))

    def refresh():
        is_brew = mode.get() in ("brew", "uninstall")
        if is_brew:
            cask_label.grid()
            cask_entry.grid()
        else:
            cask_label.grid_remove()
            cask_entry.grid_remove()
        listbox.config(state="disabled" if is_brew else "normal")

    # ---- mode selector -----------------------------------------------------
    frm_mode = ttk.LabelFrame(root, text="Action")
    frm_mode.grid(row=0, column=0, columnspan=2, sticky="ew", padx=10, pady=6)
    for txt, val in (("Install", "install"), ("Inspect", "inspect"),
                      ("BOM redo (preview)", "bom-redo"), ("Brew cask", "brew"),
                      ("Uninstall", "uninstall")):
        ttk.Radiobutton(frm_mode, text=txt, variable=mode, value=val,
                        command=refresh).grid(
            row=0, column=("install", "inspect", "bom-redo", "brew", "uninstall").index(val),
            padx=6)

    # ---- file list ---------------------------------------------------------
    frm_files = ttk.LabelFrame(root, text="Packages / target")
    frm_files.grid(row=1, column=0, columnspan=2, sticky="nsew", padx=10, pady=6)
    listbox = tk.Listbox(frm_files, height=6, selectmode=tk.EXTENDED)
    listbox.grid(row=0, column=0, columnspan=3, sticky="nsew", padx=4, pady=4)
    frm_files.columnconfigure(0, weight=1)

    ttk.Button(frm_files, text="Add…", command=add_files).grid(row=1, column=0, sticky="w", padx=4)
    ttk.Button(frm_files, text="Remove", command=remove_sel).grid(row=1, column=1, sticky="w")

    # cask name entry (brew/uninstall modes)
    cask_entry = ttk.Entry(frm_files, textvariable=cask_var)
    cask_label = ttk.Label(frm_files, text="Cask name (brew/uninstall):")
    cask_label.grid(row=3, column=0, columnspan=3, sticky="w", padx=4)
    cask_entry.grid(row=2, column=0, columnspan=3, sticky="ew", padx=4, pady=2)

    # ---- options -----------------------------------------------------------
    frm_opt = ttk.LabelFrame(root, text="Options")
    frm_opt.grid(row=2, column=0, columnspan=2, sticky="ew", padx=10, pady=6)
    ttk.Label(frm_opt, text="Target dir:").grid(row=0, column=0, sticky="w", padx=4)
    ttk.Entry(frm_opt, textvariable=target).grid(row=0, column=1, sticky="ew", padx=4)
    ttk.Button(frm_opt, text="Browse…",
               command=lambda: target.set(filedialog.askdirectory(initialdir=target.get()) or target.get())
               ).grid(row=0, column=2, padx=4)
    ttk.Checkbutton(frm_opt, text="Run pre/post-install scripts (--run-scripts)",
                    variable=run_scripts).grid(row=1, column=0, columnspan=3, sticky="w", padx=4)
    ttk.Checkbutton(frm_opt, text="Force every path to ~/ (--home-rooted)",
                    variable=home_rooted).grid(row=2, column=0, columnspan=3, sticky="w", padx=4)
    ttk.Label(frm_opt, text="--only prefix (optional):").grid(row=3, column=0, sticky="w", padx=4)
    ttk.Entry(frm_opt, textvariable=only_prefix).grid(row=3, column=1, columnspan=2, sticky="ew", padx=4)
    frm_opt.columnconfigure(1, weight=1)

    # ---- output log --------------------------------------------------------
    out = scrolledtext.ScrolledText(root, height=14, state="disabled")
    out.grid(row=3, column=0, columnspan=2, sticky="nsew", padx=10, pady=6)

    ttk.Button(root, text="Run repkger", command=run).grid(row=4, column=0, sticky="w", padx=10, pady=6)
    ttk.Button(root, text="Quit", command=root.destroy).grid(row=4, column=1, sticky="e", padx=10, pady=6)

    # preload dropped files (double-click / Finder drag-drop / "Open With")
    for p in files:
        if os.path.isfile(p):
            selected.append(p)
            listbox.insert(tk.END, p)
    refresh()
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
