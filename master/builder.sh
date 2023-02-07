#!/bin/bash

# DONT FORGET TO LOGIN DOCKER
# aws ecr get-login-password --profile dev --region eu-west-2 | docker login --username AWS --password-stdin 032258715043.dkr.ecr.eu-west-2.amazonaws.com

IMAGE=032258715043.dkr.ecr.eu-west-2.amazonaws.com/master:latest

docker build --tag $IMAGE .
docker image push $IMAGE