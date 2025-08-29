FROM alpine

RUN apk add busybox-extras

RUN mkdir /server

WORKDIR /server

COPY index.html .

ENTRYPOINT ["httpd", "-f"]

