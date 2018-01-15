

# Bootstrap

## Setup goolgle project

* Select or create a projet https://console.cloud.google.com
* Activate the `Google Drive API`
* Create an client OAuth2 named `gphoto-sh` for example
* copy/paste `client_id` and `client_secret` to `config.cfg` like this :

```
client_id="xxxxxxxx-xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com"
client_secret="xxxxxxxxxxx-xxxxxxxxxxxxxx" 
```

## Dependencies

To install dependencies run `sudo ./bootstrap` but before take a look inside, it will : 

* download and install [parallel](https://www.gnu.org/software/parallel/).
* install `imagemagic` for the resize tool
* install `exiftool` to read image exif tags (`CreationDate`) 

## Run

* During the first run a credential file will be created, follow link, login into you google account, and copy/paste code in the terminal, finally hit enter