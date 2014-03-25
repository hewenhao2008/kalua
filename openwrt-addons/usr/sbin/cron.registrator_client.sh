#!/bin/sh
. /tmp/loader
. /usr/share/libubox/jshn.sh

URL_BASE="http://reg.weimarnetz.de"

if [ -e '/www/monitoring.wifimac' ]; then
	read MAC <'/www/monitoring.wifimac'
else
	MAC="$( _net dev2mac "$WIFIDEV" )"
	MAC="$( _sanitizer do "$MAC" urlvalue )"
fi

PASS="$( _ssh key_public_fingerprint_get )"
PASS="$( _sanitizer do "$PASS" urlvalue )"

NETWORK="$( echo "$CONFIG_PROFILE" | cut -d'_' -f1 )"
[ "$NETWORK" = 'liszt28' ] && NETWORK='ffweimar'

# try to get existing nodenumber from config
NODENUMBER="$( uci get system.@profile[0].nodenumber )"

# get the config for "NODE_NUMBER_RANDOM"
eval $( _ipsystem do "$NODENUMBER" | grep ^"NODE_NUMBER_RANDOM=" )

# only if RANDOM is set to false, …
[ "$NODE_NUMBER_RANDOM" = "false" ] && {

	# API call is: Send an 'Update' for our NODENUMBER, with MAC and PASS.
	# - if the NODENUMBER did not exist, it will be created with the supplied data
	# - if the NODENUMBER did exist,
	#     - and the PASS did not match: Error
	#     - and PASS did match: Success (and extension of lease in registrator)
	URL="$URL_BASE/PUT/$NETWORK/knoten/$NODENUMBER?mac=${MAC}&pass=${PASS}"
	_log do heartbeat daemon info "$URL"

	# call API and convert JSON answer to shell variables
	# answer e.g.:
	# {
	#  "status": 200,
	#  "message": "updated",
	#  "result": {
	#    "number": 261,
	#    "mac": "106f3f0e318e",
	#    "last_seen": 1395749203533,
	#    "network": "ffweimar",
	#    "location": "/ffweimar/knoten/261"
	#  }
	# }
	#
	# or:
	#
	# {
	#  "status": 201,
	#  "message": "Created!",
	#  "result": {
	#    "number": 269,
	#    "mac": "6466b3ded9d7",
	#    "last_seen": 1395752262820,
	#    "network": "ffweimar",
	#    "location": "/ffweimar/knoten/269"
	#  }
	# }
	HTTP_ANSWER="$( _wget do "$URL" 30 )"
	eval $( jshn -r "$HTTP_ANSWER" )

	# check if we've got HTTP Status 401 'Not Authorized'
	case "$JSON_VAR_status" in
		'401')
			# TODO: resetting the number here would auto-recover lost passwords
			#       and asign new NODENUMBER on next try. like this:
			# uci delete system.@profile[0].nodenumber
			_log do registrator daemon alert "[ERR] somebody has your number '$NODENUMBER'"

			# API call is: Send a 'Create', with MAC and PASS.
			# - successful answer *always* contains our NODENUMBER
			# - if a new NODENUMBER was registered for us, status is 201 Created
			# - if a NODENUMBER with same MAC already existed, status is 303 Redirect
			URL="$URL_BASE/POST/$NETWORK/knoten?mac=${MAC}&pass=${PASS}"

			# call API and convert JSON answer to shell variables
			HTTP_ANSWER="$( _wget do "$URL" 30 )"
			eval $( jshn -r "$HTTP_ANSWER" )

			# if the status is >400, there was some kind of error
			if test 2>/dev/null "$JSON_VAR_status" -lt 400; then
				# check if the answer contains a NODENUMBER
				if test 2>/dev/null "$JSON_TABLE1_number" -gt 1 ; then
					_log do registrator daemon alert "[OK] new nodenumber: '$JSON_TABLE1_number'"
					# check with `_ipsystem` if it is a *valid* NODENUMBER
					if _ipsystem do "$JSON_TABLE1_number" >/dev/null ; then
						# TODO: does one of these already save the number to uci ???
						NETWORK="$( echo "$CONFIG_PROFILE" | cut -d'_' -f1 )"
						MODE="$( echo "$CONFIG_PROFILE" | cut -d'_' -f2 )"
						/etc/init.d/apply_profile.code "$NETWORK" "$MODE" "$JSON_TABLE1_number"
					else
						_log do error daemon info "nodenumber invalid: '$JSON_TABLE1_number'"
					fi
				else
					_log do error daemon info "number format wrong: '$JSON_TABLE1_number'"
				fi
			else
				_log do error daemon info "message: '$JSON_VAR_msg'"
			fi
		;;
		'201')
			_log do heartbeat daemon alert "OK: HTTP-Status: '$JSON_VAR_status' -> '$JSON_VAR_msg'"
		;;
		'200')
			_log do heartbeat daemon info "OK"
		;;
		*)
			_log do heartbeat daemon alert "[ERR] HTTP-Status: '$JSON_VAR_status' -> '$JSON_VAR_msg'"
		;;
	esac
}
