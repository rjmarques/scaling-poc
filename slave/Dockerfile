FROM public.ecr.aws/docker/library/golang:1.19 AS build

WORKDIR /go/src/app

# copy go mod files and download depedencies
# do with as a seperate step to build to cache it
COPY go.mod go.sum ./
RUN go mod download

# copy the rest of the source files
COPY . .

RUN GOOS=linux GOARCH=amd64 go build -v -o /go/bin/slave .

# extract the binary alone from the build steps
# and place it in an easy to access folder
FROM scratch AS bin

COPY --from=build /go/bin/slave /

# runnable container
FROM public.ecr.aws/docker/library/debian:bullseye-slim

RUN apt-get update && apt-get install -y ca-certificates 

WORKDIR /home/

# copy artefacts over
COPY --from=bin /slave .

# run service
USER 1000
CMD ["/bin/bash", "-c", "./slave"]