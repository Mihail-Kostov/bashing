#!/bin/bash
export __BASHING_VERSION='0.1.0-alpha6'
export __VERSION='0.1.0-alpha6'
export __ARTIFACT_ID='bashing'
export __GROUP_ID='bashing'
BASHING_ROOT=$(cd "$(dirname "$0")" && pwd)
BASHING_VERSION="$__VERSION"
BASHING_PROJECT_FILE="bashing.project"
CWD=$(pwd)
PROJECT_ROOT=$(pwd)
case "$1" in
    "compile"|"uberbash"|"run")
        while [ -d "$PROJECT_ROOT" ]; do
            if [ -e "$PROJECT_ROOT/$BASHING_PROJECT_FILE" ]; then break; fi
            PROJECT_ROOT="$PROJECT_ROOT/.."
        done
        if [ ! -d "$PROJECT_ROOT" ]; then
            echo "Could not find Root Directory of this Project!" 1>&2
            exit 1;
        fi
        PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd);
    ;;
esac
PROJECT_FILE="$PROJECT_ROOT/$BASHING_PROJECT_FILE"
SRC_PATH="$PROJECT_ROOT/src"
CLI_PATH="$SRC_PATH/tasks"
LIB_PATH="$SRC_PATH/lib"
HID_PATH="$SRC_PATH/hidden-tasks"
function print_out() {
    if [ -z "$OUT" ]; then
        echo "$@";
    else
        echo "$@" >> "$OUT"
    fi
}
function redirect_out() {
    local line=""
    while IFS='' read -r line; do
        print_out "$line";
    done
}
function sep() { 
    if [[ "$COMPACT" != "yes" ]]; then
        print_out -n "# ";  
        print_out "$(head -c 45 /dev/zero | tr '\0' '-')"; 
    fi
}
function comment() { 
    if [[ "$COMPACT" != "yes" ]]; then print_out "# $@"; fi; 
}
function nl() { 
    if [[ "$COMPACT" != "yes" ]]; then print_out ""; fi; 
}
function includeBashFile() {
    if [ -s "$1" ] && bash -n "$1"; then
        if [[ "$COMPACT" != "yes" ]]; then echo "# $1"; fi; 
        sed '/^\s*#.*$/d' "$1" | sed '/^\s*$/d';
    fi
}
function generateHeader() {
    print_out "#!/bin/bash"
    sep
    comment " Artifact:     $GROUP_ID/$ARTIFACT_ID"
    comment " Version:      $ARTIFACT_VERSION"
    comment " Date (UTC):   $(date -u)"
    comment " Generated by: bashing $BASHING_VERSION"
    sep
}
function generateMetadata() {
    print_out "export __BASHING_VERSION='$BASHING_VERSION'"
    print_out "export __VERSION='$ARTIFACT_VERSION'"
    print_out "export __ARTIFACT_ID='$ARTIFACT_ID'"
    print_out "export __GROUP_ID='$GROUP_ID'"
    sep
}
function genInclude() {
    if [ -s "$SRC_PATH/$1" ]; then
        cd "$SRC_PATH"
        debug "Including File    ./$1 ..."
        includeBashFile "./$1" | redirect_out
        sep
        cd "$CWD"
    fi
}
function includeLibFile() {
    local path=""
    while read -r path; do
        local fullPath=$(cd "$SRC_PATH/$(dirname "$path")" && pwd)/$(basename "$path");
        if bash -n "$fullPath" 1> /dev/null; then
            debug "Including Library $path ..."
            includeBashFile "$path" | redirect_out
            nl
        else
            return 1;
        fi
    done
    return 0
}
function generateLibrary() {
    comment "Library"
    nl
    cd "$SRC_PATH";
    find "./lib" -type f -name "*.sh" | includeLibFile
    if [[ "$?" != "0" ]]; then exit 1; fi
    sep
    cd "$CWD";
}
function collectCliScripts() {
    if [ -d "$CLI_PATH" ]; then
        cd "$CLI_PATH"
        find "." -type f -name "*.sh"
        cd "$CWD"
    fi
    if [ -d "$HID_PATH" ]; then
        cd "$HID_PATH"
        find "." -type f -name "*.sh"
        cd "$CWD"
    fi
}
function toFn() {
    local n="$1"
    echo "cli_${n:2:-3}" | tr '/' '_' | sed 's/_+/_/g'
}
function toCliArg() {
    local n="$1"
    echo "${n:2:-3}" | tr '/' '.'
}
function includeCliFn() {
    local path="$1"
    local fnName=$(toFn "$path");
    local fullPath="$CLI_PATH/$path"
    local hidden="no"
    if [ -e "$fullPath" ] && [ -e "$HID_PATH/$path" ]; then
        fatal "Task and hidden Task of the same name: $path"
    else if [ -e "$HID_PATH/$path" ]; then
        local fullPath="$HID_PATH/$path";
        local hidden="yes"
    fi; fi
    if [[ "$fnName" == "cli_help" ]] && [[ "$BUILD_HELP" == "yes" ]]; then
        echo "WARN: CLI Function 'help' ($fullPath) overwrite built-in help." 1>&2;
        echo "WARN: Supply '--no-help' if you want to create your own help function." 1>&2;
    fi
    if bash -n "$fullPath" 1> /dev/null; then
        if [[ "$hidden" == "no" ]]; then debug "Including Task    $path -> $fnName ..."; comment "./tasks/${path:2}";
        else debug "Including Task    $path -> $fnName (hidden) ..."; comment "./hidden-tasks/${path:2}"; fi
        print_out "function ${fnName}() {"
        includeBashFile "$fullPath" | sed 's/^/  /g' | redirect_out
        print_out "}"
        return 0;
    fi
    return 1;
}
function buildCliHandler() {
    local path="$1"
    local fnName=$(toFn "$path")
    local argName=$(toCliArg "$path")
    print_out "    \"$argName\")"
    print_out "      $fnName \"\$@\" &"
    print_out '      local pid="$!"'
    print_out '      ;;'
}
function buildCliHeader() {
    print_out "function __run() {"
    print_out '  local pid=""'
    print_out '  local status=255'
    print_out '  local cmd="$1"'
    print_out '  shift'
    print_out '  case "$cmd" in'
    print_out '    "")'
    print_out '      __run "help";'
    print_out '      return $?'
    print_out '      ;;'
}
function buildCliFooter() {
    print_out '    *)'
    print_out '      echo "Unknown Command: $cmd" 1>&2;'
    print_out '      ;;'
    print_out '  esac'
    print_out '  if [ ! -z "$pid" ]; then'
    print_out '      wait "$pid"'
    print_out '      local status=$?'
    print_out '  fi'
    print_out '  return $status'
    print_out "}"
}
function buildHelpTable() {
    local hlp="yes"
    local vrs="yes"
    for path in $@; do
        if [ ! -e "$HID_PATH/$path" ]; then
            local argName=$(toCliArg "$path");
            echo "$argName|:|(no help available)"
            case "$argName" in
                "help") local hlp="no";;
                "version") local vrs="no";;
            esac
        fi
    done
    if [ "$hlp" == "yes" ]; then echo "help|:|display this help message"; fi
    if [ "$vrs" == "yes" ]; then echo "version|:|display version"; fi
}
function buildHelpFunction() {
    print_out '    "help")'
    print_out '      echo "Usage: $0 <command> [<parameters> ...]" 1>&2'
    print_out '      cat 1>&2 <<HELP'
    print_out ''
    buildHelpTable "$@" | column -s "|" -t\
        | sort\
        | sed 's/^/    /'\
        | redirect_out
    print_out ''
    print_out 'HELP'
    print_out '      status=0'
    print_out '      ;;'
}
function buildVersionFunction() {
    print_out '    "version")'
    print_out "      echo \"$ARTIFACT_ID $ARTIFACT_VERSION (bash \$BASH_VERSION)\""
    print_out '      status=0'
    print_out '      ;;'
}
function generateCli() {
    cliScripts=$(collectCliScripts);
    set -e
    comment "CLI Functions"
    nl
    for path in $cliScripts; do includeCliFn "$path"; done
    sep
    comment "Main Function"
    nl
    buildCliHeader
    for path in $cliScripts; do buildCliHandler "$path"; done
    if [[ "$BUILD_HELP" == "yes" ]]; then buildHelpFunction "$cliScripts"; fi
    buildVersionFunction
    buildCliFooter
    print_out "__run \"\$@\""
    print_out 'export __STATUS="$?"'
    sep
    cd "$CWD";
}
function generateCliExit() {
    print_out 'exit $__STATUS'
}
function generateStandaloneTask() {
    local task="$1"
    COMPACT="yes"
    OUT=""
    DEBUG="no"
    VERBOSE="no"
    generateHeader
    generateMetadata
    genInclude "init.sh"
    generateLibrary
    genInclude "before-task.sh"
    print_out 'shift'
    print_out 'function __run() { echo "__run not available when running CLI task directly!" 1>&2; exit 1; }'
    genInclude "cli/$task"
    genInclude "after-task.sh"
    genInclude "cleanup.sh"
}
RED="`tput setaf 1`"
GREEN="`tput setaf 2`"
YELLOW="`tput setaf 3`"
BLUE="`tput setaf 4`"
MAGENTA="`tput setaf 5`"
CYAN="`tput setaf 6`"
WHITE="`tput setaf 7`"
RESET="`tput sgr0`"
function colorize() {
    if [[ "$USE_COLORS" != "no" ]]; then
        c="$1"
        shift
        echo -n ${c}${@}${RESET};
    else
        shift
        echo -n "$@";
    fi
}
function green() { colorize "${GREEN}" "${@}"; }
function red() { colorize "${RED}" "${@}"; }
function yellow() { colorize "${YELLOW}" "${@}"; }
function blue() { colorize "${BLUE}" "${@}"; }
function magenta() { colorize "${MAGENTA}" "${@}"; }
function cyan() { colorize "${CYAN}" "${@}"; }
function white() { colorize "${WHITE}" "${@}"; }
RX_ID='[a-zA-Z][a-zA-Z0-9_-]*'
RX_INT='\(0\|[1-9][0-9]*\)'
RX_VERSION="$RX_INT\\.$RX_INT\\.$RX_INT\(-$RX_ID\\)\\?"
RX_ARTIFACT_STRING="^\\s*\\(\\($RX_ID\\)\\/\\)\\?\\($RX_ID\\)\\s\\+\\($RX_VERSION\\)\\s*$"
function artifactString() { head -n 1 "$PROJECT_FILE"; }
function artifactGet() { echo "$1" | sed -n "s/$RX_ARTIFACT_STRING/\\$2/p"; }
function artifactVersion() { artifactGet "$1" 4; }
function artifactId() { artifactGet "$1" 3; }
function artifactGroupId() { artifactGet "$1" 2; }
function error() {
    echo -n "$(red "(ERROR) ") " 1>&2
    echo "$@" 1>&2
}
function fatal() {
    error "$@";
    exit 1;
}
function success() {
    echo "$(green "$@")"
}
function verbose() {
    if [[ "$VERBOSE" != "no" ]] || [ -z "$VERBOSE" ]; then
        echo "$@" 
    fi
}
function debug() {
    if [[ "$DEBUG" == "yes" ]]; then
        echo -n "$(yellow "(DEBUG)  ")";
        echo "$@";
    fi
}
GROUP_ID=""
ARTIFACT_ID=""
ARTIFACT_VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        "--debug")
            DEBUG="yes"
            shift
            ;;
        "compile"|"uberbash"|"run")
            s=$(artifactString)
            GROUP_ID=$(artifactGroupId "$s")
            ARTIFACT_ID=$(artifactId "$s")
            ARTIFACT_VERSION=$(artifactVersion "$s")
            if [ -z "$ARTIFACT_ID" -o -z "$ARTIFACT_VERSION" ]; then 
                error "Invalid Artifact String in $BASHING_PROJECT_FILE: $s";
                exit 1;
            fi
            if [ -z "$GROUP_ID" ]; then GROUP_ID="$ARTIFACT_ID"; fi
            debug "Artifact: $ARTIFACT_ID"
            debug "Group ID: $GROUP_ID"
            debug "Version:  $ARTIFACT_VERSION"
            debug "Root:     $PROJECT_ROOT"
            break;;
        *) break;;
    esac
done
function cli_run() {
  CLI="$1"
  if [ -z "$CLI" ]; then
      error "Usage: run <CLI Command> <Parameters>"
      exit 1;
  fi
  SRC="$(echo "$CLI" | tr '.' '/').sh"
  if [ ! -e "$CLI_PATH/$SRC" ]; then
      error "No such CLI File: $SRC"
      exit 1
  fi
  generateStandaloneTask "$SRC" | bash -s "$@" &
  wait "$!"
  st="$?"
  exit "$st"
}
function cli_init() {
  ARTIFACT="$1"
  INIT_PATH="$2"
  if [ -z "$ARTIFACT" ]; then
      error "Usage: init <Artifact ID> [<Path>]"
      exit 1;
  fi
  if [ -z "$INIT_PATH" ]; then INIT_PATH="./$ARTIFACT"; fi
  if [ -d "$INIT_PATH" ]; then
      error "$INIT_PATH already exists.";
      exit 1;
  fi
  echo "Initializing $INIT_PATH ..."
  if ! mkdir -p "$INIT_PATH/src/cli" || ! mkdir -p "$INIT_PATH/src/lib"; then
      error "Could not create Directories 'src/cli' and 'src/lib'."
      exit 1;
  fi
  if ! touch "$INIT_PATH/.gitignore"; then
      error "Could not create '.gitignore'."
      exit 1;
  fi
  for txt in "target/" "*.swp" "*~"; do
      echo "$txt" >> "$INIT_PATH/.gitignore"
  done
  if ! touch "$INIT_PATH/bashing.project"; then
      error "Could not creat 'bashing.project'."
      exit 1;
  fi
  echo "$ARTIFACT 0.1.0-SNAPSHOT" >> "$INIT_PATH/bashing.project"
  h="$INIT_PATH/src/cli/hello.sh";
  if touch "$h"; then
      echo "#!/bin/bash" > "$h"
      echo "" >> "$h"
      echo "# Run this Script with:" >> "$h"
      echo "#" >> "$h"
      echo "#   bashing run hello" >> "$h"
      echo "" >> "$h"
      echo 'echo "Hello World!"' >> "$h"
  fi
  success "Successfully initialized '$INIT_PATH'."
  exit 0
}
function cli_uberbash() {
  TARGET_PATH="$PROJECT_ROOT/target"
  TARGET_FILE="$TARGET_PATH/$ARTIFACT_ID-$ARTIFACT_VERSION.sh"
  if ! mkdir -p "$TARGET_PATH" 2> /dev/null; then
      error "Could not create target directory: $TARGET_PATH";
      exit 1;
  fi
  echo "Creating $TARGET_FILE ..."
  __run "compile" "--compact" -o "$TARGET_FILE"
  if [[ "$?" != "0" ]]; then
      error "An Error occured while running task 'compile'."
      exit 1;
  fi
  chmod +x "$TARGET_FILE" >& /dev/null
  success "Uberbash created successfully."
  exit 0
}
function cli_compile() {
  BUILD_HEADER="yes"
  BUILD_METADATA="yes"
  BUILD_LIBRARY="yes"
  BUILD_CLI="yes"
  BUILD_HELP="yes"
  COMPACT="no"
  OUTPUT_FILE=""
  while [ $# -gt 0 ]; do
      arg="$1"
      case "$arg" in
          "--out"|"-o") shift; OUTPUT_FILE="$1";;
          "--compact") COMPACT="yes";;
          "--no-metadata") BUILD_METADATA="no";;
          "--no-lib") BUILD_LIBRARY="no";;
          "--no-cli") BUILD_CLI="no";;
          "--no-header") BUILD_HEADER="no";;
          --*)
              error "Invalid command line argument: $arg"
              exit 1
              ;;
          *)
              if [ -z "$PROJECT_ROOT" ]; then PROJECT_ROOT="$arg";
              else error "Invalid command line argument: $arg"; exit 1; fi
              ;;
      esac
      shift
  done
  if [ ! -z "$OUTPUT_FILE" ]; then
      OUTPUT_FILE="$(cd $(dirname "$OUTPUT_FILE") && pwd)/$(basename "$OUTPUT_FILE")"
      rm -f "$OUTPUT_FILE"
      if ! touch "$OUTPUT_FILE" 2> /dev/null; then
          error "Cannot write to given Output File: $OUTPUT_FILE.";
          exit 1;
      fi
      export OUT="$OUTPUT_FILE"
  fi
  cd "$SRC_PATH"
  if [[ "$BUILD_HEADER" == "yes" ]]; then generateHeader; fi
  if [[ "$BUILD_METADATA" == "yes" ]]; then generateMetadata; fi
  genInclude "init.sh"
  if [[ "$BUILD_LIBRARY" == "yes" ]] && [ -d "$LIB_PATH" ]; then generateLibrary; fi
  if [[ "$BUILD_CLI" == "yes" ]]; then 
      genInclude "before-task.sh"
      generateCli
      genInclude "after-task.sh"
  fi
  genInclude "cleanup.sh"
  if [[ "$BUILD_CLI" == "yes" ]]; then generateCliExit; fi
  cd "$CWD"
}
function __run() {
  local pid=""
  local status=255
  local cmd="$1"
  shift
  case "$cmd" in
    "")
      __run "help";
      return $?
      ;;
    "run")
      cli_run "$@" &
      local pid="$!"
      ;;
    "init")
      cli_init "$@" &
      local pid="$!"
      ;;
    "uberbash")
      cli_uberbash "$@" &
      local pid="$!"
      ;;
    "compile")
      cli_compile "$@" &
      local pid="$!"
      ;;
    "help")
      echo "Usage: $0 <command> [<parameters> ...]" 1>&2
      cat 1>&2 <<HELP

    compile   :  (no help available)
    help      :  display this help message
    init      :  (no help available)
    run       :  (no help available)
    uberbash  :  (no help available)
    version   :  display version

HELP
      status=0
      ;;
    "version")
      echo "bashing 0.1.0-alpha6 (bash $BASH_VERSION)"
      status=0
      ;;
    *)
      echo "Unknown Command: $cmd" 1>&2;
      ;;
  esac
  if [ ! -z "$pid" ]; then
      wait "$pid"
      local status=$?
  fi
  return $status
}
__run "$@"
export __STATUS="$?"
exit $__STATUS
