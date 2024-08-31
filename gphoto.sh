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

source_and_export () {
    source "$1"
    export $(cut -d= -f1 "$1")
}
export -f source_and_export

#config and credentials
export config_file=client.cfg
export credential_file=credential.cfg

if [ ! -f $config_file ]; then
   echo "$config_file does not exist, please setup google project dance (see readme.md)"
   exit 1
fi
source_and_export $config_file

#TODO add config for path
export target_image_size=3840 
import_dir="/mnt/nas/Uploads"
photo_root="/mnt/nas-2/Data/Photos"
video_root="/mnt/nas-2/Data/Videos"
photo_resized_root="/mnt/nas-2/Data/Photos_Resized"

image_ext_regex="\.JPG$|\.JPEG$|\.jpg$|\.jpeg$|\.GIF$|\.gif$"
video_ext_regex="\.MOV$|\.mov$|\.AVI$|\.avi$|\.3GP$|\.3gp$|\.mp4$|\.MP4$"
###

function check() {
    if ! which ${1} > /dev/null ; then
        echo "'${1}' not found"
        exit 1
    fi
}

function check_dependencies() {
    check parallel
    check imgp
    check exiftool
    check curl
}

function resize() {
    destination="$3"
    path_file="$1"
    filename=$(basename -- "$path_file")
    dest_file=${destination}/${filename}
    cp "${path_file}" "${dest_file}"

    # check if gif --> no resize just copy
    if test -e ${dest_file} -a $(file -b --mime-type ${dest_file}) = "image/gif"; then
        echo 'PNG file !'
    else
        echo "resizing ..."
        imgp --res $2x$2 --optimize --mute --overwrite --quality 82 "${destination}/${filename}"
    fi

    resize_output=$?
    if [ ${resize_output} -ne 0 ]; then
        mv "${path_file}" "${path_file}_"
    fi
}
export -f resize

function extract_original_date() {
    original_date=$(exiftool "$1" | grep "^Create Date" | head -n 1 | cut -d":" -f 2- | cut -d" " -f 2 | tr ":" "/")
    if [ -z "$original_date" ] ; then
        original_date=$(stat -c %y "$1" | cut -d" " -f 1 | tr "-" "/")
    fi
    echo $original_date
}
export -f extract_original_date

function import() {
    local image_file=$1
    local dest_root=$2

    local source_dir=$(dirname "$image_file")
    local source_name=$(basename "$image_file")

    #extract date firt from exif orginal date
    local original_date=$(extract_original_date "$image_file")

    local dest_dir="$dest_root/$original_date"
    local dest_name=$(echo $source_name | tr " " "_")
    local dest_file="$dest_dir/$dest_name"

    mkdir -p "$dest_dir"

    if [ ! -f "$dest_file" ] ; then 
        if cp "$image_file" "$dest_file"; then
            rm "$image_file"
        fi
    else
        rm "$image_file"
    fi
}
export -f import


function import_resize_upload() {
    local image_file=$1
    local dest_root=$2
    local resized_dest_root=$3

    local source_dir=$(dirname "$image_file")
    local source_name=$(basename "$image_file")

    #extract date firt from exif orginal date
    local original_date=$(extract_original_date "$image_file")

    local dest_dir="$dest_root/$original_date"
    local dest_name=$(echo $source_name | tr " " "_")
    local dest_file="$dest_dir/$dest_name"

    local resized_dest_dir="$resized_dest_root/$original_date"
    local resized_dest_file="$resized_dest_dir/$dest_name"

    local json_file="$resized_dest_file.json"

    mkdir -p "$dest_dir"

    # check if already done --> skip
    if [ -f "$json_file" ] ; then
        echo "💡 already imported"
        rm "$image_file"
        return
    fi

    cp "$image_file" "$dest_file"
    
    # chekc if no resized_dest_root --> we are done
    if [ -z ${resized_dest_root} ] ; then
        echo "💡 resized_dest_root"
        rm "$image_file"
        return
    fi

    mkdir -p "$resized_dest_dir"

    resize "$dest_file" $target_image_size "$resized_dest_dir"
    upload "$resized_dest_file"

    # stupid rate limiter to avoid hitting google WritePerMinute
    sleep 20

    if [ -f "$json_file" ] ; then
        rm "$image_file"
    fi
}
export -f import_resize_upload

#copy the following from some stack overflow answer ...
function google_auth() {
    if [ -s ${credential_file} ]; then
        # if we already have a token stored, use it
        source_and_export ${credential_file}
        time_now=`date +%s`
    else
        #scope="https://picasaweb.google.com/data/"
        scope="https://www.googleapis.com/auth/photoslibrary"
        # Form the request URL
        auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${client_id}&scope=${scope}&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob"

        echo "please go to:"
        echo
        echo "${auth_url}"
        echo
        echo "after accepting, enter the code you are given:"
        read auth_code

        # swap authorization code for access and refresh tokens
        auth_result=$(curl -s https://accounts.google.com/o/oauth2/token \
            -H "Content-Type: application/x-www-form-urlencoded" -d code=${auth_code} -d client_id=${client_id} -d client_secret=${client_secret} \
            -d redirect_uri=urn:ietf:wg:oauth:2.0:oob -d grant_type=authorization_code)

        access_token=$(echo -e "${auth_result}" | grep -Po '"access_token" *: *.*?[^\\]",' | awk -F'"' '{ print $4 }')
        refresh_token=$(echo -e "${auth_result}" | grep -Po '"refresh_token" *: *.*?[^\\]",*' | awk -F'"' '{ print $4 }')
        expires_in=$(echo -e "${auth_result}" | grep -Po '"expires_in" *: *.*' | awk -F' ' '{ print $3 }' | awk -F',' '{ print $1}')
        time_now=`date +%s`
        expires_at=$((time_now + expires_in - 60))

        if [ -z ${access_token} ] ; then
            echo "oauth failed: ${auth_result}"
            exit 1
        fi

        echo -e "access_token=\"${access_token}\"" > ${credential_file}
        echo -e "refresh_token=\"${refresh_token}\"" >> ${credential_file}
        echo -e "expires_at=${expires_at}" >> ${credential_file}
    fi

    # if our access token is expired, use the refresh token to get a new one
    if [ ${time_now} -gt ${expires_at} ]; then
        refresh_result=$(curl -s https://accounts.google.com/o/oauth2/token \
        -H "Content-Type: application/x-www-form-urlencoded" -d refresh_token=${refresh_token} -d client_id=${client_id} \
        -d client_secret=${client_secret} -d grant_type=refresh_token)
        access_token=$(echo -e "${refresh_result}" | grep -Po '"access_token" *: *.*?[^\\]",' | awk -F'"' '{ print $4 }')
        expires_in=$(echo -e "${refresh_result}" | grep -Po '"expires_in" *: *.*' | awk -F' ' '{ print $3 }' | awk -F',' '{ print $1 }')
        time_now=`date +%s`
        expires_at=$((${time_now} + ${expires_in} - 60))

        if [ -z ${access_token} ] ; then
            echo "refresh oauth failed: ${refresh_result}"
            exit 1
        fi

        echo -e "access_token=\"${access_token}\"" > ${credential_file}
        echo -e "refresh_token=\"${refresh_token}\"" >> ${credential_file}
        echo -e "expires_at=${expires_at}" >> ${credential_file}
    fi
}
export -f google_auth

function upload() {
    google_auth
    local image_file="$1"
    local source_name=$(basename "$image_file")
    local xml_file="$image_file.xml"
    local json_file="$image_file.json"

    if [ -f "$xml_file" ] ; then     
        echo "already upload($xml_file)"
        exit 0
    fi
    if [ -f "$json_file" ] ; then     
        echo "already upload($json_file)"
        exit 0
    fi

    upload_token_file=".upload_tokens"
    curl -s --request POST --data-binary "@${image_file}" \
    --header "Content-type: application/octet-stream" \
    --header "Authorization: Bearer ${access_token}" \
    --header "X-Goog-Upload-File-Name: ${source_name}" \
    --header "X-Goog-Upload-Protocol: raw" \
    https://photoslibrary.googleapis.com/v1/uploads > "${upload_token_file}"

    upload_token=$(cat ${upload_token_file})
    curl -s --request POST \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer ${access_token}" \
    --data '{"newMediaItems": [{"description": "'"${source_name}"'", "simpleMediaItem": {"uploadToken": "'"${upload_token}"'"}}]}' \
    https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate > "${json_file}"

    # do not keep response for file that are not properly uploaded
    if [[ ! -s "${json_file}" ]] ; then
        echo "🚨 fail to upload ${image_file} (empty)" 
        rm "${json_file}"
    fi
    if grep -E 'error' "${json_file}" ; then
        echo "🚨 fail to upload ${image_file} (contains error)" 
        mv "${json_file}" "${json_file}_error"
    fi
}
export -f upload

function import_all() {
    #find all files

    local images_to_import=".images_to_import"
    local videos_to_import=".videos_to_import"

    rm ${images_to_import}
    rm ${videos_to_import}

    find ${import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${image_ext_regex}" >> ${images_to_import}
    find ${import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${video_ext_regex}" >> ${videos_to_import}

    image_count=$(wc -l < ${images_to_import})
    video_count=$(wc -l < ${videos_to_import})
    echo "📸 image / 📹 video to import --> ${image_count} / ${video_count}"

    if [ -n "${skip_no_import}" ] && (( ${image_count} == 0 )) && (( ${video_count} == 0 )) ; then
        echo "nothing to import"
        exit 0
    fi

    import_arguments=".import_arguments"
    rm -f ${import_arguments}

    while IFS='' read -r image_file || [[ -n "${image_file}" ]]; do
        echo "${image_file}:${photo_root}:${photo_resized_root}" >> ${import_arguments}
    done < "${images_to_import}"

    while IFS='' read -r video_file || [[ -n "${video_file}" ]]; do
        echo "${video_file}:${video_root}" >> ${import_arguments}
    done < "${videos_to_import}"


    if [ -f "${import_arguments}" ] ; then
        echo "importing / resizing / uploading ..."
        cat ${import_arguments} | parallel --bar --eta --colsep ':' import_resize_upload {1} {2} {3}
    fi

    # remove empty directory left behind
    find ${import_dir} -depth -type d -empty -delete
}

# main sequence
date
check_dependencies
google_auth
import_all

echo "🎉 done"
exit 0
