#!/bin/bash

### build KiCad docs in a Docker container with minimal hassle

_abort() {
  echo "ABORTING: $*" >&2
  exit 1
}

_go_to_top() {
  local top=""
  if ! top="$(git rev-parse --show-toplevel)" ; then
    _abort "can't find top of repository"
  fi
  if ! cd "$top" ; then
    _abort "can't move to top level of repository"
  fi
}

_have_builder_image() {
  docker images -q kicadeda/kicad-doc-builder-base \
    | grep -Eq '^[0-9a-f]+$'
}

_build_builder_image() {
  docker build \
    -t kicadeda/kicad-doc-builder-base:latest \
    -f utils/docker/Dockerfile.kicad-doc-builder-base \
    utils/docker
}

forks=4
formats=pdf
force_docker_build=no
while getopts "c:f:hR" arg ; do
  case "$arg" in
    c)
      forks="$OPTARG"
      if ! grep -Eq '^[0-9]+$' <<<"$forks" ; then
        _abort "-c option requires a numeric argument"
      fi
      ;;
    f)
      formats="$OPTARG"
      if [[ -z "$formats" ]] ; then
        _abort "-f option requires a semicolon-delimited list of file formats, eg. -f 'pdf;epub'"
      fi
      ;;
    R) force_docker_build=yes ;;
    *)
      (
        echo "usage: $0 [-c CONCURRENCY] [-f FORMATS] [-R]"
        echo
        echo 'options:'
        echo '  -c CONCURRENCY    build parallelism limit. Must be a number.   Default: 4'
        echo '  -f FORMATS        semicolon-separated list of file formats.    Default: pdf'
        echo '  -R                force rebuild of Docker base image.          Default: no'
      ) >&2
      status=0
      if [[ "$arg" != 'h' ]] ; then
        status=1
      fi
      exit "$status"
  esac
done

command -v git    > /dev/null || _abort "Git not available"
command -v docker > /dev/null || _abort "Docker not available?"

_go_to_top
if ! _have_builder_image || [[ "$force_docker_build" = 'yes' ]] ; then
  if ! _build_builder_image ; then
    _abort "unable to build builder base image"
  fi
fi

# at this point we're finally ready to build the docs
docker run \
  --interactive \
  --tty \
  --rm \
  --user=1000 \
  --volume "$(pwd):/src" \
  --workdir=/src/build \
  --env BUILD_FORMATS="$formats" \
  --env FORKS="$forks" \
  kicadeda/kicad-doc-builder-base \
  bash -c 'cmake -DBUILD_FORMATS="$BUILD_FORMATS" .. && make -j"$FORKS"'
