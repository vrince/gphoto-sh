FROM debian:bookworm-slim
RUN apt update && apt install -y --no-install-recommends curl exiftool parallel nano imgp cron
ADD gphoto.sh .
RUN chmod +x gphoto.sh
RUN echo "*/1 * * * * root /gphoto.sh > /proc/1/fd/1 2>/proc/1/fd/2" >> /etc/crontab
ENTRYPOINT [ "cron", "-f" ]