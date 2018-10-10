set -e

VAR_ENC=
FILE_EXT=
FILE_INPUT=$1
FILE_OUTPUT=$2
TMPFILE=$(mktemp --tmpdir goscript.XXXXX.go)
SHELL_CMD=

trap 'cleanup' EXIT

main() {
    checkArg "$@"
    checkDep
    checkFileType "$FILE_INPUT" 
    setShellCmd "$FILE_EXT"
    base64Encode "$FILE_INPUT" 
    generateGoFile
    buildBinary
}

base64Encode() {
    VAR_ENC=$(cat $1 | base64 | tr -d '\n' )
}

buildBinary() {
    if go build -o "$FILE_OUTPUT" "$TMPFILE"; then
        echo "done building binary file"
    else
        exit 1
    fi
}

cleanup() {
    if [ -f $TMPFILE ];then
        rm "$TMPFILE"
    fi
}

checkArg() {
    if [ $# -ne 2 ]; then
        echo -e "illegal number of parameters\n"
        echo "usage: $(basename $0) inputfile outputfile"
        exit 1
    fi
}

checkDep() {
    which go > /dev/null || { echo "Missing package: go."; exit 1; }
    which base64 > /dev/null || { echo "Missing package: base64."; exit 1; }
}

checkFileType() {
    FILE_EXT=$(file -b --mime-type "$1")
}

generateGoFile() {
    cat << EOF > "$TMPFILE"
package main

import (
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"sync"
	"syscall"
)

func main() {

	scriptArgs := os.Args

	data := "$VAR_ENC"

	uDec, _ := base64.StdEncoding.DecodeString(data)
	cmdScript := string(uDec)

	cmd := []string{"${SHELL_CMD[1]}", cmdScript}
	cmd = append(cmd, scriptArgs...)

	var waitStatus syscall.WaitStatus

	var wg sync.WaitGroup

	cmdexec := exec.Command("${SHELL_CMD[0]}", cmd...)

	stdout, err := cmdexec.StdoutPipe()
	if err != nil {
		panic(err)
	}

	stderr, err := cmdexec.StderrPipe()
	if err != nil {
		panic(err)
	}

	if err := cmdexec.Start(); err != nil {
		panic(err)
	}

	wg.Add(2)

	go func() {
		defer wg.Done()
		b, err := ioutil.ReadAll(stdout)
		if err != nil {
			panic(err)
		}
		fmt.Fprint(os.Stdout, string(b))
	}()

	go func() {
		defer wg.Done()
		b, err := ioutil.ReadAll(stderr)
		if err != nil {
			panic(err)
		}
		fmt.Fprint(os.Stderr, string(b))
	}()

	wg.Wait()

	if err := cmdexec.Wait(); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			waitStatus = exitError.Sys().(syscall.WaitStatus)
		} else {
			waitStatus = cmdexec.ProcessState.Sys().(syscall.WaitStatus)
		}
	}
	exitCode := int(waitStatus.ExitStatus())

	os.Exit(exitCode)
}
EOF
}

setShellCmd() {
    case $1 in
        text/x-shellscript)
            SHELL_CMD=("bash" "-c")
            ;;
        text/x-perl)
            SHELL_CMD=("perl" "-e")
            ;;
        text/x-python)
            SHELL_CMD=("python" "-c")
            ;;
        *)
            echo "file not supported"
            exit 1
            ;;
    esac
}

main "$@"
