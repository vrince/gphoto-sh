

# Bootstrap

## Setup goolgle project

* Select or create a projet from the google console https://console.cloud.google.com
* enable the Google Drive API
* Create a client OAuth2 named `gphoto-sh` for example
* Create a config file named `client.cfg` and populate it with :
  * Your `client_id` and `client_secret` from the client oauth page
  * Your `user_id`, go to https://get.google.com/albumarchive you'll be redirect to https://get.google.com/albumarchive/<user_id>

```bash
# ./client.cfg
client_id="xxxxxxxx-xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com"
client_secret="xxxxxxxxxxx-xxxxxxxxxxxxxx" 
user_id="123456789132456798123"
```

```bash
# ./path.cfg
nas_import_dir="/mnt/nas/Uploads"
import_dir=""
photo_root="/mnt/nas/Data/Photos"
video_root="/mnt/nas/Data/Videos"
photo_resized_root="/mnt/nas/Data/Photos_Resized"
```

## Dependencies

To install dependencies run `./bootstrap.sh` but before take a look inside, it will :

* download and install [parallel](https://www.gnu.org/software/parallel/).
* install `imagemagic` for the resize tool
* install `exif` to read image exif tags (`CreationDate`)
* install `xmlstarlet` to store readeable xml files

## Run

* During the first run a credential file will be created, follow link, login into you google account, and copy/paste code in the terminal, finally hit enter

## Upload validation

To check if your photos are really ending in you google photo account go there https://photos.google.com/u/2/search/_tra_ it will show recently added photos ...