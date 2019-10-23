#! /bin/sh

set -e

cd $(dirname $0)/dockerfiles

export DOCKER_BUILDKIT=1

#SKIP_BUILD=true
#SKIP_DEPLOY=true

#--

enable_color() {
  ENABLECOLOR='-c '
  ANSI_RED="\033[31m"
  ANSI_GREEN="\033[32m"
  ANSI_YELLOW="\033[33m"
  ANSI_BLUE="\033[34m"
  ANSI_MAGENTA="\033[35m"
  ANSI_GRAY="\033[90m"
  ANSI_CYAN="\033[36;1m"
  ANSI_DARKCYAN="\033[36m"
  ANSI_NOCOLOR="\033[0m"
}

disable_color() { unset ENABLECOLOR ANSI_RED ANSI_GREEN ANSI_YELLOW ANSI_BLUE ANSI_MAGENTA ANSI_CYAN ANSI_DARKCYAN ANSI_NOCOLOR; }

enable_color

print_start() {
  if [ "x$2" != "x" ]; then
    COL="$2"
  elif [ "x$BASE_COL" != "x" ]; then
    COL="$BASE_COL"
  else
    COL="$ANSI_MAGENTA"
  fi
  printf "${COL}${1}$ANSI_NOCOLOR\n"
}

gstart () {
  print_start "$@"
}
gend () {
  :
}

if [ -n "$GITHUB_EVENT_PATH" ]; then
  export CI=true
fi

[ -n "$CI" ] && {
  gstart () {
    printf '::group::'
    print_start "$@"
    SECONDS=0
  }

  gend () {
    duration=$SECONDS
    echo '::endgroup::'
    printf "${ANSI_GRAY}took $(($duration / 60)) min $(($duration % 60)) sec.${ANSI_NOCOLOR}\n"
  }
} || echo "INFO: not in CI"

#--

case "$TRAVIS_COMMIT_MESSAGE" in
  *'[skip]'*)
    SKIP_BUILD=true
  ;;
esac
echo "SKIP_BUILD: $SKIP_BUILD"

#--

build_img () {
  gstart "[DOCKER build] $DREPO : ${DTAG}"
  DCTX="-"
  case "$1" in
    "--ctx"*)
    DCTX="-f- $(echo $1 | sed 's/--ctx=//g')"
    shift
    ;;
  esac
  printf "· ${ANSI_CYAN}File: ${ANSI_NOCOLOR}"
  echo "$DFILE"
  printf "· ${ANSI_CYAN}Ctx:  ${ANSI_NOCOLOR}"
  echo "$DCTX"
  printf "· ${ANSI_CYAN}Args: ${ANSI_NOCOLOR}"
  echo "$@"
  if [ "x$SKIP_BUILD" = "xtrue" ]; then
    printf "${ANSI_YELLOW}SKIP_BUILD...$ANSI_NOCOLOR\n"
  else
    docker build -t "ghdl/${DREPO}:$DTAG" "$@" $DCTX < $DFILE
  fi
  gend
}

build_debian_images () {
  for tag in mcode llvm gcc; do
    i="${ITAG}-$tag"
    if [ "x$tag" = "xllvm" ]; then i="$i-$LLVM_VER"; fi
    TAG="$d-$i" \
    DREPO="$d" \
    DTAG="$i" \
    DFILE="${d}_debian" \
    build_img \
    --target="$tag" \
    "$@"
  done
}

#--

create () {
  TASK="$1"
  VERSION="$2"
  case $TASK in
    ls)
      case "$VERSION" in
        debian)
          BASE_IMAGE="python:3-slim-buster"
          LLVM_VER="7"
          GNAT_VER="7"
          APT_PY=""
        ;;
        ubuntu)
          BASE_IMAGE="ubuntu:bionic"
          LLVM_VER="6.0"
          GNAT_VER="7"
          APT_PY="python3 python3-pip"
        ;;
      esac
      for img in build run; do
        TAG="ghdl/$img.ls-$VERSION" \
        DREPO="$img" \
        DTAG="ls-$VERSION" \
        DFILE=ls_debian_base \
        build_img \
        --target="$img" \
        --build-arg IMAGE="$BASE_IMAGE" \
        --build-arg LLVM_VER="$LLVM_VER" \
        --build-arg GNAT_VER="$GNAT_VER" \
        --build-arg APT_PY="$APT_PY"
      done
    ;;

    *)
      for d in build run; do
          case $TASK in

            "debian")
              case $VERSION in
                *stretch*)
                  LLVM_VER="4.0"
                  GNAT_VER="6"
                ;;
                *buster*)
                  LLVM_VER="7"
                  GNAT_VER="8"
                ;;
                *sid*)
                  LLVM_VER="8"
                  GNAT_VER="8"
                ;;
              esac
              ITAG="$VERSION"
              build_debian_images \
                --build-arg IMAGE="$TASK:$VERSION-slim" \
                --build-arg LLVM_VER="$LLVM_VER" \
                --build-arg GNAT_VER="$GNAT_VER"
            ;;

            "ubuntu")
              case $VERSION in
                14) #trusty
                  LLVM_VER="3.8"
                  GNAT_VER="4.6"
                ;;
                16) #xenial
                  LLVM_VER="3.9"
                  GNAT_VER="4.9"
                ;;
                18) #bionic
                  LLVM_VER="5.0"
                  GNAT_VER="7"
                ;;
              esac
              ITAG="ubuntu$VERSION"
              build_debian_images \
                --build-arg IMAGE="$TASK:$VERSION.04" \
                --build-arg LLVM_VER="$LLVM_VER" \
                --build-arg GNAT_VER="$GNAT_VER"
            ;;

            "fedora")
              for tgt in  mcode llvm gcc; do
                i="fedora${VERSION}-$tgt"
                TAG="$d-$i" DREPO="$d" DTAG="$i" DFILE="${d}_fedora" build_img --target="$tgt" --build-arg IMAGE="fedora:${VERSION}"
              done
            ;;
          esac
      done
    ;;
  esac
}

#--

cache() {
  case "$1" in
    gtkwave)
      DREPO=cache DTAG=gtkwave DFILE=cache_gtkwave build_img
    ;;
    pnr)
      for TAG in icestorm nextpnr; do
        DREPO=synth DTAG="$TAG" DFILE=cache_pnr build_img --target="$TAG"
      done
    ;;
    yosys)
      DREPO=synth DTAG=yosys DFILE=cache_yosys build_img --target=yosys
      DREPO=cache DTAG=yosys-gnat DFILE=cache_yosys build_img
    ;;
    formal)
      DREPO=cache DTAG=formal DFILE=cache_formal build_img --target=cache
    ;;
    symbiyosys)
      DREPO=synth DTAG=symbiyosys DFILE=cache_formal build_img
    ;;
    *)
      printf "${ANSI_RED}cache: unknown task $1!$ANSI_NOCOLOR\n"
      exit 1
    ;;
  esac
}

#--

extended() {
  case "$1" in
    synth)
      printf "${ANSI_MAGENTA}[Clone] tgingold/ghdlsynth-beta${ANSI_NOCOLOR}"
      mkdir -p ghdlsynth
      cd ghdlsynth
      curl -fsSL https://codeload.github.com/tgingold/ghdlsynth-beta/tar.gz/master | tar xzf - --strip-components=1
      printf "${ANSI_MAGENTA}[Run] ./travis.sh${ANSI_NOCOLOR}"
      ./travis.sh
      cd ..

      DREPO=synth DTAG="formal" DFILE=synth_formal build_img
    ;;
    vunit)
      export DOCKER_BUILDKIT=0
      for fulltag in buster-mcode buster-llvm-7 buster-gcc-8.3.0; do
        TAG="$(echo $fulltag | sed 's/buster-\(.*\)/\1/g' | sed 's/-.*//g' )"
        for version in stable master; do
          if [ "x$version" = "xmaster" ]; then
            TAG="$TAG-master"
          fi
          DREPO=vunit DTAG="$TAG" DFILE=vunit build_img --target="$version" --build-arg TAG="$fulltag"
        done
      done
    ;;
    gui)
      for TAG in ls-vunit latest; do
        DREPO=ext DTAG="$TAG" DFILE=gui build_img --target="$TAG"
      done
      TAG="broadway" DREPO=ext DTAG="broadway" DFILE=gui build_img --ctx=.. --target="broadway"
    ;;
    *)
      printf "${ANSI_RED}ext: unknown task $1!$ANSI_NOCOLOR\n"
      exit 1
    ;;
  esac
}

#--

language_server() {
  distro="$1"
  llvm_ver="7"
  if [ "x$distro" = "xubuntu" ]; then
    llvm_ver="6.0"
  fi
  TAG="ls-$distro" DREPO="ext" DTAG="ls-$distro" DFILE=ls_debian build_img --build-arg "DISTRO=$distro" --build-arg LLVM_VER=$llvm_ver
}

#--

deploy () {
  case $1 in
    "")
      FILTER="/ghdl /pkg";;
    "base")
      FILTER="/build /run";;
    "ext")
      FILTER="/ext";;
    "synth")
      FILTER="/synth";;
    "vunit")
      FILTER="/vunit";;
    "pkg")
      FILTER="/pkg:all";;
    *)
      FILTER="/";;
  esac

  echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin

  echo "IMAGES: $FILTER"
  docker images

  for key in $FILTER; do
    for tag in `echo $(docker images "ghdl$key*" | awk -F ' ' '{print $1 ":" $2}') | cut -d ' ' -f2-`; do
      if [ "$tag" = "REPOSITORY:TAG" ]; then break; fi
      i="`echo $tag | grep -oP 'ghdl/\K.*' | sed 's#:#-#g'`"
      gstart "[DOCKER push] ${tag}" "$ANSI_YELLOW"
      if [ "x$SKIP_DEPLOY" = "xtrue" ]; then
        printf "${ANSI_YELLOW}SKIP_DEPLOY...$ANSI_NOCOLOR\n"
      else
        docker push $tag
      fi
      gend
    done
  done

  docker logout
}

#--

build () {
  CONFIG_OPTS="--default-pic " ./dist/ci-run.sh -c "$@"

  if [ "$GITHUB_OS" != "macOS" ] && [ -f testsuite/test_ok ]; then
    IMAGE_TAG="$(docker images "ghdl/ghdl:*" | head -n2 | tail -n1 | awk -F ' ' '{print $2}')"
    gstart "[CI] Docker build ghdl/pkg:${IMAGE_TAG}"

    pwd
    ls -la

    docker build -t "ghdl/pkg:$IMAGE_TAG" . -f-<<EOF
FROM scratch
COPY `ls | grep -v '\.src\.' | grep '^ghdl.*\.tgz'` ./
COPY BUILD_TOOLS ./
EOF
    gend
  fi
}

#--

case "$1" in
  -c)
    shift
    create "$@"
  ;;
  -x)
    shift
    cache "$@"
  ;;
  -e)
    shift
    extended "$@"
  ;;
  -b)
    shift
    cd ../ghdl
    build "$@"
  ;;
  -l)
    shift
    language_server "$@"
  ;;
  *)
    deploy $@
esac
