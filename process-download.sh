#!/bin/bash

# A script for re-encoding mkv files into something that iTunes and Apple TV
# likes. Suitable for calling from a Folder Action in order to automatically
# encode and add new downloaded movies.
# Requires HandBrakeCLI:
#  http://handbrake.fr/downloads2.php
# Requires growlnotify (probably works without it):
#  http://growl.info/extras.php

# To make this script run automatically when a new file is downloaded,
# start Automator, select Folder Action, drag a "Run Shell Script" action
# to the flow. Set the contents of the Shell Script to the path of this
# file plus "$@" for all arguments, for example:
#     /Users/rasmus/bin/process-download.sh "$@"
# Change the "Pass input" dropdown to "as arguments" if it isn't set already.
# The Folder Action activates when saved.

# todo:
# * encode into temporary directory to avoid cluttering Downloads folder
# * do label_file_encoded without revealing the file in Finder (can interfere
#   if you're working with Finder at the moment)
# * check if the file already exists in iTunes library before adding it

growlnotify=/usr/local/bin/growlnotify
hbcli=/usr/local/bin/HandBrakeCLI
export growlnotify hbcli

log() {
    logger -t "process-download.sh/log" "$@"
    echo "$@" | $growlnotify -s "process-download"
}

notice() {
    logger -t "process-download.sh/notice" "$@"
    echo "$@" | $growlnotify "process-download"
}

needs_encoding() {
    filexa=`xattr -p nu.dll.pd.added-to-itunes "$f" 2> /dev/null`
    expr "$1" : ".*.mkv$" > /dev/null || expr "$1" : ".*.avi$" > /dev/null && [ "$filexa" != "true" ] 
}

add_to_itunes_and_delete() {
    mediafile="$1"
    notice "Adding $mediafile to iTunes library"
    cat <<EOF | osascript
with timeout of (10*60) seconds
    set p to "$mediafile"
    set a to POSIX file p
    tell application "iTunes"
        launch
        add a
    end tell
end timeout
EOF
    rc=$?
    if [ $rc -eq 0 ] ; then
	rm "$mediafile"
	log "$mediafile added to iTunes and deleted"
    else
	log "Failed to add $mediafile to iTunes"
	return $rc
    fi
}

label_file_encoded() {
    mediafile="$1"
    xattr -w nu.dll.pd.is-encoded true "$mediafile"
cat <<EOF | osascript
set f to POSIX file "$mediafile"
tell application "Finder"
    reveal f
    set s to selection
    set label index of first item of s to 6
end tell
EOF
}

encode_file() {
    infile="$1"
    encodedfile=""
    outfile=`echo "$infile" | sed -e 's/\.[0-9a-z]*$/.m4v/'`
    if [ -f "$outfile" ] ; then
	label_file_encoded "$f"
	log "Output file $outfile already exists - not re-encoding"
	encodedfile="$outfile"
	return 0
    fi
    notice "Encoding $infile to $outfile"
    # if HandBrakeCLI success, set $encodedfile to the resulting file
    $hbcli -i "$infile" -o "$outfile" -f mp4 --preset="Normal" > /tmp/handbrake.log.`date +%s`.$$ 2>&1 && encodedfile="$outfile"
}

process_file() {
    f="$1"
    if needs_encoding "$f" ; then
	notice "$f was downloaded and needs encoding"
	encode_file "$f"
	if [ "$encodedfile" ] ; then
	    notice "Encoding successful"
	    label_file_encoded "$f"
	    add_to_itunes_and_delete "$encodedfile" && \
		xattr -w nu.dll.pd.added-to-itunes true "$f"
	else
	    log "Encoding failed for $f"
	fi 
    else
	notice "Nothing to do for file $f" 
    fi
}

process_directory() {
    dir="$1"
    notice "Processing directory \"$dir\""
    for dirent in "$dir"/* ; do
	process_entry "$dirent"
    done
}

process_entry() {
    if [ -f "$1" ] ; then
	process_file "$1"
    elif [ -d "$1" ] ; then
	process_directory "$1"
    else
	log "Don't know what to do with \"$1\""
    fi
}

(
    for f; do
	process_entry "$f"
    done
) &
