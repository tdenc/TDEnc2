on open TDEnc2
	set args to ""
	repeat with droppedFile in TDEnc2
		set filePath to POSIX path of droppedFile
		set args to args & " \"" & filePath & "\""
	end repeat
	tell application "Finder"
		set appPath to parent of (path to current application) as text
		set unixPath to POSIX path of appPath & "tool/TDEnc2.sh"
	end tell
	tell application "Terminal"
		activate
		do script "\"" & unixPath & "\"" & args & ";exit"
	end tell
end open
	tell application "Finder"
		set appPath to parent of (path to current application) as text
		set unixPath to POSIX path of appPath & "tool/TDEnc2.sh"
	end tell
tell application "Terminal"
	activate
	do script "\"" & unixPath & "\";exit"
end tell