# grid-fr-scripting
GRID-FR related tool(s) used to request and renew grid-fr certificates

### How this works

The script requires some (personal and institutional) data and then sends requests the GRID-FR CA cgis (the CA is using opentrust).

Wget is used... because the CA website appeared to be incompatible with Curl neither in CentOS 7/5 nor SL 6.9 : no compatible cipher keys...
This has the unfortunate consequence that for now, it's not possible to specify a password then pass it on to wget : either you must use a user passwordless key, or you must enter your passphrase each time that key is used.

If you find a way to work around the above issue, PRs are welcome...

Script usage example (for now)(as root) :

~~~~ 
** request a cert, creating the private key in PATH/hostnameA.key.new AND PATH/hostnameA.`date +%s`.key **
./grid-fr.sh -v -c USERCERT.pem -k USERKEY -t PHONE -e USERMAIL -f USER_CERTS_SERVICE_MAIL -s -O USER_ORGANISATION -U USER_OU -u CHOWN_TO -p PATH -m .new -r req hostnameA altname1 altname2
** fetch the cert creating the public key in PATH/hostnameA.pem.new AND PATH/hostnameA.[the cert serial num].pem **
./grid-fr.sh -v -c USERCERT.pem -k USERKEY -t PHONE -e USERMAIL -f USER_CERTS_SERVICE_MAIL -s -O USER_ORGANISATION -U USER_OU -u CHOWN_TO -p PATH -m .new -r req hostnameA altname1 altname2 
~~~~

where :

- USERKEY is either passwordless, or password protected (but it will then be really painfull)
- USER_CERTS_SERVICE_MAIL is the lab service email formerly used to receive notifications about expiring certificates. The CA will refuse requests with the user email
- USER_ORGANISATION for instance, is your institute. For instance : CEA, IN2P3
- USER_OU : your OU. For instance IRFU, LLR...
- CHOWN_TO : if specified, all files created will(should) be chowned to this user

The ".new" file extention can be disabled by not specifying a suffix, but it's usefull for "in place" certificate renewal requests, to prevent old keys from beeing overwritten by the new private keys while waiting for the signed CERT.pem...

See the script help for more guidance.

### Altnames notice

when asking for altnames, the host FQDN will be automatically added as 1st altname as this is not handleded automatically by the CA.

### Requirements

This script requires usual wget/grep/gawk tools, but in addition it requires __xml_grep__ for basic xml parsing using xpath. If you find a better way to parse the search cgi output... send a PR ;)

### Contribution

Contributions are welcome : fork, fix/enhance, send PRs...

Support requests and bugs may be submitted, they will be fixed on a best effort basis

### Legal notice
This repository contents is provided "as is" under the Cecill 2.1 licence.
In no way shall we be held responsible of any damage done to you nor anyone/anything by your use of our scripts, blah blah blah
