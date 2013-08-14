#!/bin/sh
#
# g - a wrapper around grep(1) that uses f(1)
#
# Copyright (c) 2007, 2008, 2009, 2010, 2011, 2012, 2013 Akinori MUSHA
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

MYNAME="$(basename "$0")"
VERSION="0.5.3"

GREP_CMD='grep'
GREP_ARGS=''

GREP_AOPTS='A:B:C:D:d:e:f:m:-:'
GREP_BOPTS='EFGHIJLPRUVZabchilnoqrsuvwxz'
N_GREP_OPTS=0

F_CMD='f'
F_BEFORE_ARGS=' -L'
F_AFTER_ARGS=''

XARGS_CMD='xargs'
XARGS_ARGS=-0
FIND_PRINT=-print0

if [ "$MYNAME" = g ]; then
    EXCLUDE_RSYNC=t
else
    EXCLUDE_RSYNC=
fi

case "$(uname -s)" in
    SunOS)
        test_local='f () { local x=2; [ "$x" = 2 ]; }; x=1; f && [ "$x" = 1 ]'
        if ! eval "$test_local" >/dev/null 2>&1; then
            for sh in /usr/gnu/bin/sh /usr/xpg4/bin/sh ksh; do
                if [ -x "$sh" ] && "$sh" -c "$test_local" >/dev/null 2>&1; then
                    exec "$sh" "$0" "$@"
                fi
            done
            echo "$0: 'local' builtin missing" >&1
            exit 255
        fi
        awk () {
            /usr/xpg4/bin/awk "$@"
        }
        GREP_CMD=/usr/xpg4/bin/grep
        FIND_PRINT=-print
        XARGS_ARGS=
        ;;
esac

trap 'echo "g: error in find(1)." >&2; exit 2' USR1

usage () {
    {
        echo "g version $VERSION - a wrapper around grep(1) that uses f(1)"
        echo "usage: $MYNAME { g_flags | grep_flags } [ { file | directory } ... ]"
        echo ""
        echo "g flags:"
        if [ "$EXCLUDE_RSYNC" = t ]; then
            echo "    --A | --all-files | --no-rsync-exclude"
            echo "        Do not auto-ignore any files.  By default, $MYNAME ignores"
            echo "        uninteresting files much like a similar way rsync -C does."
        else
            echo "    --C | --rsync-exclude"
            echo "        Ignore files much like a similar way rsync -C does."
        fi
        echo "    --exclude=PATTERN | --X=PATTERN"
        echo "        Ignore files matching PATTERN."
        echo "    --exclude-dir=PATTERN"
        echo "        Ignore directories matching PATTERN."
        echo "    --e=EXPR | --find-expr=EXPR"
        echo "        Specify expressions to pass to find(1)."
        echo "    --include=PATTERN | -I=PATTERN"
        echo "        Do not ignore files matching PATTERN."
        echo "    --include-dir=PATTERN"
        echo "        Do not ignore directories matching PATTERN."
        echo "    --help"
        echo "        Show this help and exit."
    } >&2
    exit 1
}

parse_opts () {
    local OPTIND=1 argc parseoptlong opt_pattern opt_exptype opt arg

    if [ $# -eq 0 ]; then
        usage
    fi
    argc=$#

    parseoptlong=`parseoptlong : \
        help debug \
        C rsync-exclude \
        A no-rsync-exclude all-files \
        I: include: include-dir: \
        X: exclude: exclude-dir: \
        e: find-expr: \
    opt`

    while getopts "$GREP_AOPTS$GREP_BOPTS" opt; do
        eval "$parseoptlong"
        case "$opt" in
            ["$GREP_BOPTS"])
                case "$opt" in
                    [EFP])
                        opt_exptype=t
                        ;;
                esac

                GREP_ARGS="$GREP_ARGS $(sh_escape "-$opt")"
                ;;
            e)
                opt_pattern=t
                GREP_ARGS="$GREP_ARGS $(sh_escape "-$opt$OPTARG")"
                ;;
            ["$GREP_AOPTS"])
                GREP_ARGS="$GREP_ARGS $(sh_escape "-$opt${OPTARG}")"
                ;;
            -help)
                usage
                ;;
            -C|-rsync-exclude)
                EXCLUDE_RSYNC=t
                ;;
            -A|-all-files|-no-rsync-exclude)
                EXCLUDE_RSYNC=
                ;;
            -I|-include|-include-dir|-X|-exclude|-exclude-dir)
                F_BEFORE_ARGS="$F_BEFORE_ARGS $(sh_escape "-$opt=$OPTARG")"
                ;;
            -e|-find-expr)
                F_AFTER_ARGS="$F_AFTER_ARGS '(' $(sh_escape "$OPTARG") ')'"
                ;;
            -*)
                GREP_ARGS="$GREP_ARGS $(sh_escape "-$opt${OPTARG+"=$OPTARG"}")"
                ;;
            :)
                echo "$0: option requires an argument -- $OPTARG" >&2
                usage
                ;;
            \?)
                if [ -n "$OPTARG" ]; then
                    GREP_ARGS="$GREP_ARGS $(sh_escape "--$OPTARG")"
                else
                    echo "$0: illegal option -- $OPTARG" >&2
                    usage
                fi
                ;;
        esac
    done

    [ $opt_exptype ] || GREP_ARGS="$GREP_ARGS -E"

    shift $((OPTIND-1))

    if [ -z "$opt_pattern" ]; then
        if [ $# -eq 0 ]; then
            usage
        fi
        GREP_ARGS="$GREP_ARGS -- $(sh_escape "$1")"
        shift
    fi
    N_GREP_OPTS=$((argc-$#))
}

sh_escape () {
    case "$*" in
        '')
            echo "''"
            ;;
        *[!A-Za-z0-9_.,:/@-]*)
            awk '
                BEGIN {
                    n = ARGC - 1
                    for (i = 1; i <= n; i++) {
                        s = ARGV[i]
                        gsub(/[^\nA-Za-z0-9_.,:\/@-]/, "\\\\&", s)
                        gsub(/\n/, "\"\n\"", s)
                        printf "%s", s
                        if (i != n) printf " "
                    }
                    exit 0
                }
                ' "$@"
            ;;
        *)
            printf '%s' "$*" 
            ;;
    esac
}

parseoptlong () {
    local carp=t error

    if [ "$1" = : ]; then
        unset carp
        shift
    fi

    case $# in
        0)
            echo 'getoptslong: not enough arguments' >&2
            return 1 ;;
        1)
            return 0 ;;
    esac

    local option name="$(shift $(($#-1)) && echo "$1")" when booloptions= margoptions= oargoptions=

    echo "\
[ \"\$$name\" != - ] ||
case \"\$(shift \$((OPTIND-2)) && echo \".\$1\")\" in
.--*)
 case \"\$OPTARG\" in"

    while [ $# -gt 1 ]; do
        case "$1" in
            *\=*)
                option="${1%%=*}"
                oargoptions="$oargoptions $option"
                # --optarg => return default value
                echo "\
 $option)
  $name=\"-\$OPTARG\"
  OPTARG=\"${1#*=}\"
  [ -n \"\$OPTARG\" ] || unset OPTARG ;;"
                ;;
            *:)
                margoptions="$margoptions ${1%:}"
                ;;
            *)
                booloptions="$booloptions $1"
                ;;
        esac
        shift
    done

    # --bool => return null argument
    if [ -n "$booloptions" ]; then
        when=
        for option in $booloptions; do
            when="$when|$option"
        done
        echo "\
 ${when#"|"})
  $name=\"-\$OPTARG\"
  unset OPTARG ;;"
    fi

    # --bool=arg => fail
    if [ -n "$booloptions" ]; then
        when=
        for option in $booloptions; do
            when="$when|$option\=*"
        done
        if [ -n "$carp" ]; then
            echo "\
 ${when#"|"})
  $name='?'
  echo \"\$0: option does not take an argument -- \${OPTARG%%=*}\" >&2
  unset OPTARG ;;"
        else
            echo "\
 ${when#"|"})
  $name='?'
  OPTARG=\"\${OPTARG%%=*}\" ;;"
        fi
    fi

    # --mandarg=arg | --optarg=arg => return arg
    if [ -n "$margoptions$oargoptions" ]; then
        when=
        for option in $margoptions $oargoptions; do
            when="$when|$option\=*"
        done
        echo "\
 ${when#"|"})
  $name=\"-\${OPTARG%%=*}\"
  OPTARG=\"\${OPTARG#*=}\" ;;"
    fi

    # --mandarg arg => return arg or fail if missing
    if [ -n "$margoptions" ]; then
        when=
        for option in $margoptions; do
            when="$when|$option"
        done
        # Altering OPTIND works for some shells like bash, but does
        # not work for shells that store the current index in an
        # internal space.  Shifting is the only way to let getopts
        # continue parsing correctly on those shells.
        echo "\
 ${when#"|"})
  if [ \$# -ge \$OPTIND ]; then
   $name=\"-\$OPTARG\"
   shift \$((OPTIND-1))
   OPTARG=\"\$1\"
   shift
   OPTIND=1
  else"
        if [ -n "$carp" ]; then
            echo "\
   echo \"\$0: option requires an argument -- \$OPTARG\" >&2
   $name='?'
   unset OPTARG"
        else
            echo "\
   $name=:"
        fi
        echo "\
  fi ;;"
    fi

    if [ -n "$carp" ]; then
        echo "\
 *)
  echo \"\$0: illegal option -- \${OPTARG%%=*}\" >&2
  $name='?'
  unset OPTARG ;;"
    else
        echo "\
 *)
  $name='?'
  OPTARG=\"\${OPTARG%%=*}\" ;;"
    fi

    echo "\
 esac ;;
*)"

    if [ -n "$carp" ]; then
        echo "\
 echo \"\$0: illegal option -- \$$name\" >&2
 $name='?'
 unset OPTARG"
    else
        echo "\
 OPTARG=\"\$$name\"
 $name='?'"
    fi

    echo "\
 ;;
esac"
}

exec_find () {
    local args

    eval "$(sh_escape "$F_CMD") $F_BEFORE_ARGS $(sh_escape "$@") $F_AFTER_ARGS -type f $FIND_PRINT" || kill -USR1 $$
    exit
}

main () {
    parse_opts "$@"
    shift "$N_GREP_OPTS"

    if [ "$EXCLUDE_RSYNC" != t ]; then
        F_BEFORE_ARGS="$F_BEFORE_ARGS --all-files"
    fi

    if [ "$#" -eq 0 ]; then
        if [ -t 0 ]; then
            exec_find . | eval "$(sh_escape "$XARGS_CMD")" "$(sh_escape "$XARGS_ARGS")" "$(sh_escape "$GREP_CMD")" "$GREP_ARGS" /dev/null
        else
            eval exec "$(sh_escape "$GREP_CMD")" "$GREP_ARGS"
            exit 127
        fi
    elif [ "$#" -eq 1 -a ! -e "$1" ]; then
        echo "$MYNAME: $1: No such file or directory" >&2
        exit 2
    elif [ "$#" -eq 1 -a -f "$1" ]; then
        if [ -z "$(exec_find "$1")" ]; then
            # the file was excluded
            exit 1
        fi
        eval exec "$(sh_escape "$GREP_CMD")" "$GREP_ARGS" "$(sh_escape "$1")"
    else
        exec_find "$@" | eval "$(sh_escape "$XARGS_CMD")" "$(sh_escape "$XARGS_ARGS")" "$(sh_escape "$GREP_CMD")" "$GREP_ARGS" /dev/null
    fi
}

main "$@"
