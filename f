#!/bin/sh
#
# f - a wrapper around find(1)
#
# Copyright (c) 2009, 2010, 2011, 2012, 2013 Akinori MUSHA
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
VERSION="0.5.2"

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
        ;;
    *)
        ;;
esac

main () {
    initialize

    parse_args "$@" || exit

    if [ "$DEBUG" = t ]; then
        info "executing the following command:
	$FIND_CMD$FIND_BEFORE_ARGS$FIND_TARGETS$FIND_AFTER_ARGS"
    fi
    eval "exec $FIND_CMD$FIND_BEFORE_ARGS$FIND_TARGETS$FIND_AFTER_ARGS"
}

usage () {
    {
        echo "f version $VERSION - a wrapper around find(1)"
        echo "usage: $MYNAME { f_flags | find_flags } [ { file | directory } ... ] [ { expressions } ]"
        echo ""
        echo "f flags:"
        if [ -n "$EXCLUDE_RSYNC" ]; then
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
        echo "    --include=PATTERN | --I=PATTERN"
        echo "        Do not ignore files matching PATTERN."
        echo "    --include-dir=PATTERN"
        echo "        Do not ignore directories matching PATTERN."
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

    if [ f = "$MYNAME" ]; then
        EXCLUDE_RSYNC=t
    else
        EXCLUDE_RSYNC=
    fi

    local find_path="$(expr "$(type "$FIND_CMD")" : ".* \(/.*\)")"

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
    local parseoptlong opt arg OPTIND=1 OPTARG= OPTERR=

    parseoptlong=`parseoptlong \
        help debug \
        C rsync-exclude \
        A no-rsync-exclude all-files \
        I: include: include-dir: \
        X: exclude: exclude-dir: \
    opt`

    echo 'local find_exclude_args find_include_args'

    while :; do
        # Stop if this argument looks like an operator
        arg="$(eval echo :\$$OPTIND)"
        case "$arg" in
            :-[a-zA-Z]*)
                arg="${arg%%[DO]*}"
                expr "$arg" : ':-[HLPEXdfsx]*$' >/dev/null || break
                ;;
        esac

        # ones after -P are FreeBSD extensions and ones after -D are
        # GNU extensions.
        getopts "HLPEXdfsxD:O:-:" opt >/dev/null 2>&1 || break
        eval "$parseoptlong"

        case "$opt" in
            [?:])
                break
                ;;
            d)
                echo 'FIND_AFTER_ARGS=" -depth$FIND_AFTER_ARGS"'
                ;;
            -help)
                echo usage
                return
                ;;
            -debug)
                echo DEBUG=t
                ;;
            -C|-rsync-exclude)
                echo EXCLUDE_RSYNC=t
                ;;
            -A|-all-files|-no-rsync-exclude)
                echo EXCLUDE_RSYNC=
                ;;
            -I|-include)
                echo 'find_include_args="${find_include_args:+"$find_include_args -o"} \( -type f -name '"$(sh_escape "$OPTARG")"' \)"'
                ;;
            -include-dir)
                echo 'find_include_args="${find_include_args:+"$find_include_args -o"} \( -type d -name '"$(sh_escape "$OPTARG")"' \)"'
                ;;
            -X|-exclude)
                echo 'find_exclude_args="$find_exclude_args \! \( -type f -name '"$(sh_escape "$OPTARG")"' \)"'
                ;;
            -exclude-dir)
                echo 'find_exclude_args=" \! \( \( -type d -name '"$(sh_escape "$OPTARG")"' \) -prune \)$find_exclude_args"'
                ;;
            L)
                case "$FIND_TYPE" in
                    GNU)
                        echo 'FIND_AFTER_ARGS="$FIND_AFTER_ARGS -follow"'
                        ;;
                    *)
                        echo 'FIND_BEFORE_ARGS="$FIND_BEFORE_ARGS '"$(sh_escape "-$opt$OPTARG")"'"'
                        ;;
                esac
                ;;
            *)
                echo 'FIND_BEFORE_ARGS="$FIND_BEFORE_ARGS '"$(sh_escape "-$opt$OPTARG")"'"'
                ;;
        esac
    done

    echo '
    if [ -n "$EXCLUDE_RSYNC" ]; then
        find_exclude_args='\'' \! \( \
            -type f \( \
              -name tags -o -name TAGS -o -name GTAGS -o \
              -name GRTAGS -o -name GSYMS -o -name GPATH -o \
              -name .make.state -o -name .nse_depinfo -o -name \*.ln -o \
              -name \*\~ -o -name \#\* -o -name .\#\* -o -name ,\* -o -name _\$\* -o \
              -name \*\$ -o -name \*.old -o -name \*.bak -o -name \*.BAK -o \
              -name \*.orig -o -name \*.rej -o -name \*.del-\* -o \
              -name \*.a -o -name \*.olb -o -name \*.o -o -name \*.obj -o \
              -name \*.so -o -name \*.so.\* -a \! -name \*.so.\*\[\!.0-9\]\* -o \
              -name \*.bundle -o -name \*.dylib -o -name \*.exe -o \
              -name \*.Z -o -name \*.elc -o -name \*.py\[co\] -o \
              -name core -o -name core.\* -a \! -name core.\*\[\!0-9\]\* \
            \) -o \
            -type d \( \
              -name RCS -o -name SCCS -o -name CVS -o -name CVS.adm -o \
              -name .svn -o -name .git -o -name .bzr -o -name .hg \
            \) -prune \)'\''"$find_exclude_args"
    fi
    if [ -n "$find_exclude_args" ]; then
        if [ -n "$find_include_args" ]; then
            FIND_AFTER_ARGS="$FIND_AFTER_ARGS"'\'' \( \('\''"$find_include_args"'\'' \) -o \('\''"$find_exclude_args"'\'' \) \)'\''
        else
            FIND_AFTER_ARGS="$FIND_AFTER_ARGS"'\'' \('\''"$find_exclude_args"'\'' \)'\''
        fi
    fi
    '

    echo "shift $((OPTIND-1))"
}

parse_args () {
    eval "$(parse_opts "$@")"

    local includes

    while [ $# -gt 0 ]; do
        case "$1" in
            -*)
                break
                ;;
            */)
                FIND_TARGETS="$FIND_TARGETS $(sh_escape "$1")"
                shift
                ;;
            *)
                FIND_TARGETS="$FIND_TARGETS $(sh_escape "$1")"
                includes="$includes -path $(find_path_escape "$1") -o"
                shift
                ;;
        esac
    done

    if [ -n "$includes" -a -n "$FIND_AFTER_ARGS" ]; then
        FIND_AFTER_ARGS=" \($includes$FIND_AFTER_ARGS \)"
    fi

    local action
    local op arg

    while [ $# -gt 0 ]; do
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
                if [ $# -gt 0 ]; then
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
                if [ $# -lt 1 ]; then
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
                if [ $# -ge 2 ]; then
                    FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op"
                    while [ $# -gt 0 ]; do
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
                if [ t != "$is_ok" ]; then
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
                if [ $# -lt 1 ]; then
                    info "missing argument to \`$op'"
                    return 64
                fi
                arg="$1"; shift
                FIND_AFTER_ARGS="$FIND_AFTER_ARGS $op $(sh_escape "$arg")"
                ;;
            # actions: binary operators; GNU extensions.
            -fprintf)
                action="$op"
                if [ $# -lt 2 ]; then
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
            : "${FIND_TARGETS:= .}"
            ;;
        *)
            : "${FIND_TARGETS:= .}"
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

parseoptlong () {
    local carp=t error

    if [ : = "$1" ]; then
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

find_path_escape () {
    case "$*" in
        *[!A-Za-z0-9_.,:/@-]*)
            awk '
                BEGIN {
                    n = ARGC - 1
                    for (i = 1; i <= n; i++) {
                        s = ARGV[i]
                        gsub(/\/\/*$/, "", s)
                        gsub(/[][*?]/, "\\\\&", s)
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
