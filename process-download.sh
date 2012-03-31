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
failfolder=$USER/Downloads/failed_to_add
export growlnotify hbcli

log() {
    logger -t "process-download.sh/log/$$" "$@"
    echo "$@" | $growlnotify -s "process-download"
}

notice() {
    logger -t "process-download.sh/notice/$$" "$@"
    echo "$@" | $growlnotify "process-download"
}

needs_encoding() {
    filexa=`xattr -p nu.dll.pd.added-to-itunes "$f" 2> /dev/null`
    expr "$1" : ".*.mkv$" > /dev/null || expr "$1" : ".*.avi$" > /dev/null && [ "$filexa" != "true" ] 
}

add_to_itunes() {
    mediafile="$1"
    filename=`basename "$mediafile"`
    friendlyname=`echo $filename | sed -e 's/\([^.]*\)\.[Ss]0*\([0-9][0-9]*\)[Ee]0*\([0-9][0-9]*\)*\..*/\1 season \2 episode \3/'|tr '.' ' '`
    season=`echo $friendlyname | sed -e 's/.*season \([0-9][0-9]*\).*/\1/'`
    if [ "$season" = "$friendlyname" ] ; then # no match
	season=""
    fi
    episode=`echo $friendlyname | sed -e 's/.*episode \([0-9][0-9]*\).*/\1/'`
    if [ "$episode" = "$friendlyname" ] ; then # no match
	episode=""
    fi

    showname=`echo $filename | sed -e 's/[sS][0-9]*[eE][0-9].*//' | tr '._' '  '`
    if [ -z "$showname" ] ; then
	showname="$friendlyname"
    fi
    echo "showname: $showname, season: $season, episode: $episode"
    notice "Adding $mediafile to iTunes library"
    cat <<EOF | osascript | logger -t "process-download.sh/osascript/$$" 2>&1
with timeout of (10*60) seconds
    set p to "$mediafile"
    set a to POSIX file p
    tell application "iTunes"
        launch
        set newTrack to (add a)
        tell newTrack to set video kind to TV show
        tell newTrack to set show to "$showname"
        tell newTrack to set season number to "$season"
        tell newTrack to set episode number to "$episode"
    end tell
end timeout
EOF
    rc=$?
    if [ $rc -eq 0 ] ; then
	log "$friendlyname added to iTunes"
	say "A new video was added to iTunes: $friendlyname"
    else
	log "Failed to add $mediafile to iTunes"
	mkdir -p "$failfolder"
	mv "$mediafile" "$failfolder" && notice "Moved `basename $mediafile` to $failfolder"
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
    tmpdir=`/usr/bin/mktemp -d -t process-downloads`
    outfile="${tmpdir}/`basename \"$outfile\"`"
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
	    add_to_itunes "$encodedfile" && \
		xattr -w nu.dll.pd.added-to-itunes true "$f"
	    rm "$encodedfile"
	else
	    log "Encoding failed for $f"
	fi 
    else
	if echo "$f" | grep -q '\.\(m4v\|mp4\)$' ; then
	    add_to_itunes "$f"
	else
	    notice "Nothing to do for file $f"
	fi
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
if [ "$1" = "--nofork" ] ; then
    shift
    for f; do
	process_entry "$f"
    done
else
    (
	for f; do
	    process_entry "$f"
	done
    ) >> /tmp/process-download-`id -u`.log 2>&1 &
fi