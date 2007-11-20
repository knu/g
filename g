#!/bin/sh
#
# g - a wrapper around grep(1)
#
# Copyright (c) 2007 Akinori MUSHA
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
#
#
# $Id$

MYNAME="$(basename "$0")"
VERSION="0.3.0"

GREP_CMD='grep'
GREP_ARGS=''

GREP_AOPTS='A:B:C:D:d:e:f:m:-:'
GREP_BOPTS='EFGHIJLPRUVZabchilnoqrsuvwxz'
N_GREP_OPTS=0

FIND_CMD='find'
FIND_EXCLUDE_ARGS=''
FIND_INCLUDE_ARGS=''
FIND_BEFORE_ARGS=''
FIND_AFTER_ARGS='-print0'

XARGS_CMD='xargs'
XARGS_ARGS='-0'

if [ "$MYNAME" = g ]; then
    EXCLUDE_CVS=t
else
    EXCLUDE_CVS=
fi

trap 'echo "g: error in find(1)." >&2; exit 2' USR1

usage () {
    {
        echo "g version $VERSION - a wrapper around grep(1)"
        echo "usage: $MYNAME { g_flags | grep_flags } [ { file | directory } ... ]"
        echo ""
        echo "g flags:"
        if [ -n "$EXCLUDE_CVS" ]; then
            echo "    --no-cvs-exclude"
            echo "        Do not auto-ignore any files.  By default, $MYNAME ignores"
            echo "        uninteresting files in the same way rsync --cvs-exclude does."
        else
            echo "    --cvs-exclude"
            echo "        Ignore files in the same way rsync --cvs-exclude does."
        fi
        echo "    --exclude=PATTERN"
        echo "        Ignore files matching PATTERN."
        echo "    --exclude-dir=PATTERN"
        echo "        Ignore directories matching PATTERN."
        echo "    --find-expr=EXPR"
        echo "        Specify expressions to pass to find(1)."
        echo "    --include=PATTERN"
        echo "        Only search files matching PATTERN."
        echo "    --help"
        echo "        Show this help and exit."
    } >&2
    exit 1
}

parse_opts () {
    local opt_pattern opt_exptype arg
    local OPTIND OPTARG OPTERR

    if [ "$#" -eq 0 ]; then
        usage
    fi

    while getopts "$GREP_AOPTS$GREP_BOPTS" o; do
        case "$o" in
            ["$GREP_BOPTS"])
                case "$o" in
                    [EFP])
                        opt_exptype=t
                        ;;
                esac

                GREP_ARGS="$GREP_ARGS $(sh_escape "-$o")"
                ;;
            [?:])
                # cause error
                usage
                ;;
            *)
                case "$o" in
                    e)
                        opt_pattern=t
                        ;;
                    [EFP])
                        opt_exptype=t
                        ;;
                    -)
                        case "$OPTARG" in
                            help)
                                usage
                                ;;
                            cvs-exclude)
                                EXCLUDE_CVS=t
                                continue
                                ;;
                            no-cvs-exclude)
                                EXCLUDE_CVS=
                                continue
                                ;;
                            "include="*)
                                if [ -z "$FIND_INCLUDE_ARGS" ]; then
                                    FIND_INCLUDE_ARGS="-type f -name $(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"
                                else
                                    FIND_INCLUDE_ARGS="$FIND_INCLUDE_ARGS -o -type f -name $(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"
                                fi
                                continue
                                ;;
                            "exclude="*)
                                FIND_EXCLUDE_ARGS="$FIND_EXCLUDE_ARGS '!' '(' -type f -name $(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")") ')'"
                                continue
                                ;;
                            "exclude-dir="*)
                                FIND_EXCLUDE_ARGS="'!' '(' '(' -type d -name $(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")") ')' -prune ')' $FIND_EXCLUDE_ARGS"
                                continue
                                ;;
                            "find-expr="*)
                                FIND_BEFORE_ARGS="$FIND_BEFORE_ARGS '(' $(sh_escape $(expr "$OPTARG" : "[^=]*=\(.*\)")) ')'"
                                continue
                                ;;
                        esac
                        ;;
                esac

                GREP_ARGS="$GREP_ARGS $(sh_escape "-$o$OPTARG")"
                ;;
        esac
    done

    [ $opt_exptype ] || GREP_ARGS="$GREP_ARGS -E"

    if [ -z "$opt_pattern" ]; then
        N_GREP_OPTS="$OPTIND"
        shift "$(($OPTIND - 1))"
        GREP_ARGS="$GREP_ARGS -- $(sh_escape "$1")"
    else
        N_GREP_OPTS="$(($OPTIND - 1))"
    fi
}

sh_escape () {
    case "$*" in
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

exec_find () {
    local args

    eval "$(sh_escape "$FIND_CMD") $(sh_escape "$@") $FIND_BEFORE_ARGS -type f $FIND_AFTER_ARGS" || kill -USR1 $$
    exit
}

main () {
    parse_opts "$@"
    shift "$N_GREP_OPTS"

    if [ -n "$EXCLUDE_CVS" ]; then
        FIND_EXCLUDE_ARGS='\! \( \( \
            -name RCS -o -name SCCS -o -name CVS -o -name CVS.adm -o \
            -name RCSLOG -o -name cvslog.\* -o -name tags -o -name TAGS -o \
            -name .make.state -o -name .nse_depinfo -o -name \*\~ -o \
            -name \#\* -o -name .\#\* -o -name ,\* -o -name _\$\* -o \
            -name \*\$ -o -name \*.old -o -name \*.bak -o -name \*.BAK -o \
            -name \*.orig -o -name \*.rej -o -name \*.del-\* -o -name \*.a -o \
            -name \*.olb -o -name \*.o -o -name \*.obj -o -name \*.so -o \
            -name \*.exe -o -name \*.Z -o -name \*.elc -o -name \*.ln -o \
            -name core -o -name .svn -o -name .bzr \
            \) -prune \)'" $FIND_EXCLUDE_ARGS"
    fi

    if [ -n "$FIND_INCLUDE_ARGS" ]; then
        FIND_INCLUDE_ARGS='\( '"$FIND_INCLUDE_ARGS"' \)'
    fi

    FIND_BEFORE_ARGS="$FIND_EXCLUDE_ARGS $FIND_BEFORE_ARGS $FIND_INCLUDE_ARGS"

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
