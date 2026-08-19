-- Repkger.app — rootless macOS .pkg installer (no admin / sudo)
-- AppleScript droplet: drop .pkg / .mpkg files on the app icon to inspect
-- them (like Suspicious Package) and install them into ~/ — every install
-- path is re-mapped from / to the home directory.
--
-- Also usable headless (for automation / testing):
--   Repkger.app --install <pkg> [--home <dir>] [--data <dir>]
--   Repkger.app --inspect <pkg>
--   Repkger.app --cask <name> [--data <dir>]   (brew cask rootless install, --rpkg)

property cliName : "repkger"

-- locate the embedded CLI (Contents/Resources/repkger); fall back to PATH
on cliPath()
    set appPath to POSIX path of (path to me)
    set cand to appPath & "Contents/Resources/" & cliName
    if (do shell script "test -x " & quoted form of cand & " && echo yes || echo no") is "yes" then
        return cand
    end if
    return cliName
end cliPath

-- aliases (from `open`) vs plain paths (from --args) both arrive here
on normalizePath(x)
    try
        return POSIX path of x
    on error
        return (x as text)
    end try
end normalizePath

on run argv
    if argv is {} then
        my modeChooser()
        return
    end if
    set a1 to (item 1 of argv) as text
    if a1 is "--install" then
        if (count of argv) < 2 then error "usage: --install <pkg> [--home dir] [--data dir]"
        set pkgPath to (item 2 of argv) as text
        set homeRoot to ""
        set dataDir to ""
        if (count of argv) > 2 then
            set i to 3
            repeat while i ≤ (count of argv)
                set a to (item i of argv) as text
                if a is "--home" and (i + 1) ≤ (count of argv) then
                    set homeRoot to (item (i + 1) of argv) as text
                    set i to i + 2
                else if a is "--data" and (i + 1) ≤ (count of argv) then
                    set dataDir to (item (i + 1) of argv) as text
                    set i to i + 2
                else
                    set i to i + 1
                end if
            end repeat
        end if
        my doInstall(pkgPath, homeRoot, dataDir, "")
        return
    end if
    if a1 is "--inspect" then
        if (count of argv) < 2 then error "usage: --inspect <pkg>"
        my showInspect((item 2 of argv) as text)
        return
    end if
    if a1 is "--cask" then
        if (count of argv) < 2 then error "usage: --cask <name> [--data dir]"
        set caskName to (item 2 of argv) as text
        set dataDir to ""
        if (count of argv) > 2 then
            set i to 3
            repeat while i ≤ (count of argv)
                set a to (item i of argv) as text
                if a is "--data" and (i + 1) ≤ (count of argv) then
                    set dataDir to (item (i + 1) of argv) as text
                    set i to i + 2
                else
                    set i to i + 1
                end if
            end repeat
        end if
        my doCaskInstall(caskName, dataDir)
        return
    end if
    -- otherwise treat argv as dropped file paths
    my handleDrops(argv)
end run

on open droppedItems
    my handleDrops(droppedItems)
end open

on handleDrops(theItems)
    repeat with itemRef in theItems
        set p to my normalizePath(itemRef)
        set isPkg to (do shell script "test -f " & quoted form of p & " && echo yes || echo no")
        if isPkg is "no" then
            display dialog "Not a file I can read:" & linefeed & p buttons {"OK"} default button "OK" with title "Repkger" with icon caution
        else
            set c to button returned of (display dialog "What do you want to do with:" & linefeed & p & linefeed & linefeed & "Inspect = read the package like Suspicious Package (components, files, where each will land under ~/)." & linefeed & "Install = unpack it into your home directory — no admin, no sudo." buttons {"Cancel", "Inspect", "Install"} default button "Inspect" with title "Repkger" with icon note)
            if c is "Inspect" then
                my showInspect(p)
            else if c is "Install" then
                my doInstall(p, "", "", "")
            end if
        end if
    end repeat
end handleDrops

on modeChooser()
    -- NOTE: display dialog allows at most 3 buttons, so use a list for the
    -- 4+ modes (a 4-button dialog fails at runtime with -50).
    set options to {"Install a .pkg into your home directory", "Inspect a .pkg", "Uninstall an installed .pkg", "Install a brew cask (--rpkg, rootless)"}
    set pick to choose from list options with title "Repkger" with prompt "Repkger — rootless macOS .pkg installer (no admin, no sudo)." & linefeed & "Drop .pkg files on the app icon anytime." default items {item 1 of options} OK button name "Continue" cancel button name "Cancel"
    if pick is false then return
    set c to item 1 of pick
    if c contains "Uninstall" then
        my doUninstall()
        return
    end if
    if c contains "brew cask" then
        my doCaskPrompt()
        return
    end if
    set pkgs to my choosePkgs()
    if pkgs is {} then return
    set n to (count of pkgs)
    if c contains "Inspect" then
        repeat with p in pkgs
            my showInspect(p)
        end repeat
    else
        set i to 0
        repeat with p in pkgs
            set i to i + 1
            if n > 1 then
                set label to ("(" & (i as text) & " of " & (n as text) & ") " & (do shell script "basename " & quoted form of p))
                my doInstall(p, "", "", label)
            else
                my doInstall(p, "", "", "")
            end if
        end repeat
    end if
end modeChooser

-- multi-select open dialog; returns a list of POSIX paths ({} if cancelled)
on choosePkgs()
    try
        set f to choose file with prompt "Choose one or more installer packages (.pkg / .mpkg)" default location (path to downloads folder) multiple selections allowed true
        set out to {}
        repeat with itemRef in f
            set end of out to POSIX path of itemRef
        end repeat
        return out
    on error
        return {}
    end try
end choosePkgs

-- Suspicious Package-style inspection: components, scripts, and the first N
-- BOM entries with their home-mapped destinations
on showInspect(p)
    set cli to my cliPath()
    try
        set out to do shell script (quoted form of cli & " inspect --files 20 " & quoted form of p)
    on error errMsg
        display dialog "Could not inspect:" & linefeed & p & linefeed & linefeed & errMsg buttons {"OK"} default button "OK" with title "Repkger" with icon stop
        return
    end try
    set titleTxt to (do shell script "basename " & quoted form of p)
    set summary to out
    if (length of out) > 3000 then set summary to (text 1 thru 3000 of out) & "…"
    set c to button returned of (display dialog summary buttons {"Cancel", "Full Report", "Install"} default button "Install" with title "Repkger — " & titleTxt)
    if c is "Full Report" then
        try
            set tmp to (do shell script "mktemp /tmp/repkger-report.XXXXXX.txt")
            do shell script "cat > " & quoted form of tmp & " <<'REPKGER_EOF'" & linefeed & out & linefeed & "REPKGER_EOF"
            do shell script "open " & quoted form of tmp
            set again to button returned of (display dialog "Full report opened in TextEdit." & linefeed & "Install " & titleTxt & " into your home directory?" buttons {"No", "Yes"} default button "Yes" with title "Repkger")
            if again is "Yes" then my doInstall(p, "", "", "")
        on error
            display dialog "Could not open the report." buttons {"OK"} default button "OK" with title "Repkger"
        end try
    else if c is "Install" then
        my doInstall(p, "", "", "")
    end if
end showInspect

on doInstall(p, homeRoot, dataDir, progressLabel)
    set cli to my cliPath()
    if homeRoot is "" then set homeRoot to (do shell script "echo $HOME")
    set envPrefix to ""
    if dataDir is not "" then set envPrefix to "REPKGER_DATA=" & quoted form of dataDir & " "
    set cmd to envPrefix & quoted form of cli & " install " & quoted form of p & " --home " & quoted form of homeRoot & " --yes"
    if progressLabel is not "" then
        display notification "Installing " & progressLabel & "…" with title "Repkger"
    end if
    try
        with timeout of 3600 seconds
            do shell script cmd
        end timeout
        if progressLabel is not "" then
            display notification "Installed " & progressLabel with title "Repkger"
        else
            display notification "Installed into your home directory (no admin needed)" with title "Repkger" subtitle (do shell script "basename " & quoted form of p)
        end if
    on error errMsg
        display dialog "Install failed:" & linefeed & p & linefeed & linefeed & errMsg buttons {"OK"} default button "OK" with title "Repkger" with icon stop
    end try
end doInstall

-- ask for a cask name, then install it via `repkger brew … --rpkg` (rootless,
-- never brew's pkg installer / sudo)
on doCaskPrompt()
    try
        set caskName to text returned of (display dialog "Install a brew cask whose artifact is a .pkg — rootlessly, no installer, no sudo (repkger brew install --cask --rpkg <name>):" default answer "" buttons {"Cancel", "Install Cask"} default button "Install Cask" with title "Repkger — cask (--rpkg)" with icon note)
    on error
        return
    end try
    if caskName is not "" then my doCaskInstall(caskName, "")
end doCaskPrompt

on doCaskInstall(caskName, dataDir)
    set cli to my cliPath()
    set envPrefix to ""
    if dataDir is not "" then set envPrefix to "REPKGER_DATA=" & quoted form of dataDir & " "
    set cmd to envPrefix & quoted form of cli & " brew install --cask --rpkg " & quoted form of caskName
    display notification "Installing cask " & caskName & " — rootless (--rpkg), no sudo" with title "Repkger"
    try
        with timeout of 3600 seconds
            do shell script cmd
        end timeout
        display notification "Installed cask " & caskName & " rootlessly (--rpkg)" with title "Repkger"
    on error errMsg
        display dialog "Cask install failed:" & linefeed & caskName & linefeed & linefeed & errMsg buttons {"OK"} default button "OK" with title "Repkger" with icon stop
    end try
end doCaskInstall

on doUninstall()
    set cli to my cliPath()
    try
        set out to do shell script (quoted form of cli & " list")
        set name to text returned of (display dialog "Installed records:" & linefeed & linefeed & out & linefeed & linefeed & "Enter the package name or record to uninstall:" default answer "" buttons {"Cancel", "Uninstall"} default button "Uninstall" with title "Repkger")
    on error
        return
    end try
    if name is not "" then
        try
            with timeout of 600 seconds
                do shell script (quoted form of cli & " uninstall " & quoted form of name & " --yes")
            end timeout
            display notification "Uninstalled" with title "Repkger"
        on error errMsg
            display dialog "Uninstall failed:" & linefeed & errMsg buttons {"OK"} default button "OK" with title "Repkger" with icon stop
        end try
    end if
end doUninstall
