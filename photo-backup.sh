#!/bin/bash

#http://stackoverflow.com/questions/1715137/the-best-way-to-ensure-only-1-copy-of-bash-script-is-running
lockfile_="/var/lock/`basename $0`"
lockFD_=99

lock() { flock -$1 $lockFD_;}
noMoreLocking() { lock u; lock xn && rm -f $lockfile_;}
prepareLocking() { eval "exec $lockFD_>\"$lockfile_\""; trap noMoreLocking EXIT;}
echoLockedAndExit() { echo "locked($lockfile_)"; exit 1;}

prepareLocking

exlockNow() { lock xn;} # obtain an exclusive lock immediately or fail
exlock() { lock x;} # obtain an exclusive lock (wait for it)
shlock() { lock s;} # obtain a shared lock
unlock() { lock u;} # drop a lock

exlockNow || echoLockedAndExit

###
ceol=`tput el` # terminfo clr_eol

source config.sh

nas_import_dir="/mnt/nas/Uploads"
import_dir=""
photo_root="/mnt/nas/Data/Photos"
video_root="/mnt/nas/Data/Videos"
photo_resized_root="/mnt/nas/Data/Photos_Resized"
image_ext_regex="\.JPG$|\.JPEG$|\.jpg$|\.jpeg$"
video_ext_regex="\.MOV$|\.mov$|\.AVI$|\.avi$|\.3GP$|\.3gp$|\.mp4$|\.MP4$"
images_to_import_file=".images_to_import.txt"
videos_to_import_file=".videos_to_import.txt"
import_arguments=".import_arguments.txt"
images_to_resize_file=".images_to_resize.txt"
resize_arguments=".resize_arguments.txt"
target_image_size=2048
uploaded_files=".uploaded_files.txt"

###

#http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--import)
        import_dir="$2"
        if [ ! -d "$import_dir" ]; then
            echo "import directory($import_dir) does not exist"
            exit 1
        fi
        echo "import directory($import_dir)"
        shift
        ;;
        -v|--verbose)
        verbose_=yes
        echo "verbose($verbose_)"
        ;;
        -p|--progress)
        progress_=yes
        echo "progress($progress_)"
        ;;
        *)
        echo "unknown option($1)"
        exit 1
        ;;
    esac
    shift # past argument or value
done

###

function resize() {
    destination="$3"
    path_file="$1"
    mogrify -path "${destination}" -filter Triangle -define filter:support=2 -resize $2x$2 -unsharp 0.25x0.08+8.3+0.045 \
    -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off -interlace none -colorspace sRGB "${path_file}" &> /dev/null
    resize_output=$?
    if [ ${resize_output} -ne 0 ]; then
        mv "${path_file}" "${path_file}_"
    fi
}
export -f resize

function originalDate() {
    #original_date=$(identify -format '%[EXIF:*]' "$1" | grep "exif:DateTimeOriginal=" | cut -d"=" -f 2 | cut -d" " -f 1 | tr ":" "/")
    original_date=$(exiftool "$1" | grep "^Create Date" | head -n 1 | cut -d":" -f 2- | cut -d" " -f 2 | tr ":" "/")
    if [ -z "$original_date" ] ; then
        original_date=$(stat -c %y "$1" | cut -d" " -f 1 | tr "-" "/")
    fi
    echo $original_date
}
export -f originalDate

function importFile() {
    image_file=$1
    dest_root=$2

    source_dir=$(dirname "$image_file")
    source_name=$(basename "$image_file")

    #extract date firt from exif orginal date
    original_date=$(originalDate "$image_file")

    dest_dir="$dest_root/$original_date"
    dest_name=$(echo $source_name | tr " " "_")
    dest_file="$dest_dir/$dest_name"

    mkdir -p "$dest_dir"

    if [ ! -f "$dest_file" ] ; then 
        if cp "$image_file" "$dest_file"; then
            rm "$image_file"
        fi
    else
        rm "$image_file"
    fi
}
export -f importFile

function googleAuth() {
    if [ -s $my_creds ]; then
        # if we already have a token stored, use it
        source $my_creds
        time_now=`date +%s`
    else
        scope="https://picasaweb.google.com/data/"
        # Form the request URL
        # http://goo.gl/U0uKEb
        auth_url="https://accounts.google.com/o/oauth2/auth?client_id=$client_id&scope=$scope&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob"

        echo "Please go to:"
        echo
        echo "$auth_url"
        echo
        echo "after accepting, enter the code you are given:"
        read auth_code

        # swap authorization code for access and refresh tokens
        # http://goo.gl/Mu9E5J
        auth_result=$(curl -s https://accounts.google.com/o/oauth2/token \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d code=$auth_code \
            -d client_id=$client_id \
            -d client_secret=$client_secret \
            -d redirect_uri=urn:ietf:wg:oauth:2.0:oob \
            -d grant_type=authorization_code)
        access_token=$(echo -e "$auth_result" | \
                        grep -Po '"access_token" *: *.*?[^\\]",' | \
                        awk -F'"' '{ print $4 }')
        refresh_token=$(echo -e "$auth_result" | \
                        grep -Po '"refresh_token" *: *.*?[^\\]",*' | \
                        awk -F'"' '{ print $4 }')
        expires_in=$(echo -e "$auth_result" | \
                    grep -Po '"expires_in" *: *.*' | \
                    awk -F' ' '{ print $3 }' | awk -F',' '{ print $1}')
        time_now=`date +%s`
        expires_at=$((time_now + expires_in - 60))
        echo -e "access_token=$access_token\nrefresh_token=$refresh_token\nexpires_at=$expires_at" > $my_creds
    fi

    # if our access token is expired, use the refresh token to get a new one
    # http://goo.gl/71rN6V
    if [ $time_now -gt $expires_at ]; then
        refresh_result=$(curl -s https://accounts.google.com/o/oauth2/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d refresh_token=$refresh_token \
        -d client_id=$client_id \
        -d client_secret=$client_secret \
        -d grant_type=refresh_token)
        access_token=$(echo -e "$refresh_result" | \
                        grep -Po '"access_token" *: *.*?[^\\]",' | \
                        awk -F'"' '{ print $4 }')
        expires_in=$(echo -e "$refresh_result" | \
                    grep -Po '"expires_in" *: *.*' | \
                    awk -F' ' '{ print $3 }' | awk -F',' '{ print $1 }')
        time_now=`date +%s`
        expires_at=$(($time_now + $expires_in - 60))
        echo -e "access_token=$access_token\nrefresh_token=$refresh_token\nexpires_at=$expires_at" > $my_creds
    fi
}
export -f googleAuth

function upload() {
    googleAuth
    image_file="$1"
    source_name=$(basename "$image_file")
    db_file="$image_file.xml"
    if [ -f "$db_file" ] ; then     
        echo "already upload($db_file)"
    fi
    curl -s --request POST --data-binary "@$image_file" \
    --header "Content-Type: image/jpg" \
    --header "Authorization: Bearer $access_token" \
    --header "Slug: $source_name" \
    https://picasaweb.google.com/data/feed/api/user/$google_user_id/albumid/$google_album_id |
    xmlstarlet format --indent-spaces 2 > "$db_file" 
}
export -f upload

function progress() {
    if [ -z "$progress_" ]; then return ; fi
    let _progress=($1*100/$2*100)/100
    let _done=($_progress*4)/10
    let _left=40-$_done
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")
    shift 2
    printf "\r[${_fill// /#}${_empty// /-}] ${_progress}%% $@${ceol}"
}

## Uploads
function uploadAll () {
    available_images_file=".available_images.txt"
    uploaded_images_file=".uploaded_images.txt"
    to_upload_photos_file=".to_upload_images.txt"

    rm -f $to_upload_photos_file

    #all files
    echo "extracting all available images ..."
    find $photo_resized_root -type f | grep -E "$image_ext_regex" > $available_images_file
    echo "images available : $(wc -l < $available_images_file)"

    echo "extracting all uploaded images ..."
    find $photo_resized_root -type f | grep -E "\.xml$" | rev | cut -f 2- -d '.' | rev > $uploaded_images_file
    echo "images uploaded : $(wc -l < $uploaded_images_file)"

    echo "extracting difference ..."
    grep -Fxvf $uploaded_images_file $available_images_file | sort -rn > $to_upload_photos_file
    number_of_images_to_upload=$(wc -l < $to_upload_photos_file)
    echo "images to upload : $number_of_images_to_upload"

    if [ -f "$to_upload_photos_file" ] ; then 
        echo "uploading ..."
        cat $to_upload_photos_file | parallel --bar --eta upload
    fi
}

function importAll() {
    #find all files

    if [ -n "$import_dir" ] ; then 
        find $import_dir -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "$image_ext_regex" > $images_to_import_file
        find $import_dir -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "$video_ext_regex" > $videos_to_import_file
    fi

    find $nas_import_dir -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "$image_ext_regex" >> $images_to_import_file
    find $nas_import_dir -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "$video_ext_regex" >> $videos_to_import_file

    number_of_image_to_import=$(wc -l < $images_to_import_file)
    number_of_video_to_import=$(wc -l < $videos_to_import_file)

    echo "images to import : $number_of_image_to_import"
    echo "videos to import : $number_of_video_to_import"

    while IFS='' read -r image_file || [[ -n "$image_file" ]]; do
        echo "$image_file:$photo_root" >> $import_arguments
    done < "$images_to_import_file"

    while IFS='' read -r video_file || [[ -n "$video_file" ]]; do
        echo "$video_file:$video_root" >> $import_arguments
    done < "$videos_to_import_file"

    if [ -f "$import_arguments" ] ; then  
        echo "importing ..."
        cat $import_arguments | parallel --bar --eta --colsep ':' importFile {1} {2}
    fi
}

function resizeAll() {

    echo "extracting images list to resize ..."
    find $photo_root -type f -printf '%P\n' | grep -E "$image_ext_regex"  | grep -v "(2)." > all_images.list
    find $photo_resized_root -type f -printf '%P\n' | grep -E "$image_ext_regex" > all_resized_images.list
    grep -Fxvf all_resized_images.list all_images.list | sort -rn | awk -v p_root="$photo_root/" '{print p_root $0}' > $images_to_resize_file
    number_of_image_to_resize=$(wc -l < $images_to_resize_file)
    echo "images to resize : $number_of_image_to_resize"

    while IFS='' read -r image_file || [[ -n "$image_file" ]]; do
        source_dir=$(dirname "$image_file")
        relative_dir=${source_dir#$photo_root}
        source_name=$(basename "$image_file")
        destination_dir="$photo_resized_root$relative_dir"
        mkdir -p "$destination_dir"
        echo "$image_file:$target_image_size:$destination_dir" >> $resize_arguments
    done < "$images_to_resize_file"
    
    if [ -f "$resize_arguments" ] ; then  
        echo "resizing ..."
        cat $resize_arguments | parallel --bar --eta --colsep ':' resize {1} {2} {3}
    fi
}

#clean stuff
rm -f $images_to_import_file
rm -f $videos_to_import_file
rm -f $import_arguments
rm -f $images_to_resize_file
rm -f $resize_arguments

googleAuth
importAll
resizeAll
uploadAll
