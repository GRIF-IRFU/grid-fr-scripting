#!/usr/bin/env bash
#
# Ce script a pour but d'automatiser la demande, le renouvellement et la récupération de certificats serveurs via la CA
# GRID-FR (2018)
#
# Copyright 2018 Frederic Schaer, CEA, IRFU
# Licence : Cecill-2.1
#

#global vars
CERTSPATH="."

#URLs
CA_URL='https://pub-ee-grid.pncn.education.gouv.fr/EE'
CA_DIR="/etc/grid-security/certificates"
CGI_CSR='csr-send.cgi'
CGI_SEARCH='search-result.cgi'
CGI_SEARCH_OPTS='mode=search'
CGI_DOWNLOAD='crt-download.cgi'
CGI_SEND='csr-send.cgi'

CERT=~/.globus/usercert.pem
KEY=~/.globus/userkey.pem
TELEPHONE=''
EMAIL=''
PROG_NAME=`basename $0`
DEBUG=0
VERBOSE=0
SUBDIR=0
NODE_ALTNAME_DEFINE=1 # define FQDN as 1st DNS altname. Same as previous CA, different default from new CA.
SUFFIX=""
RUNAS=`id -un`
DRYRUN=1

help()
{
cat <<EOF

Helper tool that allows for easier GRID-FR certificate management.

When asking for a new certificate, a CSR will be created using openssl and then sent to the CA.
The private key will be already locally generated, only will remain the task of retrieving the public key when the CA validates the request

Usage : $PROG_NAME -t <TELEPHONE NUMBER> -p <PATH FOR CERTS DIR> -e email@org ACTION NODE ALT_DNS1 ALT_DNS2 ... ALT_DNS30

Where :
    ACTION can be :
    - req      : request a *NEW* certificate
    - renew    : request a certificate renewal
    - retrieve : retrieve a certificate public key from the CA

    NODE : is the hostname which for which the certificate is required

    ALT_DNS1 .. ALT_DNS30 : are the host alternative subjects that are requested. Up to 30 can be requested.

    Note : when asking for altnames, the NODE name (CN) will automatically be added as 1st altname as it's required but
    not automatic using the CA web service.

Mandatory options :
 ** THESE MUST BE KNOWN TO THE CA **
 -t : your phone number
 -e : * your * personal email. This will tell the CA that YOU are requesting a service cert (in addition to presenting your cert)
 -f : a service email address such as "mylab-admin@lab.fr" where reminders will be sent
 -O : your Organization (O=)
 -U : your Organization Unit (OU=)

 -r : turn on RUN mode : by default, no request will be sent

Options :

  -u <user>   : chown files to user. Defaults to current user.
  -p <path>   : set where the certs, CSR and keys will be stored (default : $CERTSPATH)
  -c <file>   : give a user certificate file (default : $CERT)
  -k <file>   : give a user certificate key  (default : $KEY). NOTE : file MUST NOT be password protected (*)
  -m <suffix> : copy (move) the generated cert/key file to a new nodename.{key|pem}.suffix . Default is to copy the new 
                files to FQDN.key and FQDN.pem...
                but this may be a problem when renewing certs "in place" where new keys would overwrite current keys while
                still waiting for the pending cert. Default suffix : empty (include the dot if you want one)

  -d        : debug (will not submit new requests nor renewal requests)

  -D        : "special" case : the new CA does not add the FQDN as alternative name 1 (DNS: x509v3 altnames ).
              This script DEFAULT to requesting the FQDN as altname#1
              If this option is used, the script will NOT add FQDN as first requested altname !

  -v        : turn on verbose mode
  -s        : turn on subdir mode : a subdir named after the cert FQDN will be created and all files created in there. Otherwide, those will be stored in \$CERTSPATH

  -h        : display this help

* : in rhel at least, curl allows to pass the password with the key file, but does not contain ciphers compatible with the CA webserver.
    openssl DOES work, BUT does not allow (?) to pass the password and will prompt for it each time IF you set a passphrase on your key file.
    your choice...

Example :
$PROG_NAME -v -k ~/.globus/userkey.nop.pem -t _MY_PHONE -e frederic.schaer___@_###?cea.fr -f mylab-admin@mylab.fr -O CEA -U IRFU -r -p ~/temp/ req node.domain
$PROG_NAME -v -k ~/.globus/userkey.nop.pem -t _MY_PHONE -e frederic.schaer___@_###?cea.fr -f mylab-admin@mylab.fr -O CEA -U IRFU -r -p ~/temp/ retrieve node.domain

EOF
}

#awesome func found on StackOverflow :
#https://stackoverflow.com/questions/296536/how-to-urlencode-data-for-curl-command
rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}


#
# logs a message depending on the user chosen log level (VERBOSE var) and the message log level
#
function log (){
    [[ -z "$1" || -z "$2" ]] && { echo "ERROR - log function : need \$1 as string and \$2 as loglevel" ; }

    case $2 in
      0|quiet) LOG_LVL=""
          LVL=0
       ;;
      1|info)  LOG_LVL="info - "
          LVL=1
       ;;
      2|debug)  LOG_LVL="debug - "
          LVL=2
          ;;
      *)  LOG_LVL="debug - "
          LVL=2
          ;;
    esac

    [ $VERBOSE -ge $LVL ] && echo "${LOG_LVL}$1"
}


function fail (){
    [[ -z "$1" || -z "$2" ]] && { echo "fail function : need \$1 and \$2 to be non empty" ; exit 2 ; }
    [ $2 > 0 ] && { echo "$1" ; exit $2 ; } || { echo "fail function : need \$2 to be >= 0" ; exit 2 ; }
}

function cert_request {
  FILE_CSR="$NODE_DIR/$NODE.$NOW.csr"
  FILE_KEY="$NODE_DIR/$NODE.$NOW.key"
  FILE_PENDING="$NODE_DIR/$NODE.pending"
  FILE_CSR_RESULT="$NODE_DIR/cert_request.`date +%s`.result.html"
  CSR_CMD="openssl req -new -newkey rsa:2048 -nodes -out $FILE_CSR -keyout $FILE_KEY -subj"
  SUBJECT="/O=GRID-FR/C=FR/O=${CA_O}/OU=${CA_OU}/CN=${NODE}"
  log "generating CSR request" 1
  log "  using openssl cmd : $CSR_CMD $SUBJECT" 2
  $CSR_CMD $SUBJECT && chown $RUNAS $FILE_CSR || fail "Error when creating $NODE CSR request .. ?" 2

  #if command was successfull, make sure key file is protected :
  chmod 600 $FILE_KEY

  #CSR data must be web-escaped to be passed into the form : only newlines need escaping here (?)
  #CSR_DATA=$(gawk '{printf "%s%%0D%%0A",$0}' $FILE_CSR)
  CSR_DATA=`cat $FILE_CSR`

  #NOW, build post data : for each form var, append contents
  POST_DATA=""
  POST_DATA="${POST_DATA}profile=GRID_FR_Services"
  POST_DATA="${POST_DATA}&datasource-step=edit"
  POST_DATA="${POST_DATA}&unique_id="`rawurlencode "mail=$EMAIL,ou=$CA_OU,o=$CA_O,o=GRID-FR"`
  POST_DATA="${POST_DATA}&pkcsten1="`rawurlencode "$CSR_DATA"`
  POST_DATA="${POST_DATA}&pkcs10=1"
  POST_DATA="${POST_DATA}&commonName1=$NODE"
  POST_DATA="${POST_DATA}&contactEmail1="`rawurlencode "$CONTACT_EMAIL"`
  POST_DATA="${POST_DATA}&comments="
  POST_DATA="${POST_DATA}&profile_form=1"


  for i in `seq 1 30`; do
    POST_DATA="${POST_DATA}&subjectAltNameDNS$i=${NODE_ALT_NAMES[i-1]}"
  done

  #we're done : post our cert request :
  CSR_URL="$CA_URL/$CGI_CSR"

  REQ_CMD="$WGET_CMD -O $FILE_CSR_RESULT --post-data \"$POST_DATA\" \"$CSR_URL\""
  if [ $DRYRUN -eq 0 ] ; then
    eval "$REQ_CMD" && chown $RUNAS $FILE_CSR_RESULT || fail  "cert_request: failed to send CSR request for $NODE at $CSR_URL" 2

    #search for this in the resulting html :
    # <div class="successMessage">The certificate request has been submitted.<br/>When it has been approved by a lifecycle administrator, you will receive an email with instructions about how to retrieve your certificate.</div>
    if grep -q "The certificate request has been submitted" $FILE_CSR_RESULT ; then
      echo "cert_request for $NODE succeeded."
      [ $DEBUG -eq 0 ] && rm -f $FILE_CSR_RESULT $FILE_CSR || log "debug is ON : not removing temporary and result files" 2
      DEST_KEY="$NODE_DIR/$NODE.key$SUFFIX"
      log "copying new key to non-timestamped file $DEST_KEY .." 1
      cp $FILE_KEY $DEST_KEY && chown $RUNAS $DEST_KEY
      chmod 600 $DEST_KEY
    else
      echo "cert_request for $NODE FAILED ? See $FILE_CSR_RESULT"
      echo "cleaning up CSR file only..."
      rm -f $FILE_CSR
    fi

  else
    log "would have sent this command if DRYRUN was not ON:" 2
    log "  $REQ_CMD" 2
    log "cleaning up useless debug private key and CSR..." 1
    rm -f $FILE_KEY $FILE_CSR
  fi

}
function cert_renew {
  echo "Unless I'm mistaken : renewing is the same as asking for a new cert..."
  cert_request
}

function cert_retrieve {
  #ex. : https://pub-ee-grid.pncn.education.gouv.fr/EE/search-result.cgi?mode=search&subject=toto.domain
  SEARCH_URL="${CA_URL}/${CGI_SEARCH}"
  POST_DATA="${CGI_SEARCH_OPTS}&subject=${NODE}"
  #the request must be authenticated using a valid user cert. If not, the resulting xml will be "empty" (no "entry" node)
  SEARCH_CMD="$WGET_CMD -O $NODE_DIR/$NODE.xml --post-data \"$POST_DATA\" \"$SEARCH_URL\""
  log "searching for $NODE pubkeys on the CA..." 1
  log "  using this cmd : $SEARCH_CMD" 2
  eval "$SEARCH_CMD" && chown $RUNAS $NODE_DIR/$NODE.xml || fail  "cert_retrieve: failed to search for $NODE at $SEARCH_URL" 2

  #search the node serial number in the list of retrieved entries using xpath/xstlproc
  # NOT SURE this will only a 1 element list !!
  # What will happen with expired certs ??
  # This will produce 2 lines per cert : serial, then end date : convert that to one line per cert - use CSV.
  # ... normally, only 1 valid, right ? What about overlap when there are renewals ?
  #
  # output format : serial:enddate(epoch)
  log "  extracting the certs serial and enddate as epoch from the xml..." 2
  OUT=`xml_grep --text_only '//value[@i18n="Serial Number" or @i18n="Valid to"]' $NODE_DIR/$NODE.xml | gawk '{if( FNR % 2) {printf "%s;",$0} else { cmd="date +%s -d \""$0"\"" ; cmd | getline var ;print var ; close(cmd) } }'`

  #sort by enddate (reverse order) : the CERT with the biggest (epoch) enddate will 'win' and see its output file named as "$NODE.pem"
  SORTED_CERT_LIST=$(echo "$OUT" | sort -t ';' -k '2' -r -n)
  IS_LATEST=1

  #NOW : process each cert and retrieve its PEM key
  FOUND_CERTS=0
  DOWNLOAD_URL="${CA_URL}/${CGI_DOWNLOAD}"
  for i in $SORTED_CERT_LIST ; do
    SERIAL=${i/;*/}
    ENDDATE=${i/*;/}
    FOUND_CERTS=$[ FOUND_CERTS + 1 ]
    if [ $ENDDATE -gt $NOW ]; then
      OUT_FILE="$NODE_DIR/${NODE}.${SERIAL}.pem"
      POST_DATA="ca=AC_GRID_FR_Services&format=PEM&serial=$SERIAL"
      RETRIEVE_CMD="$WGET_CMD -O $OUT_FILE --post-data \"$POST_DATA\" \"$DOWNLOAD_URL\""
      eval "$RETRIEVE_CMD" && chown $RUNAS $OUT_FILE || fail  "cert_retrieve: failed to retrieve $NODE PEM cert at $DOWNLOAD_URL" 2
      if [ $IS_LATEST -eq 1 ]; then
        IS_LATEST=0
        FINAL_PEM="$NODE_DIR/${NODE}.pem$SUFFIX"
        cp $OUT_FILE $FINAL_PEM && chown $RUNAS $FINAL_PEM
      fi
    else
      log "NOT retrieving expired cert with serial $SERIAL" 1
    fi
  done

  if [ $FOUND_CERTS -gt 0 ]; then
    fail "$NODE : ok - downloaded $FOUND_CERTS pubkeys" 0
  else
    fail "$NODE : warn - downloaded NO pubkeys ??" 1
  fi
}

# MAIN

while getopts "t:p:c:k:e:f:u:m:O:U:dDrvhs" options; do
  case $options in
    t ) TELEPHONE=$OPTARG;;
    p ) CERTSPATH=$OPTARG;;
    c ) CERT=$OPTARG;;
    k ) KEY=$OPTARG;;
    m)  SUFFIX=$OPTARG;;
    e ) EMAIL=$OPTARG;;
    f ) CONTACT_EMAIL=$OPTARG;;
    O ) CA_O=$OPTARG;;
    U ) CA_OU=$OPTARG;;
    u)  RUNAS=$OPTARG;;
    v ) VERBOSE=1 ;;
    s ) SUBDIR=1  ;;
    d)
       DEBUG=1
       VERBOSE=2 ;;
    D) NODE_ALTNAME_DEFINE=0 ;;
    r) DRYRUN=0 ;;
    h)
      help
      exit 0
      ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      help
      exit 1
      ;;
  esac
done

shift "$((OPTIND - 1))"

#process remaining mandatory args
ACTION="${1}"
NODE="${2}"

#check mandatory args
for i in "ACTION" "NODE" "CA_O" "CA_OU" "EMAIL" "TELEPHONE" "CONTACT_EMAIL"; do
  [ -z " ${!i}" ] && help && fail "$i cannot be empty" 2
done

#only run intermediate commands (cert request generation for instance) if either -r is selected, or debug is on
# (and run them when -r or -d is selected)
RUN_CMD=0
if [[ $DRYRUN -eq 0 || $DEBUG -eq 1 ]]; then
  RUN_CMD=1
fi


#process alternative names (max : 30)
# don't always "shift 2" the remaining args ("command" & "node name") : the node name must also be used as an alt name in case that's requested with -D
if [ $NODE_ALTNAME_DEFINE -eq 1 ]; then
  #keep FQDN as 1st altname
  shift 1
else
  shift 2
fi
NODE_ALT_NAMES=( "$@" )

#if the number of alt names is 0, then no alt name was provided : empty the ALT_NAME var
#probably useless check.
if [ ${#NODE_ALT_NAMES[*]} -eq 0 ] ; then
  NODE_ALT_NAMES=()
fi


#validate mandatory tools used by this script
CAN_RUN=1
for i in "wget" "xml_grep" "gawk" "host" "grep" "printf" "openssl" ; do
  which $i >/dev/null
  [ $? -gt 0 ] && echo "This script need the tool '$i' in order to run. Please install it in your PATH." && CAN_RUN=0
done
[ $CAN_RUN -eq 0 ] && exit 2

#check the node resolves in the DNS : this is mandatory for this CA
#check NODE name in DNS. Do the altnames need to resolve in DNS ??
#for i in $NODE ${NODE_ALT_NAMES[*]} ; do
for i in $NODE ; do
  host $i >/dev/null 2>&1
  DNS_RET=$?
  [ $DNS_RET -ne 0 ] && fail "$NODE does not seem to resolve DNS as $i : <<host $i>> returned $DNS_RET" 2
done

if [ $RUN_CMD -eq 1 ] ; then

  #create a directory where the node files will be stored
  if [ $SUBDIR -eq 1 ]; then
    NODE_DIR="$CERTSPATH/$NODE"
  else
    NODE_DIR="$CERTSPATH"
  fi
  mkdir -p $NODE_DIR && chown $RUNAS $NODE_DIR || fail "Could not create certificates destination directory $NODE_DIR" 2

  #prepare the url basic commands
  # cURL does not seem to contain ciphers with the CA. We must use wget with no pass :'( ??

  # TODO : use GNU expect or something similar to remove the need for pass-less CERT key ?
  # read -s -p 'Please enter YOUR USER key password :' PASS && echo


  [ ! -d $CA_DIR ] && fail "Cannot access the directory where the CA certs are stored - this is mandatory for validating the host certs." 2
  #CURL_CMD="curl -s $CURL_DEBUG -k --cert $CERT:$PASS --key $KEY" #curl issue with grid-fr CA website : no common ciphers :/
  WGET_CMD="wget -q --ca-directory=$CA_DIR --certificate $CERT --private-key $KEY"
  NOW="`date +%s`"

  case "$ACTION" in
    req)       cert_request  ;;
    renew)     cert_renew    ;;
    retrieve)  cert_retrieve ;;
    *) help ;;
  esac
else
  log "INFO: would run action $ACTION for $NODE if option -r was used without -d" 0
fi
exit 0
