#!/bin/bash
#set -eu

CMDNAME=`basename $0`
source ./config

### Usage ###
_usage() {
  echo "usage: ${CMDNAME} [-v] @mgrname | membername"
  echo "    @mgrname   : a manager's short name with the prefix of "@" to export all members under him(her)."
  echo "    membername : a member's short name to export individual personnel."
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
verbose=${FLG_v}
input=$1

### Function : getldapinfo() ###
function getldapinfo () {
  local _members
  local _member

  if [ ${1:0:1} = "@" ] ; then
    # if the input is a manager, extract members under the manager group and put them into _members
    group=cn=${1##@}_org_ww
    echo "[${CMDNAME}] exporting members under ${group} organization"
    _members=$(ldapsearch -x -h ${ldapserver} -LLL "${group}" | grep '^uniquemember:' | sed -e 's/uniquemember: //' | sed -e 's/,.*//')

  else
    # if the input is a member, then put it into _members
    _members=uid=${input}
  fi 

  for _member in ${_members}; do
    
    if [ "$(echo ${_member} | grep _org_ww)" ] ; then
      echo "[${CMDNAME}] ${_member} is a nested group. extracting..."  1>&2
      getldapinfo @$(echo $_member | sed -e 's/^cn=//' | sed -e 's/_org_ww$//')

    else
      echo "[${CMDNAME}] collecting ldap information for ${_member} ..."

      displayname=$(ldapsearch -x -h $ldapserver -LLL "${_member}" displayname | grep '^displayname:' |  sed -e 's/displayname: //')
      firstname=$(echo ${displayname} | sed -e 's/ .*$//')
      lastname=$(echo ${displayname} | sed -e 's/^.* //')
      email=$(ldapsearch -x -h $ldapserver -LLL "${_member}" mail | grep '^mail:' |  sed -e 's/mail: //')
      uname=$(echo $email | sed -e 's/@'${domain}'//' | tr '[:upper:]' '[:lower:]')

      echo "${email},${email},,work,,${firstname},,${lastname},"  >>${idcsusers}.new
      echo "oci_member-${uname}_admins,,${email}"  >>${idcsgroups}.new
      echo "Regular_Users,,${email}"  >>${idcsgroups}.new
      echo "  {name=\"${uname}\"},"  >>${terraform}.new
    fi
    done

  return 0
}


### Main ###
echo "[${CMDNAME}] start exporting all the members under ${input} from ldap server" 1>&2
echo "    - ldap server : ${ldapserver}" 1>&2
echo "    - domain      : ${domain}" 1>&2

terraform=users_${input}.tfvars
idcsusers=users_idcs_${input}.csv
idcsgroups=groups_idcs_${input}.csv

# Create blank files
rm -f ${terraform}.new {idcsusers}.new {idcsgroups}.new
## Terraform tfvars file
echo "users = ["  >>${terraform}.new
## IDCS users csv file
echo "User Name,Work Email,Home Email,Primary Email Type,Honorific Prefix,First Name,Middle Name,Last Name,Honorific Suffix"  >>${idcsusers}.new
## IDCS groups csv file
echo "Name,Description,User Members"  >>${idcsgroups}.new

# Get user data from ldap and add lines to the tfvars/csv files
getldapinfo ${input}

# Add surfix data
echo "]"  >>${terraform}.new

# Closing
echo "[${CMDNAME}] export completed. exported file : ${idcsusers}, ${idcsgroups}, ${terraform}" 1>&2
rm -f ${terraform} ${idcsusers} ${idcsgroups}
mv ${idcsusers}.new ${idcsusers}
mv ${idcsgroups}.new ${idcsgroups}
mv ${terraform}.new ${terraform}
