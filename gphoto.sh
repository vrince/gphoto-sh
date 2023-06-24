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

sourceAndExport () {
    source "$1"
    export $(cut -d= -f1 "$1")
}
export -f sourceAndExport

export target_image_size=3840 

#config and credentials
export config_file=client.cfg
export credential_file=credential.cfg

if [ ! -f $config_file ]; then
   echo "$config_file does not exist, please setup google project dance (see readme.md)"
   exit 1
fi
sourceAndExport $config_file

#temporary index folder
export index_dir="./index"
mkdir -p $index_dir
rm $index_dir/*

#TODO add config for path
nas_import_dir="/mnt/nas/Uploads"
import_dir=""
photo_root="/mnt/nas/Data/Photos"
video_root="/mnt/nas/Data/Videos"
photo_resized_root="/mnt/nas/Data/Photos_Resized"

album_root="./albums"

image_ext_regex="\.JPG$|\.JPEG$|\.jpg$|\.jpeg$"
video_ext_regex="\.MOV$|\.mov$|\.AVI$|\.avi$|\.3GP$|\.3gp$|\.mp4$|\.MP4$"
###

#http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -i|--import)
        export import_dir="$2"
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
        -m|--mode)
        export mode="$2"
        echo "mode($mode)"
        shift
        ;;
        -s|--skip-no-import)
        export skip_no_import=yes
        echo "skip_no_import($skip_no_import)"
        ;;       
        --)
        shift
        break
        ;;
    esac
    shift # past argument or value
done

photo_root=${photo_root}
video_root=${video_root}
photo_resized_root=${photo_resized_root}

###

function check() {
    if ! which ${1} > /dev/null ; then
        echo "'${1}' not found"
        exit 1
    fi
}

function checkDependencies() {
    check parallel
    check mogrify
    check exiftool
    check curl
}

function resize() {
    destination="$3"
    path_file="$1"
    filename=$(basename -- "$path_file")
    cp "${path_file}" "${destination}/"
    #mogrify -path "${destination}" -filter Triangle -define filter:support=2 -resize $2x$2 -unsharp 0.25x0.08+8.3+0.045 \
    #-dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off -interlace none -colorspace sRGB "${path_file}" &> /dev/null
    imgp --res $2x$2 --optimize --mute --overwrite --quality 82 "${destination}/${filename}"
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
    local image_file=$1
    local dest_root=$2

    local source_dir=$(dirname "$image_file")
    local source_name=$(basename "$image_file")

    #extract date firt from exif orginal date
    local original_date=$(originalDate "$image_file")

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
export -f importFile


function importResizeUploadFile() {
    local image_file=$1
    local dest_root=$2
    local resized_dest_root=$3

    if [ -z "${resized_dest_root}" ] ; then
        importFile "${image_file}" "${dest_root}"
        return
    fi

    local source_dir=$(dirname "$image_file")
    local source_name=$(basename "$image_file")

    #extract date firt from exif orginal date
    local original_date=$(originalDate "$image_file")

    local dest_dir="$dest_root/$original_date"
    local dest_name=$(echo $source_name | tr " " "_")
    local dest_file="$dest_dir/$dest_name"

    local resized_dest_dir="$resized_dest_root/$original_date"
    local resized_dest_file="$resized_dest_dir/$dest_name"

    local json_file="$resized_dest_file.json"

    mkdir -p "$dest_dir"
    mkdir -p "$resized_dest_dir"

    # already done skip
    if [ -f "$json_file" ] ; then
        rm "$image_file"
        return
    fi

    cp "$image_file" "$dest_file"
    resize "$dest_file" $target_image_size "$resized_dest_dir"
    upload "$resized_dest_file"

    # stupid rate limiter to avoid hitting google WritePerMinute
    sleep 20

    if [ -f "$json_file" ] ; then
        rm "$image_file"
    fi
}
export -f importResizeUploadFile

#copy the following from some stack overflow answer ...
function googleAuth() {
    if [ -s ${credential_file} ]; then
        # if we already have a token stored, use it
        sourceAndExport ${credential_file}
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
export -f googleAuth

function resetGoogleAuth() {
    mv -f ${credential_file} ${credential_file}_bck
    googleAuth
}

function upload() {
    googleAuth
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

    upload_token_file="${index_dir}/upload_tokens"
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
        echo "fail to upload ${image_file} (empty)" 
        rm "${json_file}"
    fi
    if grep -E 'error' "${json_file}" ; then
        echo "fail to upload ${image_file} (contains error)" 
        mv "${json_file}" "${json_file}_error"
    fi
}
export -f upload

## Uploads
function uploadAll () {

    echo "extracting images list to upload ..."

    local available_images="${index_dir}/available_images"
    local uploaded_images="${index_dir}/uploaded_images"
    local upload_arguments="${index_dir}/to_upload_arguments"
    find ${photo_resized_root} -type f | grep -E "${image_ext_regex}" > ${available_images}
    find ${photo_resized_root} -type f | grep -E "\.(xml|json)$" | rev | cut -f 2- -d '.' | rev > $uploaded_images
    grep -Fxvf ${uploaded_images} ${available_images} | sort -rn > ${upload_arguments}

    echo "images available($(wc -l < ${available_images})) uploaded($(wc -l < ${uploaded_images})) => to upload($(wc -l < $upload_arguments))"

    if [ -s "${upload_arguments}" ] ; then 
        echo "uploading ..."
        cat ${upload_arguments} | parallel -j1 --bar --delay 10 --eta upload
    fi
}

function findUploadErrors () {
    local uploaded_errors="${index_dir}/uploaded_errors"
    find ${photo_resized_root} -name "*.json" | xargs grep -E 'error' -l > ${uploaded_errors}
    echo "upload errors($(wc -l < ${uploaded_errors}))"
    echo "to remove \"cat ${uploaded_errors} | xargs rm\""
}

function listAlbums () {
    echo "listing albums"
    local albums_json="${index_dir}/albums.json"
    googleAuth

    curl -s --request GET \
    --header "Authorization: Bearer ${access_token}" \
    https://photoslibrary.googleapis.com/v1/albums?pageSize=50 \
    > "$albums_json"

    #TODO get nextPageToken value until all albums are retreived
}

function downloadAlbum () {
    local album_id=${1}
    local album_json="$index_dir/album-${1}.json"
    googleAuth

    curl -s --request GET \
    --header "Authorization: Bearer ${access_token}" \
    https://photoslibrary.googleapis.com/v1/albums/${album_id} > "${album_json}"
}
export -f downloadAlbum

function downloadImage () {
    id=$1
    uri=$2
    timestamp=$(date -d@${3::-3} --iso=seconds) #remove last 3 char the ts --> date
    published=$(date -d$4 --iso=seconds)
    name=$5
    album_id=$(echo $id | cut -d/ -f 10)
    image_id=$(echo $id | cut -d/ -f 12)
    mkdir -p ./albums
    # quietly if not newer download to album directory
    wget -O ./albums/$published-$timestamp-$album_id-$image_id-$name -q -nc $uri
    exit 1
}
export -f downloadImage

function listUploadedItems () {
    #https://developers.google.com/photos/library/reference/rest/v1/mediaItems/list
    googleAuth
    uploaded_items="uploaded_items.json"
    current_items="current_items.json"
    items_count=0

    while true
    do
        curl -s --request GET \
        --header "Authorization: Bearer ${access_token}" \
        "https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=100&pageToken=${next_page_token}" > "${current_items}"

        length=$(cat ${current_items} | jq '.mediaItems | length')
        items_count=$((items_count + length))
        next_page_token=$(cat ${current_items} | jq -r .nextPageToken)
        cat ${current_items} | jq -r '.mediaItems | .[] | "\"\(.filename)\" \"\(.mimeType)\" \"\(.mediaMetadata.creationTime)\" \"\(.baseUrl)\""' >> ${uploaded_items}

        echo -ne "uploaded item listed(${items_count})\r"

        if [ -z ${next_page_token} ] ; then
            break
        fi
    done
}

function importAll() {
    #find all files

    local images_to_import="${index_dir}/images_to_import"
    local videos_to_import="${index_dir}/videos_to_import"

    #TODO make import argument an array/list and iterate on it
    if [ -n "${import_dir}" ] ; then 
        find ${import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${image_ext_regex}" > ${images_to_import}
        find ${import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${video_ext_regex}" > ${videos_to_import}
    fi

    find ${nas_import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${image_ext_regex}" >> ${images_to_import}
    find ${nas_import_dir} -type f | grep -v '@Recycle' | grep -v '.Trash' | grep -E "${video_ext_regex}" >> ${videos_to_import}

    image_count=$(wc -l < ${images_to_import})
    video_count=$(wc -l < ${videos_to_import})
    echo "image / video to import --> ${image_count} / ${video_count}"

    if [ -n "${skip_no_import}" ] && (( ${image_count} == 0 )) && (( ${video_count} == 0 )) ; then
        echo "nothing to import"
        exit 0
    fi

    import_arguments="${index_dir}/import_arguments"

    while IFS='' read -r image_file || [[ -n "${image_file}" ]]; do
        echo "${image_file}:${photo_root}:${photo_resized_root}" >> ${import_arguments}
    done < "${images_to_import}"

    while IFS='' read -r video_file || [[ -n "${video_file}" ]]; do
        echo "${video_file}:${video_root}" >> ${import_arguments}
    done < "${videos_to_import}"



    if [ -f "${import_arguments}" ] ; then
        if [[ "${mode}" == "push" ]] ; then
            echo "importing / resizing / uploading (delay 10 sec)..."
            # stupid 10 sec delay to avoid hitting write limit of google
            cat ${import_arguments} | parallel --bar --eta --delay 10 --colsep ':' importResizeUploadFile {1} {2} {3}
        else
            echo "importing ..."
            cat ${import_arguments} | parallel --bar --eta --colsep ':' importFile {1} {2}
        fi
    fi

    # remove empty directory left behind
    find ${nas_import_dir} -depth -type d -empty -delete
}

function resizeAndUploadOnlyImported() {
    echo "rezise & upload (only imported)..."
}

function resizeAll() {

    echo "extracting images list to resize ..."

    local images_index="${index_dir}/all_images"
    local resized_images_index="${index_dir}/all_resized_images"
    local images_to_resize="${index_dir}/images_to_resize"
    find ${photo_root} -type f -printf '%P\n' | grep -E "${image_ext_regex}"  | grep -v "(2)." > ${images_index}
    find ${photo_resized_root} -type f -printf '%P\n' | grep -E "${image_ext_regex}" > ${resized_images_index}
    grep -Fxvf ${resized_images_index} ${images_index} | sort -rn | awk -v p_root="${photo_root}/" '{print p_root $0}' > ${images_to_resize}

    echo "images to resize : $(wc -l < ${images_to_resize})"

    local resize_arguments="${index_dir}/resize_arguments"

    while IFS='' read -r image_file || [[ -n "${image_file}" ]]; do
        source_dir=$(dirname "${image_file}")
        relative_dir=${source_dir#$photo_root}
        source_name=$(basename "${image_file}")
        destination_dir="${photo_resized_root}${relative_dir}"
        mkdir -p "${destination_dir}"
        echo "${image_file}:${target_image_size}:${destination_dir}" >> ${resize_arguments}
    done < "${images_to_resize}"
    
    if [ -f "${resize_arguments}" ] ; then  
        echo "resizing ..."
        cat ${resize_arguments} | parallel -j 4 --bar --eta --colsep ':' resize {1} {2} {3}
    fi
}

date
checkDependencies

case "$mode" in
    auth)
        resetGoogleAuth
        ;;
    import)
        importAll
        ;;
    resize)
        resizeAll
        ;;
    upload)
        uploadAll
        ;;
    upload-errors)
        findUploadErrors
        ;;
    list-albums)
        listAlbums
        ;;
    list-uploaded-items)
        listUploadedItems
        ;;
    push)
        importAll
        ;;
    sync-all)
        importAll
        resizeAll
        uploadAll
        ;;
    *)
        echo "unknow mode"
        exit 1
esac

echo "done!!"
exit 0
