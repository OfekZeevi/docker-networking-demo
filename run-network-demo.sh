#!/bin/bash

docker kill client-1 server-1
docker network rm demo-net

docker network create demo-net
docker run -d --rm -p 4000:80 --name server-1 --network demo-net demo-server
docker run -d --rm --name client-1 --network demo-net demo-client

