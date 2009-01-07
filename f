#!/bin/sh
#
# f - a wrapper around find(1)
#
# Copyright (c) 2009 Akinori MUSHA
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
VERSION="0.1.1"

type local >/dev/null 2>&1 || \
local () {
    for __arg__; do
        case "$__arg__" in
            *'='*)
                eval "set $(sh_escape "$__arg__")"
                ;;
            *)
                eval "set $(sh_escape "$__arg__")="
                ;;
        esac
    done
}

main () {
    initialize

    parse_args "$@" || exit

    if [ "$DEBUG" = t ]; then
        info "executing the following command:
	$FIND_CMD$FIND_BEFORE_ARGS$FIND_TARGETS$FIND_$FIND_AFTER_ARGS"
    fi
    eval "exec $FIND_CMD$FIND_BEFORE_ARGS$FIND_TARGETS$FIND_$FIND_AFTER_ARGS"
}

usage () {
    {
        echo "f version $VERSION - a wrapper around find(1)"
        echo "usage: $MYNAME { f_flags | find_flags } [ { file | directory } ... ] [ { expressions } ]"
        echo ""
        echo "f flags:"
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
        echo "    --include=PATTERN"
        echo "        Only search files matching PATTERN."
        echo "    --help"
        echo "        Show this help and exit."
    } >&2
    exit 1
}

initialize () {
    : "${FIND_CMD:=find}"
    FIND_BEFORE_ARGS=''
    FIND_TARGETS=''
    FIND_AFTER_ARGS=''
    FIND_TYPE='SUSv3'

    if [ "$MYNAME" = f ]; then
        EXCLUDE_CVS=t
    else
        EXCLUDE_CVS=
    fi

    local find_path="$(expr "$(type "$FIND_CMD")" : ".* is \(.*\)")"

    case "$find_path" in
        '')
            info "$FIND_CMD not found"
            exit 1
            ;;
        */gfind|*/gnu*)
            FIND_TYPE=GNU
            ;;
        *)
            case "$(uname -s)" in
                Linux)
                    FIND_TYPE=GNU
                    ;;
                FreeBSD|Darwin)
                    FIND_TYPE=FreeBSD
                    ;;
            esac
            ;;
    esac

    FIND_CMD="$find_path"
}

parse_opts () {
    local opt

    echo 'local find_exclude_args find_include_args'

    # ones after -P are FreeBSD extensions and ones after -r are GNU
    # extensions.
    while getopts "HLPEXdfsx-:" opt >/dev/null 2>&1; do
        case "$opt" in
            [?:])
                break
                ;;
            d)
                sh_escape FIND_AFTER_ARGS="$FIND_AFTER_ARGS -depth"; echo
                ;;
            -)
                case "$OPTARG" in
                    help)
                        echo usage
                        return
                        ;;
                    debug)
                        echo DEBUG=t
                        ;;
                    cvs-exclude)
                        echo EXCLUDE_CVS=t
                        ;;
                    no-cvs-exclude)
                        echo EXCLUDE_CVS=
                        ;;
                    "include="*)
                        echo '
                        if [ -z "$find_include_args" ]; then
                            find_include_args=" -type f -name '"$(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"'"
                        else
                            find_include_args="$find_include_args -o -type f -name '"$(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"'"
                        fi
                        '
                        ;;
                    "exclude="*)
                        echo '
                        find_exclude_args="$find_exclude_args \! \( -type f -name '"$(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"' \)"
                        '
                        ;;
                    "exclude-dir="*)
                        echo '
                        find_exclude_args=" \! \( \( -type d -name '"$(sh_escape "$(expr "$OPTARG" : "[^=]*=\(.*\)")")"' \) -prune \) $find_exclude_args"
                        '
                        ;;
                    *)
                        echo '
                        FIND_BEFORE_ARGS="$FIND_BEFORE_ARGS '"$(sh_escape "-$opt$OPTARG")"'"
                        '
                        ;;
                esac
                ;;
            *)
                echo '
                FIND_BEFORE_ARGS="$FIND_BEFORE_ARGS '"$(sh_escape "-$opt$OPTARG")"'"
                '
                ;;
        esac
    done

    echo '
    if [ -n "$EXCLUDE_CVS" ]; then
        find_exclude_args='\'' \! \( \( \
            -name RCS -o -name SCCS -o -name CVS -o -name CVS.adm -o \
            -name RCSLOG -o -name cvslog.\* -o -name tags -o -name TAGS -o \
            -name .make.state -o -name .nse_depinfo -o -name \*\~ -o \
            -name \#\* -o -name .\#\* -o -name ,\* -o -name _\$\* -o \
            -name \*\$ -o -name \*.old -o -name \*.bak -o -name \*.BAK -o \
            -name \*.orig -o -name \*.rej -o -name \*.del-\* -o -name \*.a -o \
            -name \*.olb -o -name \*.o -o -name \*.obj -o -name \*.so -o \
            -name \*.exe -o -name \*.Z -o -name \*.elc -o -name \*.ln -o \
            -name core -o -name .svn -o -name .git -o -name .bzr -o -name .hg \
            \) -prune \)'\''" $find_exclude_args"
    fi
    if [ -n "$find_include_args" ]; then
        find_include_args='\'' \( '\''"$find_include_args"'\'' \)'\''
    fi
    FIND_AFTER_ARGS="$find_exclude_args$FIND_AFTER_ARGS$find_include_args"
    '

    echo "shift $(($OPTIND - 1))"
}

parse_args () {
    eval "$(parse_opts "$@")"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -*)
                break
                ;;
            *)
                FIND_TARGETS="$FIND_TARGETS $(sh_escape "$1")"
                shift
                ;;
        esac
    done

    local action
    local op arg

    while [ "$#" -gt 0 ]; do
        op="$1"; shift

        case "$op" in
            # logical operators; ones after -execdir are FreeBSD
            # extensions and ones after [,] are GNU extensions.
            -a|-o|['()!']|-and|-or|-false|-not|[,])
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $(sh_escape "$op")"
                ;;
            # nonary operators; ones after -acl are FreeBSD extensions
            # and ones after -follow are GNU extensions.
            -nouser|-nogroup|-xdev|-prune|-acl|-empty|-prune|-follow|-daystart|-quit|-noleaf|-ignore_readdir_race|-noignore_readdir_race|-mount|-true)
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op)"
                ;;
            -depth)
                # FreeBSD's find(1) takes an optional numeric argument.
                if [ "$#" -gt 0 ]; then
                    case "$1" in
                        [0-9]*)
                            FIND_AFTER_ARGS="$FIND_AFTER_ARGS -$op $(sh_escape "$1")"
                            shift
                            ;;
                    esac
                fi
                ;;
            # unary operators ones after -[Bacm]min are FreeBSD
            # extensions and ones after -wholename are GNU extensions.
            -name|-perm|-type|-links|-user|-group|-size|-[acm]time|-newer|-[Bacm]min|-[Bacm]newer|-[B]time|-flags|-fstype|-iname|-inum|-ipath|-iregex|-maxdepth|-mindepth|-newer[Bacm][Bacmt]|-path|-regex|-wholename|-iwholename|-regextype|-lname|-ilname|-samefile|-used|-xtype|-uid|-gid|-readable|-writable|-executable|-true|-false)
                if [ "$#" -lt 1 ]; then
                    info "missing argument to \`$op'"
                    return 64
                fi
                arg="$1"; shift
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op $(sh_escape "$arg")"
                ;;
            # actions: multiary operators; ones after -execdir are FreeBSD extensions.
            -exec|-ok|-execdir|-okdir)
                action="$op"
                local is_ok has_braces
                if [ "$#" -ge 2 ]; then
                    FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op"
                    while [ "$#" -gt 0 ]; do
                        arg="$1"; shift
                        FIND_AFTER_ARGS="$FIND_AFTER_ARGS $(sh_escape "$arg")"
                        case "$arg" in
                            '{}')
                                has_braces=t
                                ;;
                            '+')
                                if [ "$op" = -exec ]; then
                                    if [ "$has_braces" = t ]; then
                                        is_ok=t
                                    fi
                                    break
                                fi
                                ;;
                            ';')
                                is_ok=t
                                break
                                ;;
                        esac
                    done
                fi
                if [ "$is_ok" != t ]; then
                    info "missing argument to \`$op'"
                fi
                ;;
            # actions: nonary operators; ones after -print0 are FreeBSD extensions.
            -print|-print0|-delete|-ls)
                action="$op"
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $(sh_escape "$op")"
                ;;
            # actions: unary operators; GNU extensions.
            -fprint|-fprint0|-fls|-printf)
                action="$op"
                if [ "$#" -lt 1 ]; then
                    info "missing argument to \`$op'"
                    return 64
                fi
                arg="$1"; shift
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op $(sh_escape "$arg")"
                ;;
            # actions: binary operators; GNU extensions.
            -fprintf)
                action="$op"
                if [ "$#" -lt 2 ]; then
                    info "missing argument to \`$op'"
                    return 64
                fi
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op $(sh_escape "$1") $(sh_escape "$2")"
                shift 2
                ;;
        esac
    done

    case "$FIND_TYPE" in
        GNU)
            ;;
        FreeBSD)
            : "${FIND_TARGETS:=" ."}"
            ;;
        *)
            : "${FIND_TARGETS:=" ."}"
            if [ -z "$action" ]; then
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS -print"
            fi
            ;;
    esac
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

info () {
    echo "$0: $@" >&2
}

main "$@"
