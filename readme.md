

# Bootstrap

## Setup goolgle project

* Select or create a projet from the google console https://console.cloud.google.com
* Activate the `Google Drive API`
* Create an client OAuth2 named `gphoto-sh` for example
* Create a config file named `client.cfg` and populate it with :
  * Your `client_id` and `client_secret` from the google console client oauth
  * Your `user_id`, go to https://get.google.com/albumarchive you'll be redirect to https://get.google.com/albumarchive/<user_id>

```bash
# ./client.cfg
client_id="xxxxxxxx-xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com"
client_secret="xxxxxxxxxxx-xxxxxxxxxxxxxx" 
user_id="123456789132456798123"
```

## Dependencies

To install dependencies run `./bootstrap.sh` but before take a look inside, it will :

* download and install [parallel](https://www.gnu.org/software/parallel/).
* install `imagemagic` for the resize tool
* install `exif` to read image exif tags (`CreationDate`)
* install `xmlstarlet` to store readeable xml files

## Run

* During the first run a credential file will be created, follow link, login into you google account, and copy/paste code in the terminal, finally hit enter