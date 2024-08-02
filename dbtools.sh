#!/bin/bash
# Copyright: Wed Jan 14 20:17:38 CST 2015
# Author: icersong
# Modified: Friday, August 02, 2024 AM03:25:22 HKT
# Version: 3.0


################################################################################
debug=false
log=/tmp/dbtools.log
err=/tmp/dbtools.err


################################################################################

if [[ "$OSTYPE" =~ ^darwin ]]; then
    readlink=greadlink
    sed=gsed
else
    readlink=readlink
    sed=sed
fi


################################################################################
# Commands test exists

function check_command_error() {
    command -v $1 >/dev/null 2>&1 || {
        echo >&2 "Error! require command $1 but it's not installed.  Abort!!!";
        exit 1;
    }
}

function check_command_warn() {
    check_command_warn=1
    command -v $1 >/dev/null 2>&1 || {
        echo >&2 "Warning! require command $1 but it's not installed.";
        check_command_warn=0;
    }
}


################################################################################
# funciton selectfile   {{{1

# usage:
#    selectfile "./*.sh";
#    echo $?, $selected
#    $?: 0, none selected; > 0, file selected
#    $selected: while $? > 0, selected is set with file path & name
selected=
function selectfile() {
    # local lst=`ls -w ${1} 2>/dev/null`
    local lst=`ls ${1} 2>/dev/null`
    local idx=1
    local name=
    local line=
    local input=
    if [ "$debug" == "true" ]; then
        echo Select file from: "${1}"
    fi
    if [ -z "$lst" ]; then
        echo None for select.
    fi
    for line in $lst
    do
        name=${line##*/}
        # echo ${idx}. ${name%.*}
        echo ${idx}. ${name}
        idx=$(($idx+1))
    done
    read -p "请输入选择的编号或名称:" input
    idx=1
    for line in $lst
    do
        name=${line##*/}
        if [ "$idx" == "$input" ] || [ "${name}" == "$input" ] || [ "${name%.*}" == "$input" ]; then
            selected=$line
            break
        fi
        idx=$(($idx+1))
    done
    if [ "$debug" == "true" ]; then
        if [ -z "$selected" ]; then
            echo "None selected!"
        else
            echo Selected: ${idx}. ${selected##*/}
        fi
    fi
    if [ -z "$selected" ]; then
        return 0
    fi
    return $idx
}


################################################################################
# funciton listdatabases {{{1

# usage:
#    listdatabases;
#    echo $?, $databases
#    $?: valid database count
#    $databases: database list
function listdatabases() {
_sql="SHOW DATABASES WHERE \`Database\` NOT IN ('test', 'mysql') AND \`Database\` NOT LIKE '%_schema';"
local _name=
local _lst=
local _cnt=0
# for name in `${1} <$sql 2>/dev/null |grep -v "^Warning: Using a password"`
for _name in `${1} -e "${_sql}" 2>/dev/null`
do
    if [ "${_name}" == "Database" ]; then
        continue
    fi
    _lst="${_lst} ${_name}"
    _cnt=$((${_cnt}+1))
done
# rm -f $sql >/dev/null 2>&1
databases=${_lst}
return ${_cnt}
}


################################################################################
# usage:
#    get_dbname;
#    echo $?, $databases
#    $?: valid database count
#    $databases: database list
function get_dbname() {
    # select database
    listdatabases "${1}"
    echo "请选择数据库！"
    select dbname in $databases; do
        break;
    done
    if [ -z "${dbname}" ]; then
        read -p "请输入要数据库名称:" dbname
    fi
    if [ -z "${dbname}" ]; then
        echo "No database specified."
        exit;
    fi
    return 0
}

################################################################################
# envariment    {{{1
# echo "scriptPath1: "$(cd `dirname $0`; pwd)
# echo "scriptPath2: "$(pwd)
# echo "scriptPath3: "$(dirname $(readlink -f $0))
# echo "scriptPath4: "$(cd $(dirname ${BASH_SOURCE:-$0});pwd)
# echo -n "scriptPath5: " && dirname $(readlink -f ${BASH_SOURCE[0]})

#### SCRIPT INFO
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "$0"  ]]; then
    # 直接执行此文件或者执行了此文件的LINK
    SCRIPT_PATH=$(readlink -f "$0")
else
    # 使用source命令引用了此文件
    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
fi
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
echo $SCRIPT_DIR

# scriptfile=${0##*/}
scriptfile="$($readlink -f ${BASH_SOURCE[0]})"
scriptfile=${scriptfile##*/}
scriptname=${scriptfile%.*}
script_ext=${scriptfile##*.}
scriptpath=$SCRIPT_DIR
# scriptpath=$(cd `dirname $0`; pwd)
# echo scriptfile: $scriptfile
# echo scriptname: $scriptname
# echo script_ext: $script_ext
# echo scriptpath: $scriptpath


################################################################################
# usage
function usage() {
        echo "Usage:"
        echo "\$ ${scriptfile} <create|remove|backup|import|export|restore> [dbname ...]"
        echo "\$ ${scriptfile} create [dbname]"
        echo "\$ ${scriptfile} remove [dbname]"
        echo "\$ ${scriptfile} backup [dbname]"
        echo "\$ ${scriptfile} import [dbname] [filename]"
        echo "\$ ${scriptfile} export [dbname][:tables] [filename]"
        echo "\$ ${scriptfile} restore [dbname] [filename]"
        exit;
}

action="$1"
if [ -z "${action}" ]; then
    usage;
fi
################################################################################
# load config
scriptconfig="$scriptpath/${scriptname}.cfg"
if [[ ! -f $scriptconfig ]]; then
    echo "Error! Config file '$scriptconfig' not exists."
    exit
fi
source $scriptconfig

# config defaults
charset=${charset:-"charset utf8 COLLATE utf8_general_ci"}
dumpargs=${dumpargs:-}
dbdump=${dbdump:-mysqldump}
dbcli=${dbcli:-"mysql"}
dbargs=${dbargs:-"--defaults-extra-file=$scriptpath/dbcli.cfg"}
dbwarn="^Warning: Using a password on the command line interface can be insecure."
skip_definer="$sed \"s/\\\\/\\\\*!5001[0-9] DEFINER=[^ ][^*]*\\\\*\\\\///g\""

# merge to new variables
dbargs="-h127.0.0.1 -uroot -pmariadb"

################################################################################
# script args
dbname="${2%:*}"
if [ "$dbname" != "$2" ]; then
    tables=${2##*.}
fi
filename="$3"

# echo "action: ${action}"
# echo "database: ${dbname}"
# echo "filename: ${filename}"
# echo "dump.args: ${dumpargs}"
# echo "dump.exec: ${dumpexec}"
# echo scriptconf: $scriptconfig


################################################################################
# do command    {{{1

function select_sql_file () {
    # selected sql file
    if [ -z "${filename}" ] || [ ! -f "${filename}" ]; then
        selectfile "*.sql *.zip *.7z *.tgz *.tar.gz *.gz *.xz";
        if [ ! -f "${selected}" ]; then
            echo "No sql file selected."
            exit;
        fi
        filename=${selected}
    fi
    echo "Sql file $filename selected."
}

function select_database() {
    if [ -z "${dbname}" ]; then
        get_dbname "${dbcli} ${dbargs}"
    fi
}

# $1: dbname
# $3: filename
function import_xz() {
    # Get uncompressed size
    dbname=$1
    fname=$2
    echo -n "Get uncompressed size"
    info=`xz -l -v $fname | grep "Uncompressed"`
    info=${info##*(}
    size=${info%% *}
    echo " $size Bytes"
    size=${size//,/}

    # Import database
    echo "Import ./$fname -> $dbname"
    ldbargs="-hlocalhost -uroot -p123456"
    cat ./$fname | xz -d | pv -s $size | mysql $dbargs --database $dbname
}

function action_import () {
    # import database
    echo "Import data from ${filename}"
    check_command_error 'pv';
    execstr="${dbcli} ${dbargs} --database ${dbname}"
    if [ "${filename##*.tar.}" == "gz" ] || [ "${filename##*.}" == "tgz" ]; then
        check_command_error 'tar';
        tarfile=`tar -tf ${filename} | grep -v "/"`
        pv ${filename}|tar -zxO ${tarfile}|${execstr} 2>&1|grep -v "${dbwarn}"
    elif [ "${filename##*.}" == "gz" ]; then
        check_command_error 'gunzip';
        pv ${filename} | gunzip -c | ${execstr} | grep -v "${dbwarn}"
    elif [ "${filename##*.}" == "xz" ]; then
        check_command_error 'xz';
        import_xz $dbname $filename
    elif [ "${filename##*.}" == "zip" ]; then
        check_command_error 'unzip';
        command -v unzip >/dev/null 2>&1 || {
            echo >&2 "I Error! require unzip but it's not installed.  Aborting."; exit 1;
        }
        size=`unzip -l ${filename}|tail -n1|awk '{print $1}'`
        unzip -p ${filename}|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
    elif [ "${filename##*.}" == "7z" ]; then
        check_command_error '7za';
        if [ -n `which 7za` ]; then
            size=`7za l ${filename}|grep ".sql"|awk '{print $4}'`
            7za x -so ${filename} 2>/dev/null|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
        else
            echo "Error! Command 7za not found. Please do command brew install p7zip."
            exit;
        fi
    elif [ "${filename##*.}" == "sql" ]; then
        pv ${filename}|${execstr} 2>&1|grep -v "${dbwarn}"
    else
        echo "Warning! Unknown selected file type. ${filename}"
    fi
}

# $1: output filename
# $2: source filename
action_compress () {
    ext=${1##*.}
    if [ "$ext" == "" -o "$ext" == "$1" ]; then
        output="$1.tgz"
        ext="tgz"
    else
        output="$1"
    fi
    if [ "$ext" == "zip" ]; then
        check_command_error "zip"
        cmp="zip"
    elif [ "$ext" == "gz" -o "$ext" == "tgz" ]; then
        check_command_error "tar"
        cmp="tar zvcf"
    else
        cmp=""
    fi
    if [ "$cmp" == "" ]; then
        echo "Rename -> ${output}"
        mv $2 $1
    else
        echo "${cmp} -> ${output}"
        ${cmp} ${output} ${2} >/dev/null
    fi
}


# $1: dbname
# $2: tables
# $3: filename
action_dumpdata () {
    if [ "$2" == "" ]; then
        ${dbdump} ${dbargs} ${dumpargs} -R -E ${1} \
            | sh -c "$skip_definer" | gzip | pv > ${3}
    else
        ${dbdump} -R -E ${dbargs} ${dumpargs} -R -E -B ${1} --tables ${2} \
            | sh -c "$skip_definer" | gzip | pv > ${3}
    fi
}


action_export () {
    select_database;
    if [[ "${filename}" == "" ]]; then
        name="`date \"+%Y%m%d%H%M%S\"`.gz"
        filename="${dbname}-${name}"
    fi
    echo "Dump data -> $filename"
    action_dumpdata "${dbname}" "${tables}" "$filename";
}


case "${action}" in
    "create")
        if [ -z "${dbname}" ]; then
            read -p "请输入要创建数据库名称:" dbname
        fi
        if [ -z "${dbname}" ]; then
            echo "No database specified."
            exit;
        fi
        ${dbcli} ${dbargs} -e "CREATE DATABASE IF NOT EXISTS ${dbname} default ${charset};"
        echo "Database '${dbname}' created!"
        ;;
    "remove")
        select_database;
        read -p "Ary you sure to delete database '${dbname}' (Yes/No)? " yn
        echo ""
        if [[ $yn == 'Y' ]] || [[ $yn == 'y' ]]; then
            ${dbcli} ${dbargs} -e "DROP DATABASE IF EXISTS ${dbname};"
            echo "Database '${dbname}' removed!"
        else
            echo 'Cancelled!'
        fi
        ;;
    "backup")
        action_export;
        ;;
    "export")
        action_export;
        ;;
    "import")
        # selected sql file
        select_sql_file;
        # select database
        select_database;
        # do action
        action_import;
        ;;
    "restore")
        # selected sql file
        select_sql_file;
        # select database
        select_database;
        # drop database
        read -p "Ary you sure to delete database '${dbname}' (Yes/No)?" -n 1 confirm
        echo ""
        if [[ $confirm == 'Y' ]] || [[ $confirm == 'y' ]]; then
            echo "Drop database ${dbname}"
            # echo "drop database if exists ${dbname};"|${dbcli} ${dbargs} 2>&1|grep -v "${dbwarn}"
            echo "drop database if exists ${dbname};"|${dbcli} ${dbargs}
        else
            echo 'Cancelled!'
            exit;
        fi
        # create database
        echo "Create database ${dbname}"
        echo "create database ${dbname};"|${dbcli} ${dbargs} 2>&1|grep -v "${dbwarn}"
        # import database
        action_import;
        ;;
    *)
        echo "Error! Unknown action \"${action}\"."
        usage;
        ;;
esac
