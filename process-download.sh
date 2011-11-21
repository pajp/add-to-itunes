#!/bin/bash

# A script for re-encoding mkv files into something that iTunes and Apple TV
# likes. Suitable for calling from a Folder Action in order to automatically
# encode and add new downloaded movies.
# Requires HandBrakeCLI:
#  http://handbrake.fr/downloads2.php
# Requires growlnotify:
#  http://growl.info/extras.php

# todo:
# * encode into temporary directory to avoid cluttering Downloads folder
# * do label_file_encoded without revealing the file in Finder (can interfere
#   if you're working with Finder at the moment)
# * check if the file already exists in iTunes library before adding it
# ** if m4v version already exists, add it to iTunes anyway

log() {
    logger -t "process-download.sh/log" "$@"
    echo "$@" | growlnotify -s "process-download"
}

notice() {
    logger -t "process-download.sh/notice" "$@"
    echo "$@" | growlnotify "process-download"
}

needs_encoding() {
    expr "$1" : ".*.mkv$" > /dev/null || expr "$1" : ".*.avi$" > /dev/null
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
    fi
}

label_file_encoded() {
    mediafile="$1"
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
	log "Output file $outfile already exists - aborting"
	return 1
    fi
    notice "Encoding $infile to $outfile"
    # if HandBrakeCLI success, set $encodedfile to the resulting file
    HandBrakeCLI -i "$infile" -o "$outfile" --preset="Apple TV 2" && encodedfile="$outfile"
}


for f; do
    if needs_encoding "$f" ; then
	notice "$f was downloaded and needs encoding"
	encode_file "$f"
	if [ "$encodedfile" ] ; then
	    notice "Encoding successful"
	    label_file_encoded "$f"
	    add_to_itunes_and_delete "$encodedfile"
	else
	    log "Encoding failed for $f"
	fi 
    else
	notice "Nothing to do for file $f" 
    fi
done
