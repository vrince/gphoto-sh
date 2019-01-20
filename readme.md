## Overview 

Bash script meant to back-up full size localy from multiple location / device and upload a 2048px copy to google photo to leverage online album creation.

### Back-up process :

1) Import location could be mounted sdcard or a network folder in sync your devices photo with some sync app (qnap / synology ...)
1) Photos will be imported (moved) to the `photo_root` directory like this `<photo_root>/<year>/<month>/<day>/<original_name.jpg>`. 
This scheme should avoid a lot of name conficts if using many devices but there is no garantee.
1) Photos will be resized and stored with the same exact scheme in `photo_resized_root`. Resize is done with `imagemagick` following this amazing [blog](https://www.smashingmagazine.com/2015/06/efficient-image-resizing-with-imagemagick/) of [David Newton](http://davidnewton.ca/).
1) Photos will be uploaded to google photo into the `Auto Backup` album and a copy of the `.xml` response of the picasaweb api is kept next to the resized image. 

> Those `.xml` file are the only way to get back **all** yours photos from google photo if needed. 

> Choice have being made to work with no db / no index / no nothing.


### Setup goolgle project / oauth

* Select or create a projet from the google console https://console.cloud.google.com
* Create a client OAuth2 named `gphoto-sh` for example
* Create a config file named `client.cfg` and populate it with :
  * Your `client_id` and `client_secret` from the client oauth page

```bash
# ./client.cfg
client_id="xxxxxxxx-xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com"
client_secret="xxxxxxxxxxx-xxxxxxxxxxxxxx"
```

### Setup root paths

```bash
# ./path.cfg
nas_import_dir="/mnt/nas/Uploads"
import_dir=""
photo_root="/mnt/nas/Data/Photos"
video_root="/mnt/nas/Data/Videos"
photo_resized_root="/mnt/nas/Data/Photos_Resized"
```

### Dependencies

To install dependencies run `./bootstrap.sh` but before take a look inside, it will :

* download and install [parallel](https://www.gnu.org/software/parallel/).
* install `imagemagic` for the resize tool
* install `exiftool` to read image exif tags (`CreationDate`)

### Run

    ./gphoto.sh -m push

> During the first run a credential file will be created, follow link, login into you google account, and copy/paste code in the terminal, finally hit enter.


### Service

List all jobs

```bash
# list jobs
atq

# remove a job
at -r <job-id>

# all jobs content
for job_id in $(atq | cut -f 1); do at -c "${job_id}"; done
```

### Upload validation

To check if your photos are really ending in you google photo account go there https://photos.google.com/u/2/search/_tra_ it will show recently added photos ...