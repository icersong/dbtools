#!/bin/bash
# Copyright: Wed Jan 14 20:17:38 CST 2015
# Author: icersong
# Modified: Thu Jan 15 03:47:03 CST 2015
# Version: 1.1


################################################################################
debug=false
log=/tmp/dbtools.log
err=/tmp/dbtools.err

################################################################################
# Commands test exists
command -v pv >/dev/null 2>&1 || { echo >&2 "Error! require pv but it's not installed.  Abort."; exit 1; }
command -v tar >/dev/null 2>&1 || { echo >&2 "Error! require tar but it's not installed.  Abort."; exit 1; }
command -v 7za >/dev/null 2>&1 || { echo >&2 "Warning! require 7za but it's not installed."; }
command -v unzip >/dev/null 2>&1 || { echo >&2 "Warning! require unzip but it's not installed."; }

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
scriptfile=${0##*/}
scriptname=${scriptfile%.*}
script_ext=${scriptfile##*.}
scriptpath=$(cd `dirname $0`; pwd)
# echo scriptfile: $scriptfile
# echo scriptname: $scriptname
# echo script_ext: $script_ext
# echo scriptpath: $scriptpath


################################################################################
# action
action="$1"
if [ -z "${action}" ]; then
    echo "Usage:"
    echo "\$ ${scriptfile} <action>"
    echo "  action: backup|import|restore|create|remove"
    exit;
fi


################################################################################
# config variables
dbuser=
dbpass=
dbname=
dbhost=
dbport=
dumpargs=
dumpexec=
sqlfile=
sqlpath=


################################################################################
# script config     {{{1

scriptconfig="$scriptpath/${scriptname}.cfg"
echo scriptconf: $scriptconfig
if [ ! -f "$scriptconfig" ]; then
    echo "Error! Cofnig file '$scriptconfig' not exists."
    exit
fi
for line in  `cat $scriptconfig`
do
    if [ "$line" == "" ]; then
        continue
    fi
    name=${line%=*}
    text=${line##*=}
    case "$name" in
        "database.user")
            dbuser=${text}
            ;;
        "database.pass")
            dbpass=${text}
            ;;
        "database.name")
            dbname=${text}
            ;;
        "database.host")
            dbhost=${text}
            ;;
        "database.port")
            dbport=${text}
            ;;
        "dump.args")
            dumpargs=${text}
            ;;
        "dump.exec")
            dumpexec=${text}
            ;;
        "sql.path")
            sqlpath=${text}
            ;;
        "*") ;;
    esac
done

if [ -z "${sqlpath}" ]; then
    sqlpath="."
fi

echo "action: ${action}"
echo "database.user: ${dbuser}"
echo "database.pass: ${dbpass}"
echo "database.name: ${dbname}"
echo "database.host: ${dbhost}"
echo "database.port: ${dbport}"
echo "dump.args: ${dumpargs}"
echo "dump.exec: ${dumpexec}"
echo "sql.path: ${sqlpath}"
echo "sql.file: ${sqlfile}"

dbexec="mysql"
dbargs="-u${dbuser} -p${dbpass} --host ${dbhost} --port ${dbport}"
dbargs=" --defaults-extra-file=${scriptpath}/mysql-extra-config.cnf"
dbwarn="^Warning: Using a password on the command line interface can be insecure."


################################################################################
# do command    {{{1

case "${action}" in
    "create")
        if [ -z "${dbname}" ]; then
            read -p "请输入要创建数据库名称:" dbname
        fi
        if [ -z "${dbname}" ]; then
            echo "No database specified."
            exit;
        fi
        ${dbexec} ${dbargs} -e "CREATE DATABASE IF NOT EXISTS ${dbname} default charset utf8 COLLATE utf8_general_ci;"
        ;;
    "remove")
        get_dbname "${dbexec} ${dbargs}"
        ${dbexec} ${dbargs} -e "DROP DATABASE IF EXISTS ${dbname};"
        ;;
    "backup")
        get_dbname "${dbexec} ${dbargs}"
        echo "Backup data to ~.sql"
        mysqldump ${dbargs} ${dumpargs} ${dbname} 2>/dev/null| pv > ~.sql
        name=`date "+%Y%m%d%H%M%S"`
        echo "Move ~.sql -> ${name}.sql"
        mv ~.sql ${name}.sql
        echo "Make zip file ${dbname}-${name}.zip"
        zip ${dbname}-${name}.zip ${name}.sql >/dev/null
        rm -f ${name}.sql ~.sql
        echo 'complete!!!'
        exit;
        ;;
    "import")
        # selected sql file
        if [ -z "${sqlfile}" ] || [ ! -f "${sqlfile}" ]; then
            selectfile "${sqlpath}/*.sql ${sqlpath}/*.zip ${sqlpath}/*.7z ${sqlpath}/*.tar.gz";
        fi
        if [ ! -f "${selected}" ]; then
            echo "No sql file selected."
            exit;
        fi
        sqlfile=${selected}
        echo "Sql file $sqlfile selected."
        # select database
        get_dbname "${dbexec} ${dbargs}"
        # import database
        echo "Import data from ${sqlfile}"
        execstr="${dbexec} ${dbargs} --database ${dbname}"
        if [ "${sqlfile##*.tar.}" == "gz" ] || [ "${sqlfile##*.}" == "tgz" ]; then
            tarfile=`tar -tf ${sqlfile} | grep -v "/"`
            pv ${sqlfile}|tar -zxO ${tarfile}|${execstr} 2>&1|grep -v "${dbwarn}"
        elif [ "${sqlfile##*.}" == "zip" ]; then
            command -v unzip >/dev/null 2>&1 || { echo >&2 "I Error! require unzip but it's not installed.  Aborting."; exit 1; }
            size=`unzip -l ${sqlfile}|tail -n1|awk '{print $1}'`
            unzip -p ${sqlfile}|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
        elif [ "${sqlfile##*.}" == "7z" ]; then
            if [ -n `which 7za` ]; then
                size=`7za l ${sqlfile}|grep ".sql"|awk '{print $4}'`
                7za x -so ${sqlfile} 2>/dev/null|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
            else
                echo "Error! Command 7za not found. Please do command brew install p7zip."
                exit;
            fi
        elif [ "${sqlfile##*.}" == "sql" ]; then
            pv ${sqlfile}|${execstr} 2>&1|grep -v "${dbwarn}"
        else
            echo "Unknown selected file type. ${sqlfile}"
        fi
        echo "completed!!!"
        exit;
        ;;
    "restore")
        # selected sql file
        if [ -z "${sqlfile}" ] || [ ! -f "${sqlfile}" ]; then
            selectfile "${sqlpath}/*.sql ${sqlpath}/*.zip ${sqlpath}/*.7z ${sqlpath}/*.tar.gz";
        fi
        if [ ! -f "${selected}" ]; then
            echo "No sql file selected."
            exit;
        fi
        sqlfile=${selected}
        echo "Sql file $sqlfile selected."
        # select database
        get_dbname "${dbexec} ${dbargs}"
        # drop database
        echo "Drop database ${dbname}"
        # echo "drop database if exists ${dbname};"|${dbexec} ${dbargs} 2>&1|grep -v "${dbwarn}"
        echo "drop database if exists ${dbname};"|${dbexec} ${dbargs}
        # create database
        echo "Create database ${dbname}"
        echo "create database ${dbname};"|${dbexec} ${dbargs} 2>&1|grep -v "${dbwarn}"
        # import database
        echo "Import data from ${sqlfile}"
        execstr="${dbexec} ${dbargs} --database ${dbname}"
        if [ "${sqlfile##*.tar.}" == "gz" ] || [ "${sqlfile##*.}" == "tgz" ]; then
            tarfile=`tar -tf ${sqlfile}|grep -v "/"`
            pv ${sqlfile}|tar -zxO ${tarfile}|${execstr} 2>&1|grep -v "${dbwarn}"
        elif [ "${sqlfile##*.}" == "zip" ]; then
            command -v unzip >/dev/null 2>&1 || { echo >&2 "I Error! require unzip but it's not installed.  Aborting."; exit 1; }
            size=`unzip -l ${sqlfile}|tail -n1|awk '{print $1}'`
            unzip -p ${sqlfile}|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
        elif [ "${sqlfile##*.}" == "7z" ]; then
            if [ -n `which 7za` ]; then
                size=`7za l ${sqlfile}|grep ".sql"|awk '{print $4}'`
                7za x -so ${sqlfile} 2>/dev/null|pv -s ${size}|${execstr} 2>&1|grep -v "${dbwarn}"
            else
                echo "Error! Command 7za not found. Please do command brew install p7zip."
                exit;
            fi
        elif [ "${sqlfile##*.}" == "sql" ]; then
            pv ${sqlfile}|${execstr} 2>&1|grep -v "${dbwarn}"
        else
            echo "Unknown selected file type. ${sqlfile}"
        fi
        echo "completed!!!"
        exit;
        ;;
    "*")
        echo "Unknown action ${action}!!!"
        exit;
        ;;
esac
