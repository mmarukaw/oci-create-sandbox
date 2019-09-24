#!/bin/bash
#set -eu

source ./config
CMDNAME=`basename $0`
domain=oracle.com

### Usage ###
_usage() {
  echo "usage: ${CMDNAME} [-v] mgrname"
  echo "    mgrname : Input manager's short name so that all members under him(her) will be eported"
  exit 1
}

### Get options ###
while getopts v OPT; do
  case ${OPT} in
    v) FLG_v="TRUE";;
    *) _usage;;
  esac
done
shift `expr ${OPTIND} - 1`

### Verify required options ###
#[ "{FLG_v}" != "TRUE" ] && _usage

### Verify number of arguments ###
[ $# -ne 1 ] && _usage

### Set varibles ###
toplevel=cn=$1_org_ww
verbose=${FLG_v}

### Function : getldapinfo() ###
function getldapinfo () {
  group=$1
  let org_level++

  echo "[${CMDNAME}] exporting members under ${group} organization"
  members=$(ldapsearch -x -h ${ldapserver} -LLL "${group}" | grep '^uniquemember:' | sed -e 's/uniquemember: //' | sed -e 's/,.*//')

  for member in ${members}; do
    echo "[${CMDNAME}] collecting ldap information for ${member} ..."

    displayname=$(ldapsearch -x -h $ldapserver -LLL "${member}" displayname | grep '^displayname:' |  sed -e 's/displayname: //')
    firstname=$(echo ${displayname} | sed -e 's/ .*$//')
    lastname=$(echo ${displayname} | sed -e 's/^.* //')
    # uid=$(ldapsearch -x -h $ldapserver -LLL "${member}" uid | grep '^uid:' |  sed -e 's/uid: //' | tr '[:upper:]' '[:lower:]')

    email=$(ldapsearch -x -h $ldapserver -LLL "${member}" mail | grep '^mail:' |  sed -e 's/mail: //')
    uname=$(echo $email | sed -e 's/@'${domain}'//' | tr '[:upper:]' '[:lower:]')

    if [ "$(echo ${uname} | grep _org_ww)" ] ; then
      echo "[${CMDNAME}] ${uname} is a group. skipped."  1>&2
    else
      echo "${email},${email},,work,,${firstname},,${lastname},"  >>${idcsusers}.new
      echo "oci_member-${uname}_admins,,${email}"  >>${idcsgroups}.new
      echo "Normal Users,,${email}"  >>${idcsgroups}.new

      echo "    - user name   : ${uname}"  1>&2
      echo -n "  {name=\"${uname}\", org={"  >>${input}.new
      org[${org_level}]=$(echo ${group} | sed -e 's/cn=//' | sed -e 's/_ww//')  

      cnt=1
      while [ ${cnt} -le ${org_level} ] ; do
        echo "    - org_level_${cnt} : ${org[${cnt}]}"  1>&2
        echo -n "\"fy20_level_${cnt}\"=\"${org[${cnt}]}\""  >>${input}.new

        if [ ${cnt} -lt ${org_level} ] ; then
          echo -n ", "  >>${input}.new
        fi

        let cnt++
      done

      echo "}},"  >>${input}.new
    fi

    done

  nestedgroups=$(ldapsearch -x -h ${ldapserver} -LLL "${group}" | grep '^uniquemember:' | grep 'cn=org_groups' | sed -e 's/uniquemember: //' | sed -e 's/,.*//')

  for group in ${nestedgroups}; do
    getldapinfo $group
  done

  let org_level--

  return 0
}


### Main ###
echo "[${CMDNAME}] start exporting all the members under ${toplevel} from ldap server" 1>&2
echo "    - ldap server : ${ldapserver}" 1>&2
echo "    - domain      : ${domain}" 1>&2

input=users_$1.tfvars
idcsusers=users_idcs_$1.csv
idcsgroups=groups_idcs_$1.csv
rm -f ${input}.new {idcsusers}.new {idcsgroups}.new

echo "User Name,Work Email,Home Email,Primary Email Type,Honorific Prefix,First Name,Middle Name,Last Name,Honorific Suffix"  >>${idcsusers}.new
echo "Name,Description,User Members"  >>${idcsgroups}.new
echo "users = ["  >>${input}.new
org_level=0
org=()
getldapinfo $toplevel
echo "]"  >>${input}.new

echo "[${CMDNAME}] export completed. exported file : ${idcsusers}, ${idcsgroups}, ${input}" 1>&2
rm -f ${input} ${idcsusers} ${idcsgroups}
mv ${idcsusers}.new ${idcsusers}
mv ${idcsgroups}.new ${idcsgroups}
mv ${input}.new ${input}

